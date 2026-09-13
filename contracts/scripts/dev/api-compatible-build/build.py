#!/usr/bin/env python3
"""Adapted V8 20-class build. Default is read-only preflight; execution is explicit.

The input tree is never mutated. Only five generated binding files may change in
the new build copy. Every native invocation passes through the exact root guard.
"""
from pathlib import Path
import argparse,base64,gzip,hashlib,importlib.util,json,os,re,shutil,subprocess,sys,tomllib
from dependencies import verify as verify_dependencies

HERE=Path(__file__).resolve().parent
sha=lambda b:hashlib.sha256(b).hexdigest()
FACADES=[('world','WorldStorage'),('player','PlayerStorage'),('planet','PlanetStorage'),('planet_revealed_coords','PlanetRevealedCoordsStorage'),('planet_events','PlanetEventsStorage'),('planet_artifacts','PlanetArtifactsStorage'),('arrival','ArrivalStorage'),('artifact','ArtifactStorage'),('artifact_location','ArtifactLocationStorage')]
SYSTEMS=[('admin','Admin'),('core','Core'),('move','Move'),('artifact_action','ArtifactAction'),('artifact_find','ArtifactFind'),('artifact_prospect','ArtifactProspect'),('artifact_valut','ArtifactValut')]
WORKERS=[('core_settlement_worker','CoreSettlementWorker'),('vault_settlement_worker','VaultSettlementWorker')]
ORIGINAL=[('config','Config'),*FACADES,*SYSTEMS]
BACKEND=('game_state_backend','GameStateBackend')
ENTRIES=[*ORIGINAL,*WORKERS,BACKEND]
BINDINGS=['contracts/libs/src/config_class.nr','contracts/prospect_original_libs/src/config_class.nr','contracts/settlement_workers/core/src/system_class.nr','contracts/settlement_workers/vault/src/system_class.nr','contracts/state_backend/src/trusted_classes.nr']
GUARD_SHA='f9576397d7db197b3607dac8a574d43a7963f086126f8b3199a89222d3711075'
KEYS_SHA='5a10dd43264601fbb3b946af861446cb07e46a928cc80a8b76eb968b3526beb4'
def require(ok,message):
 if not ok:raise ValueError(message)
def filename(entry):return '-'.join(entry)+'.json'
def identity_evidence(initial,final):
 require(initial['classId']==final['classId'],f'Class changed after Backend binding: {final["file"]}')
 return {'file':final['file'],'classIdStable':True,'initialArtifactSHA256':initial['sha256'],'finalArtifactSHA256':final['sha256'],'artifactBytesIdentical':initial['sha256']==final['sha256']}
def load_module(name,p):
 spec=importlib.util.spec_from_file_location(name,p);m=importlib.util.module_from_spec(spec);sys.modules[name]=m;spec.loader.exec_module(m);return m
api=load_module('check',HERE/'reference/api.py')
facade_layout=load_module('verify_facade_layout',HERE/'reference/verify_facade_layout.py')
backend_layout=load_module('verify_backend_layout',HERE/'reference/verify_backend_layout.py')
def pinned_file(row):
 p=Path(row['path']);require(p.is_file() and not p.is_symlink(),f'Not a regular pinned file: {p}');b=p.read_bytes();require(sha(b)==row['sha256'],f'Pin drift: {p}');return b
def dump(p,obj):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(obj,indent=2)+'\n')
def sources(root,manifest,allow_bindings=False):
 result={}
 for n,h in manifest.items():
  p=root/n;require(p.is_file() and not p.is_symlink(),f'Missing/symlinked input {n}');result[n]=sha(p.read_bytes())
  if not (allow_bindings and n in BINDINGS):require(result[n]==h,f'Frozen input changed: {n}')
 for directory in ['contracts','vendor']:
  for p in (root/directory).rglob('*'):
   if {'target','node_modules'} & set(p.relative_to(root).parts):continue
   require(not p.is_symlink(),f'Symlink in source closure: {p}')
   if p.is_file() and (p.suffix=='.nr' or p.name=='Nargo.toml'):require(str(p.relative_to(root)) in manifest,f'Unlisted compiler input: {p}')
 return result
def one_sdk_origin(root,manifest):
 origins=[]
 for n in manifest:
  if n.startswith('contracts/') and n.endswith('Nargo.toml'):
   p=root/n
   for name,dep in tomllib.loads(p.read_text()).get('dependencies',{}).items():
    if name=='aztec':
     require(set(dep)=={'path'},f'Mixed Aztec origin: {n}');origins.append((p.parent/dep['path']).resolve())
    elif 'git' in dep:raise ValueError(f'Unreviewed game Git dependency: {n}:{name}')
    if 'path' in dep:require((p.parent/dep['path']/'Nargo.toml').is_file(),f'Missing local dependency: {n}:{name}')
 require(len(origins)==26 and set(origins)=={(root/'vendor/aztec').resolve()},'Expected26 identical local Aztec origins')
 sdk=tomllib.loads((root/'vendor/aztec/Nargo.toml').read_text())['dependencies']
 require(sdk=={'protocol_types':{'git':'https://github.com/AztecProtocol/aztec-packages','tag':'v5.0.1','directory':'noir-projects/noir-protocol-circuits/crates/types'},'sha256':{'tag':'v0.3.0','git':'https://github.com/noir-lang/sha256'},'poseidon':{'tag':'v0.3.0','git':'https://github.com/noir-lang/poseidon'}},'Unreviewed SDK dependency graph')
def source_inventory(root,manifest):return api.inventory({n:(root/n).read_text() for n in manifest if n.startswith('contracts/') and n.endswith(('.nr','.toml'))})
def literal_routes(root,manifest):
 rows=[];backend=filename(BACKEND);system_names=dict(SYSTEMS)
 for n in manifest:
  if not n.startswith('contracts/') or not n.endswith('.nr'):continue
  text=api.clean((root/n).read_text());found=list(re.finditer(r'from_signature\(\s*"([^"\n]+)"\s*,?\s*\)',text))
  require(len(found)==len(re.findall(r'\bfrom_signature\s*\(',text)),f'Nonliteral/manual selector needs explicit review: {n}')
  for m in found:
   signature=m.group(1);method=signature.split('(',1)[0]
   if method in ['commit_plan_small','commit_plan_medium','commit_plan','try_settle_give_spaceships','try_settle_initialize_new','try_settle_refresh_empty','try_settle_move_move','try_settle_move_move_empty']:target=backend
   elif n=='contracts/system/core/src/main.nr' and method in ['try_initialize_player_public_prepared','try_refresh_planet_public_prepared','try_upgrade_planet_public_prepared','try_withdraw_silver_public_prepared']:target=filename(WORKERS[0])
   elif n=='contracts/system/artifact_valut/src/main.nr' and method in ['try_deposit_artifact_public_prepared','try_withdraw_artifact_public_prepared','try_give_spaceships_public_prepared']:target=filename(WORKERS[1])
   elif n.startswith('contracts/system/') and method.endswith('_public'):
    package=n.split('/')[2];require(package in system_names,f'Unknown self-call source {n}');target=filename((package,system_names[package]))
   else:raise ValueError(f'Unclassified raw selector, review required: {n}: {method}')
   rows.append({'source':n,'offset':m.start(),'signature':signature,'method':method,'target':target})
 require(rows,'No raw selector inventory');return rows
PRIVATE_METHOD_PREFIX='__aztec_nr_internals__'
def private_inventory(data):
 # Native processing removes this exact compiler prefix once. Do not fuzzy-match
 # names or use dict comprehensions that can hide duplicate normalized entries.
 result={};seen=set()
 for f in data['functions']:
  raw_name=f['name'];require(isinstance(raw_name,str),'Invalid method name')
  name=raw_name.removeprefix(PRIVATE_METHOD_PREFIX)
  require(re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*',name) is not None,'Invalid normalized method name')
  require(name not in seen,f'Duplicate normalized method name: {name}');seen.add(name)
  require(type(f['is_unconstrained']) is bool,f'Invalid constrained flag: {name}')
  attrs=f.get('custom_attributes',[]);require(isinstance(attrs,list),f'Invalid ABI attributes: {name}')
  constrained=not f['is_unconstrained'];private='abi_private' in attrs
  require(constrained==private,f'Constrained/abi_private disagreement: {name}')
  if private:
   require(not ({'abi_public','abi_utility'} & set(attrs)),f'Conflicting private ABI attributes: {name}')
   result[name]=f
 return result
def check_private(data,reference,known,check_keys):
 if reference:require(data['noir_version']==reference['noir_version'],'Pinned private compiler version changed')
 current=private_inventory(data)
 expected=private_inventory(reference) if reference else {}
 require(current.keys()==expected.keys(),'Private method inventory changed')
 rows=[]
 for name,f in current.items():
  raw=gzip.decompress(base64.b64decode(f['bytecode'],validate=True));digest=sha(raw)
  require(digest in known,f'Unknown private circuit {name}')
  require(raw==gzip.decompress(base64.b64decode(expected[name]['bytecode'],validate=True)),f'Unexpected private identity {name}')
  if check_keys:
   key=base64.b64decode(f['verification_key'],validate=True)
   require(key==base64.b64decode(expected[name]['verification_key'],validate=True),f'Cached native key differs for {name}')
   require(sha(key)==known[digest]['keySha256'],f'Key not in authenticated whitelist: {name}')
  rows.append({'method':name,'decompressedBytecodeSHA256':digest,'cachedKeySHA256':known[digest]['keySha256']})
 return rows
def config_binding(initial,allow_unbound_touch=False):
 cid=lambda e:initial[filename(e)]['classId']
 artifact=('artifact','ArtifactStorage');location=('artifact_location','ArtifactLocationStorage')
 if not allow_unbound_touch:require(filename(artifact) in initial and filename(location) in initial,'Both actual touch facade classes required')
 artifact_class=cid(artifact) if filename(artifact) in initial else '0'
 location_class=cid(location) if filename(location) in initial else '0'
 return '// Generated from the actual native Config and touch facade artifacts before compiling Systems.\n'+f'pub global CONFIG_CLASS: Field = {cid(ORIGINAL[0])};\n'+f'pub global ARTIFACT_TOUCH_CLASS: Field = {artifact_class};\n'+f'pub global LOCATION_TOUCH_CLASS: Field = {location_class};\n'
def codegen(initial):
 cid=lambda e:initial[filename(e)]['classId']
 out={}
 config=config_binding(initial)
 for n in BINDINGS[:2]:out[n]=config
 for n,entry in zip(BINDINGS[2:4],[('core','Core'),('artifact_valut','ArtifactValut')]):out[n]='// Generated immutable initiating System class.\n'+f'pub global SYSTEM_CLASS: Field = {cid(entry)};\n'
 out[BINDINGS[4]]='// Generated from the immutable native artifacts by build-api-compatible.mjs.\n// Full public hash validation remains mandatory for every other writer.\n'+f'pub global CONFIG_CLASS: Field = {cid(ORIGINAL[0])};\n'+f'pub global WORKER_CLASSES: [Field; 2] = [{", ".join(cid(e) for e in WORKERS)}];\n'+f'pub global SYSTEM_CLASSES: [Field; 7] = [{", ".join(cid(e) for e in SYSTEMS)}];\n'+f'pub global FACADE_CLASSES: [Field; 9] = [{", ".join(cid(e) for e in FACADES)}];\n'+'pub fn contains(id: Field) -> bool {\n    (id != 0) & ('+' | '.join(f'(id == SYSTEM_CLASSES[{i}])' for i in range(7))+')\n}\n'
 return out
def preflight(plan):
 root=Path(plan['sourceRoot']).resolve();manifest=json.loads(pinned_file(plan['sourceManifest']))
 require(isinstance(manifest,dict) and len(manifest)==349,'Expected final349-input manifest')
 require('vendor/LICENCE' in manifest,'SDK licence missing from input hashes')
 sources(root,manifest);one_sdk_origin(root,manifest)
 tooling=json.loads(pinned_file(plan['toolingManifest']))
 for n,h in tooling.items():require(sha((HERE/n).read_bytes())==h,f'Tooling changed: {n}')
 lock=json.loads(pinned_file(plan['dependencyLock']));verify_dependencies(lock)
 for item in plan['toolchain'].values():pinned_file(item)
 require(set(['nargo','python','node','guard','stdlibAbi','stdlibContract','constants','jsPackageJson','jsDependencyLock','nativeProcessor'])<=set(plan['toolchain']),'Metadata JS toolchain entry and lock pins are mandatory')
 require(plan['toolchain']['guard']['sha256']==GUARD_SHA,'Only exact approved root guard is supported')
 require(sha((HERE/'reference/known-private-keys.json').read_bytes())==KEYS_SHA,'Known-key manifest changed')
 require(plan['validators'],'A reviewed candidate-specific semantic/source validator is mandatory')
 for row in plan['validators']:
  require(row.get('name') and row.get('script') and row.get('files'),'Empty source validation is forbidden')
  for f in row['files']:pinned_file(f)
  require(any(f['path']==row['script'] for f in row['files']),'Validator script is not pinned')
  require(Path(row['script']).suffix=='.py','Only reviewed source Python validators supported')
 references={n:json.loads(pinned_file(v)) for n,v in plan['privateReferences'].items()}
 require(set(references)=={filename(e) for e in SYSTEMS},'All seven private-bearing Systems require exact reference artifacts')
 inventory=source_inventory(root,manifest);old=json.loads((HERE/'reference/original-inventory.json').read_text());report=api.compare(old,inventory)
 baseline_manifest=json.loads((HERE/'reference/original-manifest.json').read_text())
 for n,dest in [('inventory.json','original-inventory.json'),('artifacts.json','original-artifacts.json')]:require(sha((HERE/'reference'/dest).read_bytes())==baseline_manifest['metadataSha256'][n],f'Original reference manifest mismatch: {n}')
 require(sum(len(c['functions']) for c in old['surfaces'].values())==447,'Original API reference inventory changed')
 require(report['compatible'] and not inventory['unresolvedExternalCalls'],'Original447 API/unresolved-call failure')
 return root,manifest,lock,references,report,literal_routes(root,manifest)
def build(plan,plan_sha):
 root,manifest,lock,references,source_report,routes=preflight(plan)
 output=Path(plan['output']).resolve();require(not output.exists(),'Output must be a new directory')
 require(output!=root and root not in output.parents,'Output must be outside frozen input tree')
 output.mkdir(parents=True);work=output/'build-source';logs=output/'logs';logs.mkdir();bindings=[]
 env={**os.environ,'RAYON_NUM_THREADS':'2','HARDWARE_CONCURRENCY':'2'}
 guard_config={'nativeProcessor':plan['toolchain']['nativeProcessor'],'knownKeys':{'path':str(HERE/'reference/known-private-keys.json'),'sha256':KEYS_SHA},'vkCache':plan['vkCache']}
 guard_path=output/'cached-only-config.json';dump(guard_path,guard_config)
 env.update(DF_CACHED_ONLY_CONFIG=str(guard_path),DF_CACHED_ONLY_CONFIG_SHA256=sha(guard_path.read_bytes()))
 def run(argv,label,cwd):
  log=logs/(label+'.log')
  with log.open('w') as f:r=subprocess.run(argv,cwd=cwd,env=env,stdout=f,stderr=subprocess.STDOUT)
  require(r.returncode==0,f'{label} failed; preserved {log}')
  return log
 for row in plan['validators']:run([plan['toolchain']['python']['path'],row['script'],*row.get('args',[])],'source-'+row['name'],root)
 # Validators cannot mutate any compile input, including the external SDK closure.
 sources(root,manifest);verify_dependencies(lock)
 for n in manifest:
  p=work/n;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes((root/n).read_bytes())
 dump(output/'plan.json',plan);dump(output/'input-manifest.json',manifest);dump(output/'source-api.json',source_report);dump(output/'raw-routes-plan.json',routes)
 known=json.loads((HERE/'reference/known-private-keys.json').read_text())['keys'];initial={};final=[];private_rows={};identity_rows=[]
 def generate(name,text,reason):
  p=work/name;old=sha(p.read_bytes());p.write_text(text);bindings.append({'path':name,'beforeSHA256':old,'afterSHA256':sha(p.read_bytes()),'reason':reason})
 def compile_native(entry,phase):
  name=filename(entry);sources(work,manifest,True);verify_dependencies(lock)
  if entry in SYSTEMS:
   expected=config_binding(initial)
   for n in BINDINGS[:2]:require((work/n).read_text()==expected,'System compilation requires both actual touch facade classes: '+n)
  run([plan['toolchain']['nargo']['path'],'compile','--package',entry[0],'--force'],f'{phase}-compile-{entry[0]}',work/'contracts')
  raw=work/'contracts/target'/name;require(raw.is_file(),f'Missing genuine compiler artifact {name}')
  data=json.loads(raw.read_text());check_private(data,references.get(name),known,False)
  dest=output/phase/name;dest.parent.mkdir(exist_ok=True);shutil.copyfile(raw,dest)
  run([plan['toolchain']['python']['path'],plan['toolchain']['guard']['path'],'aztec_process','-i',str(dest)],f'{phase}-native-{entry[0]}',work/'contracts')
  native=json.loads(dest.read_text());private_rows[name]=check_private(native,references.get(name),known,True)
  row_path=output/phase/(name+'.metadata.json')
  run([plan['toolchain']['node']['path'],str(HERE/'native-checks.mjs'),'metadata',str(dest),plan['jsResolutionRoot'],str(row_path)],f'{phase}-metadata-{entry[0]}',HERE)
  row=json.loads(row_path.read_text());require(row['passed'] and row['file']==name,'Invalid native metadata result')
  for spec,key in [('@aztec/stdlib/abi','stdlibAbi'),('@aztec/stdlib/contract','stdlibContract'),('@aztec/constants','constants')]:
   pin=plan['toolchain'][key];require(row['sdkEntries'][spec]=={'path':str(Path(pin['path']).resolve()),'sha256':pin['sha256']},f'Loaded metadata SDK entry changed: {spec}')
  require(row['sha256']==sha(dest.read_bytes()),'Native artifact changed after metadata check')
  sources(root,manifest);sources(work,manifest,True);verify_dependencies(lock);return row
 for entry in ORIGINAL:
  initial[filename(entry)]=compile_native(entry,'initial')
  if entry==ORIGINAL[0]:
   for n in BINDINGS[:2]:generate(n,config_binding(initial,True),'Actual native Config class; touch classes disabled until all facades compile')
  if entry==FACADES[-1]:
   for n in BINDINGS[:2]:generate(n,config_binding(initial),'Actual native Config and both newly compiled touch facade classes')
 for entry,n,system in zip(WORKERS,BINDINGS[2:4],[('core','Core'),('artifact_valut','ArtifactValut')]):
  generate(n,'// Generated immutable initiating System class.\n'+f'pub global SYSTEM_CLASS: Field = {initial[filename(system)]["classId"]};\n','Actual initiating System class')
  initial[filename(entry)]=compile_native(entry,'initial')
 generate(BINDINGS[4],codegen(initial)[BINDINGS[4]],'Actual19 immutable native Config/facade/System/Worker classes')
 backend=compile_native(BACKEND,'final')
 for entry in [*ORIGINAL,*WORKERS]:
  row=compile_native(entry,'identity');identity_rows.append(identity_evidence(initial[filename(entry)],row));final.append(row)
 final.append(backend);require(len(final)==20,'Expected20 full native contracts')
 require(all(row['limits']==final[0]['limits'] for row in final),'Inconsistent pinned native limits')
 candidate=output/'checked-artifacts';candidate.mkdir()
 for row in final:
  source=output/('final' if row['file']==filename(BACKEND) else 'identity')/row['file'];shutil.copyfile(source,candidate/row['file'])
 compiled={row['name']:row for row in (api.artifact_summary(candidate/r['file']) for r in final)}
 current=source_inventory(work,manifest);comparison=api.compare_artifacts(json.loads((HERE/'reference/original-artifacts.json').read_text()),compiled,current)
 require(comparison['compatible'] and not comparison['staleArtifacts'],'Compiled447 API/event or source-provenance mismatch')
 dump(output/'compiled-api.json',comparison)
 backend_layout.verify_backend(candidate/filename(BACKEND),work);facade_layout.verify_facades(candidate,work)
 verify_config(candidate,work)
 names={name:filename((package,name)) for package,name in ENTRIES}
 protections=[{'file':names[c['name']],'method':f['name']} for c in current['contracts'] if c['name'] in names for f in c['functions'] if 'only_self' in f['attributes']]
 require(protections,'Expected original/prepared only_self protections');dump(output/'only-self-plan.json',protections)
 run([plan['toolchain']['node']['path'],str(HERE/'native-checks.mjs'),'routes',str(candidate),plan['jsResolutionRoot'],str(output/'raw-routes-plan.json'),str(output/'raw-selectors.json'),str(output/'only-self-plan.json')],'all-raw-selectors',HERE)
 require(sum(len(v) for v in private_rows.values())==14,'Private audit must cover all14 methods')
 final_sources=sources(work,manifest,True);sources(root,manifest);verify_dependencies(lock)
 for n,text in codegen(initial).items():require((work/n).read_text()==text,f'Generated binding changed: {n}')
 # No codegen/deployable directory exists until every gate passes.
 published=output/'codegen';published.mkdir()
 for row in final:shutil.copyfile(candidate/row['file'],published/row['file'])
 report={'passed':True,'scope':'Full genuine native admission, API/private cached identity and immutable bindings; no fee, proof-latency or deployment claim','planSHA256':plan_sha,'inputSourceFiles':manifest,'sourceFiles':final_sources,'externalDependencies':lock,'codegenInputs':bindings,'sourceRootUnchanged':True,'privateMethods':private_rows,'proofsGenerated':0,'newKeysGenerated':0,'artifacts':final,'classIds':{r['file']:r['classId'] for r in final},'limits':final[0]['limits'],'artifactDirectory':'codegen','secondIdentityPass':19,'identityChecks':identity_rows,'artifactMetadataDifferences':[r['file'] for r in identity_rows if not r['artifactBytesIdentical']],'codegenDirectory':str(published)}
 dump(output/'build-provenance.json',report)
def verify_config(directory,root):
 artifact=json.loads((directory/'config-Config.json').read_text());source=(root/'contracts/config/src/main.nr').read_text()
 embedded=[f['source'] for f in artifact['file_map'].values() if f['path'].replace('\\','/').endswith('/config/src/main.nr')]
 require(embedded==[source],'Config compiled source mismatch')
 slots=facade_layout.storage_slots(artifact,'Config')
 require(slots['planet_default_stats_hash']==299 and slots['move_configuration_root']==304,'Config SLOAD slots changed')
 # Keep the original predicate check without importing or running a generator.
 m=re.search(r'fn verify_move_configuration\([^\)]*\)[^{]*\{([^}]+)\}',source);require(m is not None,'Config predicate absent')
 expected='(self.storage.move_configuration_root.read() == common_root) & (self.storage.planet_default_stats_hash.at(level).read() == default_stats_root)'
 require(api.norm(m.group(1))==api.norm(expected),'Config predicate changed')
 backend=(root/'contracts/state_backend/src/main.nr').read_text()
 require('let config_common_slot: Field = 304;' in backend and 'let config_stats_map_slot: Field = 299;' in backend,'Backend Config slots changed')
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('plan',type=Path);ap.add_argument('--execute',action='store_true');ap.add_argument('--reviewed-plan-sha');a=ap.parse_args();raw=a.plan.read_bytes();plan=json.loads(raw)
 if a.execute:
  require(a.reviewed_plan_sha==sha(raw),'Execution requires the exact reviewed plan hash');build(plan,sha(raw))
 else:
  result=preflight(plan);print(json.dumps({'passed':True,'scope':'Read-only preflight only; validators/compiler/native processor not executed','sourceFiles':len(result[1]),'rawSelectors':len(result[-1])}))
