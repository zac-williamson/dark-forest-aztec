#!/usr/bin/env python3
"""Replace six original Admin verification calls with guarded live VM reads.

All other statements, original typed writes, and function signatures must restore
exactly to the frozen source. This checks the transform, not transaction fees.
"""
import argparse
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('admin_prepared', HERE / 'prepare-system-writes.py')
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
ROOT = p.ROOT
SOURCE = ROOT / 'contracts/system/admin/src/main.nr'
BASELINE = HERE / 'baseline/sources/contracts/system/admin/src/main.nr'
MANIFEST = HERE / 'generated/admin-read-transform.json'
ACTIONS = {
    'pause': ('world', '0', 'world'),
    'unpause': ('world', '0', 'world'),
    'set_owner': ('planet', 'planet_id', 'planet_state'),
    'deduct_score': ('player', 'player_address', 'player_state'),
    'add_score': ('player', 'player_address', 'player_state'),
    'admin_set_world_radius': ('world', '0', 'world'),
}
TYPES = {'world': ('World', 'WorldStorage', 'Field', 1),
         'planet': ('Planet', 'PlanetStorage', 'Field', 3),
         'player': ('Player', 'PlayerStorage', 'AztecAddress', 2)}


def expressions(name):
    kind, key, state = ACTIONS[name]
    original = f'self.view({kind}_storage.verify({key}, {state}))'
    optimized = (f'_verify_{kind}_for_admin(self.context, self.storage.state_backend.read(), '
                 f'{kind}_storage.target_contract, {key}, {state})')
    return original, optimized


def restore_body(name, body):
    if name not in ACTIONS:
        return body
    original, optimized = expressions(name)
    if f'_verify_{ACTIONS[name][0]}_for_admin(' not in body:
        return body
    assert body.count(optimized) == 1, (name, 'unexpected optimized read')
    return body.replace(optimized, original, 1)


def helpers():
    result = ''
    for kind, (typ, store, key_type, namespace_kind) in TYPES.items():
        key_field = 'id.to_field()' if key_type == 'AztecAddress' else 'id'
        result += f'''
    #[inline_never]
    #[contract_library_method]
    unconstrained fn _verify_{kind}_for_admin(
        context: aztec::context::PublicContext,
        backend: AztecAddress,
        namespace: AztecAddress,
        id: {key_type},
        state: {typ},
    ) -> bool {{
        let mut self = __aztec_nr_internals__create_public_self_from_context(context);
        let recognized = if backend.is_zero() {{ false }} else {{
            ::state_backend_readonly::public_read::get_namespace_kind(backend,namespace) == {namespace_kind}
        }};
        if recognized {{
            let root = ::state_backend_readonly::public_read::get_state_root(backend,namespace,{key_field});
            // Keep verify(state) semantics: explicit H(zero) also accepts zero.
            if root == 0 {{ state == {typ}::zero() }} else {{ poseidon2_hash(state.serialize()) == root }}
        }} else {{
            // Unknown stores keep the original typed call and original Admin caller.
            self.view({store}::at(namespace).verify(id,state))
        }}
    }}
'''
    return result


def generate(apply=False):
    source = SOURCE.read_text()
    frozen = p.functions(BASELINE.read_text())
    current = p.functions(source)
    edits = []
    records = []
    for name in ACTIONS:
        old = frozen[name]
        before, after = expressions(name)
        assert old['body'].count(before) == 1
        expected = old['header'] + '{' + old['body'].replace(before, after, 1) + '}'
        actual = current[name]
        assert p.digest(actual['header']) == p.digest(old['header']), (name, 'signature changed')
        assert p.digest(restore_body(name, actual['body'])) == p.digest(old['body']), (name, 'other behavior changed')
        if apply:
            edits.append((actual['start'], actual['body_end'] + 1, expected))
        else:
            assert p.digest(actual['full']) == p.digest(expected), (name, 'read optimization missing')
        records.append({'function': name, 'originalHash': p.digest(old['full']),
                        'optimizedHash': p.digest(expected), 'originalExpression': before,
                        'optimizedExpression': after})
    for name, expected in p.functions(helpers()).items():
        actual = current.get(name)
        if apply:
            if actual:
                edits.append((actual['start'], actual['body_end'] + 1, expected['full']))
            else:
                edits.append((source.rfind('}'), source.rfind('}'), '\n' + expected['full'] + '\n'))
        else:
            assert actual and p.digest(actual['full']) == p.digest(expected['full']), (name, 'helper changed')
    manifest = {'scope': 'Exact six-function source restoration and guarded verify semantics; execution and fees tested separately.',
                'functions': records, 'helpersHash': p.digest(helpers())}
    if apply:
        for start, end, replacement in sorted(edits, reverse=True):
            source = source[:start] + replacement + source[end:]
        SOURCE.write_text('\n'.join(line.rstrip() for line in source.splitlines()) + '\n')
        MANIFEST.write_text(json.dumps(manifest, indent=2) + '\n')
        generate(False)
    else:
        assert json.loads(MANIFEST.read_text()) == manifest
        print('PASS: six Admin verification reads; exact original signatures, assertions, and typed writes restored')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--apply', action='store_true')
    group.add_argument('--check', action='store_true')
    generate(parser.parse_args().apply)
