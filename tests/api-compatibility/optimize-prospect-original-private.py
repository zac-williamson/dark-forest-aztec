#!/usr/bin/env python3
"""Source-only V7 Prospect route; original private body and local fallback.

The canonical branch is recovered from the authenticated V6 generated source.
Only two scalar plan records change from private-prepared roots to full public
hashing. No extra self call, private enqueue, or supplied actor is introduced.
"""
import hashlib
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent
ACTIONS={'artifact_prospect':('prospect_planet','prospect_planet_public')}
PRIVATE,PUBLIC=ACTIONS['artifact_prospect']
PREPARED=PUBLIC+'_prepared'
LEGACY='_legacy_'+PUBLIC
PROVENANCE=HERE/'snapshots/v7-prospect-v6/provenance.json'
ROOT_STATES=[(6,'new_planet_artifacts_state'),(5,'new_planet_events_state')]


def frozen_functions(parser):
    provenance=json.loads(PROVENANCE.read_text())
    info=provenance['v6ProspectSnapshot']
    raw=(HERE.parents[1]/info['path']).read_bytes()
    assert hashlib.sha256(raw).hexdigest()==info['sha256'],'V6 Prospect snapshot changed'
    return parser.functions(raw.decode())


def baseline_functions(parser):
    relative='contracts/system/artifact_prospect/src/main.nr'
    manifest=json.loads((HERE/'baseline/manifest.json').read_text())
    raw=(HERE/'baseline/sources'/relative).read_bytes()
    assert hashlib.sha256(raw).hexdigest()==manifest['sources'][relative]
    return parser.functions(raw.decode())


def route_body(parser):
    frozen=frozen_functions(parser)
    full=frozen[PREPARED]['body']
    marker='        let state_backend_address = self.storage.state_backend.read();'
    assert full.count(marker)==1
    body='\n'+full[full.index(marker):]
    for namespace,state in ROOT_STATES:
        before=f'write_plan.set({namespace}, location_id, prepared_{state}_root, true, {state}.serialize())'
        after=f'write_plan.set({namespace}, location_id, 0, false, {state}.serialize())'
        assert body.count(before)==1,(state,'Unexpected V6 root record')
        body=body.replace(before,after,1)
    assert 'prepared_payload' not in body and 'prepared_new_' not in body
    assert 'self.enqueue_self.' not in body and 'self.context.this_address()' not in body
    assert body.count('self.internal.'+LEGACY+'(')==1
    assert 'self.view(config.' not in body
    # Every record/callback and check except these two root flags stays V6-exact.
    restored=body
    for namespace,state in ROOT_STATES:
        restored=restored.replace(f'write_plan.set({namespace}, location_id, 0, false, {state}.serialize())',
          f'write_plan.set({namespace}, location_id, prepared_{state}_root, true, {state}.serialize())',1)
    assert restored=='\n'+full[full.index(marker):]
    return body


def is_active(definition):
    return definition['name']==PUBLIC and 'let state_backend_address = ' in definition['body']


def restore_original(source,definition,parser):
    assert is_active(definition)
    baseline=baseline_functions(parser)
    assert parser.digest(definition['header'])==parser.digest(baseline[PUBLIC]['header'])
    assert parser.digest(definition['body'])==parser.digest(route_body(parser)),'Prospect canonical adapter changed'
    helper=parser.functions(source)[LEGACY]
    assert parser.digest(helper['body'])==parser.digest(baseline[PUBLIC]['body']),'Prospect original local fallback changed'
    return dict(baseline[PUBLIC])


def apply_original_path(source,package,parser):
    if package not in ACTIONS:return source
    current=parser.functions(source);baseline=baseline_functions(parser);edits=[]
    for name,body in [(PRIVATE,baseline[PRIVATE]['body']),(PUBLIC,route_body(parser))]:
        old=current[name]
        assert parser.digest(old['header'])==parser.digest(baseline[name]['header'])
        edits.append((old['start'],old['body_end']+1,baseline[name]['header']+'{'+body+'}'))
    assert parser.digest(current[LEGACY]['body'])==parser.digest(baseline[PUBLIC]['body'])
    if PREPARED in current:
        old=current[PREPARED];edits.append((old['start'],old['body_end']+1,''))
    for start,end,replacement in sorted(edits,reverse=True):source=source[:start]+replacement+source[end:]
    return source
