#!/usr/bin/env python3
"""Check class-guarded Move Config SLOADs against actual compiler metadata.

The immutable current-class check is verified by test_move_transform.py. This
check binds its two raw slots to the current compiled Config source and ensures
the cached predicate still means exactly the original public view predicate.
"""
import importlib.util
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('move_config_layout', HERE / 'generate-backend-move.py')
MOVE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOVE)
ROOT = MOVE.p.ROOT


def verify(artifact):
    compiled = json.loads(pathlib.Path(artifact).read_text())
    source_path = ROOT / 'contracts/config/src/main.nr'
    source = source_path.read_text()
    embedded = [item['source'] for item in compiled['file_map'].values()
                if item['path'].replace('\\', '/').endswith('/config/src/main.nr')]
    assert embedded == [source], 'Compiled Config contains stale or ambiguous source; rebuild Config'
    for entry in compiled['outputs']['globals']['storage']:
        fields = {field['name']: field['value'] for field in entry['fields']}
        if fields['contract_name']['value'] == 'Config':
            slots = {field['name']: int(field['value']['fields'][0]['value']['value'], 16)
                     for field in fields['fields']['fields']}
            break
    else:
        raise AssertionError('Compiled Config storage metadata missing')
    for name, expected in MOVE.CONFIG_SLOTS.items():
        assert slots.get(name) == expected, (name, expected, slots.get(name))
    predicate = MOVE.p.functions(source)['verify_move_configuration']['body']
    expected = '''(self.storage.move_configuration_root.read() == common_root)
        & (self.storage.planet_default_stats_hash.at(level).read() == default_stats_root)'''
    assert re.sub(r'\s+', '', predicate) == re.sub(r'\s+', '', expected), \
        'Config predicate changed; raw Move SLOAD predicate must be reviewed'
    fragment = MOVE.DEST.read_text()
    assert f'let config_common_slot: Field = {MOVE.CONFIG_SLOTS["move_configuration_root"]};' in fragment
    assert f'let config_stats_map_slot: Field = {MOVE.CONFIG_SLOTS["planet_default_stats_hash"]};' in fragment
    print('PASS: class-guarded Move Config SLOAD slots and predicate match current compiled Config')


if __name__ == '__main__':
    verify(sys.argv[1] if len(sys.argv) > 1 else ROOT / 'contracts/target/config-Config.json')
