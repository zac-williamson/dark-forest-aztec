#!/usr/bin/env python3
"""Validate all constrained/utility reader slots against native compiler metadata."""
import argparse
import json
from pathlib import Path
import re
import check
from verify_facade_layout import storage_slots, verify_facades

ROOT=Path(__file__).resolve().parents[2]
BACKEND_FIELDS=['kinds','arrivals','counters']

def verify_backend(artifact,root=ROOT):
    artifact=Path(artifact);root=Path(root)
    slots=storage_slots(json.loads(artifact.read_text()),'GameStateBackend')
    source=(root/'contracts/state_backend/src/main.nr').read_text()
    actual=check.parse_source('contracts/state_backend/src/main.nr',source)['storage']
    assert [f['name'] for f in actual]==BACKEND_FIELDS,'Unexpected Backend fields/order'
    assert slots==dict(zip(BACKEND_FIELDS,range(1,4))),('Unexpected Backend compiler layout',slots)
    readers=(root/'contracts/state_backend_readonly/src/lib.nr').read_text()
    constants={n:int(v) for n,v in re.findall(r'pub global (\w+): Field = (\d+);',readers)}
    facade_constants={'FACADE_ROOTS':3,'FACADE_ADMIN':1,'FACADE_AUTHORIZED':4,'FACADE_INDEXES':5,'FACADE_LISTS':6,'FACADE_COUNT':7}
    for name,slot in facade_constants.items():assert constants.pop(name)==slot,('Wrong facade reader slot',name)
    expected={n.lower():v for n,v in constants.items()}
    assert expected==slots,('Reader/backend slot mismatch',expected,slots)
    assert 'self.storage.roots' not in source,'Backend must not retain a second root authority'
    for expression in re.findall(r'derive_storage_slot_in_map\(([^,]+),',source):
        if expression.strip().isdigit():assert int(expression) in (3,4),'Unexpected hard-coded facade map slot'
    return slots

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('artifact',nargs='?',type=Path,default=ROOT/'contracts/target/game_state_backend-GameStateBackend.json')
    parser.add_argument('--root',type=Path,default=ROOT)
    parser.add_argument('--backend-only',action='store_true',help='Isolated size probe only; production validates all9 facades too')
    args=parser.parse_args()
    slots=verify_backend(args.artifact,args.root)
    if not args.backend_only:verify_facades(args.artifact.parent,args.root)
    print('PASS:',len(slots),'Backend slots and',0 if args.backend_only else 9,'facade root layouts match compiled metadata')
