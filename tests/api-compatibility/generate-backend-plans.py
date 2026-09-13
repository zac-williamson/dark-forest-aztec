#!/usr/bin/env python3
"""Generate the selected API-compatible public settlement paths.

Core retains its exact cached V7 private/compact source and shares four V8
public typed bodies in process. Vault retains its three prepared plan routes.
Reveal, Safe Owner, Prospect, Find, Activate and Deactivate keep original private
functions. Checks restore all original public bodies and every guarded fallback;
private-bytecode identity, runtime equivalence and fees remain separate gates.
"""
import argparse, functools, hashlib, importlib.util, json, re
from pathlib import Path
import artifact_touch
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('settlements',HERE/'generate-backend-settlements.py')
s=importlib.util.module_from_spec(spec);spec.loader.exec_module(s)
p=s.prepared; ROOT=p.ROOT
admin_spec=importlib.util.spec_from_file_location('admin_reads',HERE/'optimize-admin-reads.py')
admin_reads=importlib.util.module_from_spec(admin_spec);admin_spec.loader.exec_module(admin_reads)
reveal_spec=importlib.util.spec_from_file_location('core_reveal',HERE/'optimize-core-reveal.py')
core_reveal=importlib.util.module_from_spec(reveal_spec);reveal_spec.loader.exec_module(core_reveal)
prospect_spec=importlib.util.spec_from_file_location('original_prospect',HERE/'optimize-prospect-original-private.py')
original_prospect=importlib.util.module_from_spec(prospect_spec);prospect_spec.loader.exec_module(original_prospect)
actions_spec=importlib.util.spec_from_file_location('original_artifact_actions',HERE/'optimize-artifact-actions-original-private.py')
original_artifact_actions=importlib.util.module_from_spec(actions_spec);actions_spec.loader.exec_module(original_artifact_actions)
core_spec=importlib.util.spec_from_file_location('original_core',HERE/'optimize-core-original-private.py')
original_core=importlib.util.module_from_spec(core_spec);core_spec.loader.exec_module(original_core)
find_spec=importlib.util.spec_from_file_location('original_find',HERE/'optimize-find-original-private.py')
original_find=importlib.util.module_from_spec(find_spec);find_spec.loader.exec_module(original_find)
selected_spec=importlib.util.spec_from_file_location('selected_core',HERE/'optimize-core-selected.py')
selected_core=importlib.util.module_from_spec(selected_spec);selected_spec.loader.exec_module(selected_core)
ORIGINAL_PRIVATE_ACTIONS={**core_reveal.ACTIONS,**original_prospect.ACTIONS}

def original_private_actions(package):
    if package=='core':return (('reveal_location','reveal_location_public'),)
    if package in original_find.ACTIONS:return original_find.ACTIONS[package]
    original=ORIGINAL_PRIVATE_ACTIONS.get(package)
    return ((original,) if original else ())+original_artifact_actions.ACTIONS.get(package,())

def original_private_provider(package):
    if package=='core':return original_core
    if package in original_find.ACTIONS:return original_find
    if package in original_artifact_actions.ACTIONS:return original_artifact_actions
    if package in original_prospect.ACTIONS:return original_prospect
    return core_reveal

def original_private_public_body(package,public,baseline):
    if package=='core':return original_core.route_body(public,p)
    if package in original_find.ACTIONS:return original_find.route_body(public,p)
    if package in original_artifact_actions.ACTIONS:return original_artifact_actions.route_body(public,p)
    if package in original_prospect.ACTIONS:return original_prospect.route_body(p)
    return core_reveal.optimized_body(public,baseline[public]['body'])
DEST=HERE/'generated/backend-plans.nr'; MANIFEST=HERE/'generated/backend-plan-transform.json'
TYPES={2:('player','Player',8),3:('planet','Planet',32),4:('planet_revealed_coords','PlanetRevealedCoords',4),5:('planet_events','PlanetEvents',22),6:('planet_artifacts','PlanetArtifacts',22),8:('artifact','Artifact',13),9:('artifact_location','ArtifactLocation',3)}
WORKERS={'core':('core','core_settlement_worker','CoreSettlementWorker'), 'artifact_valut':('vault','vault_settlement_worker','VaultSettlementWorker')}
FRESH_INIT_FIELDS=('sender','location_id','timestamp','config_hashes','planet_default_stats_hash','world_hash','new_planet','new_player','prepared_new_planet_root','prepared_new_player_root')
EMPTY_REFRESH_FIELDS=('location','timestamp','planet_state_hash','planet_artifacts_state_hash','planet_events_state_hash','new_planet','new_planet_artifacts_state','new_planet_events_state','prepared_new_planet_root','prepared_new_planet_artifacts_state_root','prepared_new_planet_events_state_root')

def fresh_init_schema(schema):
    selected=[];offset=0
    for name in FRESH_INIT_FIELDS:
        field=next(field for field in schema if field['name']==name)
        selected.append(dict(field,originalOffset=field['offset'],offset=offset))
        offset+=field['width']
    assert offset==56
    return selected

def empty_refresh_schema(schema):
    selected=[];offset=0
    for name in EMPTY_REFRESH_FIELDS:
        field=next(field for field in schema if field['name']==name)
        selected.append(dict(field,originalOffset=field['offset'],offset=offset))
        offset+=field['width']
    assert offset==84
    return selected

def empty_refresh_system_schema(schema):
    # The canonical zero-count setter ignores these location words, but an
    # arbitrary original configured store may inspect them on the legacy path.
    selected=empty_refresh_schema(schema)
    locations=next(field for field in schema if field['name']=='new_arrival_artifact_locations')
    assert locations['width']==60
    return selected+[dict(locations,originalOffset=locations['offset'],offset=84)]

def branches(body):
    """Find input-only if/else block conditions surrounding original operations."""
    clean=p.mask(body,strings=True); result=[]
    for m in re.finditer(r'\bif\b',clean):
        start=clean.find('{',m.end()); end=p.closing(body,start,'{','}')
        condition=body[m.end():start].strip()
        # Every current continuation branch tests original arguments or pure guards.
        assert not any(word in condition for word in ['self.', 'plan_results', 'new_planet.owner']),condition
        result.append((start,end,condition))
        tail=re.match(r'\s*else\s*\{',clean[end+1:])
        if tail:
            other=end+1+tail.end()-1;other_end=p.closing(body,other,'{','}')
            result.append((other,other_end,'!('+condition+')'))
    return result

def calls(body):
    result=[]
    for m in re.finditer(r'self\.(view|call)\((\w+)\.(\w+)\s*\(',p.mask(body,strings=True)):
        mode,store,method=m.groups()
        if store=='config':continue
        assert store in s.NAMESPACES,(store,method)
        start=body.index('(',m.end()-1);end=p.closing(body,start,'(',')')
        outer=p.closing(body,body.index('(',m.start()),'(',')')
        args=p.split_arguments(body[start+1:end]); index,kind,_=s.NAMESPACES[store]
        result.append(dict(start=m.start(),end=outer+1,mode=mode,store=store,method=method,args=args,index=index,kind=kind))
    return result

def backend():
    out='''// Generated generic plan execution. Original System continuations retain all game checks.
    #[inline_never]
    #[contract_library_method]
    unconstrained fn _resolve_plan_actor(context: aztec::context::PublicContext, claimed_actor: AztecAddress) -> AztecAddress {
        let self = __aztec_nr_internals__create_public_self_from_context(context);
        let caller = self.msg_sender();
        let current = get_contract_instance_current_class_id_avm(caller);
        assert(current.is_some(), "Only audited settlement worker");
        let caller_id = current.unwrap().to_field();
        if super::trusted_classes::contains(caller_id) { caller } else {
            let system_class = get_contract_instance_current_class_id_avm(claimed_actor);
            assert(system_class.is_some(), "Only audited settlement worker");
            let system_id = system_class.unwrap().to_field();
            assert((caller_id != 0) & (system_id != 0), "Only audited settlement worker");
            assert(
                ((caller_id == super::trusted_classes::WORKER_CLASSES[0]) & (system_id == super::trusted_classes::SYSTEM_CLASSES[1]))
                | ((caller_id == super::trusted_classes::WORKER_CLASSES[1]) & (system_id == super::trusted_classes::SYSTEM_CLASSES[6])),
                "Only audited settlement worker",
            );
            claimed_actor
        }
    }
    #[inline_never]
    #[contract_library_method]
    unconstrained fn _commit_state_plan(context: aztec::context::PublicContext, addresses:[AztecAddress;10], required_mask:u16, words:[Field], length:u32, actor:AztecAddress) {
        let self = __aztec_nr_internals__create_public_self_from_context(context);
        assert(self.internal._can_settle(addresses,required_mask), "Settlement namespaces changed");
        let end = 12 + length;
        assert(end <= words.len(), "Write plan length exceeded");
        let mut cursor = 12;
        while cursor < end {
            assert(cursor + 3 <= end, "Truncated write header");
            let descriptor = words[cursor] as u32;
            assert(descriptor as Field == words[cursor], "Invalid write descriptor");
            assert(descriptor < 128, "Invalid write descriptor");
            let namespace = descriptor & 15;
            let prepared = descriptor & 16 != 0;
            let auth_only = descriptor & 32 != 0;
            let batch = descriptor & 64 != 0;
            assert(!(batch & (auth_only | prepared)), "Invalid batch descriptor");
            assert(namespace >= 1 & namespace <= 9, "Invalid write namespace");
            assert((required_mask & (1u16 << (namespace as u16))) != 0, "Unvalidated write namespace");
            let ns = addresses[namespace];
            let key = words[cursor+1];
            let root = words[cursor+2];
            cursor += 3;
            if auth_only | batch {
                self.internal._assert_authorized(ns,actor);
                let count = key as u32;
                let maximum = root as u32;
                assert(count as Field == key, "Invalid batch count");
                assert(maximum as Field == root, "Invalid batch maximum");
                assert(((namespace == 9) & ((maximum == 5) | (maximum == 20))) | ((namespace == 8) & (maximum == 5)), "Invalid batch kind");
                assert(count <= maximum, "count exceeds batch size");
                if batch {
                    assert(cursor < end, "Truncated batch header");
                    let active=words[cursor] as u32;
                    assert(active as Field == words[cursor], "Invalid active count");
                    assert(active <= count, "Active count exceeds batch count");
                    cursor+=1;
                    if namespace == 9 {
                        assert(cursor + active*4 <= end, "Truncated location batch");
                        let mut ids=[0;20];
                        let mut fields=[[0;3];20];
                        for i in 0..active {
                            ids[i]=words[cursor];
                            fields[i]=[words[cursor+1],words[cursor+2],words[cursor+3]];
                            assert(ids[i]!=0,"Invalid compact batch ID");
                            cursor+=4;
                        }
                        self.internal._emit_artifact_location_batch_max20(ns,ids,fields,active);
                    } else {
                        assert(cursor + active*14 <= end, "Truncated artifact batch");
                        let mut ids=[0;5];
                        let mut fields=[[0;13];5];
                        for i in 0..active {
                            ids[i]=words[cursor];
                            for j in 0..13 { fields[i][j]=words[cursor+1+j]; }
                            assert(ids[i]!=0,"Invalid compact batch ID");
                            cursor+=14;
                        }
                        self.internal._emit_artifact_batch_max5(ns,ids,fields,active);
                    }
                }
            } else {
'''
    for i,(kind,typ,width) in TYPES.items():
        out+=f'''                {'if' if i==2 else 'else if'} namespace == {i} {{
                    assert(cursor + {width} <= end, "Truncated {kind} payload");
                    let fields: [Field;{width}] = [{', '.join('words[cursor+'+str(j)+']' for j in range(width))}];
                    // The audited System serialized canonical typed state before the guarded commit.
                    self.internal._set_{kind}_fields(ns,actor,key,fields,root,prepared);
                    cursor += {width};
                }}
'''
    out+='''                else { assert(false, "Unsupported write namespace"); }
            }
        }
    }
'''
    for capacity, suffix in [(128, '_small'), (172, '_medium'), (384, '')]:
        width=capacity+13
        addresses='['+', '.join(f'AztecAddress::from_field(payload.words[{1+i}])' for i in range(10))+']'
        out+=f'''    #[external("public")]
    fn commit_plan{suffix}(payload: ::libs::field_buffer::FieldBuffer<{width}>) {{
        let actor = _resolve_plan_actor(self.context, AztecAddress::from_field(payload.words[0]));
        let addresses={addresses};
        let required_mask=payload.words[11] as u16;
        let length=payload.words[{width-1}] as u32;
        assert(length <= {capacity}, "Write plan length exceeded");
        _commit_state_plan(self.context,addresses,required_mask,payload.words.as_slice(),length,actor);
    }}
'''
    return out+give_spaceships_backend()+fresh_init_backend()+empty_refresh_backend()


def legacy_name(name): return '_legacy_' + name

def legacy_call(original):
    names=[re.match(r'(?:mut\s+)?(\w+)\s*:',arg).group(1) for arg in original['params']]
    return 'self.internal.'+legacy_name(original['name'])+'('+', '.join(names)+');'

def expanded_current_definition(source, name):
    if name=='update_artifact':source=artifact_touch.restore_vault(source,p)
    current=p.functions(source); original=dict(current[name]); helper=current.get(legacy_name(name))
    if name.removesuffix('_public') in selected_core.ACTIONS and '_'+name+'_local' in current:
        return selected_core.expanded_definition(source,name,p,original_core)
    if original_core.is_active(original):
        return original_core.restore_original(source,original,p)
    if original_find.is_active(original):
        return original_find.restore_original(source,original,p)
    if original_artifact_actions.is_active(original):
        return original_artifact_actions.restore_original(source,original,p)
    if original_prospect.is_active(original):
        return original_prospect.restore_original(source,original,p)
    original=core_reveal.restore_original(source,original,p)
    if helper:
        assert p.digest(original['body'])==p.digest(legacy_call(original)),('Unexpected legacy wrapper',name)
        original['body']=helper['body']
        original['full']=original['header']+'{'+helper['body']+'}'
    if name in admin_reads.ACTIONS:
        original['body']=admin_reads.restore_body(name,original['body'])
        original['full']=original['header']+'{'+original['body']+'}'
    return original

def remove_canonical_batch_guards(body):
    """Undo only pure guards around batch reads, for an independent baseline check."""
    pattern=r'\bif\s+(?:(?:original_arrivals_count|origin_arrivals_count|owned_artifact_count)\s*!=\s*0\s*|::libs::batch_utils::has_nonzero_ids\s*\([^{}]*?\)\s*)\{'
    while True:
        matches=list(re.finditer(pattern,p.mask(body,strings=True)))
        if not matches:return body
        match=matches[-1];start=body.index('{',match.start());end=p.closing(body,start,'{','}')
        assert not re.match(r'\s*else\b',p.mask(body[end+1:],strings=True))
        inner=body[start+1:end]
        operations=calls(inner)
        assert operations and all(op['mode']=='view' and op['method']=='verify_hashes_batch' for op in operations), 'Only canonical batch views may be skipped'
        # Innermost guards are removed first. Their remaining bodies must consist
        # entirely of the original assertions, without writes or other effects.
        remainder=inner
        for assertion in reversed(list(re.finditer(r'\bassert\s*\(',p.mask(inner,strings=True)))):
            close=p.closing(inner,inner.index('(',assertion.start()),'(',')')
            terminator=re.match(r'\s*;',inner[close+1:]);assert terminator
            remainder=remainder[:assertion.start()]+remainder[close+1+terminator.end():]
        assert not p.mask(remainder,strings=True).strip(), 'Unexpected canonical guarded operation'
        body=body[:match.start()]+body[start+1:end]+body[end+1:]

@functools.lru_cache(maxsize=1)
def continuation_sources():
    """Use the pinned original Git snapshot for every legacy public body.

    The earlier prepared snapshot contains safe canonical-only batch-read skips.
    Authenticate it separately and prove that removing only those guards restores
    the original body. Never use that historical optimization as legacy fallback.
    """
    first=json.loads(p.MANIFEST.read_text())
    baseline_manifest=json.loads((HERE/'baseline/manifest.json').read_text())
    result={}
    for package,entry in first['packages'].items():
        relative=f'contracts/system/{package}/src/main.nr'
        raw=(HERE/'baseline/sources'/relative).read_bytes()
        assert hashlib.sha256(raw).hexdigest()==baseline_manifest['sources'][relative]
        baseline=p.functions(raw.decode())
        historical=p.functions((HERE/'snapshots/prepared-original-stores'/package/'src/main.nr').read_text())
        for record in entry['continuations']:
            name=record['original'];original=baseline[name];canonical=historical[name]
            assert name not in result,('Ambiguous original continuation',name)
            assert p.digest(canonical['full'])==entry['originalFunctions'][name]['functionHash']
            assert p.digest(original['header'])==p.digest(canonical['header'])
            assert p.digest(remove_canonical_batch_guards(canonical['body']))==p.digest(original['body']),('Unaudited canonical change',package,name)
            result[name]={'original':original,'canonical':canonical,'source':relative,
                          'sourceSha256':baseline_manifest['sources'][relative],
                          'gitCommit':baseline_manifest['gitCommit']}
    return result

def original_definition(source, name):
    current=expanded_current_definition(source,name)
    pinned=continuation_sources().get(name)
    if pinned:
        assert p.digest(current['header'])==p.digest(pinned['original']['header']),(name,'Original header changed')
        return dict(pinned['original'])
    return current

def type_width(typ):
    typ=typ.strip()
    if typ in ['Field','bool','u8','u16','u32','u64','u128','AztecAddress']: return 1
    widths={value[1]:value[2] for value in TYPES.values()}
    widths['PlanetEvent']=1
    if typ in widths:return widths[typ]
    if typ in STRUCTS:return sum(type_width(field_type) for _,field_type in STRUCTS[typ][1])
    match=re.fullmatch(r'\[\s*(.+)\s*;\s*(\d+)\s*\]',typ)
    assert match, ('Unknown prepared type',typ)
    return type_width(match.group(1))*int(match.group(2))

def storage_structs():
    result={}
    for module in ['planet','artifact','player','world','arrival']:
        text=(ROOT/f'contracts/types/src/storage/{module}.nr').read_text()
        for match in re.finditer(r'pub struct (\w+)\s*\{',p.mask(text)):
            start=text.index('{',match.start());end=p.closing(text,start,'{','}')
            fields=[]
            for value in p.split_arguments(text[start+1:end]):
                field=re.fullmatch(r'pub\s+(\w+)\s*:\s*(.+)',value)
                assert field,('Unsupported storage field',value)
                fields.append(field.groups())
            result[match.group(1)]=(f'::types::storage::{module}::{match.group(1)}',fields)
    return result

STRUCTS=storage_structs()

def direct_value(typ, offset):
    typ=typ.strip()
    if typ=='Field':return f'prepared_payload[{offset}]'
    if typ=='bool':return f'(prepared_payload[{offset}] == 1)'
    if typ in ['u8','u16','u32','u64','u128']:return f'(prepared_payload[{offset}] as {typ})'
    if typ=='AztecAddress':return f'AztecAddress::from_field(prepared_payload[{offset}])'
    match=re.fullmatch(r'\[\s*(.+)\s*;\s*(\d+)\s*\]',typ)
    if match:
        inner,count=match.groups();width=type_width(inner)
        return '['+', '.join(direct_value(inner,offset+i*width) for i in range(int(count)))+']'
    path,fields=STRUCTS[typ];values=[]
    for name,field_type in fields:
        values.append(name+': '+direct_value(field_type,offset));offset+=type_width(field_type)
    return path+' { '+', '.join(values)+' }'


def selector_type(typ):
    typ=typ.strip()
    if typ in ['Field','bool','u8','u16','u32','u64','u128']:return typ
    if typ=='AztecAddress':return '(Field)'
    match=re.fullmatch(r'\[\s*(.+)\s*;\s*(\d+)\s*\]',typ)
    if match:return '['+selector_type(match.group(1))+';'+match.group(2)+']'
    return '('+','.join(selector_type(t) for _,t in STRUCTS[typ][1])+')'


def original_raw_fallback(original,schema):
    types=[re.match(r'(?:mut\s+)?\w+\s*:\s*(.+)',param).group(1) for param in original['params']]
    width=sum(type_width(typ) for typ in types)
    signature=original['name']+'('+','.join(selector_type(typ) for typ in types)+')'
    assert schema[len(types)-1]['offset']+schema[len(types)-1]['width']==width
    return f'''            let mut original_calldata:[Field;{width+1}]=[0;{width+1}];
            let original_selector = comptime {{ aztec::protocol::abis::function_selector::FunctionSelector::from_signature("{signature}") }};
            original_calldata[0]=original_selector.to_field();
            for fallback_i in 0..{width} {{ original_calldata[1+fallback_i]=prepared_payload[fallback_i]; }}
            let result = ::libs::public_call::call(self.context.this_address(),original_calldata);
            assert(result.len() == 0, "Unexpected original continuation result");
'''


def flat_details(original,record):
    params=original['params']+[p.root_name(state)+': Field' for state in record['states']]
    args=p.enqueue(record['preparedEnqueue'],record['prepared'])[2]
    assert len(args)==len(params)
    cursor=0; decoded=[]; schema=[]
    for param in params:
        match=re.match(r'(mut\s+)?(\w+)\s*:\s*(.+)',param)
        mutable,name,typ=match.groups();width=type_width(typ)
        value=direct_value(typ,cursor)
        decoded.append('        let '+('mut ' if mutable else '')+name+': '+typ+' = '+value+';')
        schema.append({'name':name,'type':typ,'offset':cursor,'width':width});cursor+=width
    enqueue='{\n            let mut prepared_payload: [Field;'+str(cursor)+'] = [0;'+str(cursor)+'];\n'
    for index,(arg,field) in enumerate(zip(args,schema)):
        part='prepared_part_'+str(index)
        enqueue += '            let '+part+' = ('+arg+').serialize();\n'
        enqueue += '            for prepared_i in 0..'+str(field['width'])+' { prepared_payload['+str(field['offset'])+' + prepared_i] = '+part+'[prepared_i]; }\n'
    enqueue += '            self.enqueue_self.'+record['prepared']+'(::libs::field_buffer::FieldBuffer { words: prepared_payload });\n        }'
    if record['private']=='initialize_player':
        selected=fresh_init_schema(schema)
        compact='{\n            let mut compact_payload:[Field;56]=[0;56];\n'
        for index,field in enumerate(selected):
            arg=args[next(i for i,item in enumerate(schema) if item['name']==field['name'])]
            compact+=f'            let compact_part_{index}=({arg}).serialize();\n'
            compact+=f'            for compact_i in 0..{field["width"]} {{ compact_payload[{field["offset"]}+compact_i]=compact_part_{index}[compact_i]; }}\n'
        compact+='            self.enqueue_self.initialize_player_new_public_prepared(::libs::field_buffer::FieldBuffer { words: compact_payload });\n        }'
        condition=args[next(i for i,field in enumerate(schema) if field['name']=='planet_state_hash')]
        enqueue='{\n            if ('+condition+') == 0 '+compact+' else '+enqueue+'\n        }'
    if record['private']=='refresh_planet':
        selected=empty_refresh_system_schema(schema)
        compact='{\n            let mut compact_payload:[Field;144]=[0;144];\n'
        for index,field in enumerate(selected):
            arg=args[next(i for i,item in enumerate(schema) if item['name']==field['name'])]
            compact+=f'            let compact_part_{index}=({arg}).serialize();\n'
            compact+=f'            for compact_i in 0..{field["width"]} {{ compact_payload[{field["offset"]}+compact_i]=compact_part_{index}[compact_i]; }}\n'
        compact+='            self.enqueue_self.refresh_planet_empty_public_prepared(::libs::field_buffer::FieldBuffer { words: compact_payload });\n        }'
        condition=args[next(i for i,field in enumerate(schema) if field['name']=='original_arrivals_count')]
        enqueue='{\n            if ('+condition+') == 0 '+compact+' else '+enqueue+'\n        }'
    return cursor,'\n'.join(decoded),enqueue,schema


def transform(package,source,record):
    current=p.functions(source);original=original_definition(source,record['original']);existing=current[record['prepared']]
    width,decoded,flat_enqueue,schema=flat_details(original,record)
    # The pure batch-read skips are valid only after canonical namespace checks.
    # Legacy fallback below always uses the immutable original body instead.
    body=continuation_sources()[record['original']]['canonical']['body']; ops=calls(body); edits=[]; group=0
    for op in ops:
        args=op['args']; idx=op['index']; method=op['method']; key=args[0]
        if op['kind']=='player':key=f'({key}).to_field()'
        if op['mode']=='view':
            assert method in ['verify_hash','verify_hashes_batch','is_initialized'],method
            if method=='verify_hashes_batch':
                replacement=f'::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[{idx}], '+', '.join(args)+')'
            else:
                extra=', '+args[1] if method=='verify_hash' else ''
                replacement=f'::state_backend_readonly::public_read::{method}(state_backend_address, plan_addresses[{idx}], {key}'+extra+')'
            group+=1
        else:
            assert method in ['set','set_arrival_locations_max20','set_spaceships_max5','set_spaceship_locations_max5'],method
            if method=='set':
                state=args[1]; is_prepared=state in record['states'];root=p.root_name(state) if is_prepared else '0'
                replacement=f'write_plan.set({idx}, {key}, {root}, '+('true' if is_prepared else 'false')+f', {state}.serialize())'
            else:
                ids,states,count=args; maximum=20 if method=='set_arrival_locations_max20' else 5
                replacement='{\n'+f'            let batch_start=write_plan.start_batch({idx}, {count}, {maximum});\n'
                replacement+=f'            let bounded_count = if ({count}) <= {maximum} {{ {count} }} else {{ {maximum} }};\n'
                replacement+=f'            for plan_i in 0..bounded_count {{ if {ids}[plan_i] != 0 {{\n'
                replacement+=f'                write_plan.append_batch_item(batch_start, {ids}[plan_i], {states}[plan_i].serialize());\n'
                replacement+='            } }\n        }'
        edits.append((op['start'],op['end'],replacement))
    assert group<=16
    for start,end,replacement in reversed(edits):body=body[:start]+replacement+body[end:]
    for store in s.NAMESPACES:body=re.sub(p.store_declaration(store),'',body)
    # Use the already resolved Config address, preserving its original declaration point.
    body=re.sub(p.store_declaration('config'),'let config = Config::at(plan_addresses[0]);',body)
    mask=sum(1<<i for i in sorted({op['index'] for op in ops}))
    used=set(re.findall(r'self\s*\.\s*storage\s*\.\s*(\w+)\s*\.\s*read\(\)',original['body']))
    addresses=['self.storage.'+field+'.read()' if field in used else 'AztecAddress::zero()' for field in s.FIELDS]
    route='\n        let prepared_payload = prepared_payload.words;\n'+decoded+'''
        let state_backend_address = self.storage.state_backend.read();
        let mut settled_by_backend = false;
        if state_backend_address != AztecAddress::zero() {
            let plan_addresses = [
'''+''.join('                '+address+',\n' for address in addresses)+'''            ];
'''+f'''
            let supported = ::state_backend_readonly::public_read::can_settle(state_backend_address, plan_addresses, {mask});
            if supported {{
                let mut write_plan = ::libs::state_plan::WritePlan::new();
'''+body+f'''
                _commit_plan_for_system(self.context, state_backend_address, plan_addresses, {mask}, write_plan);
                settled_by_backend = true;
            }}
        }}
        if !settled_by_backend {{\n            '''+legacy_call(original)+'\n        }\n'
    header=existing['header']
    arg_start=existing['paren']-existing['start'];arg_end=existing['end_paren']-existing['start']
    header=header[:arg_start+1]+'prepared_payload: ::libs::field_buffer::FieldBuffer<'+str(width)+'>'+header[arg_end:]
    worker=None
    if package in WORKERS:
        _,_,worker_class=WORKERS[package]
        worker_body=body.replace('self.storage.admin.read()', 'system_admin')
        assert 'self.storage.' not in worker_body, (package,record['prepared'],'unforwarded worker storage')
        worker='''    #[external("public")]
    fn try_'''+record['prepared']+'''(payload: ::libs::field_buffer::FieldBuffer<'''+str(width+12)+'''>) -> bool {
        let caller_class = aztec::oracle::get_contract_instance::get_contract_instance_current_class_id_avm(self.msg_sender());
        assert(caller_class.is_some(), "Only audited system");
        assert(caller_class.unwrap().to_field() == super::system_class::SYSTEM_CLASS, "Only audited system");
'''+'''        let state_backend_address=AztecAddress::from_field(payload.words[0]);
        let plan_addresses=['''+', '.join(f'AztecAddress::from_field(payload.words[{1+i}])' for i in range(10))+'''];
        let system_admin=AztecAddress::from_field(payload.words[11]);
'''+re.sub(r'prepared_payload\[(\d+)\]',lambda m:f'payload.words[{int(m.group(1))+12}]',decoded)+f'''
        let supported = ::state_backend_readonly::public_read::can_settle(state_backend_address, plan_addresses, {mask});
        if supported {{
            let mut write_plan = ::libs::state_plan::WritePlan::new();
'''+worker_body+f'''
            _commit_plan_for_system(self.context, state_backend_address, plan_addresses, {mask}, write_plan);
        }}
        supported
    }}
'''
        route='''
        let prepared_payload = prepared_payload.words;
        let state_backend_address = self.storage.state_backend.read();
        let state_worker_address = self.storage.state_worker.read();
        let mut settled_by_backend = false;
        if (state_backend_address != AztecAddress::zero()) & (state_worker_address != AztecAddress::zero()) {
            let plan_addresses = [
'''+''.join('                '+address+',\n' for address in addresses)+'''            ];
            let system_admin = '''+('self.storage.admin.read()' if 'self.storage.admin.read()' in body else 'AztecAddress::zero()')+''';
            let worker_selector = comptime { aztec::protocol::abis::function_selector::FunctionSelector::from_signature("try_'''+record['prepared']+'''(([Field;'''+str(width+12)+''']))") };
            let mut worker_calldata:[Field;'''+str(width+13)+''']=[0;'''+str(width+13)+'''];
            worker_calldata[0]=worker_selector.to_field();
            worker_calldata[1]=state_backend_address.to_field();
            for worker_i in 0..10 { worker_calldata[2+worker_i]=plan_addresses[worker_i].to_field(); }
            worker_calldata[12]=system_admin.to_field();
            for worker_i in 0..'''+str(width)+''' { worker_calldata[13+worker_i]=prepared_payload[worker_i]; }
            let result = ::libs::public_call::call(state_worker_address,worker_calldata);
            settled_by_backend = _checked_worker_result(result);
        }
        if !settled_by_backend {
'''+original_raw_fallback(original,schema)+'\n        }\n'
        # Full literal general forwarding exceeded the native class limit in
        # independent Core (112216 / paired 113112 bytes) and Vault (102160 bytes) probes.
        # Keep these loops; the compact Core routes retain their fitting small literals.
        if re.search(r'self\.view\(config\.', original['body']):
            # Config is freely configurable in the original API. Only the
            # shipped caller-independent class may observe a Worker caller;
            # custom Config contracts retain the original System caller.
            start=route.index('            let system_admin = ')
            end=route.index('\n        }\n        if !settled_by_backend',start)
            route=route[:start]+'''            if ::libs::config_recognition::supports_config(plan_addresses[0]) {
'''+route[start:end]+'''\n            }'''+route[end:]
    if package=='artifact_valut' and record['prepared']=='give_spaceships_public_prepared':
        assert width==341
        route=give_spaceships_route(original,schema)
    meta=dict(flatEnqueue=flat_enqueue,flatSchema=schema,flatWidth=width,package=package,private=record['private'],prepared=record['prepared'],mask=mask,readGroups=group,operations=ops,bodyHash=p.digest(route),originalBodyHash=p.digest(original['body']))
    if worker is not None:meta['workerFunction']=worker
    return header+'{'+route+'}',meta

def give_spaceships_route(original,schema):
    """Direct settlement; preserve every private output for exact legacy fallback."""
    names=['sender','location_id','timestamp','planet_hash','planet_artifacts_state_hash',
           'planet_events_state_hash','player_hash','new_planet','new_planet_events_state',
           'new_planet_artifacts_state','new_player','spaceships_ids','spaceships',
           'spaceships_locations','prepared_new_planet_root','prepared_new_planet_events_state_root',
           'prepared_new_planet_artifacts_state_root','prepared_new_player_root']
    selected=[next(field for field in schema if field['name']==name)for name in names]
    offsets=[i for field in selected for i in range(field['offset'],field['offset']+field['width'])]
    assert offsets==list(range(0,6))+list(range(107,184))+list(range(244,341))
    namespaces=['player','planet','planet_events','planet_artifacts','artifact','artifact_location']
    fields=['selector.to_field()']+[f'{name}.to_field()'for name in namespaces]
    fields += [f'prepared_payload[{i}]'for i in offsets]
    assert len(fields)==187
    out='''
        let prepared_payload=prepared_payload.words;
        let state_backend_address=self.storage.state_backend.read();
        let mut settled_by_backend=false;
        if state_backend_address != AztecAddress::zero() {
            // The original zero-count Arrival view still calls arbitrary stores.
            // Skip it only for the immutable canonical namespace; otherwise the
            // original System continuation observes the exact configured caller.
            let arrival=self.storage.arrivals_storage_address.read();
            if ::state_backend_readonly::public_read::get_namespace_kind(state_backend_address,arrival)==7 {
'''
    for name in namespaces:
        out+=f'            let {name}=self.storage.{name}_storage_address.read();\n'
    out+='''            let selector=comptime { aztec::protocol::abis::function_selector::FunctionSelector::from_signature("try_settle_give_spaceships(([Field;186]))") };
            let calldata=['''+', '.join(fields)+'''];
            let result=::libs::public_call::call(state_backend_address,calldata);
            settled_by_backend=_checked_worker_result(result);
            }
        }
        if !settled_by_backend {
'''+original_raw_fallback(original,schema)+'''
        }
'''
    return out

def give_spaceships_backend():
    """No new private hashes. Original private GiveSpaceships already requires count0."""
    array=lambda start,width:'['+', '.join(f'payload.words[{i}]'for i in range(start,start+width))+']'
    ship='['+', '.join(f'payload.words[102+i*13+{j}]'for j in range(13))+']'
    location='['+', '.join(f'payload.words[167+i*3+{j}]'for j in range(3))+']'
    return '''
    // The original private System asserts both queue and inventory counts zero.
    // Its complete341-word enqueue is retained for exact custom-store fallback.
    #[external("public")]
    fn try_settle_give_spaceships(payload: ::libs::field_buffer::FieldBuffer<186>) -> bool {
        assert(self.internal._is_prepared_writer(self.msg_sender()), "Only audited system");
        let player=AztecAddress::from_field(payload.words[0]);
        let planet=AztecAddress::from_field(payload.words[1]);
        let planet_events=AztecAddress::from_field(payload.words[2]);
        let planet_artifacts=AztecAddress::from_field(payload.words[3]);
        let artifact=AztecAddress::from_field(payload.words[4]);
        let artifact_location=AztecAddress::from_field(payload.words[5]);
        let supported=(self.storage.kinds.at(player).read()==2)
            & (self.storage.kinds.at(planet).read()==3)
            & (self.storage.kinds.at(planet_events).read()==5)
            & (self.storage.kinds.at(planet_artifacts).read()==6)
            & (self.storage.kinds.at(artifact).read()==8)
            & (self.storage.kinds.at(artifact_location).read()==9);
        if supported {
            let actor=self.msg_sender();
            let sender=payload.words[6];
            let location=payload.words[7];
            assert_public_timestamp(payload.words[8] as u64,self.context.timestamp());
            assert(self.internal._verify_hash(planet,location,payload.words[9]),"planet hash mismatch");
            assert(self.internal._verify_hash(planet_artifacts,location,payload.words[10]),"planet_artifacts hash mismatch");
            assert(self.internal._verify_hash(planet_events,location,payload.words[11]),"planet_events hash mismatch");
            assert(self.internal._verify_hash(player,sender,payload.words[12]),"player hash mismatch");
            self.internal._set_planet_fields(planet,actor,location,'''+array(13,32)+''',payload.words[182],true);
            self.internal._set_planet_events_fields(planet_events,actor,location,'''+array(45,22)+''',payload.words[183],true);
            self.internal._set_planet_artifacts_fields(planet_artifacts,actor,location,'''+array(67,22)+''',payload.words[184],true);
            // Even an empty batch retains its original authorization check.
            self.internal._assert_authorized(artifact_location,actor);
            self.internal._set_player_fields(player,actor,sender,'''+array(89,8)+''',payload.words[185],true);
            self.internal._assert_authorized(artifact,actor);
            let mut ids=[0;5];
            let mut ships=[[0;13];5];
            let mut active=0;
            for i in 0..5 {
                let id=payload.words[97+i];
                if id!=0 {
                    ids[active]=id;
                    ships[active]='''+ship+''';
                    active+=1;
                }
            }
            self.internal._emit_artifact_batch_max5(artifact,ids,ships,active);
            self.internal._assert_authorized(artifact_location,actor);
            let mut locations=[[0;3];5];
            active=0;
            for i in 0..5 {
                if payload.words[97+i]!=0 {
                    locations[active]='''+location+''';
                    active+=1;
                }
            }
            self.internal._emit_artifact_location_batch_max5(artifact_location,ids,locations,active);
        }
        supported
    }
'''

def fresh_init_definitions(source, record):
    original=original_definition(source,'initialize_player_public')
    selected=fresh_init_schema(record['flatSchema'])
    types=[re.match(r'(?:mut\s+)?\w+\s*:\s*(.+)',param).group(1) for param in original['params']]
    original_width=sum(type_width(typ) for typ in types)
    assert original_width==263
    signature=original['name']+'('+','.join(selector_type(typ) for typ in types)+')'
    system='''    #[external("public")] #[only_self]
    fn initialize_player_new_public_prepared(prepared_payload: ::libs::field_buffer::FieldBuffer<56>) {
        let prepared_payload=prepared_payload.words;
        let backend=self.storage.state_backend.read();
        let mut settled=false;
        if !backend.is_zero() {
            if ::libs::config_recognition::supports_config(self.storage.config_storage_address.read()) {
            let selector=comptime { aztec::protocol::abis::function_selector::FunctionSelector::from_signature("try_settle_initialize_new(([Field;60]))") };
'''
    fields=['selector.to_field()']+[f'self.storage.{field}.read().to_field()' for field in s.FIELDS[:4]]
    fields+=[f'prepared_payload[{i}]' for i in range(56)]
    assert len(fields)==61
    system+='            let calldata=['+', '.join(fields)+'];\n'
    system+='''            settled=_checked_worker_result(::libs::public_call::call(backend,calldata));
            }
        }
        if !settled {
            // The original new-planet branch never reads these omitted parameters.
            // Reconstruct its same typed call; the supplied fields remain exact.
            let mut original_calldata:[Field;264]=[0;264];
'''
    for field in selected:
        if field['name'].startswith('prepared_'):continue
        system+=f'            for i in 0..{field["width"]} {{ original_calldata[{field["originalOffset"]+1}+i]=prepared_payload[{field["offset"]}+i]; }}\n'
    system+=f'''            let selector=comptime {{ aztec::protocol::abis::function_selector::FunctionSelector::from_signature("{signature}") }};
            original_calldata[0]=selector.to_field();
            let result=::libs::public_call::call(self.context.this_address(),original_calldata);
            assert(result.len()==0,"Unexpected original continuation result");
        }}
    }}
'''
    return system,''


def fresh_init_backend():
    out='''    #[external("public")]
    fn try_settle_initialize_new(payload: ::libs::field_buffer::FieldBuffer<60>) -> bool {
        assert(self.internal._is_prepared_writer(self.msg_sender()), "Only audited system");
        let config_address=AztecAddress::from_field(payload.words[0]);
        let world=AztecAddress::from_field(payload.words[1]);
        let player=AztecAddress::from_field(payload.words[2]);
        let planet=AztecAddress::from_field(payload.words[3]);
        let supported=(self.storage.kinds.at(world).read()==1)
            & (self.storage.kinds.at(player).read()==2)
            & (self.storage.kinds.at(planet).read()==3);
        if supported {
            assert_public_timestamp(payload.words[6] as u64,self.context.timestamp());
            let config=Config::at(config_address);
'''
    out+='            let config_hashes=['+', '.join(f'payload.words[{7+i}]' for i in range(9))+'];\n'
    out+='''            assert(self.view(config.verify_config_hashes(payload.words[21] as u8,payload.words[16],config_hashes)),"Config hash mismatch");
            assert(!self.internal._is_initialized(player,payload.words[4]),"Player already initialized");
            assert(payload.words[17]!=0,"World state must be initialized");
            assert(self.internal._verify_hash(world,0,payload.words[17]),"World state hash mismatch");
            let actor=self.msg_sender();
'''
    out+='            let planet_fields=['+', '.join(f'payload.words[{18+i}]' for i in range(32))+'];\n'
    out+='            let player_fields=['+', '.join(f'payload.words[{50+i}]' for i in range(8))+'];\n'
    out+='''            self.internal._set_planet_fields(planet,actor,payload.words[5],planet_fields,payload.words[58],true);
            self.internal._set_player_fields(player,actor,payload.words[4],player_fields,payload.words[59],true);
        }
        supported
    }
'''
    return out

def empty_refresh_backend():
    out='''    // The initiating private function selects this path only for count zero.
    #[external("public")]
    fn try_settle_refresh_empty(payload: ::libs::field_buffer::FieldBuffer<88>) -> bool {
        assert(self.internal._is_prepared_writer(self.msg_sender()), "Only audited system");
        let planet=AztecAddress::from_field(payload.words[0]);
        let planet_artifacts=AztecAddress::from_field(payload.words[1]);
        let planet_events=AztecAddress::from_field(payload.words[2]);
        let artifact_location=AztecAddress::from_field(payload.words[3]);
        let supported=(self.storage.kinds.at(planet).read()==3)
            & (self.storage.kinds.at(planet_artifacts).read()==6)
            & (self.storage.kinds.at(planet_events).read()==5)
            & (self.storage.kinds.at(artifact_location).read()==9);
        if supported {
            let actor=self.msg_sender();
            let location=payload.words[4];
            assert_public_timestamp(payload.words[5] as u64,self.context.timestamp());
            assert(self.internal._verify_hash(planet,location,payload.words[6]),"Planet state hash mismatch");
            assert(self.internal._verify_hash(planet_artifacts,location,payload.words[7]),"Planet artifacts state hash mismatch");
            assert(self.internal._verify_hash(planet_events,location,payload.words[8]),"Planet events state hash mismatch");
'''
    for name,offset,width,root in [('planet',9,32,85),('planet_artifacts',41,22,86),('planet_events',63,22,87)]:
        out+='            let '+name+'_fields=['+', '.join(f'payload.words[{offset+i}]' for i in range(width))+'];\n'
        out+=f'            self.internal._set_{name}_fields({name},actor,location,{name}_fields,payload.words[{root}],true);\n'
    out+='''            // The original zero-count batch still checks its writer permission.
            // It occurs after the three typed writes and emits no additional event.
            self.internal._assert_authorized(artifact_location,actor);
        }
        supported
    }
'''
    return out


def empty_refresh_definition(source,record):
    original=original_definition(source,'refresh_planet_public')
    selected=empty_refresh_system_schema(record['flatSchema'])
    types=[re.match(r'(?:mut\s+)?\w+\s*:\s*(.+)',param).group(1) for param in original['params']]
    original_width=sum(type_width(typ) for typ in types)
    assert original_width==242
    signature=original['name']+'('+','.join(selector_type(typ) for typ in types)+')'
    out='''    #[external("public")] #[only_self]
    fn refresh_planet_empty_public_prepared(prepared_payload: ::libs::field_buffer::FieldBuffer<144>) {
        let prepared_payload=prepared_payload.words;
        let backend=self.storage.state_backend.read();
        let mut settled=false;
        if !backend.is_zero() {
            let arrival=self.storage.arrivals_storage_address.read();
            let artifact=self.storage.artifact_storage_address.read();
            if (::state_backend_readonly::public_read::get_namespace_kind(backend,arrival)==7)
                & (::state_backend_readonly::public_read::get_namespace_kind(backend,artifact)==8) {
            let selector=comptime { aztec::protocol::abis::function_selector::FunctionSelector::from_signature("try_settle_refresh_empty(([Field;88]))") };
'''
    fields=['selector.to_field()']+[f'self.storage.{name}_storage_address.read().to_field()' for name in ['planet','planet_artifacts','planet_events','artifact_location']]
    fields+=[f'prepared_payload[{i}]' for i in range(84)]
    assert len(fields)==89
    out+='            let calldata=['+', '.join(fields)+'];\n'
    out+='''            settled=_checked_worker_result(::libs::public_call::call(backend,calldata));
            }
        }
        if !settled {
            // Count-zero hash/ID arrays are provably zero; preserve every location word
            // because an arbitrary configured legacy setter can inspect inactive values.
            let mut original_calldata:[Field;243]=[0;243];
'''
    for field in selected:
        if field['name'].startswith('prepared_'):continue
        out+=f'            for i in 0..{field["width"]} {{ original_calldata[{field["originalOffset"]+1}+i]=prepared_payload[{field["offset"]}+i]; }}\n'
    out+=f'''            let selector=comptime {{ aztec::protocol::abis::function_selector::FunctionSelector::from_signature("{signature}") }};
            original_calldata[0]=selector.to_field();
            let result=::libs::public_call::call(self.context.this_address(),original_calldata);
            assert(result.len()==0,"Unexpected original continuation result");
        }}
    }}
'''
    return out


def system_plan_helpers(delegated=False,full_literal=True,medium=False):
    out="""
    // Build complete calldata once; the guarded backend accepts canonical fields.
    #[inline_never]
    #[contract_library_method]
    unconstrained fn _commit_plan_for_system(
        context: aztec::context::PublicContext,
        backend_address: AztecAddress,
        addresses: [AztecAddress;10],
        required_mask: u16,
        plan: ::libs::state_plan::WritePlan,
    ) {
        let mut self = __aztec_nr_internals__create_public_self_from_context(context);
"""
    capacities = [(128, '_small')] + ([(172, '_medium')] if medium else []) + [(384, '')]
    for capacity, suffix in capacities:
        small = capacity == 128
        offset=1
        width=capacity+12+offset
        method='commit_plan'+suffix
        out+=('        if plan.length <= 128 {\n' if small else
              '        } else if plan.length <= 172 {\n' if capacity == 172 else '        } else {\n')
        out+=f'''            let selector = comptime {{ aztec::protocol::abis::function_selector::FunctionSelector::from_signature("{method}(([Field;{width}]))") }};
'''
        fields=['selector.to_field()','self.msg_sender().to_field()']+[f'addresses[{i}].to_field()' for i in range(10)]
        fields+=['required_mask as Field']+[f'plan.words[{i}]' for i in range(capacity)]+['plan.length as Field']
        assert len(fields)==width+1
        if small or full_literal or capacity == 172:
            out+='            let calldata=['+', '.join(fields)+'];\n'
        else:
            # CoreWorker's full literal payload exceeded the native class limit.
            # Preserve the small hot path while sharing the bounded large copy.
            out+=f'''            let mut calldata:[Field;{width+1}]=[0;{width+1}];
            calldata[0]=selector.to_field();
            calldata[1]=self.msg_sender().to_field();
            for i in 0..10 {{ calldata[2+i]=addresses[i].to_field(); }}
            calldata[12]=required_mask as Field;
            for i in 0..{capacity} {{ if i < plan.length {{ calldata[13+i]=plan.words[i]; }} }}
            calldata[{width}]=plan.length as Field;
'''
        out+='''
            let result=::libs::public_call::call(backend_address,calldata);
            assert(result.len()==0, "Unexpected settlement result");
'''
    out+='        }\n    }\n'
    return out


def worker_source(package,source,records):
    directory,worker_package,worker_class=WORKERS[package]
    prefix=source[:source.index('    #[storage]')]
    prefix=re.sub(r'contract\s+\w+\s*\{', 'pub contract '+worker_class+' {', prefix, count=1)
    prefix=re.sub(r'\s*use ::'+worker_package+r'::'+worker_class+r';', '', prefix)
    prefix='// Generated stateless settlement worker. The actor is its authenticated System caller.\nmod system_class;\n'+prefix
    storage='''    #[storage]
    struct Storage<Context> {
        reserved: PublicMutable<Field,Context>,
    }
    #[external("public")] #[initializer]
    fn constructor() {}
'''
    helpers=system_plan_helpers(delegated=True,full_literal=package!='core',medium=True)
    extra=''
    if package=='core':
        record=next(record for record in records if record['private']=='initialize_player')
        extra=fresh_init_definitions(source,record)[1]
    output=prefix+storage+'\n'.join(record['workerFunction'] for record in records if record['package']==package)+extra+helpers+'\n}\n'
    return '\n'.join(line.rstrip() for line in output.splitlines())+'\n'


def worker_admin_helpers(package):
    helpers='''
    #[inline_never]
    #[contract_library_method]
    unconstrained fn _checked_worker_result(result:[Field]) -> bool {
        // A malformed response cannot bypass the original continuation.
        if result.len()==1 { result[0]==1 } else { false }
    }
    #[external("public")]
    fn set_state_worker(state_worker:AztecAddress) {
        self.internal.assert_admin();
        self.storage.state_worker.write(state_worker);
    }
    #[external("public")] #[view]
    fn get_state_worker() -> AztecAddress {
        self.storage.state_worker.read()
    }
'''
    if package=='core':
        helpers=helpers.replace('#[external("public")] #[view]\n    fn get_state_worker()', '#[external("utility")]\n    unconstrained fn get_state_worker()')
    return helpers


def preserve_blank_line_layout(existing,generated):
    # A Prospect-only experiment must not rewrite other Systems merely because
    # repeated helper replacement accumulates empty lines between definitions.
    lines=lambda text:[line for line in text.splitlines() if line.strip()]
    return existing if lines(existing)==lines(generated) else generated


def generate(apply=False):
    first=json.loads(p.MANIFEST.read_text());records=[]
    prior_manifest=json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {'continuations':[]}
    prior_records={(r['package'],r['private']):r for r in prior_manifest['continuations']}
    for package,entry in first['packages'].items():
        path=ROOT/f'contracts/system/{package}/src/main.nr';source=path.read_text();changes=[]
        if package=='core':
            generated,_=selected_core.render(p)
            if apply:
                path.write_text(generated)
                nargo=path.parents[1]/'Nargo.toml'
                manifest=nargo.read_text().replace('libs = { path = "../../prospect_original_libs" }','libs = { path = "../../libs" }')
                nargo.write_text(manifest)
            selected_core.validate(path.read_text(),p)
            original_core.verify_retained_worker(ROOT)
            continue
        direct_actions = original_private_actions(package)
        direct_privates = {private for private,_ in direct_actions}
        prepared_records = [record for record in entry['continuations'] if record['private'] not in direct_privates]
        if apply:
            for direct_private,_ in direct_actions:
                record = next(record for record in entry['continuations'] if record['private'] == direct_private)
                current = p.functions(source)[direct_private]['full']
                baseline = core_reveal.baseline_functions(package,p)[direct_private]['full']
                if p.digest(current) != p.digest(baseline):
                    previous = prior_records.get((package,direct_private),{}).get('flatEnqueue',record['preparedEnqueue'])
                    assert current.count(previous) == 1, (package,direct_private,'Unexpected previous enqueue')
                    assert p.digest(current.replace(previous,record['originalEnqueue'],1)) == p.digest(baseline), (package,direct_private,'Unaudited private change')
                # Independently validate the existing original public body before replacing it.
                expanded = expanded_current_definition(source,record['original'])
                assert p.digest(expanded['full']) == p.digest(continuation_sources()[record['original']]['original']['full'])
            if direct_actions:
                source = original_private_provider(package).apply_original_path(source,package,p)
            for record in prepared_records:
                original=original_definition(source,record['original'])
                _,_,flat_enqueue,_=flat_details(original,record)
                previous=prior_records.get((package,record['private']),{}).get('flatEnqueue',record['preparedEnqueue'])
                assert source.count(previous)==1,(package,record['private'],'expected previous private enqueue')
                source=source.replace(previous,flat_enqueue,1)
        for record in prepared_records:
            text,meta=transform(package,source,record);records.append(meta)
            existing=p.functions(source)[record['prepared']]
            if apply: changes.append((existing['start'],existing['body_end']+1,text))
            else:assert p.digest(existing['full'])==p.digest(text),(package,record['prepared'],'plan wrapper differs')
            if apply:
                old=p.functions(source)[record['original']]
                original=original_definition(source,record['original'])
                if package in WORKERS:
                    changes.append((old['start'],old['body_end']+1,old['header']+'{'+original['body']+'}'))
                    if legacy_name(record['original']) in p.functions(source):
                        helper=p.functions(source)[legacy_name(record['original'])]
                        changes.append((helper['start'],helper['body_end']+1,''))
                else:
                    changes.append((old['start'],old['body_end']+1,old['header']+'{\n        '+legacy_call(original)+'\n    }'))
                if package not in WORKERS:
                    helper_header=original['header'].replace('#[external("public")]', '#[internal("public")]').replace('#[only_self]', '')
                    helper_header=helper_header.replace('fn '+record['original']+'(', 'fn '+legacy_name(record['original'])+'(')
                    existing_helper=p.functions(source).get(legacy_name(record['original']))
                    start=existing_helper['start'] if existing_helper else source.rfind('}')
                    end=existing_helper['body_end']+1 if existing_helper else start
                    changes.append((start,end,'\n'+helper_header+'{'+original['body']+'}\n'))
        if apply:
            if not MANIFEST.exists():
                dest=HERE/f'snapshots/backend-thirteen-settlements/{package}/src/main.nr';dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(source)
            for start,end,text in sorted(changes,reverse=True):source=source[:start]+text+source[end:]
            if 'use aztec::protocol::traits::FromField;' not in source:
                m=re.search(r'\bcontract\s+\w+\s*\{',source); point=source.index('{',m.start())+1
                source=source[:point]+'\n    use aztec::protocol::traits::FromField;\n'+source[point:]
            if 'use aztec::protocol::traits::Deserialize;' not in source:
                m=re.search(r'\bcontract\s+\w+\s*\{',source); point=source.index('{',m.start())+1
                source=source[:point]+'\n    use aztec::protocol::traits::Deserialize;\n'+source[point:]
            if 'use aztec::protocol::traits::ToField;' not in source:
                m=re.search(r'\bcontract\s+\w+\s*\{',source); point=source.index('{',m.start())+1
                source=source[:point]+'\n    use aztec::protocol::traits::ToField;\n'+source[point:]
            helpers=p.functions(worker_admin_helpers(package) if package in WORKERS else system_plan_helpers(medium=package=='artifact_find'))
            existing_helpers=p.functions(source)
            helper_changes=[]
            for name,definition in helpers.items():
                if name in existing_helpers:
                    existing=existing_helpers[name]
                    helper_changes.append((existing['start'],existing['body_end']+1,definition['full']))
                else:
                    helper_changes.append((source.rfind('}'),source.rfind('}'),'\n'+definition['full']+'\n'))
            for start,end,text in sorted(helper_changes,reverse=True):source=source[:start]+text+source[end:]
            obsolete_read=p.functions(source).get('_read_plan_for_system')
            if obsolete_read:
                source=source[:obsolete_read['start']]+source[obsolete_read['body_end']+1:]
            nargo_path=path.parents[1]/'Nargo.toml';nargo=nargo_path.read_text()
            readonly_dependency='state_backend_readonly = { path = "../../state_backend_readonly" }'
            if readonly_dependency not in nargo:
                nargo+='\n'+readonly_dependency+'\n';nargo_path.write_text(nargo)
            if package in WORKERS:
                directory,worker_package,worker_class=WORKERS[package]
                if 'state_worker: PublicMutable<AztecAddress, Context>,' not in source:
                    source=source.replace('state_backend: PublicMutable<AztecAddress, Context>,','state_backend: PublicMutable<AztecAddress, Context>,\n        state_worker: PublicMutable<AztecAddress, Context>,')
                if 'use ::'+worker_package+'::'+worker_class+';' not in source:
                    source=source.replace('    use ::game_state_backend::GameStateBackend;', '    use ::game_state_backend::GameStateBackend;\n    use ::'+worker_package+'::'+worker_class+';')
                if package=='core' and prepared_records:
                    record=next(record for record in records if record['private']=='initialize_player')
                    fresh=fresh_init_definitions(source,record)[0]
                    old=p.functions(source).get('initialize_player_new_public_prepared')
                    if old:source=source[:old['start']]+fresh+source[old['body_end']+1:]
                    else:source=source[:source.rfind('}')]+fresh+source[source.rfind('}'):]
                    refresh_record=next(record for record in records if record['private']=='refresh_planet')
                    compact_refresh=empty_refresh_definition(source,refresh_record)
                    old=p.functions(source).get('refresh_planet_empty_public_prepared')
                    if old:source=source[:old['start']]+compact_refresh+source[old['body_end']+1:]
                    else:source=source[:source.rfind('}')]+compact_refresh+source[source.rfind('}'):]
                existing_helpers=p.functions(source)
                for old_helper in sorted((existing_helpers[n] for n in p.functions(system_plan_helpers()) if n in existing_helpers),key=lambda f:f['start'],reverse=True):
                    source=source[:old_helper['start']]+source[old_helper['body_end']+1:]
                nargo_path=path.parents[1]/'Nargo.toml';nargo=nargo_path.read_text()
                dependency=worker_package+' = { path = "../../settlement_workers/'+directory+'" }'
                if dependency not in nargo:nargo+='\n'+dependency+'\n';nargo_path.write_text(nargo)
                if package!='core':
                    worker_path=ROOT/'contracts/settlement_workers'/directory
                    (worker_path/'src').mkdir(parents=True,exist_ok=True)
                    worker_nargo=re.sub(r'^'+worker_package+r'.*\n','',nargo,flags=re.M).replace('name = "'+package+'"','name = "'+worker_package+'"')
                    (worker_path/'Nargo.toml').write_text(worker_nargo)
                    (worker_path/'src/main.nr').write_text(worker_source(package,source,records))
                    class_path=worker_path/'src/system_class.nr'
                    if not class_path.exists():class_path.write_text('// Replaced by the reproducible final class-freeze build.\npub global SYSTEM_CLASS: Field = 0x1000000000000000000000000000000000000000000000000000000000000001;\n')
            if package=='core':
                old=p.functions(source)['get_state_backend']
                new='''    #[external("utility")]
    unconstrained fn get_state_backend() -> AztecAddress {
        self.storage.state_backend.read()
    }'''
                source=source[:old['start']]+'\n'+new+source[old['body_end']+1:]
            source='\n'.join(line.rstrip() for line in source.splitlines())+'\n'
            source=preserve_blank_line_layout(path.read_text(),source)
            if package=='artifact_valut':source=artifact_touch.apply_vault(source,p)
            path.write_text(source)
        for name,definition in p.functions(worker_admin_helpers(package) if package in WORKERS else system_plan_helpers(medium=package=='artifact_find')).items():
            assert p.digest(p.functions(source)[name]['full']) == p.digest(definition['full']), (package,name,'plan helper differs')
        if package=='core':
            original_core.verify_retained_worker(ROOT)
            for obsolete in ['initialize_player_new_public_prepared','refresh_planet_empty_public_prepared']:
                assert obsolete not in p.functions(source),(package,obsolete,'Unreachable continuation retained')
        elif package in WORKERS:
            worker_path=ROOT/'contracts/settlement_workers'/WORKERS[package][0]/'src/main.nr'
            assert worker_path.read_text()==worker_source(package,source,records),(package,'worker source differs')
        if package=='artifact_valut':artifact_touch.validate_vault(source,p)
        # Original functions (and private output hash bindings) remain exact.
        current=p.functions(source);private_records={r['private']:r for r in prepared_records}
        for direct_private,public in direct_actions:
            baseline = core_reveal.baseline_functions(package,p)
            assert current[direct_private]['body'] == baseline[direct_private]['body'], (package,direct_private,'Private body must be byte-identical to original Git')
            expected_body = original_private_public_body(package,public,baseline)
            assert p.digest(current[public]['body']) == p.digest(expected_body), (package,public,'Direct canonical reads differ')
            assert public+'_prepared' not in current
        for name,expected in entry['originalFunctions'].items():
            fn=expanded_current_definition(source,name);assert p.digest(fn['header'])==expected['signatureHash'],(package,name,'signature')
            restored=fn['full']
            if name in private_records:
                record=private_records[name]
                original=original_definition(source,record['original'])
                _,_,flat_enqueue,_=flat_details(original,record)
                assert restored.count(flat_enqueue)==1
                restored=restored.replace(flat_enqueue,record['originalEnqueue'],1)
            pinned=continuation_sources().get(name)
            expected_hash=p.digest(pinned['original']['full']) if pinned else expected['functionHash']
            assert p.digest(restored)==expected_hash,(package,name,'original changed')
    origins={name:{key:value for key,value in info.items()if key not in ('original','canonical')}
             for name,info in continuation_sources().items()}
    metadata={'selectedCore':selected_core.metadata(p),'scope':'Source generation only; runtime fee and behavioral verification required. Core uses exact V7 cached private bodies and compact routes; its four full routes share exact V8 typed public bodies in process. Reveal, Safe Owner, Prospect, Find, Activate and Deactivate retain byte-identical original private bodies. The unused CoreWorker source is retained and hash checked; only Vault routes through a worker. Other original public continuations restore the immutable Git baseline; historical canonical-only read guards are independently checked.','originalPrivateActions':[{'package':package,'private':private,'public':public} for package in first['packages'] for private,public in original_private_actions(package)],'legacyOrigins':origins,'continuations':records}
    if apply:
        DEST.write_text(backend());MANIFEST.write_text(json.dumps(metadata,indent=2)+'\n');generate(False)
    else:
        assert DEST.read_text()==backend(),'Backend plan engine differs'
        assert json.loads(MANIFEST.read_text())==metadata,'Manifest differs'
        print(f'PASS: {len(records)} plan wrappers, untouched original APIs and private output bindings')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);group=parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--apply',action='store_true');group.add_argument('--check',action='store_true')
    args=parser.parse_args();generate(args.apply)
