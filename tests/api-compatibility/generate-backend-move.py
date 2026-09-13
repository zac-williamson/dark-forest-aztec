#!/usr/bin/env python3
"""Generate Move's central settlement, automatic empty path and exact fallback.

Original gameplay computation and original public signature are retained.
The original public artifact checks are restored to the three legacy scalar
methods, so its fallback does not require any additive storage selector.
"""
import argparse
import hashlib
import importlib.util
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('backend_generator', HERE / 'generate-backend-settlements.py')
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)
p = backend.prepared
SOURCE = p.ROOT / 'contracts/system/move/src/main.nr'
DEST = HERE / 'generated/backend-move.nr'
MANIFEST = HERE / 'generated/backend-move-transform.json'
SNAPSHOT = HERE / 'snapshots/backend-move-original/main.nr'
BASELINE = HERE / 'baseline/sources/contracts/system/move/src/main.nr'
STATES = ['new_source_planet', 'new_source_planet_artifacts_state', 'new_source_planet_events_state',
          'new_target_planet', 'new_target_planet_artifacts_state',
          'new_source_activated_artifact', 'new_source_activated_artifact_location']
OMITTED = {f'{side}_{name}' for side in ['source', 'target'] for name in
           ['arrival_ids', 'arrival_hashes', 'arrival_artifact_ids', 'arrival_artifact_hashes', 'arrival_artifact_location_hashes']}
OMITTED |= {f'original_{side}_arrivals_count' for side in ['source', 'target']}
OMITTED |= {f'new_{side}_arrival_artifact_locations' for side in ['source', 'target']}
# Exact pinned Config storage layout, independently checked against compiler
# metadata by verify_config_layout.py before deployment. Only the attested
# current CONFIG_CLASS may use these slots; other classes retain public calls.
CONFIG_SLOTS = {'planet_default_stats_hash': 299, 'move_configuration_root': 304}


def param_name(param):
    return re.match(r'(?:mut\s+)?(\w+)\s*:', param).group(1)


def scalar_checks(body):
    pattern = r'let artifact_checks = self\.view\(artifact_storage\.verify_hashes_three\('
    match = re.search(pattern, body)
    assert match
    end = body.index('assert(artifact_checks[2], "Target activated artifact hash mismatch");', match.start())
    end += len('assert(artifact_checks[2], "Target activated artifact hash mismatch");')
    before = body[match.start():end]
    calls = [
        ('moved_artifact_id', 'moved_artifact_hash', 'Moved artifact hash mismatch'),
        ('source_activated_artifact_id', 'source_activated_artifact_hash', 'Activated artifact hash mismatch'),
        ('target_activated_artifact_id', 'target_activated_artifact_hash', 'Target activated artifact hash mismatch'),
    ]
    after = '\n        '.join(f'assert(self.view(artifact_storage.verify_hash({key}, {root})), "{error}");' for key, root, error in calls)
    return body[:match.start()] + after + body[end:], {'before': before, 'after': after}


def immutable_originals():
    """The captured upstream commit, never an intermediate optimization snapshot."""
    manifest = json.loads((HERE / 'baseline/manifest.json').read_text())
    source_bytes = BASELINE.read_bytes()
    expected = manifest['sources']['contracts/system/move/src/main.nr']
    assert hashlib.sha256(source_bytes).hexdigest() == expected, 'Immutable Move source changed'
    return p.functions(source_bytes.decode()), {
        'gitCommit': manifest['gitCommit'], 'source': str(BASELINE.relative_to(HERE)),
        'sha256': expected, 'unconditionalBatchVerificationCalls': 6,
    }


def make_header(name, params):
    return '\n    #[external("public")]\n    #[only_self]\n    fn ' + name + '(\n' + ''.join('        ' + param + ',\n' for param in params) + '    ) '


def empty_fragment(full):
    fn = p.functions(full)['try_settle_move_move']
    params = [param for param in fn['params'] if param_name(param) not in OMITTED]
    body = fn['body']
    for side in ['source', 'target']:
        match = re.search(r'if original_' + side + r'_arrivals_count != 0\s*\{', body)
        assert match
        opening = body.index('{', match.start())
        end = p.closing(body, opening, '{', '}')
        body = body[:match.start()] + body[end + 1:]
        pattern = r'self\.internal\._set_arrival_locations_max20\(addresses\[9\], actor, ' + side + r'_arrival_artifact_ids, new_' + side + r'_arrival_artifact_locations, original_' + side + r'_arrivals_count\)'
        body, count = re.subn(pattern, 'self.internal._assert_authorized(addresses[9], actor)', body)
        assert count == 1
    for name in OMITTED:
        assert not re.search(r'\b' + name + r'\b', p.mask(body)), ('Empty backend retains omitted data', name)
    header = '\n    #[external("public")]\n    fn try_settle_move_move_empty(\n'
    header += ''.join('        ' + param + ',\n' for param in params) + '    ) -> bool '
    return header + '{' + body + '}\n'


def factor_move_blocks(full, empty):
    """Extract exact shared statements without moving them across batch barriers.

    The recorded transform hashes continue to describe the canonical unfactored
    statements. Expansion below proves the new helpers reproduce those exact
    statements in each entry. Public signatures and private Move code are untouched.
    """
    entries = [p.functions(text)[name] for text, name in [
        (full, 'try_settle_move_move'), (empty, 'try_settle_move_move_empty')]]
    bodies = [entry['body'] for entry in entries]
    originals = bodies.copy()
    parameters = {param_name(param): param for param in entries[0]['params']}
    parameters.update({'actor':'actor: AztecAddress', 'new_arrival':'new_arrival: Arrival',
                       'new_moved_artifact_location':'new_moved_artifact_location: ArtifactLocation',
                       'new_target_planet_events_state':'new_target_planet_events_state: PlanetEvents'})
    definitions = [
        ('_move_check_source', '// Verify timestamp', 'if original_source_arrivals_count != 0', None),
        ('_move_check_target', '// Verify target planet state hashes', '// Batch verify target arrivals', None),
        ('_move_check_world_and_allocate', '// Verify world, moved artifact, and activated artifact hashes', 'new_arrival.id = event_id;', 'event_id'),
        ('_move_write_source', '// Write new states to storage', '// Batch write source arrival artifact locations', None),
        ('_move_write_target', 'self.internal._set_planet(addresses[3], actor, target_loc,', '// Batch write target arrival artifact locations', None),
        ('_move_write_tail', 'self.internal._set_arrival(addresses[7], actor, new_arrival.id,', None, None),
    ]
    helpers=[];expansions=[]
    for name,start_marker,end_marker,returned in definitions:
        start=bodies[0].index(start_marker)
        end=bodies[0].index(end_marker,start) if end_marker else bodies[0].rindex('            true')
        shared=bodies[0][start:end].rstrip()
        assert shared and bodies[1].count(shared)==1, ('Block is not identical in both paths',name)
        words=set(re.findall(r'\b[A-Za-z_]\w*\b',p.mask(shared)))
        selected=[param for variable,param in parameters.items() if variable in words]
        selected_names=[param_name(param) for param in selected]
        invocation=name+'(self.context, '+', '.join(selected_names)+')'
        invocation=('let event_id: Field = '+invocation+';') if returned else invocation+';'
        signature='    #[inline_never]\n    #[contract_library_method]\n    unconstrained fn '+name+'(\n        context: aztec::context::PublicContext,\n'
        signature+=''.join('        '+param+',\n' for param in selected)
        signature+='    )'+(' -> Field' if returned else '')+' {\n'
        helpers.append(signature+'        let mut self = __aztec_nr_internals__create_public_self_from_context(context);\n        '+shared+ ('\n        event_id' if returned else '')+'\n    }\n')
        for i in range(2):
            assert bodies[i].count(shared)==1
            bodies[i]=bodies[i].replace(shared,invocation,1)
        expansions.append((invocation,shared))
    output=[]
    for original_body,new_body,text,entry in zip(originals,bodies,[full,empty],entries):
        expanded=new_body
        for invocation,shared in reversed(expansions):
            assert expanded.count(invocation)==1
            expanded=expanded.replace(invocation,shared,1)
        assert expanded==original_body,'Factoring changed statement order or payloads'
        output.append(text[:entry['body_start']+1]+new_body+text[entry['body_end']:])
    assert 'new_source_arrival_artifact_locations' not in p.mask(output[1])
    assert output[1].count('self.internal._assert_authorized(addresses[9], actor)')==2
    return '\n'.join(helpers+output)


def serialized_schema():
    captured=json.loads((HERE/'baseline/artifacts.json').read_text())['Move']['functions']['move_public']['schema']
    params=next(field['type']['fields'] for field in captured if field['name']=='parameters')
    schemas={param['name']:param['type'] for param in params}
    schemas.update({p.root_name(state):{'kind':'field'} for state in STATES})
    return schemas


def field_width(schema):
    if schema['kind']=='array':return schema['length']*field_width(schema['type'])
    if schema['kind']=='struct':return sum(field_width(field['type']) for field in schema['fields'])
    return 1


def needs_canonical_check(schema):
    if schema['kind']=='array':return needs_canonical_check(schema['type'])
    if schema['kind']=='struct':return any(needs_canonical_check(field['type']) for field in schema['fields'])
    return schema['kind'] in ('integer','boolean')


def reconstruct_typed(schema, offset):
    """Decode only authenticated typed private output without dynamic Readers."""
    kind=schema['kind'];word=f'prepared_payload[{offset}]'
    if kind=='field':return word,offset+1
    if kind=='integer':
        assert schema['sign']=='unsigned'
        return f'({word} as u{schema["width"]})',offset+1
    if kind=='boolean':return f'({word} == 1)',offset+1
    if kind=='array':
        values=[]
        for _ in range(schema['length']):
            value,offset=reconstruct_typed(schema['type'],offset);values.append(value)
        return '['+', '.join(values)+']',offset
    assert kind=='struct'
    typename=schema['path'].split('::')[-1]
    if typename=='AztecAddress':
        assert schema['fields']==[{'name':'inner','type':{'kind':'field'}}]
        return f'AztecAddress::from_field({word})',offset+1
    values=[]
    for field in schema['fields']:
        value,offset=reconstruct_typed(field['type'],offset)
        values.append(field['name']+': '+value)
    return typename+' { '+', '.join(values)+' }',offset


def flatten_prepared_wrapper(wrapper, name, params):
    schemas=serialized_schema();offset=0;decode='\n';layout=[]
    for param in params:
        variable=param_name(param);typ=param.split(':',1)[1].strip();schema=schemas[variable];width=field_width(schema)
        value,end=reconstruct_typed(schema,offset)
        assert end==offset+width
        decode+=f'        let {variable}: {typ} = {value};\n'
        layout.append({'name':variable,'type':typ,'offset':offset,'width':width,
                       'canonicalSource':'only_self typed private serialization'})
        offset+=width
    fn=p.functions(wrapper)[name]
    header=make_header(name,[f'prepared_payload: [Field; {offset}]'])
    # only_self authenticates the typed private serialization above. Rechecking
    # integer ranges by serializing every record again adds duplicate public
    # work. Original move_public remains typed and keeps its original ABI checks.
    return header+'{'+decode+fn['body']+'}', {'fields':offset,'layout':layout,'decode':decode,'typedBodyHash':p.digest(fn['body'])}


def flatten_forwarding_wrapper(wrapper,name,params,backend_name):
    _,metadata=flatten_prepared_wrapper(wrapper,name,params)
    fn=p.functions(wrapper)[name];body=fn['body']
    marker='state_backend.'+backend_name+'('
    start=body.index(marker)+len(marker)-1;end=p.closing(body,start,'(',')')
    arguments=p.split_arguments(body[start+1:end])
    assert len(arguments)==len(params)+1
    assert all(arg.strip()==param_name(param) for arg,param in zip(arguments[1:],params))
    body=body[:start+1]+arguments[0]+',\n                prepared_payload,\n            '+body[end:]
    # Only the compatibility branch reconstructs typed values; a successful
    # central settlement forwards the already proved fields without processing.
    fallback_decode=''.join(line for line in metadata['decode'].splitlines(keepends=True)
                            if not any('let '+p.root_name(state)+':' in line for state in STATES))
    assert body.count('if !settled_by_backend {')==1
    body=body.replace('if !settled_by_backend {','if !settled_by_backend {'+fallback_decode,1)
    header=make_header(name,[f'prepared_payload: [Field; {metadata["fields"]}]'])
    metadata['systemFallbackDecode']=fallback_decode
    return header+'{'+body+'}',metadata


def flatten_backend_entries(fragment,layouts):
    for name,metadata in layouts.items():
        fn=p.functions(fragment)[name]
        assert len(fn['params'])==len(metadata['layout'])+1
        assert param_name(fn['params'][0])=='addresses'
        assert [param_name(param) for param in fn['params'][1:]]==[item['name'] for item in metadata['layout']]
        header='\n    #[external("public")]\n    fn '+name+'(\n        addresses: [AztecAddress; 10],\n'
        header+=f'        prepared_payload: [Field; {metadata["fields"]}],\n    ) -> bool '
        guard='\n        assert(self.internal._is_prepared_writer(self.msg_sender()), "Only audited system");'
        replacement=header+'{'+guard+metadata['decode']+fn['body']+'}'
        assert replacement.endswith(fn['body']+'}'), 'Backend statement order changed'
        fragment=fragment[:fn['start']]+replacement+fragment[fn['body_end']+1:]
    return fragment


def cache_move_configuration(fragment):
    """Use the attested Config cache; every failure keeps the original checks."""
    fn=p.functions(fragment)['_move_check_source'];body=fn['body']
    start=body.index('// Verify base config hashes in a single cross-contract call')
    end=body.index('// Verify source planet state hashes',start)
    original=body[start:end]
    expected_calls=[
        'self.view(config.verify_config_hashes(\n                    target_level,\n                    planet_default_stats_hash,\n                    config_hashes,\n                ))',
        'self.view(config.verify_artifacts_config_hash(artifacts_config_hash))',
    ]
    assert all(original.count(call)==1 for call in expected_calls)
    assert original.index(expected_calls[0])<original.index(expected_calls[1])
    cached='''// The current class, rather than an address or supplied flag, authenticates this cache.
            let mut cached_configuration_matches = false;
            let config_class = get_contract_instance_current_class_id_avm(addresses[0]);
            if config_class.is_some() {
                if (super::trusted_classes::CONFIG_CLASS != 0)
                    & (config_class.unwrap().to_field() == super::trusted_classes::CONFIG_CLASS) {
                    // SLOAD is constrained by the public VM and observes pending
                    // writes. These are the compiler-verified slots of this
                    // exact immutable Config class, not off-chain witness data.
                    let config_common_slot: Field = CONFIG_COMMON_SLOT;
                    let config_stats_map_slot: Field = CONFIG_STATS_MAP_SLOT;
                    let config_common_root = aztec::oracle::avm::storage_read(
                        config_common_slot, addresses[0].to_field(),
                    );
                    let config_stats_slot = aztec::protocol::storage::map::derive_storage_slot_in_map(
                        config_stats_map_slot, target_level,
                    );
                    let config_default_stats_root = aztec::oracle::avm::storage_read(
                        config_stats_slot, addresses[0].to_field(),
                    );
                    cached_configuration_matches = (config_common_root == poseidon2_hash([
                            config_hashes[0], config_hashes[1], config_hashes[2],
                            config_hashes[3], config_hashes[4], config_hashes[5],
                            config_hashes[6], config_hashes[7], config_hashes[8],
                            artifacts_config_hash,
                        ])) & (config_default_stats_root == planet_default_stats_hash);
                }
            }
            if !cached_configuration_matches {
                '''+original+'''
            }

            '''
    cached=cached.replace('CONFIG_COMMON_SLOT',str(CONFIG_SLOTS['move_configuration_root']))
    cached=cached.replace('CONFIG_STATS_MAP_SLOT',str(CONFIG_SLOTS['planet_default_stats_hash']))
    replacement=body[:start]+cached+body[end:]
    assert replacement.replace(cached,original,1)==body
    fragment=fragment[:fn['body_start']+1]+replacement+fragment[fn['body_end']:]
    return fragment,{'originalChecks':original,'replacement':cached, 'compiledConfigSlots': CONFIG_SLOTS,
                     'condition':'Current immutable Config class; ten exact original common hashes and requested-level stats',
                     'falseOrUnknown':'Run both original assertions in their original order'}


def retain_proved_state_fields(fragment, layouts):
    """Carry canonical private state fields directly to the raw event writers.

    The immutable System guard precedes decoding in both entries. Every field
    below already came from typed private Serialize; retaining the same words
    avoids a public typed reconstruction followed by another serialization.
    Arrival remains typed for its keyed lossless storage codec. No old-state
    verification, authorization, callback order or original public ABI changes.
    """
    original = fragment
    changes = []

    def replace(before, after, count=None):
        nonlocal fragment
        found = fragment.count(before)
        assert found > 0 and (count is None or found == count), (before, found, count)
        fragment = fragment.replace(before, after)
        changes.append({'before': before, 'after': after, 'count': found})

    states = {
        'new_source_planet': ('Planet', 32),
        'new_source_planet_artifacts_state': ('PlanetArtifacts', 22),
        'new_source_planet_events_state': ('PlanetEvents', 22),
        'new_target_planet': ('Planet', 32),
        'new_target_planet_artifacts_state': ('PlanetArtifacts', 22),
        'new_target_planet_events_state_input': ('PlanetEvents', 22),
        'new_moved_artifact_location_input': ('ArtifactLocation', 3),
        'new_source_activated_artifact': ('Artifact', 13),
        'new_source_activated_artifact_location': ('ArtifactLocation', 3),
    }
    for metadata in layouts.values():
        for item in metadata['layout']:
            name = item['name']
            if name not in states:
                continue
            typ, width = states[name]
            assert item['type'] == typ and item['width'] == width
            before = next(line for line in metadata['decode'].splitlines()
                          if line.startswith('        let '+name+': '))
            offset = item['offset']
            words = ', '.join(f'prepared_payload[{i}]' for i in range(offset, offset+width))
            after = f'        let {name}: [Field; {width}] = [{words}];'
            replace(before, after, 1)

    aliases = {**states,
               'new_target_planet_events_state': ('PlanetEvents', 22),
               'new_moved_artifact_location': ('ArtifactLocation', 3)}
    # Shared helper parameters use the same serialized representation. Entry
    # parameters remain the exact v1 [Field;539]/[Field;217] transport.
    for name, (typ, width) in aliases.items():
        before = f'{name}: {typ},'
        if before in fragment:
            replace(before, f'{name}: [Field; {width}],')

    for kind in ['planet', 'planet_artifacts', 'planet_events', 'artifact', 'artifact_location']:
        replace(f'self.internal._set_{kind}(', f'self.internal._set_{kind}_fields(')

    # These are the only publicly mutable fields in retained raw records. Their
    # offsets come from the captured original Serialize layouts, checked below.
    replace('new_target_planet_events_state.events[new_target_planet_events_state.count - 1].id',
            'new_target_planet_events_state[(new_target_planet_events_state[20] as u32) - 1]', 2)
    replace('new_target_planet_events_state.count > 0',
            '(new_target_planet_events_state[20] as u32) > 0', 2)
    # The original typed array has 20 event slots, although the complete raw
    # record also contains count/timestamp. Keep the same array bounds rather
    # than allowing either metadata slot to become an event through indexing.
    replace('new_target_planet_events_state[(new_target_planet_events_state[20] as u32) - 1] =',
            'assert((new_target_planet_events_state[20] as u32) <= 20, "Index out of bounds");\n            new_target_planet_events_state[(new_target_planet_events_state[20] as u32) - 1] =', 2)
    replace('new_moved_artifact_location.voyage_id', 'new_moved_artifact_location[1]', 2)
    replace('new_source_activated_artifact.artifact_type',
            '(new_source_activated_artifact[5] as u8)', 2)
    replace('new_source_activated_artifact.last_deactivated',
            '(new_source_activated_artifact[8] as u64)', 1)
    replace('new_source_activated_artifact.last_activated',
            '(new_source_activated_artifact[7] as u64)', 1)

    restored = fragment
    for change in reversed(changes):
        assert restored.count(change['after']) == change['count'], change
        restored = restored.replace(change['after'], change['before'])
    assert restored == original, 'Raw-state transform changed unrecorded statements'
    return fragment, {
        'states': {name: {'originalType': typ, 'fields': width} for name, (typ, width) in states.items()},
        'changes': changes,
        'originalFragmentHash': p.digest(original),
        'rawFragmentHash': p.digest(fragment),
        'trust': 'Actual immutable System class is checked before retaining typed private Serialize words.',
        'arrival': 'Original typed Arrival retained for late ID assignment and lossless keyed codec.',
    }


def flattened_private_enqueue(name, arguments, params):
    schemas=serialized_schema();widths=[field_width(schemas[param_name(param)]) for param in params]
    assert len(arguments)==len(params)
    width=sum(widths);lines=[f'let mut prepared_payload: [Field; {width}] = [0; {width}];']
    offset=0
    for index,(argument,size) in enumerate(zip(arguments,widths)):
        lines.append(f'let prepared_argument_{index}: [Field; {size}] = ({argument}).serialize();')
        lines.append(f'for prepared_index_{index} in 0..{size} {{ prepared_payload[{offset} + prepared_index_{index}] = prepared_argument_{index}[prepared_index_{index}]; }}')
        offset+=size
    assert offset==width
    lines.append(f'self.enqueue_self.{name}(prepared_payload);')
    return '\n            '.join(lines)


def bulk_move_transport(source, fragment, manifest):
    """Use proper typed bulk serde and construct successful public calldata once.

    Only additive transport APIs change. Their serialized values stay identical,
    with the existing ten configured addresses prefixed at the Backend boundary.
    The original public method and the original fallback body stay untouched.
    """
    original_fragment = fragment
    transport = {'library': 'libs::field_buffer::FieldBuffer', 'addressFields': 10, 'entries': {}}
    for variant, system_name, backend_name in [
        ('full', 'move_public_prepared', 'try_settle_move_move'),
        ('empty', 'move_public_empty_prepared', 'try_settle_move_move_empty'),
    ]:
        metadata = manifest['flatPreparedPayloads'][variant]
        width = metadata['fields']
        total = width + 10
        signature = f'{backend_name}(([Field;{total}]))'
        system = p.functions(source)[system_name]
        body = system['body']
        begin = body.index('            let state_backend = GameStateBackend::at(state_backend_address);')
        marker = 'state_backend.'+backend_name+'('
        opening = body.index(marker, begin)+len(marker)-1
        closing = p.closing(body, opening, '(', ')')
        args = p.split_arguments(body[opening+1:closing])
        assert len(args) == 2 and args[1].strip() == 'prepared_payload'
        assert args[0].strip().startswith('[') and args[0].strip().endswith(']')
        addresses = p.split_arguments(args[0].strip()[1:-1])
        assert len(addresses) == 10
        end = closing+len('));')
        assert body[closing:end] == '));'
        previous_forward = body[begin:end]
        lines = [
            f'            let mut backend_calldata: [Field; {total+1}] = [0; {total+1}];',
            '            backend_calldata[0] = comptime {',
            '                aztec::protocol::abis::function_selector::FunctionSelector::from_signature(',
            f'                    "{signature}",',
            '                ).to_field()',
            '            };',
        ]
        for index, address in enumerate(addresses):
            lines.append(f'            backend_calldata[{index+1}] = ({address.strip()}).to_field();')
        lines += [
            f'            for field_index in 0..{width} {{',
            '                backend_calldata[field_index + 11] = prepared_payload.words[field_index];',
            '            }',
            '            let backend_returns = libs::public_call::call(state_backend_address, backend_calldata);',
            '            settled_by_backend = aztec::protocol::traits::Deserialize::deserialize(backend_returns.as_array());',
        ]
        forward = '\n'.join(lines)
        body = body[:begin]+forward+body[end:]
        body = body.replace('prepared_payload[', 'prepared_payload.words[')
        header = make_header(system_name, [f'prepared_payload: FieldBuffer<{width}>'])
        replacement = header+'{'+body+'}'
        source = source[:system['start']]+replacement+source[system['body_end']+1:]

        entry = p.functions(fragment)[backend_name]
        original_backend_header = fragment[entry['start']:entry['body_start']]
        original_backend_body = entry['body']
        body = re.sub(r'prepared_payload\[(\d+)\]',
                      lambda m: f'prepared_payload.words[{int(m[1])+10}]', original_backend_body)
        guard = 'assert(self.internal._is_prepared_writer(self.msg_sender()), "Only audited system");'
        assert body.count(guard) == 1
        address_decode = '\n        let addresses: [AztecAddress; 10] = ['+ ', '.join(
            f'AztecAddress::from_field(prepared_payload.words[{i}])' for i in range(10))+'];'
        body = body.replace(guard, guard+address_decode, 1)
        header = '\n    #[external("public")]\n    fn '+backend_name+'(\n'
        header += f'        prepared_payload: libs::field_buffer::FieldBuffer<{total}>,\n    ) -> bool '
        fragment = fragment[:entry['start']]+header+'{'+body+'}'+fragment[entry['body_end']+1:]

        old_enqueue = f'self.enqueue_self.{system_name}(prepared_payload);'
        new_enqueue = f'self.enqueue_self.{system_name}(FieldBuffer {{ words: prepared_payload }});'
        assert source.count(old_enqueue) == 1
        source = source.replace(old_enqueue, new_enqueue)
        assert manifest['preparedEnqueue'].count(old_enqueue) == 1
        manifest['preparedEnqueue'] = manifest['preparedEnqueue'].replace(old_enqueue, new_enqueue)
        transport['entries'][variant] = {
            'systemMethod': system_name, 'backendMethod': backend_name,
            'systemFields': width, 'backendFields': total, 'calldataFields': total+1,
            'signature': signature, 'addresses': addresses,
            'previousForward': previous_forward, 'forward': forward,
            'originalBackendHeader': original_backend_header,
            'originalBackendBodyHash': p.digest(original_backend_body),
            'addressDecode': address_decode,
        }
    source = source.replace('use ::game_state_backend::GameStateBackend;',
                            'use ::game_state_backend::GameStateBackend;\n    use ::libs::field_buffer::FieldBuffer;', 1)
    source = source.replace('traits::{Serialize, FromField}', 'traits::{Serialize, FromField, ToField}', 1)
    manifest['fieldBufferTransport'] = transport
    manifest['preparedPayloadEncoding'] = 'Typed FieldBuffer bulk serde; one manual selector/address/payload buffer; exact SDK return decoding'
    manifest['sourceHash'] = p.digest(source)
    manifest['fullWrapperHash'] = p.digest(p.functions(source)['move_public_prepared']['full'])
    manifest['emptyWrapperHash'] = p.digest(p.functions(source)['move_public_empty_prepared']['full'])
    assert restore_backend_transport(fragment, transport) == original_fragment
    return source, fragment, manifest



def literal_move_calldata(source, manifest):
    """Build the same selector/address/payload sequence without zero-fill/copy.

    This changes only public transport. Preserve each prefix expression in its
    original evaluation order and each payload word exactly once in index order.
    """
    transform = {'entries': {}}
    for entry in manifest['fieldBufferTransport']['entries'].values():
        name = entry['systemMethod']
        fn = p.functions(source)[name]
        body = fn['body']
        start = body.index('let mut backend_calldata:')
        end = body.index('let backend_returns', start)
        before = body[start:end]
        size = int(re.search(r'backend_calldata: \[Field; (\d+)\]', before)[1])
        opening = before.index('{', before.index('backend_calldata[0]'))
        closing = p.closing(before, opening, '{', '}')
        selector = 'comptime ' + before[opening:closing+1]
        prefix = [selector] + [re.search(
            r'backend_calldata\['+str(index)+r'\] = (.*?);', before)[1]
            for index in range(1, 11)]
        width = int(re.search(r'for field_index in 0\.\.(\d+)', before)[1])
        assert width == entry['systemFields'] and width + 11 == size
        assert before.count('backend_calldata[field_index + 11] = prepared_payload.words[field_index];') == 1
        values = prefix + [f'prepared_payload.words[{index}]' for index in range(width)]
        after = f'let backend_calldata: [Field; {size}] = [\n' + ''.join(
            '                '+expression+',\n' for expression in values) + '            ];\n            '
        replacement = body[:start] + after + body[end:]
        assert replacement.replace(after, before, 1) == body
        assert replacement.split('if !settled_by_backend {', 1)[1] == body.split('if !settled_by_backend {', 1)[1]
        source = source[:fn['body_start']+1] + replacement + source[fn['body_end']:]
        transform['entries'][name] = {'before': before, 'after': after,
            'prefix': prefix, 'fields': width, 'originalBodyHash': p.digest(body)}
        entry['loopForward'] = entry['forward']
        assert entry['forward'].count(before) == 1
        entry['forward'] = entry['forward'].replace(before, after, 1)
    manifest['literalCalldataTransform'] = transform
    return source, manifest


def preserve_custom_configuration_caller(source, manifest):
    """Only relocate Config reads when its actual immutable class is recognized.

    A compatible custom Config may inspect msg_sender. Leaving it inside the
    original Move helper preserves that caller as well as arguments and errors.
    This public dispatch change adds no private call or player transaction.
    """
    recognition = {'helper': '::libs::config_recognition::supports_config', 'entries': {}}
    for name in ['move_public_prepared', 'move_public_empty_prepared']:
        fn = p.functions(source)[name]
        body = fn['body']
        condition = 'if state_backend_address != AztecAddress::zero() {'
        assert body.count(condition) == 1
        opening = body.index('{', body.index(condition))
        closing = p.closing(body, opening, '{', '}')
        original_inner = body[opening+1:closing]
        assert original_inner.count('libs::public_call::call(state_backend_address, backend_calldata)') == 1
        guard = 'if ::libs::config_recognition::supports_config(self.storage.config_storage_address.read()) {'
        guarded_inner = '\n            '+guard+''.join(
            '\n    '+line if line else '\n' for line in original_inner.split('\n')[1:])
        guarded_inner = guarded_inner.rstrip()+'\n            }\n        '
        replacement = body[:opening+1]+guarded_inner+body[closing:]
        assert replacement.replace(guarded_inner, original_inner, 1) == body
        assert replacement.split('if !settled_by_backend {', 1)[1] == body.split('if !settled_by_backend {', 1)[1]
        source = source[:fn['body_start']+1]+replacement+source[fn['body_end']:]
        recognition['entries'][name] = {'guard':guard, 'originalInner':original_inner,
            'guardedInner':guarded_inner, 'originalBodyHash':p.digest(body)}
    manifest['systemConfigurationRecognition'] = recognition
    manifest['sourceHash'] = p.digest(source)
    manifest['fullWrapperHash'] = p.digest(p.functions(source)['move_public_prepared']['full'])
    manifest['emptyWrapperHash'] = p.digest(p.functions(source)['move_public_empty_prepared']['full'])
    return source, manifest


def preserve_empty_fallback_locations(source, manifest):
    """Retain inactive batch payloads that arbitrary compatible stores can read.

    A canonical count-zero batch ignores its states, but a configured custom
    implementation can inspect every argument. Append both location arrays for
    System fallback only; the authenticated Backend keeps its original217 words.
    """
    name = 'move_public_empty_prepared'
    schema = serialized_schema()
    entry = manifest['fieldBufferTransport']['entries']['empty']
    assert entry['systemFields'] == 217 and entry['backendFields'] == 227
    fn = p.functions(source)[name]
    old_header = source[fn['start']:fn['body_start']]
    body = fn['body']
    old_body = body
    changes = []
    append = []
    offset = 217
    for side in ['source', 'target']:
        variable = f'new_{side}_arrival_artifact_locations'
        typ = '[ArtifactLocation; 20]'
        value, end = reconstruct_typed(schema[variable], offset)
        assert end == offset + 60
        value = value.replace('prepared_payload[', 'prepared_payload.words[')
        before = f'let {variable}: {typ} = [ArtifactLocation::zero(); 20];'
        after = f'let {variable}: {typ} = {value};'
        assert body.count(before) == 1
        body = body.replace(before, after, 1)
        changes.append({'name':variable, 'offset':offset, 'width':60, 'before':before, 'after':after})
        append += [f'let fallback_{side}_locations: [Field; 60] = ({variable}).serialize();',
            f'for fallback_{side}_index in 0..60 {{ prepared_payload[{offset} + fallback_{side}_index] = fallback_{side}_locations[fallback_{side}_index]; }}']
        offset = end
    assert offset == 337
    # No appended field is forwarded to the canonical Backend.
    old_forward = old_body.split('if !settled_by_backend {', 1)[0]
    assert body.split('if !settled_by_backend {', 1)[0] == old_forward
    header = old_header.replace('FieldBuffer<217>', 'FieldBuffer<337>')
    assert header != old_header
    source = source[:fn['start']] + header+'{'+body+'}' + source[fn['body_end']+1:]
    old_enqueue = manifest['preparedEnqueue']
    enqueue = old_enqueue.replace('let mut prepared_payload: [Field; 217] = [0; 217];',
                                  'let mut prepared_payload: [Field; 337] = [0; 337];', 1)
    assert enqueue != old_enqueue
    call = 'self.enqueue_self.move_public_empty_prepared(FieldBuffer { words: prepared_payload });'
    assert enqueue.count(call) == 1
    append_text = '\n            '.join(append)+'\n            '
    enqueue = enqueue.replace(call, append_text+call, 1)
    assert source.count(old_enqueue) == 1
    source = source.replace(old_enqueue, enqueue, 1)
    manifest['preparedEnqueue'] = enqueue
    entry['settlementFields'] = 217
    entry['systemFields'] = 337
    manifest['emptyFallbackPayload'] = {'fields':337, 'settlementPrefixFields':217,
        'changes':changes, 'originalBodyHash':p.digest(old_body),
        'originalHeader':old_header, 'originalEnqueue':old_enqueue, 'append':append_text,
        'reason':'Original configured stores can observe count-zero location-array fields; canonical Backend does not need them.'}
    manifest['sourceHash'] = p.digest(source)
    manifest['fullWrapperHash'] = p.digest(p.functions(source)['move_public_prepared']['full'])
    manifest['emptyWrapperHash'] = p.digest(p.functions(source)[name]['full'])
    return source, manifest


def restore_empty_fallback_locations(body, manifest):
    for change in reversed(manifest['emptyFallbackPayload']['changes']):
        assert body.count(change['after']) == 1
        body = body.replace(change['after'], change['before'], 1)
    assert p.digest(body) == manifest['emptyFallbackPayload']['originalBodyHash']
    return body


def restore_backend_transport(fragment, transport):
    """Reverse only bulk transport, for independent v2 statement equivalence."""
    for entry in transport['entries'].values():
        fn = p.functions(fragment)[entry['backendMethod']]
        body = fn['body']
        assert body.count(entry['addressDecode']) == 1
        body = body.replace(entry['addressDecode'], '', 1)
        def original_word(match):
            index = int(match[1])
            assert index >= 10, 'Address prefix leaked into an original Move state field'
            return f'prepared_payload[{index-10}]'
        body = re.sub(r'prepared_payload\.words\[(\d+)\]', original_word, body)
        assert p.digest(body) == entry['originalBackendBodyHash'], 'Bulk transport changed a settlement statement'
        fragment = fragment[:fn['start']]+entry['originalBackendHeader']+'{'+body+'}'+fragment[fn['body_end']+1:]
    return fragment


def build(snapshot):
    old = p.functions(snapshot)
    head, fallback_authority = immutable_originals()
    for name, original_function in head.items():
        assert name in old, (name, 'Original Move function missing from snapshot')
        assert p.digest(old[name]['header']) == p.digest(original_function['header']), (name, 'Original signature drift')
        if name != 'move_public':
            assert p.digest(old[name]['full']) == p.digest(original_function['full']), (name, 'Snapshot differs from immutable original')
    private, public = old['move'], old['move_public']
    old_public_body = public['body']
    _, restoration = scalar_checks(old_public_body)
    # The earlier snapshot includes count/ID guards. Those guards are safe only
    # in the recognized canonical backend, because arbitrary original stores
    # can observe (or reject) even an empty verification call. Restore the full
    # original public body, including all six unconditional batch verifications.
    fallback_body = head['move_public']['body']
    restored_source = snapshot[:public['body_start'] + 1] + fallback_body + snapshot[public['body_end']:]
    original = p.functions(restored_source)
    public = original['move_public']
    record = {'private': 'move', 'original': 'move_public', 'prepared': 'move_public_prepared', 'states': STATES}
    full_params = public['params'] + [p.root_name(state) + ': Field' for state in STATES]
    empty_params = [param for param in full_params if param_name(param) not in OMITTED]
    scaffolding = make_header(record['prepared'], full_params) + '{' + fallback_body + '}'
    scaffolding += make_header('move_public_empty_prepared', empty_params) + '{' + fallback_body + '}'
    synthetic = restored_source + scaffolding
    full_wrapper, _ = backend.wrapper('move', synthetic, record)
    empty_record = {**record, 'private': 'move_empty', 'prepared': 'move_public_empty_prepared'}
    empty_wrapper, _ = backend.wrapper('move', synthetic, empty_record)
    zero_declarations = '\n'
    for param in public['params']:
        name = param_name(param)
        if name not in OMITTED:
            continue
        kind = param.split(':', 1)[1].strip()
        if kind == '[Field; 20]':
            value = '[0; 20]'
        elif kind == '[ArtifactLocation; 20]':
            value = '[ArtifactLocation::zero(); 20]'
        elif kind == 'u32':
            value = '0'
        else:
            raise AssertionError((name, kind))
        zero_declarations += f'            let {name}: {kind} = {value};\n'
    empty_wrapper = empty_wrapper.replace('if !settled_by_backend {', 'if !settled_by_backend {' + zero_declarations, 1)
    # The backend retains its efficient scalar triple verifier; fallback uses
    # the three original public methods, including scalar ID-zero reads.
    full_backend, operations = backend.fragment('move', snapshot, record)
    empty_backend = empty_fragment(full_backend)
    fragment = '// Generated Move settlement: seven private-bound roots; late ID fields remain public-hashed.\n' + full_backend + empty_backend
    private = original['move']
    start, end, args = p.enqueue(private['body'], 'move_public')
    param_names = [param_name(param) for param in public['params']]
    roots = ['poseidon2_hash((' + args[param_names.index(state)] + ').serialize())' for state in STATES]
    empty_args = [arg for name, arg in zip(param_names, args) if name not in OMITTED]
    def call(name, arguments):
        params = empty_params if name == 'move_public_empty_prepared' else full_params
        return flattened_private_enqueue(name,arguments+roots,params)
    branch = 'if (original_source_arrivals_count == 0) & (original_target_arrivals_count == 0) {\n'
    branch += '            ' + call('move_public_empty_prepared', empty_args) + '\n        } else {\n'
    branch += '            ' + call('move_public_prepared', args) + '\n        }'
    source = restored_source[:private['body_start'] + 1 + start] + branch + restored_source[private['body_start'] + 1 + end:]
    contract = re.search(r'\bcontract\s+\w+\s*\{', source)
    opening = source.index('{', contract.start())
    ending = p.closing(source, opening, '{', '}')
    full_wrapper,full_flat=flatten_forwarding_wrapper(full_wrapper,'move_public_prepared',full_params,'try_settle_move_move')
    empty_wrapper,empty_flat=flatten_forwarding_wrapper(empty_wrapper,'move_public_empty_prepared',empty_params,'try_settle_move_move_empty')
    additions = full_wrapper + '\n' + empty_wrapper + '''
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

    #[external("public")]
    #[view]
    fn get_state_backend() -> AztecAddress {
        self.storage.state_backend.read()
    }
'''
    source = source[:ending] + additions + '\n' + source[ending:]
    source = source[:opening + 1] + '\n    use ::game_state_backend::GameStateBackend;\n' + source[opening + 1:]
    storage_match = re.search(r'struct Storage<Context>\s*\{', source)
    closing = p.closing(source, source.index('{', storage_match.start()), '{', '}')
    source = source[:closing] + '    state_backend: PublicMutable<AztecAddress, Context>,\n    ' + source[closing:]
    source = source.replace('traits::Serialize', 'traits::{Serialize, FromField}', 1)
    # All three public selectors retain their signatures, but share the exact
    # original legacy implementation. Empty arrays are created only inside the
    # existing fallback branch, never on a successful central empty settlement.
    legacy_call = '\n        _move_public_legacy(\n            self.context,\n' + ''.join(
        '            ' + param_name(param) + ',\n' for param in public['params']) + '        );\n    '
    assert source.count(fallback_body) == 3, 'Expected exactly three original legacy body copies'
    source = source.replace(fallback_body, legacy_call)
    full_wrapper = full_wrapper.replace(fallback_body, legacy_call)
    empty_wrapper = empty_wrapper.replace(fallback_body, legacy_call)
    legacy_context = '\n        let mut self = __aztec_nr_internals__create_public_self_from_context(context);'
    legacy_helper = '\n    #[inline_never]\n    #[contract_library_method]\n    unconstrained fn _move_public_legacy(\n        context: aztec::context::PublicContext,\n' + ''.join(
        '        ' + param + ',\n' for param in public['params']) + '    ) {' + legacy_context + fallback_body + '}\n'
    ending=p.closing(source,source.index('{',re.search(r'\bcontract\s+\w+\s*\{',source).start()),'{','}')
    source=source[:ending]+legacy_helper+source[ending:]
    manifest = {
        'scope': 'Fresh-deployment Move full/empty centralized paths. Original signatures, checks and event order retained.',
        'flatPreparedPayloads': {'full':full_flat,'empty':empty_flat},
        'preparedPayloadEncoding': 'Typed private serialization; opaque System forwarding; audited Backend static decode',
        'preparedStates': STATES, 'omittedEmptyParameters': sorted(OMITTED),
        'legacyFactoring': {'helper':'_move_public_legacy', 'call':legacy_call, 'body':fallback_body, 'contextSetup':legacy_context, 'helperHash':p.digest(legacy_helper)},
        'emptyEligibility': 'Both original arrival counts are zero; ignored inactive input slots remain semantically ignored.',
        'scalarFallbackRestoration': restoration, 'operations': operations,
        'baselineFallbackAuthority': fallback_authority,
        'originalFunctions': {name: {'signatureHash': p.digest(fn['header']), 'functionHash': p.digest(fn['full'])} for name, fn in head.items()},
        'originalEnqueue': private['body'][start:end], 'preparedEnqueue': branch,
        'sourceHash': p.digest(source), 'fragmentHash': p.digest(fragment),
        'fullWrapperHash': p.digest(full_wrapper), 'emptyWrapperHash': p.digest(empty_wrapper),
    }
    # Keep the manifest's original canonical body hash, and independently verify
    # factored expansion within factor_move_blocks before writing the new fragment.
    fragment = '// Generated shared Move settlement; exact canonical statement expansion checked.\n' + factor_move_blocks(full_backend, empty_backend)
    fragment=flatten_backend_entries(fragment,{'try_settle_move_move':full_flat,'try_settle_move_move_empty':empty_flat})
    fragment,manifest['configurationCacheTransform']=cache_move_configuration(fragment)
    fragment,manifest['rawStateTransform']=retain_proved_state_fields(fragment,{'full':full_flat,'empty':empty_flat})
    source,fragment,manifest=bulk_move_transport(source,fragment,manifest)
    source,manifest=literal_move_calldata(source,manifest)
    source,manifest=preserve_custom_configuration_caller(source,manifest)
    source,manifest=preserve_empty_fallback_locations(source,manifest)
    source='\n'.join(line.rstrip() for line in source.splitlines())+'\n'
    return source, fragment, manifest


def run(apply=False):
    initial_apply = apply and not MANIFEST.exists()
    if initial_apply:
        snapshot = SOURCE.read_text()
    else:
        snapshot = SNAPSHOT.read_text()
    source, fragment, manifest = build(snapshot)
    if apply:
        if initial_apply:
            SNAPSHOT.parent.mkdir(parents=True, exist_ok=True)
            SNAPSHOT.write_text(snapshot)
        else:
            # Regenerating a public compatibility correction must not silently
            # change the already approved private circuit or its enqueue.
            before = p.functions(SOURCE.read_text())['move']
            after = p.functions(source)['move']
            assert before['body'] == after['body'], 'Public-only regeneration changed private Move'
        SOURCE.write_text(source)
        DEST.write_text(fragment)
        MANIFEST.write_text(json.dumps(manifest, indent=2) + '\n')
        nargo = SOURCE.parents[1] / 'Nargo.toml'
        text = nargo.read_text()
        if 'game_state_backend' not in text:
            nargo.write_text(text.rstrip() + '\ngame_state_backend = { path = "../../state_backend" }\n')
    else:
        assert p.digest(SOURCE.read_text()) == manifest['sourceHash'], 'Move source differs from recorded transform'
        assert DEST.read_text() == fragment, 'Move backend fragment differs'
        assert json.loads(MANIFEST.read_text()) == manifest, 'Move manifest differs'
    # Independently reverse the private call change and check every old method.
    current = p.functions(SOURCE.read_text())
    for name, expected in manifest['originalFunctions'].items():
        fn = current[name]
        assert p.digest(fn['header']) == expected['signatureHash'], (name, 'signature changed')
        restored = fn['full']
        if name == 'move':
            assert restored.count(manifest['preparedEnqueue']) == 1
            restored = restored.replace(manifest['preparedEnqueue'], manifest['originalEnqueue'], 1)
        if name == 'move_public':
            assert restored.count(manifest['legacyFactoring']['call'])==1
            restored=restored.replace(manifest['legacyFactoring']['call'],manifest['legacyFactoring']['body'],1)
        assert p.digest(restored) == expected['functionHash'], (name, 'original computation changed')
    helper=current['_move_public_legacy']
    assert helper['body']==manifest['legacyFactoring']['contextSetup']+manifest['legacyFactoring']['body']
    head, authority = immutable_originals()
    assert authority == manifest['baselineFallbackAuthority']
    assert p.digest(manifest['legacyFactoring']['body']) == p.digest(head['move_public']['body']), 'Fallback must match immutable original, not its transform manifest'
    clean_trailing = lambda text: '\n'.join(line.rstrip() for line in text.splitlines())
    for name in ['move_public_prepared', 'move_public_empty_prepared']:
        assert clean_trailing(current[name]['body']).count(clean_trailing(manifest['legacyFactoring']['call'])) == 1, 'Fallback must call the shared original method exactly once'
    print('PASS: Move original API/computation; seven prepared roots; full and zero-queue backend paths; scalar legacy fallback')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--apply', action='store_true')
    group.add_argument('--check', action='store_true')
    args = parser.parse_args()
    run(args.apply)
