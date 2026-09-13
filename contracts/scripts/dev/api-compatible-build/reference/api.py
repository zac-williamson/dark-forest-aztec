#!/usr/bin/env python3
"""Pinned, dependency-free Noir API/source inventory and compatibility checker.

This is a structural checker, not a compiler or a semantic-equivalence proof.
Compiled ABI output schemas supplement the source inventory when supplied.
"""
import argparse, collections, hashlib, json, pathlib, re, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
BASE = HERE / 'baseline'
DOCS = ROOT / 'docs/api-compatibility'
GENERATED = {'offchain_receive', 'public_dispatch', 'sync_state'}
TOKEN = re.compile(r'"(?:\\.|[^"\\])*"|[A-Za-z_]\w*|\d+|::|->|==|!=|<=|>=|&&|\|\||[^\s]')

def sha(data): return hashlib.sha256(data if isinstance(data, bytes) else data.encode()).hexdigest()
def dump(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
def git(*args): return subprocess.check_output(['git', *args], cwd=ROOT).decode()
def clean(s):
    """Blank comments without changing offsets or the contents of strings."""
    out=list(s); i=0
    while i < len(s):
        if s[i]=='"':
            i+=1
            while i<len(s):
                if s[i]=='\\': i+=2
                elif s[i]=='"': i+=1;break
                else:i+=1
        elif s.startswith('//',i):
            j=s.find('\n',i);j=len(s) if j<0 else j
            out[i:j]=' '*(j-i);i=j
        elif s.startswith('/*',i):
            j=i+2;depth=1
            while j<len(s) and depth:
                if s.startswith('/*',j):depth+=1;j+=2
                elif s.startswith('*/',j):depth-=1;j+=2
                else:j+=1
            for k in range(i,j):
                if out[k]!='\n':out[k]=' '
            i=j
        else:i+=1
    return ''.join(out)
def norm(s): return ' '.join(TOKEN.findall(clean(s)))
def balanced(s, pos, left='(', right=')'):
    assert s[pos]==left,(pos,s[pos:pos+40]);depth=1;i=pos+1
    while i<len(s):
        if s[i]=='"':
            i+=1
            while i<len(s):
                if s[i]=='\\':i+=2
                elif s[i]=='"':break
                else:i+=1
        elif s[i]==left:depth+=1
        elif s[i]==right:
            depth-=1
            if depth==0:return i
        i+=1
    raise ValueError('Unbalanced '+s[pos:pos+80])
def split_top(s, sep=','):
    out=[];start=0;stack=[];pairs={')':'(',']':'[','>':'<','}':'{'};i=0
    while i<len(s):
        ch=s[i]
        if ch in '([{<':stack.append(ch)
        elif ch in ')]}>':
            if stack and stack[-1]==pairs[ch]:stack.pop()
        elif ch==sep and not stack:out.append(s[start:i].strip());start=i+1
        i+=1
    if s[start:].strip():out.append(s[start:].strip())
    return out
def fields(s):
    return [{'name':p.split(':',1)[0].strip().removeprefix('pub '),'type':norm(p.split(':',1)[1])} for p in split_top(s) if ':' in p]
def attributes(s,pos):
    out=[];i=pos
    while True:
        while i and s[i-1].isspace():i-=1
        if not i or s[i-1]!=']':break
        j=s.rfind('#[',0,i)
        if j<0 or balanced(s,j+1,'[',']')!=i-1:break
        out.insert(0,norm(s[j+2:i-1]));i=j
    return out
def calls(s,pattern):
    out=[]
    for m in re.finditer(pattern,s):
        op=s.find('(',m.start(),m.end()+1)
        if op<0:continue
        end=balanced(s,op);out.append((m,s[op+1:end],end))
    return out

def storage_access(body,operation):
    out=[]
    for m in re.finditer(r'self\s*\.\s*storage\s*\.\s*(\w+)',body):
        i=m.end();keys=[]
        while True:
            nxt=re.match(r'\s*\.\s*(\w+)\s*\(',body[i:])
            if not nxt:break
            name=nxt[1];op=i+nxt.end()-1;end=balanced(body,op)
            arg=norm(body[op+1:end]);i=end+1
            if name=='at':keys.append(arg)
            elif name==operation:
                out.append({'field':m[1],'keys':keys,'value':arg,'expression':norm(body[m.start():i])});break
            else:break
    return out

def parse_source(path,text):
    s=clean(text);cm=re.search(r'\bcontract\s+(\w+)\s*\{',s)
    if not cm:return None
    name=cm[1];end=balanced(s,cm.end()-1,'{','}')
    local_names=set(re.findall(r'\bfn\s+(\w+)\s*\(',s[cm.end():end]))
    contract={'name':name,'path':path,'sourceSha256':sha(text),'functions':[],'events':[],'storage':[]}
    for m in re.finditer(r'\b(?:pub\s+)?struct\s+(\w+)(?:\s*<[^{}]+>)?\s*\{',s):
        if not cm.end()<=m.start()<end:continue
        e=balanced(s,m.end()-1,'{','}');attrs=attributes(s,m.start());f=fields(s[m.end():e])
        if 'event' in attrs:contract['events'].append({'name':m[1],'fields':f,'line':s.count('\n',0,m.start())+1})
        if m[1]=='Storage':contract['storage']=f
    for m in re.finditer(r'\b(?:pub\s+)?(?:unconstrained\s+)?fn\s+(\w+)\s*\(',s):
        if not cm.end()<=m.start()<end:continue
        op=m.end()-1;cl=balanced(s,op);bs=s.find('{',cl);be=balanced(s,bs,'{','}');body=s[bs+1:be];attrs=attributes(s,m.start())
        ext=next((re.search(r'"(public|private|utility)"',a)[1] for a in attrs if a.startswith('external')),None)
        access='internal' if any(a.startswith('internal') for a in attrs) else 'library'
        f={'name':m[1],'kind':ext or access,'attributes':attrs,'unconstrained':'unconstrained' in s[m.start():op],
           'parameters':fields(s[op+1:cl]),'returnType':norm(s[cl+1:bs].strip().removeprefix('->').strip()) or '()',
           'line':s.count('\n',0,m.start())+1,'bodyTokenSha256':sha(norm(body)),
           'directWrites':storage_access(body,'write'),'directReads':storage_access(body,'read'),
           'assertions':[],'externalCalls':[],'selfCalls':[],'events':[], 'callerExpressions':[]}
        for am,args,_ in calls(body,r'\b(?:assert|assert_eq|assert_ne|panic)\s*\('):f['assertions'].append(norm(body[am.start():am.end()])+norm(args)+')')
        bindings={}
        for bm,args,_ in calls(body,r'\blet\s+(\w+)(?:\s*:[^;=]+)?\s*=\s*(\w+)::at\s*\('):
            bindings[bm[1]]={'contract':bm[2],'addressExpression':norm(args)}
        for xm,args,_ in calls(body,r'self\s*\.\s*(call|view)\s*\('):
            call=re.match(r'\s*(\w+)\s*\.\s*(\w+)\s*\(',args)
            b=bindings.get(call[1],{}) if call else {}
            method=call[2] if call else None
            direct=re.match(r'\s*(\w+)::at\s*\(',args)
            if direct:
                opening=args.find('(',direct.start());closing=balanced(args,opening)
                member=re.match(r'\s*\.\s*(\w+)\s*\(',args[closing+1:])
                b={'contract':direct[1],'addressExpression':norm(args[opening+1:closing])}
                method=member[1] if member else None
            f['externalCalls'].append({'mode':xm[1],'targetContract':b.get('contract'),'method':method,'binding':call[1] if call else None,'addressExpression':b.get('addressExpression'),'expression':norm(args),'line':s.count('\n',0,bs+1+xm.start())+1})
        for sm in re.finditer(r'self\s*\.\s*(internal|enqueue_self)\s*\.\s*(\w+)\s*\(',body):f['selfCalls'].append({'mode':sm[1],'method':sm[2]})
        for lm in re.finditer(r'(?<![\w.:])([A-Za-z_]\w*)\s*\(',body):
            if lm[1] in local_names:f['selfCalls'].append({'mode':'library','method':lm[1]})
        for em in re.finditer(r'self\s*\.\s*emit\s*\(\s*(\w+)\s*\{',body):f['events'].append(em[1])
        for qm in re.finditer(r'(?:self\s*\.\s*(?:context\s*\.\s*)?msg_sender|self\s*\.\s*context\s*\.\s*this_address)\s*\([^)]*\)',body):f['callerExpressions'].append(norm(qm[0]))
        f['addressBindings']=bindings
        contract['functions'].append(f)
    return contract

def parse_types(files):
    result={}
    for path,text in files.items():
        if not path.startswith('contracts/types/') or not path.endswith('.nr'):continue
        s=clean(text)
        for m in re.finditer(r'\bpub\s+struct\s+(\w+)\s*\{',s):
            e=balanced(s,m.end()-1,'{','}');result[m[1]]={'path':path,'fields':fields(s[m.end():e]),'line':s.count('\n',0,m.start())+1}
    return result

def resolve_type(t,types,seen=()):
    t=''.join(TOKEN.findall(t));short=t.split('::')[-1]
    if t.startswith('['):
        parts=split_top(t[1:-1],';')
        if len(parts)==2:return {'array':resolve_type(parts[0],types,seen),'length':parts[1]}
    if short in types:
        if short in seen:return {'recursive':short}
        return {'struct':short,'fields':[{'name':f['name'],'type':resolve_type(f['type'],types,seen+(short,))} for f in types[short]['fields']]}
    return short

def surface(c,types):
    return {'name':c['name'],'functions':{f['name']:{'kind':f['kind'],'attributes':f['attributes'],'parameters':[{'name':p['name'],'type':resolve_type(p['type'],types)} for p in f['parameters']],'returnType':resolve_type(f['returnType'],types),'unconstrained':f['unconstrained']} for f in c['functions'] if f['kind'] in ('public','private','utility')},'events':{e['name']:[{'name':f['name'],'type':resolve_type(f['type'],types)} for f in e['fields']] for e in c['events']}}

def inventory(files):
    types=parse_types(files);cs=[]
    for path,text in files.items():
        if re.match(r'contracts/(?:(?:system|storage|settlement_workers)/[^/]+|[^/]+)/src/main.nr$',path):
            c=parse_source(path,text)
            if c:cs.append(c)
    known={c['name']:c for c in cs};unresolved=[]
    for c in cs:
        for f in c['functions']:
            for x in f['externalCalls']:
                target=known.get(x['targetContract'],{})
                tf=next((t for t in target.get('functions',[]) if t['name']==x['method']),None)
                x['readOnly']=bool(tf and (tf['kind']=='utility' or 'view' in tf['attributes']))
    for c in cs:
        byname={f['name']:f for f in c['functions']}
        def visit(n,seen=()):
            if n in seen or n not in byname:return []
            f=byname[n];out=[{'via':list(seen)+( [n]),**x} for x in f['externalCalls'] if x['mode']=='call' and not x.get('readOnly')]
            for x in f['selfCalls']:out+=visit(x['method'],seen+(n,))
            return out
        for f in c['functions']:
            f['transitiveExternalWrites']=visit(f['name'])
            for x in f['externalCalls']:
                if not x['targetContract'] or x['targetContract'] not in known:unresolved.append({'contract':c['name'],'function':f['name'],**x})
    return {'contracts':cs,'types':types,'surfaces':{c['name']:surface(c,types) for c in cs},'unresolvedExternalCalls':unresolved}

def artifact_type(t):
    if not isinstance(t,dict):return t
    return {k:(v.split('::')[-1] if k=='path' else [artifact_type(x) for x in v] if isinstance(v,list) else artifact_type(v)) for k,v in t.items()}
def artifact_summary(path):
    d=json.loads(path.read_text())
    # Completed builds keep their validation reports beside the artifacts.
    # Ignore report objects, but fail closed on a malformed compiler artifact.
    if isinstance(d,dict) and not any(key in d for key in ('name','functions','outputs','file_map','noir_version')):return None
    if not isinstance(d,dict) or not isinstance(d.get('name'),str) or not isinstance(d.get('functions'),list) or not isinstance(d.get('outputs'),dict):
        raise ValueError(f'Invalid compiler artifact: {path}')
    out=d.get('outputs',{}).get('structs',{});funcs={}
    attrs={f['name'].removeprefix('__aztec_nr_internals__'):sorted(f.get('custom_attributes',[])) for f in d['functions']}
    for f in out.get('functions',[]):
        name=f['path'].split('::')[-1].removesuffix('_abi')
        funcs[name]={'schema':artifact_type(f['fields']),'attributes':attrs.get(name,[])}
    generated={f['name']: {'attributes':f.get('custom_attributes',[]),'abi':artifact_type({k:v for k,v in f['abi'].items() if k!='error_types'})} for f in d['functions'] if f['name'] in GENERATED}
    source=[]
    for f in d.get('file_map',{}).values():
        if re.search(r'\bcontract\s+'+re.escape(d['name'])+r'\s*\{',clean(f.get('source',''))):source.append({'artifactPath':f.get('path'),'sha256':sha(f['source']),'tokenSha256':sha(norm(f['source']))})
    return {'name':d['name'],'file':path.name,'sha256':sha(path.read_bytes()),'noirVersion':d.get('noir_version'),'transpiled':bool(d.get('transpiled')),'functions':funcs,'events':{x['path'].split('::')[-1]:artifact_type(x['fields']) for x in out.get('events',[])},'generatedFunctions':generated,'owningSource':source,'storageMetadata':d.get('outputs',{}).get('globals',{}).get('storage',[])}
def artifact_inventory(directory):
    return {d['name']:d for p in sorted(directory.glob('*.json')) if (d:=artifact_summary(p))}

def external_references(files):
    refs=[];routes=[];addresses=[]
    markers=re.compile(r'(?:\.\s*methods\s*(?:\.\s*(\w+)|\[)|\b(\w+Contract)\s*\.\s*at\s*\(|\b(\w+Contract)\.events\.(\w+)|\b\w*(?:CONTRACT_ADDRESS|DEPLOYER_ADDRESS|DEPLOYMENT_SALT)\b|registerContract\s*\(|registerContractClass\s*\(|getPublicEvents\s*\()')
    for path,text in files.items():
        if not path.endswith(('.ts','.tsx','.js','.mjs')) or '/artifacts/' in path or '.test.' in path:continue
        for m in markers.finditer(text):
            ln=text.count('\n',0,m.start())+1;line=text.splitlines()[ln-1].strip();refs.append({'path':path,'line':ln,'method':m[1],'contractWrapper':m[2] or m[3],'event':m[4],'snippet':line})
        if path.endswith('ContractResolver.ts'):
            for m in re.finditer(r'case\s+"([^"]+)"\s*:\s*return\s*\{\s*contract:\s*this\.(\w+)\s*,\s*method:\s*"([^"]+)"',text):routes.append({'intent':m[1],'binding':m[2],'method':m[3],'path':path,'line':text.count('\n',0,m.start())+1})
        if path=='packages/contracts/src/index.ts':
            for m in re.finditer(r'export const (\w+)\s*=\s*("[^"]+"|\d+)',text):addresses.append({'name':m[1],'value':m[2].strip('"'),'line':text.count('\n',0,m.start())+1})
    return {'references':refs,'intentRoutes':routes,'deploymentConstants':addresses,'limitations':['Literal and structural source references are enumerated; dynamically computed method names require manual review. Generated artifact wrappers and third-party consumers are not inferred from names alone.']}

def compare(before,after):
    errors=[];additions=[];behavior=[];storage=[]
    for name,b in before['surfaces'].items():
        a=after['surfaces'].get(name)
        if a is None:errors.append({'contract':name,'kind':'missing_contract'});continue
        for category in ('functions','events'):
            for n,sig in b[category].items():
                if n not in a[category]:errors.append({'contract':name,'member':n,'kind':'missing_'+category})
                elif sig!=a[category][n]:errors.append({'contract':name,'member':n,'kind':'changed_'+category,'before':sig,'after':a[category][n]})
            for n in a[category].keys()-b[category].keys():additions.append({'contract':name,'member':n,'kind':'added_'+category})
        bc=next(c for c in before['contracts'] if c['name']==name);ac=next(c for c in after['contracts'] if c['name']==name);af={f['name']:f for f in ac['functions']}
        for f in bc['functions']:
            if f['name'] in af and f['bodyTokenSha256']!=af[f['name']]['bodyTokenSha256']:
                x=af[f['name']];behavior.append({'contract':name,'function':f['name'],'kind':f['kind'],'beforeLine':f['line'],'afterLine':x['line'],'assertionsChanged':f['assertions']!=x['assertions'],'callerExpressionsChanged':f['callerExpressions']!=x['callerExpressions'],'writesChanged':f['directWrites']!=x['directWrites'],'callsChanged':f['externalCalls']!=x['externalCalls'],'reviewRequired':True})
        if bc['storage']!=ac['storage']:storage.append({'contract':name,'before':bc['storage'],'after':ac['storage'],'appendOnly':ac['storage'][:len(bc['storage'])]==bc['storage']})
    return {'compatible':not errors,'breakingChanges':errors,'additions':additions,'behaviorChangesRequiringReview':behavior,'storageLayoutChanges':storage,'scope':'Structural compatibility only. Matching APIs and body hashes do not prove whole-game semantics, fees, migration safety, or external address continuity.'}

def compare_artifacts(before,after,current):
    errors=[];stale=[];additions=[]
    for name,b in before.items():
        a=after.get(name)
        if not a:errors.append({'contract':name,'kind':'missing_artifact'});continue
        for category in ('functions','events'):
            for n,x in b[category].items():
                if n not in a[category]:errors.append({'contract':name,'member':n,'kind':'missing_'+category})
                elif x!=a[category][n]:errors.append({'contract':name,'member':n,'kind':'changed_'+category})
            additions.extend({'contract':name,'member':n,'kind':'added_'+category} for n in a[category].keys()-b[category].keys())
        c=next((c for c in current['contracts'] if c['name']==name),None)
        if c and not any(x['sha256']==c['sourceSha256'] for x in a['owningSource']):stale.append({'contract':name,'sourcePath':c['path'],'artifactFile':a['file'],'reason':'Artifact owning-source SHA does not match the current source file; rebuild before treating compiled ABI as current.'})
    return {'compatible':not errors,'breakingChanges':errors,'additions':additions,'staleArtifacts':stale,'stageNote':'Noir-generated outputs.structs.functions supplies the user ABI at either raw or transpiled stage. Compiler-generated protocol methods are retained separately, not compared across compiler stages.'}

def source_files(ref=None):
    if ref:
        paths=git('ls-tree','-r','--name-only',ref).splitlines()
    else:
        # Frozen source-only candidates intentionally carry no Git metadata.
        # Inventory current regular files there; the pinned baseline remains
        # separately SHA-authenticated by run(), never inferred from this scan.
        tracked=set(git('ls-files').splitlines()) if (ROOT/'.git').exists() else set()
        def current_files(directory):
            if not directory.exists():return
            for child in directory.iterdir():
                if child.is_symlink() or child.name in {'.git','node_modules','target','dist','.next','__pycache__'}:continue
                if child.is_dir():yield from current_files(child)
                elif child.suffix in {'.nr','.toml','.ts','.tsx','.js','.mjs'}:yield str(child.relative_to(ROOT))
        for directory in ['contracts','client/src','packages','server/src']:
            tracked.update(current_files(ROOT/directory))
        paths=sorted(tracked)
    files={}
    for p in paths:
        if not (p.startswith(('contracts/','client/src/','packages/','server/src/')) and p.endswith(('.nr','.toml','.ts','.tsx','.js','.mjs'))):continue
        try:files[p]=git('show',ref+':'+p) if ref else (ROOT/p).read_text()
        except (OSError,UnicodeError):pass
    return files

def capture(args):
    if BASE.exists():raise SystemExit('Baseline already exists; refusing to replace the pinned reference.')
    ref=git('rev-parse',args.ref).strip();files=source_files(ref);inv=inventory(files);refs=external_references(files)
    needed={p for p in files if p.startswith('contracts/') and p.endswith(('.nr','.toml'))}
    needed.update(r['path'] for r in refs['references']);needed.add('contracts/scripts/deploy/storageAuthorizationExpectations.ts')
    manifest={'gitCommit':ref,'sources':{},'scope':'All contract Noir sources/manifests plus literal API caller files, frozen from the original Git commit.'}
    for p in sorted(needed):
        if p not in files:continue
        dest=BASE/'sources'/p;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(files[p]);manifest['sources'][p]=sha(files[p])
    dump(BASE/'inventory.json',inv);dump(BASE/'external-references.json',refs)
    if args.artifacts:
        arts=artifact_inventory(pathlib.Path(args.artifacts));dump(BASE/'artifacts.json',arts)
        manifest['artifacts']={n:{'sha256':a['sha256'],'owningSourceMatchesSnapshot':any(x['sha256']==next(c['sourceSha256'] for c in inv['contracts'] if c['name']==n) for x in a['owningSource'])} for n,a in arts.items()}
    manifest['metadataSha256']={p.name:sha(p.read_bytes()) for p in BASE.glob('*.json') if p.name!='manifest.json'}
    dump(BASE/'manifest.json',manifest);print(json.dumps({'baselineCommit':ref,'contracts':len(inv['contracts']),'frozenFiles':len(manifest['sources'])}))

def run(args):
    manifest=json.loads((BASE/'manifest.json').read_text())
    for p,h in manifest['sources'].items():
        if sha((BASE/'sources'/p).read_bytes())!=h:raise SystemExit('Pinned baseline source changed: '+p)
    for p,h in manifest.get('metadataSha256',{}).items():
        if sha((BASE/p).read_bytes())!=h:raise SystemExit('Pinned baseline metadata changed: '+p)
    before=json.loads((BASE/'inventory.json').read_text());files=source_files();after=inventory(files);report=compare(before,after);report['baselineCommit']=manifest['gitCommit'];report['sourceTreeSha256']=sha(json.dumps({c['path']:c['sourceSha256'] for c in after['contracts']},sort_keys=True))
    refs=external_references(files)
    if args.artifacts and (BASE/'artifacts.json').exists():report['compiledAbi']=compare_artifacts(json.loads((BASE/'artifacts.json').read_text()),artifact_inventory(pathlib.Path(args.artifacts)),after)
    dump(DOCS/'current-inventory.json',after);dump(DOCS/'external-references.json',refs);dump(DOCS/'compatibility-report.json',report)
    writer_rows=[]
    for c in after['contracts']:
        for f in c['functions']:
            if f['kind'] in ('public','private','utility') and (f['directWrites'] or f['transitiveExternalWrites']):writer_rows.append({'contract':c['name'],'function':f['name'],'kind':f['kind'],'path':c['path'],'line':f['line'],'attributes':f['attributes'],'directWrites':f['directWrites'],'transitiveExternalWrites':f['transitiveExternalWrites']})
    dump(DOCS/'writers.json',writer_rows)
    coverage=[]
    for c in before['contracts']:
        for f in c['functions']:
            if f['kind'] not in ('public','private','utility'):continue
            original=before['surfaces'][c['name']]['functions'][f['name']]
            candidate=after['surfaces'].get(c['name'],{}).get('functions',{}).get(f['name'])
            coverage.append({'contract':c['name'],'function':f['name'],'kind':f['kind'],'originalPath':c['path'],'originalLine':f['line'],'present':candidate is not None,'exactSourceApi':candidate==original,'externalMutations':f['transitiveExternalWrites'],'sourceReferences':[r for r in refs['references'] if r.get('method')==f['name']],'runtimeEquivalence':'Not inferred from structural API coverage; see separate executable regression and action receipt reports.'})
    dump(DOCS/'coverage.json',{'referenceCommit':manifest['gitCommit'],'originalMethodCount':len(coverage),'preservedMethodCount':sum(row['exactSourceApi'] for row in coverage),'methods':coverage})
    print(json.dumps({'contracts':len(after['contracts']),'originalExternalFunctions':sum(len(x['functions']) for x in before['surfaces'].values()),'currentExternalFunctions':sum(len(x['functions']) for x in after['surfaces'].values()),'breakingChanges':len(report['breakingChanges']),'behaviorReviews':len(report['behaviorChangesRequiringReview']),'unresolvedExternalCalls':len(after['unresolvedExternalCalls']),'compiledAbi':{k:len(v) if isinstance(v,list) else v for k,v in report.get('compiledAbi',{}).items() if k!='stageNote'}},indent=2))
    if args.strict and (not report['compatible'] or (args.artifacts and (not report['compiledAbi']['compatible'] or report['compiledAbi']['staleArtifacts']))):return 1
    return 0

def main():
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='command',required=True)
    c=sub.add_parser('capture');c.add_argument('--ref',default='HEAD');c.add_argument('--artifacts')
    c=sub.add_parser('check');c.add_argument('--artifacts');c.add_argument('--strict',action='store_true')
    a=p.parse_args();return capture(a) if a.command=='capture' else run(a)
if __name__=='__main__':sys.exit(main())
