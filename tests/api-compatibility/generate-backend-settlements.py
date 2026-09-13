#!/usr/bin/env python3
"""Generate central settlement fragments and API-preserving system wrappers.

The source of each settlement/fallback is its untouched original public
continuation. The preceding prepared-system manifest supplies only the hashes
already bound by the original private function. --check regenerates the backend
text and checks exact wrapper body hashes, original function invariants and
private output-hash bindings. Execution/fee/proof checks remain separate.
"""

import argparse
import importlib.util
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('prepared_transform', HERE / 'prepare-system-writes.py')
prepared = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepared)
ROOT = prepared.ROOT
DEST = HERE / 'generated' / 'backend-settlements.nr'
MANIFEST = HERE / 'generated' / 'backend-system-transform.json'
NAMESPACES = {
    'world_storage': (1, 'world', 'world_storage_address'),
    'player_storage': (2, 'player', 'player_storage_address'),
    'planet_storage': (3, 'planet', 'planet_storage_address'),
    'planet_revealed_coords_storage': (4, 'planet_revealed_coords', 'planet_revealed_coords_storage_address'),
    'planet_events_storage': (5, 'planet_events', 'planet_events_storage_address'),
    'planet_artifacts_storage': (6, 'planet_artifacts', 'planet_artifacts_storage_address'),
    'arrival_storage': (7, 'arrival', 'arrivals_storage_address'),
    'arrivals_storage': (7, 'arrival', 'arrivals_storage_address'),
    'artifact_storage': (8, 'artifact', 'artifact_storage_address'),
    'artifact_location_storage': (9, 'artifact_location', 'artifact_location_storage_address'),
}
FIELDS = ['config_storage_address', 'world_storage_address', 'player_storage_address',
          'planet_storage_address', 'planet_revealed_coords_storage_address',
          'planet_events_storage_address', 'planet_artifacts_storage_address',
          'arrivals_storage_address', 'artifact_storage_address', 'artifact_location_storage_address']


def method_name(package, record):
    return 'try_settle_' + package + '_' + record['private']


def convert_calls(body, record):
    operations = []
    edits = []
    pattern = r'self\.(view|call)\((\w+)\.(\w+)\s*\('
    for match in re.finditer(pattern, prepared.mask(body, strings=True)):
        mode, store, method = match.groups()
        if store == 'config':
            continue
        assert store in NAMESPACES, (record['original'], store, method)
        index, kind, _ = NAMESPACES[store]
        argument_start = body.index('(', match.end() - 1)
        argument_end = prepared.closing(body, argument_start, '(', ')')
        outer_end = prepared.closing(body, body.index('(', match.start()), '(', ')')
        assert not body[argument_end + 1:outer_end].strip()
        args = prepared.split_arguments(body[argument_start + 1:argument_end])
        namespace = f'addresses[{index}]'
        key = args[0] if args else None
        if kind == 'player' and key is not None:
            key = '(' + key + ').to_field()'
        if method == 'verify_hash':
            assert mode == 'view' and len(args) == 2
            replacement = f'self.internal._verify_hash({namespace}, {key}, {args[1]})'
        elif method == 'verify_hashes_batch':
            assert mode == 'view' and len(args) == 3
            replacement = f'self.internal._verify_hashes_batch({namespace}, ' + ', '.join(args) + ')'
        elif method == 'verify_hashes_three':
            assert mode == 'view' and len(args) == 2
            replacement = f'self.internal._verify_hashes_three({namespace}, ' + ', '.join(args) + ')'
        elif method == 'allocate_event_id':
            assert mode == 'call' and not args
            replacement = f'self.internal._allocate_event_id({namespace}, actor)'
        elif method == 'is_initialized':
            assert mode == 'view' and len(args) == 1
            replacement = f'self.internal._is_initialized({namespace}, {key})'
        elif method == 'set':
            assert mode == 'call' and len(args) == 2
            state = args[1]
            is_prepared = state in record['states']
            root = prepared.root_name(state) if is_prepared else '0'
            flag = 'true' if is_prepared else 'false'
            replacement = f'self.internal._set_{kind}({namespace}, actor, {key}, {state}, {root}, {flag})'
        elif method in ['set_arrival_locations_max20', 'set_spaceships_max5', 'set_spaceship_locations_max5']:
            assert mode == 'call' and len(args) == 3
            replacement = f'self.internal._{method}({namespace}, actor, ' + ', '.join(args) + ')'
        else:
            raise AssertionError((record['original'], store, method))
        edits.append((match.start(), outer_end + 1, replacement))
        operations.append({'namespaceIndex': index, 'namespaceKind': kind, 'method': method,
                           'source': body[match.start():outer_end + 1], 'replacement': replacement})
    for start, end, replacement in reversed(edits):
        body = body[:start] + replacement + body[end:]
    return body, operations


def fragment(package, source, record):
    original = prepared.functions(source)[record['original']]
    body, operations = convert_calls(original['body'], record)
    # All original storage-address resolutions become the canonical array.
    for store in NAMESPACES:
        body = re.sub(prepared.store_declaration(store), '', body)
    body = re.sub(prepared.store_declaration('config'), 'let config = Config::at(addresses[0]);', body)
    body = body.replace('self.storage.admin.read()', 'self.internal._get_system_admin(actor)')
    assert not re.search(r'self\.storage\.', prepared.mask(body)), record['original']
    assert not re.search(r'self\.(view|call)\((?!config\.)', prepared.mask(body)), record['original']
    required_mask = sum(1 << index for index in sorted(set(o['namespaceIndex'] for o in operations)))
    args = original['params'] + [prepared.root_name(state) + ': Field' for state in record['states']]
    params = ['addresses: [AztecAddress; 10]'] + args
    result = '\n    #[external("public")]\n    fn ' + method_name(package, record) + '(\n'
    result += ''.join('        ' + arg + ',\n' for arg in params)
    result += '    ) -> bool {\n'
    result += f'        if self.internal._can_settle(addresses, {required_mask}) {{\n'
    result += '            let actor = self.msg_sender();\n'
    result += '\n'.join('    ' + line if line else line for line in body.split('\n'))
    result += '\n            true\n        } else {\n            false\n        }\n    }\n'
    return result, {'package': package, 'private': record['private'], 'method': method_name(package, record),
                    'requiredMask': required_mask, 'operations': operations,
                    'originalBodyHash': prepared.digest(original['body'])}


def wrapper(package, source, record):
    current = prepared.functions(source)
    original = current[record['original']]
    existing = current[record['prepared']]
    storage_match = re.search(r'struct Storage<Context>\s*\{', source)
    start = source.index('{', storage_match.start())
    end = prepared.closing(source, start, '{', '}')
    storage = source[start:end]
    # Only fields read by the original continuation are resolved. Unused slots
    # remain zero instead of introducing additional public storage reads.
    used_fields = set(re.findall(r'self\s*\.\s*storage\s*\.\s*(\w+)\s*\.\s*read\(\)', original['body']))
    addresses = ['self.storage.' + field + '.read()' if field in used_fields and re.search(r'\b' + field + r'\s*:', storage) else 'AztecAddress::zero()' for field in FIELDS]
    params = [re.match(r'(?:mut\s+)?(\w+)\s*:', p).group(1) for p in existing['params']]
    route = '\n        let state_backend_address = self.storage.state_backend.read();\n'
    route += '        let mut settled_by_backend = false;\n'
    route += '        if state_backend_address != AztecAddress::zero() {\n'
    route += '            let state_backend = GameStateBackend::at(state_backend_address);\n'
    route += '            settled_by_backend = self.call(state_backend.' + method_name(package, record) + '(\n'
    route += '                [\n' + ''.join('                    ' + address + ',\n' for address in addresses) + '                ],\n'
    route += ''.join('                ' + name + ',\n' for name in params)
    route += '            ));\n        }\n'
    route += '        if !settled_by_backend {' + original['body'] + '\n        }\n'
    return existing['header'] + '{' + route + '}', route


def generate(apply=False, refresh=False):
    first = json.loads(prepared.MANIFEST.read_text())
    output = '// Generated from original public continuations. Do not edit by hand.\n'
    output += '// Required masks use [config, world, player, planet, coords, events, planet_artifacts, arrival, artifact, location].\n'
    records = []
    outputs = {}
    for package, entry in first['packages'].items():
        path = ROOT / f'contracts/system/{package}/src/main.nr'
        source = path.read_text()
        changes = []
        for record in entry['continuations']:
            text, details = fragment(package, source, record)
            output += text
            new_wrapper, wrapper_body = wrapper(package, source, record)
            details['wrapperBodyHash'] = prepared.digest(wrapper_body)
            details['prepared'] = record['prepared']
            records.append(details)
            if apply or refresh:
                current = prepared.functions(source)[record['prepared']]
                changes.append((current['start'], current['body_end'] + 1, new_wrapper))
            else:
                current = prepared.functions(source)[record['prepared']]
                assert prepared.digest(current['body']) == details['wrapperBodyHash'], (package, record['prepared'], 'wrapper differs')
        if apply or refresh:
            for start, end, replacement in sorted(changes, reverse=True):
                source = source[:start] + replacement + source[end:]
        if apply:
            storage_match = re.search(r'struct Storage<Context>\s*\{', source)
            start = source.index('{', storage_match.start())
            end = prepared.closing(source, start, '{', '}')
            assert not re.search(r'\bstate_backend\s*:', source[start:end])
            source = source[:end] + '    state_backend: PublicMutable<AztecAddress, Context>,\n    ' + source[end:]
            contract = re.search(r'\bcontract\s+\w+\s*\{', source)
            insertion = source.index('{', contract.start()) + 1
            source = source[:insertion] + '\n    use ::game_state_backend::GameStateBackend;\n' + source[insertion:]
            if package == 'admin':
                source = source.replace('functions::{external, initializer, internal, only_self}', 'functions::{external, initializer, internal, only_self, view}', 1)
            end = prepared.closing(source, source.index('{', contract.start()), '{', '}')
            additions = '''
    #[external("public")]
    fn set_state_backend(state_backend: AztecAddress) {
        self.internal.assert_admin();
        self.storage.state_backend.write(state_backend);
    }

    #[external("public")]
    #[view]
    fn get_backend_admin() -> AztecAddress {
        self.storage.admin.read()
    }

'''
            source = source[:end] + additions + source[end:]
        if apply or refresh:
            outputs[path] = source
    if apply or refresh:
        assert MANIFEST.exists() if refresh else not MANIFEST.exists(), 'Use --apply once, then --refresh/--check'
        snapshots = HERE / 'snapshots' / 'prepared-original-stores'
        if apply:
            for package in first['packages']:
                for name in ['src/main.nr', 'Nargo.toml']:
                    source_path = ROOT / f'contracts/system/{package}' / name
                    destination = snapshots / package / name
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_text(source_path.read_text())
        for path, source in outputs.items():
            path.write_text(source)
            if apply:
                nargo = path.parents[1] / 'Nargo.toml'
                text = nargo.read_text()
                assert 'game_state_backend' not in text
                nargo.write_text(text.rstrip() + '\ngame_state_backend = { path = "../../state_backend" }\n')
        DEST.parent.mkdir(parents=True, exist_ok=True)
        DEST.write_text(output)
        MANIFEST.write_text(json.dumps({'scope': 'Fresh deployment centralized settlement with exact original API fallback. Source checks only.', 'continuations': records}, indent=2) + '\n')
        generate(False)
    else:
        assert DEST.read_text() == output, 'Backend fragment differs from generated original behavior'
        stored = json.loads(MANIFEST.read_text())
        assert stored['continuations'] == records, 'Generation manifest differs'
        for package, entry in first['packages'].items():
            source = (ROOT / f'contracts/system/{package}/src/main.nr').read_text()
            current = prepared.functions(source)
            private_records = {r['private']: r for r in entry['continuations']}
            for name, expected in entry['originalFunctions'].items():
                fn = current[name]
                assert prepared.digest(fn['header']) == expected['signatureHash'], (package, name, 'original signature changed')
                restored = fn['full']
                if name in private_records:
                    record = private_records[name]
                    assert restored.count(record['preparedEnqueue']) == 1
                    restored = restored.replace(record['preparedEnqueue'], record['originalEnqueue'], 1)
                assert prepared.digest(restored) == expected['functionHash'], (package, name, 'original function changed')
        print(f'PASS: {len(records)} generated backend settlements/wrappers; all original functions and private hash bindings preserved')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_mutually_exclusive_group(required=True)
    actions.add_argument('--apply', action='store_true')
    actions.add_argument('--check', action='store_true')
    actions.add_argument('--refresh', action='store_true', help='Regenerate wrapper bodies after generator changes')
    args = parser.parse_args()
    if (HERE / 'generated' / 'backend-plan-transform.json').exists():
        assert args.check, 'Plan wrappers are active; use generate-backend-plans.py --apply to regenerate'
        plan_spec = importlib.util.spec_from_file_location('backend_plans', HERE / 'generate-backend-plans.py')
        plans = importlib.util.module_from_spec(plan_spec)
        plan_spec.loader.exec_module(plans)
        plans.generate(False)
    else:
        generate(args.apply, args.refresh)
