#!/usr/bin/env python3
"""Keep Reveal and Safe Owner on their exact original private continuations.

Only authenticated canonical store reads are replaced by live VM storage reads.
Every Config call, unknown-store call, assertion and typed write stays in its
original System and original position. The V5 helper adapter below only restores
previous generated source; it is never emitted by this generator.
"""
import hashlib
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
ACTIONS = {
    "core": ("reveal_location", "reveal_location_public"),
    "admin": ("safe_set_owner", "safe_set_owner_public"),
}
BACKEND_READ = "        let state_backend_address = self.storage.state_backend.read();\n"
CONFIG_ADDRESS = "        let config = Config::at(self.storage.config_storage_address.read());"

ORIGINAL = 'reveal_location_public'
PREPARED = 'reveal_location_public_prepared'
HELPER = '_validate_reveal_shared'
WRITES = '''
        self.call(planet_storage.set(location, new_planet));
        self.call(planet_revealed_coords_storage.set(location, new_planet_revealed_coords));
        self.call(player_storage.set(sender, new_player_state));
    '''
CONTEXT = '        let mut self = __aztec_nr_internals__create_public_self_from_context(context);'
HELPER_HEADER = '''    #[inline_never]
    #[contract_library_method]
    unconstrained fn _validate_reveal_shared(
        context: aztec::context::PublicContext,
        location: Field, sender: AztecAddress, timestamp: u64, is_admin: bool,
        config_hashes: [Field;9], planet_default_stats_hash: Field,
        planet_state_hash: Field, player_state_hash: Field, world_hash: Field,
        planet_level: u8,
    ) '''


def validation_prefix(original_body, parser):
    marker = '        self.call(planet_storage.set('
    position = original_body.index(marker)
    prefix, writes = original_body[:position], original_body[position:]
    assert parser.digest(writes) == parser.digest(WRITES), 'Reveal write order or arguments changed'
    # Sharing reads across validation is safe: all original intervening calls are
    # view calls. No mutating callback is moved across a cached address read.
    assert 'self.call(' not in prefix
    lines = prefix.splitlines()
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    return '\n' + '\n'.join(line.rstrip() for line in lines) + '\n\n'


def helper_definition(original_body, parser):
    prefix = validation_prefix(original_body, parser)
    return HELPER_HEADER + '{\n' + CONTEXT + '\n' + prefix.replace('new_planet.planet_level', 'planet_level') + '    }'


def legacy_body(original_body, parser):
    validation_prefix(original_body, parser)
    return '''
        _validate_reveal_shared(self.context, location, sender, timestamp, is_admin, config_hashes, planet_default_stats_hash, planet_state_hash, player_state_hash, world_hash, new_planet.planet_level);
        let planet_storage = PlanetStorage::at(self.storage.planet_storage_address.read());
        let planet_revealed_coords_storage = PlanetRevealedCoordsStorage::at(self.storage.planet_revealed_coords_storage_address.read());
        let player_storage = PlayerStorage::at(self.storage.player_storage_address.read());
''' + WRITES


def restore_original(source, definition, parser):
    """Recover the exact original body for the independent baseline hash check."""
    functions = parser.functions(source)
    if definition['name'] in [pair[1] for pair in ACTIONS.values()] and BACKEND_READ in definition['body']:
        restored = dict(definition)
        restored['body'] = restore_body(definition['name'], definition['body'])
        restored['full'] = definition['header'] + '{' + restored['body'] + '}'
        return restored
    if definition['name'] != ORIGINAL:
        return definition
    if HELPER not in functions:
        restored = dict(definition)
        restored['body'] = validation_prefix(definition['body'], parser) + WRITES
        restored['full'] = definition['header'] + '{' + restored['body'] + '}'
        return restored
    helper = functions[HELPER]
    assert parser.digest(helper['header']) == parser.digest(HELPER_HEADER), 'Reveal helper signature changed'
    body = helper['body']
    assert body.lstrip().startswith(CONTEXT.strip()), 'Reveal helper context changed'
    prefix = body[body.index(CONTEXT) + len(CONTEXT):]
    prefix = re.sub(r'\bplanet_level\b', 'new_planet.planet_level', prefix)
    original_body = validation_prefix(prefix + WRITES, parser) + WRITES
    assert parser.digest(definition['body']) == parser.digest(legacy_body(original_body, parser)), 'Reveal original wrapper changed'
    assert parser.digest(helper['full']) == parser.digest(helper_definition(original_body, parser)), 'Reveal validation helper changed'
    restored = dict(definition)
    restored['body'] = original_body
    restored['full'] = definition['header'] + '{' + original_body + '}'
    return restored


def baseline_functions(package, parser):
    relative = f'contracts/system/{package}/src/main.nr'
    manifest = json.loads((HERE / 'baseline/manifest.json').read_text())
    raw = (HERE / 'baseline/sources' / relative).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == manifest['sources'][relative]
    return parser.functions(raw.decode())


def read_expressions(name):
    """Exact replacements, evaluated at each original assertion position."""
    if name == ORIGINAL:
        reads = [
            ('planet_storage', 3, 'location', 'planet_state_hash', False),
            ('planet_revealed_coords_storage', 4, 'location', None, True),
            ('player_storage', 2, 'sender', 'player_state_hash', False),
            ('world_storage', 1, '0', 'world_hash', False),
        ]
    elif name == 'safe_set_owner_public':
        reads = [
            ('world_storage', 1, '0', 'world_state_hash', False),
            ('planet_storage', 3, 'location_id', 'planet_state_hash', False),
        ]
    else:
        return []
    result = []
    for store, kind, key, expected, initialized in reads:
        original = (f'self.view({store}.is_initialized({key}))' if initialized else
                    f'self.view({store}.verify_hash({key}, {expected}))')
        root_key = key + '.to_field()' if kind == 2 else key
        root = ('::state_backend_readonly::public_read::get_state_root('
                f'state_backend_address, {store}.target_contract, {root_key})')
        comparison = root + (' != 0' if initialized else f' == {expected}')
        optimized = (f'(if (if state_backend_address.is_zero() {{ false }} else {{ '
                     '::state_backend_readonly::public_read::get_namespace_kind('
                     f'state_backend_address, {store}.target_contract) == {kind} '
                     f'}}) {{ {comparison} }} else {{ {original} }})')
        result.append((original, optimized))
    return result


def optimized_body(name, original_body):
    body = original_body
    assert body.count(CONFIG_ADDRESS) == 1
    body = body.replace(CONFIG_ADDRESS, BACKEND_READ + CONFIG_ADDRESS, 1)
    for original, optimized in read_expressions(name):
        assert body.count(original) == 1, (name, original)
        body = body.replace(original, optimized, 1)
    return body


def restore_body(name, body):
    if BACKEND_READ not in body:
        return body
    assert body.count(BACKEND_READ) == 1
    for original, optimized in read_expressions(name):
        assert body.count(optimized) == 1, (name, 'Unexpected optimized store read', original)
        body = body.replace(optimized, original, 1)
    return body.replace(BACKEND_READ, '', 1)


def apply_original_path(source, package, parser):
    """Restore private source verbatim and emit only guarded original public APIs.

    The caller validates the previous private enqueue transformation before this
    function runs. All body/signature checks use the immutable Git capture.
    """
    if package not in ACTIONS:
        return source
    private, public = ACTIONS[package]
    baseline = baseline_functions(package, parser)
    functions = parser.functions(source)
    edits = []
    for name in (private, public):
        current, original = functions[name], baseline[name]
        assert parser.digest(current['header']) == parser.digest(original['header']), (name, 'API changed')
        body = original['body'] if name == private else optimized_body(public, original['body'])
        edits.append((current['start'], current['body_end'] + 1, original['header'] + '{' + body + '}'))
    obsolete = [public + '_prepared', '_legacy_' + public]
    if package == 'core':
        obsolete.append(HELPER)
    for name in obsolete:
        assert name not in baseline, ('Cannot remove an original function', name)
        if name in functions:
            old = functions[name]
            edits.append((old['start'], old['body_end'] + 1, ''))
    for start, end, replacement in sorted(edits, reverse=True):
        source = source[:start] + replacement + source[end:]
    return source
