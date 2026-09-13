#!/usr/bin/env python3
"""All original Core private circuits; original public settlement with guarded live reads.

Every typed Config/store call and assertion position survives exact restoration.
Only the four remaining original Core public paths add canonical read alternatives.
Reveal retains its already-audited V7 route. No new privileged writer is introduced.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import re
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('original_core_reveal',HERE/'optimize-core-reveal.py')
reveal=importlib.util.module_from_spec(spec);spec.loader.exec_module(reveal)
ACTIONS={'core':tuple((name,name+'_public') for name in ['refresh_planet','upgrade_planet','withdraw_silver','initialize_player','reveal_location'])}
PUBLICS={public for _,public in ACTIONS['core']}
MARKER='        let state_backend_address = self.storage.state_backend.read();'
KINDS={'world_storage':1,'player_storage':2,'planet_storage':3,'planet_revealed_coords_storage':4,'planet_events_storage':5,'planet_artifacts_storage':6,'arrival_storage':7,'artifact_storage':8,'artifact_location_storage':9}
def optimize_public(body):
    # Read the additive backend pointer after the original timestamp assertion.
    anchor = '        assert_public_timestamp(timestamp, actual_timestamp);'
    assert body.count(anchor) == 1
    result = body.replace(anchor, anchor + '\n        let state_backend_address = self.storage.state_backend.read();', 1)
    reads = []
    pattern = r'self\.view\(\s*(\w+)\.(verify_hashes_batch|verify_hash|is_initialized)\((.*?)\)\s*\)'
    def replace(match):
        store, method, raw_args = match.groups()
        if store not in KINDS:
            return match.group()
        kind = KINDS[store]
        args = [arg.strip() for arg in raw_args.split(',') if arg.strip()]
        assert all(re.fullmatch(r'[A-Za-z_0-9]+', value) for value in args), args
        base = f'state_backend_address, {store}.target_contract'
        if method == 'verify_hashes_batch':
            assert len(args) == 3
            optimized = f'::state_backend_readonly::public_read::verify_hashes_batch_20({base}, {", ".join(args)})'
        else:
            key = args[0] + ('.to_field()' if kind == 2 else '')
            if method == 'verify_hash':
                assert len(args) == 2
                optimized = f'::state_backend_readonly::public_read::verify_hash({base}, {key}, {args[1]})'
            else:
                assert len(args) == 1
                optimized = f'::state_backend_readonly::public_read::is_initialized({base}, {key})'
        recognized = f'(if state_backend_address.is_zero() {{ false }} else {{ ::state_backend_readonly::public_read::get_namespace_kind({base}) == {kind} }})'
        replacement = f'(if {recognized} {{ {optimized} }} else {{ {match.group()} }})'
        reads.append({'store': store, 'kind': kind, 'method': method, 'arguments': args,
                      'original': match.group(), 'replacement': replacement})
        return replacement
    result = re.sub(pattern, replace, result, flags=re.S)
    assert reads
    return result, reads


def baseline(parser):return reveal.baseline_functions('core',parser)

def route_body(public,parser):
    original=baseline(parser)[public]['body']
    if public=='reveal_location_public':return reveal.optimized_body(public,original)
    return optimize_public(original)[0]

def is_active(definition):return definition['name'] in PUBLICS and MARKER in definition['body']

def restore_original(source,definition,parser):
    if not is_active(definition):return definition
    if definition['name']=='reveal_location_public':return reveal.restore_original(source,definition,parser)
    expected=baseline(parser)[definition['name']]
    _,records=optimize_public(expected['body'])
    body=definition['body']
    for record in records:
        assert body.count(record['replacement'])==1,(definition['name'],'Unknown canonical read change')
        body=body.replace(record['replacement'],record['original'],1)
    assert body.count('\n'+MARKER)==1
    body=body.replace('\n'+MARKER,'',1)
    restored=dict(definition);restored['body']=body;restored['full']=definition['header']+'{'+body+'}'
    return restored

def apply_original_path(source,package,parser):
    if package!='core':return source
    original=baseline(parser);current=parser.functions(source);edits=[]
    for private,public in ACTIONS['core']:
        for name in [private,public]:
            old,initial=current[name],original[name]
            assert parser.digest(old['header'])==parser.digest(initial['header']),(name,'Original API changed')
            body=initial['body'] if name==private else route_body(public,parser)
            edits.append((old['start'],old['body_end']+1,initial['header']+'{'+body+'}'))
    obsolete=[public+'_prepared' for _,public in ACTIONS['core']]
    obsolete+=['_legacy_'+public for _,public in ACTIONS['core']]
    obsolete+=['initialize_player_new_public_prepared','refresh_planet_empty_public_prepared','_validate_reveal_shared']
    for name in obsolete:
        assert name not in original
        if name in current:
            old=current[name];edits.append((old['start'],old['body_end']+1,''))
    for start,end,text in sorted(edits,reverse=True):source=source[:start]+text+source[end:]
    nargo=HERE.parents[1]/'contracts/system/core/Nargo.toml'
    before=nargo.read_text();old='libs = { path = "../../libs" }';new='libs = { path = "../../prospect_original_libs" }'
    assert (old in before) != (new in before),'Unexpected Core libs alias'
    after=before.replace(old,new)
    if after!=before:nargo.write_text(after)
    return source

def verify_retained_worker(root):
    manifest=json.loads((HERE/'generated/retained-core-worker.json').read_text())
    for relative,expected in manifest['files'].items():
        assert hashlib.sha256((root/relative).read_bytes()).hexdigest()==expected,('Unused CoreWorker changed',relative)
