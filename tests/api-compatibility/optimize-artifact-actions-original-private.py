#!/usr/bin/env python3
"""V8 source candidate: original Activate/Deactivate private computations.

Reuse authenticated V7 canonical validation and local custom-store fallbacks.
Only five scalar plan records per action move from private-prepared hashes to
full public hashing. No original API, state field, batch or callback is removed.
"""
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ACTIONS = {'artifact_action': (
    ('activate_artifact', 'activate_artifact_public'),
    ('deactivate_artifact', 'deactivate_artifact_public'),
)}
PROVENANCE = HERE / 'snapshots/v8-actions-v7/provenance.json'
ROOT_STATES = (
    (3, 'location_id', 'new_planet'),
    (5, 'location_id', 'new_planet_events_state'),
    (6, 'location_id', 'new_planet_artifacts_state'),
    (8, 'artifact_id', 'new_artifact'),
    (9, 'artifact_id', 'new_artifact_location'),
)


def baseline_functions(parser):
    relative = 'contracts/system/artifact_action/src/main.nr'
    manifest = json.loads((HERE / 'baseline/manifest.json').read_text())
    raw = (HERE / 'baseline/sources' / relative).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == manifest['sources'][relative]
    return parser.functions(raw.decode())


def frozen_functions(parser):
    record = json.loads(PROVENANCE.read_text())['v7ActionSnapshot']
    raw = (HERE.parents[1] / record['path']).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == record['sha256'], 'V7 Action snapshot changed'
    return parser.functions(raw.decode())


def route_body(public, parser):
    assert public in {name for _, name in ACTIONS['artifact_action']}
    full = frozen_functions(parser)[public + '_prepared']['body']
    marker = '        let state_backend_address = self.storage.state_backend.read();'
    assert full.count(marker) == 1
    original = '\n' + full[full.index(marker):]
    body = original
    for namespace, key, state in ROOT_STATES:
        before = f'write_plan.set({namespace}, {key}, prepared_{state}_root, true, {state}.serialize())'
        after = f'write_plan.set({namespace}, {key}, 0, false, {state}.serialize())'
        assert body.count(before) == 1, (public, state)
        body = body.replace(before, after, 1)
    assert 'prepared_payload' not in body and 'prepared_new_' not in body
    assert 'self.enqueue_self.' not in body and 'self.context.this_address()' not in body
    assert body.count('self.internal._legacy_' + public + '(') == 1
    restored = body
    for namespace, key, state in ROOT_STATES:
        restored = restored.replace(
            f'write_plan.set({namespace}, {key}, 0, false, {state}.serialize())',
            f'write_plan.set({namespace}, {key}, prepared_{state}_root, true, {state}.serialize())', 1)
    assert restored == original, (public, 'Unaudited canonical change')
    return body


def is_active(definition):
    return definition['name'] in {public for _, public in ACTIONS['artifact_action']} and 'let state_backend_address = ' in definition['body']


def restore_original(source, definition, parser):
    assert is_active(definition)
    original = baseline_functions(parser)[definition['name']]
    assert parser.digest(definition['header']) == parser.digest(original['header'])
    assert parser.digest(definition['body']) == parser.digest(route_body(definition['name'], parser))
    fallback = parser.functions(source)['_legacy_' + definition['name']]
    assert parser.digest(fallback['body']) == parser.digest(original['body'])
    return dict(original)


def apply_original_path(source, package, parser):
    if package not in ACTIONS:
        return source
    current, baseline = parser.functions(source), baseline_functions(parser)
    edits = []
    for private, public in ACTIONS[package]:
        for name, body in [(private, baseline[private]['body']), (public, route_body(public, parser))]:
            old = current[name]
            assert parser.digest(old['header']) == parser.digest(baseline[name]['header'])
            edits.append((old['start'], old['body_end'] + 1, baseline[name]['header'] + '{' + body + '}'))
        assert parser.digest(current['_legacy_' + public]['body']) == parser.digest(baseline[public]['body'])
        if public + '_prepared' in current:
            old = current[public + '_prepared']
            edits.append((old['start'], old['body_end'] + 1, ''))
    for start, end, replacement in sorted(edits, reverse=True):
        source = source[:start] + replacement + source[end:]
    return source
