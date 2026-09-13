#!/usr/bin/env python3
"""Require the exact authoritative local-root layout in every original facade."""
import argparse
import json
from pathlib import Path
import check

ROOT=Path(__file__).resolve().parents[2]
FACADES={'world':'WorldStorage','player':'PlayerStorage','planet':'PlanetStorage',
 'planet_revealed_coords':'PlanetRevealedCoordsStorage','planet_events':'PlanetEventsStorage',
 'planet_artifacts':'PlanetArtifactsStorage','arrival':'ArrivalStorage','artifact':'ArtifactStorage',
 'artifact_location':'ArtifactLocationStorage'}
EXPECTED={'admin':1,'state_backend':2,'local_roots':3,'authorized_map':4,'authorized_index':5,'authorized_list':6,'authorized_count':7}

def storage_slots(artifact,contract):
    matches=[]
    for entry in artifact['outputs']['globals']['storage']:
        fields={f['name']:f['value'] for f in entry['fields']}
        if fields['contract_name']['value']==contract:
            matches.append({f['name']:int(f['value']['fields'][0]['value']['value'],16)
                            for f in fields['fields']['fields']})
    assert len(matches)==1,('Expected one compiler storage layout',contract,len(matches))
    return matches[0]

def verify_facades(directory,root=ROOT):
    directory=Path(directory);root=Path(root)
    for slug,contract in FACADES.items():
        path=directory/f'{slug}-{contract}.json'
        compiled=storage_slots(json.loads(path.read_text()),contract)
        assert compiled==EXPECTED,(slug,'Unexpected compiler layout',compiled)
        source=root/f'contracts/storage/{slug}/src/main.nr'
        fields=check.parse_source(str(source),source.read_text())['storage']
        assert [f['name'] for f in fields]==list(EXPECTED),(slug,'Source layout differs from compiler layout')
        assert fields[2]['type']==check.norm('Map<Field,PublicMutable<Field,Context>,Context>'),(slug,'Root keys and values must stay full Field')
    return len(FACADES)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('directory',type=Path);parser.add_argument('--root',type=Path,default=ROOT)
    args=parser.parse_args();print('PASS:',verify_facades(args.directory,args.root),'compiled facade layouts')
