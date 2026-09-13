"""Exact typed-setter event replacement; no permission or state-model changes.

The original typed state serialization is also the suffix of its public event.
Reuse it after hashing, avoiding an outer Writer. This is a source transformation,
not evidence of compiled gas savings. Only these four original setters opt in.
"""
import re
from pathlib import Path
import check

SPECS = {
    'planet': ('Planet', 'PlanetUpdate', 'planet', 32),
    'planet_artifacts': ('PlanetArtifacts', 'PlanetArtifactsUpdate', 'state', 22),
    'artifact': ('Artifact', 'ArtifactUpdate', 'state', 13),
    'artifact_location': ('ArtifactLocation', 'ArtifactLocationUpdate', 'state', 3),
}


def function_body(source, name):
    match = re.search(r'\bfn\s+' + re.escape(name) + r'\s*\(', source)
    assert match is not None, name
    parameters_end = check.balanced(check.clean(source), match.end() - 1)
    start = source.index('{', parameters_end)
    end = check.balanced(check.clean(source), start, '{', '}')
    return source[start + 1:end]


def original_setter_body(slug):
    assert slug in SPECS, slug
    path = Path('contracts/storage') / slug / 'src/main.nr'
    source = (check.BASE / 'sources' / path).read_text()
    return function_body(source, 'set').replace('self.storage.state_roots', 'self.storage.local_roots')


def typed_setter_body(slug):
    _, event, state_arg, width = SPECS[slug]
    fields = ', '.join(f'fields[{i}]' for i in range(width))
    return f'''        self.internal.assert_authorized();
        let block_number = self.context.block_number();
        let fields = {state_arg}.serialize();
        let root = poseidon2_hash(fields);
        self.storage.local_roots.at(id).write(root);
        let tag = comptime {{ aztec::protocol::hash::compute_log_tag(
            {event}::get_event_type_id().to_field(), aztec::protocol::constants::DOM_SEP__EVENT_LOG_TAG,
        ) }};
        let log = [tag, id, block_number as Field, {fields}];
        // Exact public event encoding: domain-separated tag, ID, block, typed state.
        aztec::oracle::avm::emit_public_log(log.as_vector());'''


def rewrite_setter(slug, body):
    """Fail closed if the copied original setter ever changes beyond root naming."""
    assert slug in SPECS, slug
    assert check.norm(body) == check.norm(original_setter_body(slug)), (slug, 'unexpected original typed setter')
    return typed_setter_body(slug)


def restore_setter(slug, body):
    """Check every replacement statement before restoring the original for audits."""
    assert slug in SPECS, slug
    assert check.norm(body) == check.norm(typed_setter_body(slug)), (slug, 'typed event replacement changed')
    return original_setter_body(slug)
