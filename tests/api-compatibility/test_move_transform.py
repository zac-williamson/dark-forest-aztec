"""Security and field-preservation checks for the new Move transport only.

Full gameplay semantics remain covered by the original-source expansion and
mined differential action tests. These tests do not claim a fee improvement.
"""
import importlib.util
import json
import re
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('move_transport', HERE / 'generate-backend-move.py')
MOVE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOVE)


class MoveTransportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source, cls.fragment, cls.manifest = MOVE.build(MOVE.SNAPSHOT.read_text())
        cls.system = MOVE.p.functions(cls.source)
        cls.backend = MOVE.p.functions(cls.fragment)

    def test_full_payload_preserves_every_original_field_and_seven_roots(self):
        original = MOVE.p.functions(MOVE.SNAPSHOT.read_text())['move_public']['params']
        expected = [MOVE.param_name(p) for p in original]
        expected += [MOVE.p.root_name(state) for state in MOVE.STATES]
        layout = self.manifest['flatPreparedPayloads']['full']
        self.assertEqual([item['name'] for item in layout['layout']], expected)
        self.assertEqual(layout['fields'], 539)
        offsets = [i for item in layout['layout']
                   for i in range(item['offset'], item['offset'] + item['width'])]
        self.assertEqual(offsets, list(range(539)))

    def test_empty_settlement_prefix_omits_only_canonical_count_zero_batches(self):
        full = self.manifest['flatPreparedPayloads']['full']['layout']
        empty = self.manifest['flatPreparedPayloads']['empty']
        self.assertEqual([item['name'] for item in empty['layout']],
                         [item['name'] for item in full if item['name'] not in MOVE.OMITTED])
        self.assertEqual(empty['fields'], 217)
        self.assertIn('new_target_planet_events_state_input', [item['name'] for item in empty['layout']])
        self.assertEqual(self.manifest['emptyFallbackPayload']['fields'], 337)

    def test_new_system_transport_is_only_self_and_does_not_decode_on_fast_path(self):
        for name in ['move_public_prepared', 'move_public_empty_prepared']:
            fn = self.system[name]
            self.assertIn('#[only_self]', fn['header'])
            forward, fallback = fn['body'].split('if !settled_by_backend {', 1)
            self.assertIn('prepared_payload.words[0]', forward)
            self.assertNotIn('for field_index', forward)
            self.assertNotIn('let mut backend_calldata', forward)
            self.assertIn('libs::public_call::call(state_backend_address, backend_calldata)', forward)
            self.assertNotIn('self.call(', forward)
            self.assertNotIn('.concat(', forward)
            self.assertNotIn(' as u', forward)
            self.assertNotIn('Planet {', forward)
            self.assertNotIn('ArtifactLocation::zero()', forward)
            self.assertIn('_move_public_legacy(', fallback)
            self.assertIn('prepared_payload.words[', fallback)

    def test_custom_config_keeps_original_system_caller_and_identical_fallback(self):
        recognition = self.manifest['systemConfigurationRecognition']
        self.assertEqual(recognition['helper'], '::libs::config_recognition::supports_config')
        for name, entry in recognition['entries'].items():
            body = self.system[name]['body']
            if name == 'move_public_empty_prepared':
                body = MOVE.restore_empty_fallback_locations(body, self.manifest)
            self.assertEqual(body.count(entry['guard']), 1)
            opening = body.index('{', body.index(entry['guard']))
            closing = MOVE.p.closing(body, opening, '{', '}')
            guarded = body[opening+1:closing]
            self.assertIn('libs::public_call::call(state_backend_address, backend_calldata)', guarded)
            self.assertNotIn('if !settled_by_backend', guarded)
            self.assertLess(closing, body.index('if !settled_by_backend {'))
            self.assertEqual(body.count('let mut settled_by_backend = false;'), 1)
            restored = body.replace(entry['guardedInner'], entry['originalInner'], 1)
            self.assertEqual(MOVE.p.digest(restored), entry['originalBodyHash'])
            fallback = body.split('if !settled_by_backend {', 1)[1]
            self.assertEqual(fallback.count('_move_public_legacy('), 1)
            self.assertNotIn('self.enqueue', body)
            self.assertNotIn('config.verify', body)
            if name == 'move_public_empty_prepared':
                self.assertIn('[ArtifactLocation::zero(); 20]', fallback)
                self.assertIn('let original_source_arrivals_count: u32 = 0;', fallback)
                self.assertIn('let original_target_arrivals_count: u32 = 0;', fallback)

    def test_backend_authenticates_actual_caller_before_static_decode(self):
        for name in ['try_settle_move_move', 'try_settle_move_move_empty']:
            body = self.backend[name]['body']
            guard = 'assert(self.internal._is_prepared_writer(self.msg_sender()), "Only audited system");'
            self.assertEqual(body.count(guard), 1)
            self.assertLess(body.index(guard), body.index('prepared_payload.words['))
            self.assertLess(body.index(guard), body.index('_can_settle('))

    def test_original_only_self_api_keeps_original_typed_parameters(self):
        original = MOVE.p.functions(MOVE.BASELINE.read_text())['move_public']
        current = self.system['move_public']
        self.assertEqual(current['params'], original['params'])
        self.assertIn('#[only_self]', current['header'])
        self.assertNotIn('prepared_payload', current['header'])
        helper = self.system['_move_public_legacy']['body']
        self.assertEqual(helper, self.manifest['legacyFactoring']['contextSetup'] + original['body'])

    def test_original_fallback_keeps_all_six_unconditional_batch_calls(self):
        original = MOVE.p.functions(MOVE.BASELINE.read_text())['move_public']['body']
        helper = self.system['_move_public_legacy']['body']
        body = helper.removeprefix(self.manifest['legacyFactoring']['contextSetup'])
        self.assertEqual(MOVE.p.digest(body), MOVE.p.digest(original))
        calls = list(re.finditer(r'self\.view\((\w+)\.verify_hashes_batch\(', body))
        self.assertEqual([call.group(1) for call in calls], [
            'arrivals_storage', 'artifact_storage', 'artifact_location_storage',
            'arrivals_storage', 'artifact_storage', 'artifact_location_storage',
        ])
        for branch in re.finditer(r'\bif\b', MOVE.p.mask(body, strings=True)):
            opening = body.index('{', branch.end())
            closing = MOVE.p.closing(body, opening, '{', '}')
            for call in calls:
                self.assertFalse(opening < call.start() < closing, 'Original batch call became conditional')
        self.assertNotIn('has_nonzero_ids', body)

    def test_empty_omitted_id_arrays_are_already_zero_in_original_private_output(self):
        def hash_helper(source):
            opening = source.index('{', source.index('pub fn compute_planet_hashes('))
            closing = MOVE.p.closing(source, opening, '{', '}')
            return source[opening + 1:closing]
        path = MOVE.HERE / 'baseline/sources/contracts/libs/src/batch_utils.nr'
        baseline_helper = hash_helper(path.read_text())
        current_helper = hash_helper((MOVE.p.ROOT / 'contracts/libs/src/batch_utils.nr').read_text())
        self.assertEqual(MOVE.p.digest(current_helper), MOVE.p.digest(baseline_helper))
        opening = baseline_helper.index('{', baseline_helper.index('if i < planet_events_state.count'))
        closing = MOVE.p.closing(baseline_helper, opening, '{', '}')
        for name in ['arrival_ids', 'arrival_hashes', 'artifact_ids', 'artifact_hashes', 'artifact_location_hashes']:
            self.assertIn(f'let mut {name}: [Field; 20] = [0; 20];', baseline_helper)
            writes = list(re.finditer(r'\b' + name + r'\[i\]\s*=', baseline_helper))
            self.assertEqual(len(writes), 1)
            self.assertTrue(opening < writes[0].start() < closing)

    def test_no_scalar_or_inactive_slot_is_removed_from_canonical_state(self):
        schemas = MOVE.serialized_schema()
        for name, width in [('new_source_planet', 32), ('new_arrival_input', 11),
                            ('new_source_activated_artifact', 13),
                            ('new_target_planet_events_state_input', 22),
                            ('new_source_arrival_artifact_locations', 60)]:
            self.assertEqual(MOVE.field_width(schemas[name]), width)
        expression, end = MOVE.reconstruct_typed(schemas['new_target_planet_events_state_input'], 0)
        self.assertEqual(end, 22)
        self.assertEqual(expression.count('PlanetEventMetadata {'), 20)
        self.assertIn('prepared_payload[19]', expression)
        self.assertIn('(prepared_payload[21] as u64)', expression)

    def test_config_cache_covers_exact_original_hashes_and_selected_level(self):
        config_source = (MOVE.p.ROOT / 'contracts/config/src/main.nr').read_text()
        config = MOVE.p.functions(config_source)
        cached_fields = re.findall(r'self\.storage\.(\w+_hash)\.read\(\)',
                                   config['refresh_move_configuration_root']['body'])
        old_fields = re.findall(r'self\.storage\.(\w+_hash)\.read\(\)',
                                config['verify_config_hashes']['body'])
        old_fields += re.findall(r'self\.storage\.(\w+_hash)\.read\(\)',
                                 config['verify_artifacts_config_hash']['body'])
        self.assertEqual(cached_fields, old_fields)
        self.assertEqual(len(cached_fields), 10)
        self.assertIn('self.storage.planet_default_stats_hash.at(level).read() == default_stats_root',
                      config['verify_move_configuration']['body'])
        checked_writers = []
        for name, fn in config.items():
            positions = [match.start() for match in re.finditer(r'self\.storage\.(\w+)\.write\(', fn['body'])
                         if match.group(1) in cached_fields]
            if positions:
                self.assertGreater(fn['body'].rfind('self.internal.refresh_move_configuration_root();'),
                                   max(positions), name)
                checked_writers.append(name)
        self.assertGreaterEqual(len(checked_writers), 10)
        self.assertIn('self.internal.refresh_move_configuration_root();', config['constructor']['body'])

    def test_config_cache_failure_restores_exact_original_assertion_order(self):
        transform = self.manifest['configurationCacheTransform']
        replacement = transform['replacement']
        self.assertEqual(replacement.count(transform['originalChecks']), 1)
        self.assertIn('if !cached_configuration_matches {', replacement)
        self.assertLess(replacement.index('get_contract_instance_current_class_id_avm(addresses[0])'),
                        replacement.index('aztec::oracle::avm::storage_read('))
        self.assertIn('config_class.unwrap().to_field() == super::trusted_classes::CONFIG_CLASS', replacement)
        self.assertEqual(replacement.count('aztec::oracle::avm::storage_read('), 2)
        self.assertNotIn('config.verify_move_configuration(', replacement)
        self.assertIn('config_stats_map_slot, target_level,', replacement)
        self.assertIn('config_default_stats_root == planet_default_stats_hash', replacement)
        self.assertEqual(transform['compiledConfigSlots'], MOVE.CONFIG_SLOTS)
        self.assertEqual(re.findall(r'config_hashes\[(\d+)\]', replacement[:replacement.index('if !cached_configuration_matches {')]),
                         [str(i) for i in range(9)])
        self.assertLess(transform['originalChecks'].index('"Config hash mismatch"'),
                        transform['originalChecks'].index('"Artifacts config hash mismatch"'))

    def test_raw_records_retain_exact_original_serialized_widths(self):
        schemas = MOVE.serialized_schema()
        raw = self.manifest['rawStateTransform']
        self.assertEqual(len(raw['states']), 9)
        for name, state in raw['states'].items():
            self.assertEqual(MOVE.field_width(schemas[name]), state['fields'])
        for name in ['try_settle_move_move', 'try_settle_move_move_empty']:
            body = self.backend[name]['body']
            for variable, state in raw['states'].items():
                self.assertIn(f'let {variable}: [Field; {state["fields"]}]', body)
            self.assertIn('let new_arrival_input: Arrival = Arrival {', body)
            self.assertNotIn('Planet {', body)

    def test_late_raw_patches_keep_original_field_offsets_and_twenty_slot_bounds(self):
        schemas = MOVE.serialized_schema()
        queue = schemas['new_target_planet_events_state_input']['fields']
        self.assertEqual([(item['name'], MOVE.field_width(item['type'])) for item in queue],
                         [('events', 20), ('count', 1), ('last_updated', 1)])
        self.assertEqual([field['name'] for field in schemas['new_moved_artifact_location_input']['fields']],
                         ['planet_id', 'voyage_id', 'last_updated'])
        artifact = [field['name'] for field in schemas['new_source_activated_artifact']['fields']]
        self.assertEqual([artifact[i] for i in [5, 7, 8]],
                         ['artifact_type', 'last_activated', 'last_deactivated'])
        for name in ['try_settle_move_move', 'try_settle_move_move_empty']:
            body = self.backend[name]['body']
            lower = body.index('assert((new_target_planet_events_state[20] as u32) > 0')
            upper = body.index('assert((new_target_planet_events_state[20] as u32) <= 20')
            write = body.index('new_target_planet_events_state[(new_target_planet_events_state[20] as u32) - 1] =')
            self.assertLess(lower, upper)
            self.assertLess(upper, write)
            self.assertIn('new_moved_artifact_location[1] = event_id;', body)

    def test_raw_transform_is_exactly_reversible_without_check_or_event_reordering(self):
        transform = self.manifest['rawStateTransform']
        restored = MOVE.restore_backend_transport(self.fragment, self.manifest['fieldBufferTransport'])
        for change in reversed(transform['changes']):
            self.assertEqual(restored.count(change['after']), change['count'])
            restored = restored.replace(change['after'], change['before'])
        self.assertEqual(MOVE.p.digest(restored), transform['originalFragmentHash'])
        for name in ['_move_write_source', '_move_write_target']:
            body = self.backend[name]['body']
            calls = re.findall(r'self\.internal\._set_(\w+)\(', body)
            self.assertEqual(calls, ['planet_fields', 'planet_artifacts_fields', 'planet_events_fields'])

    def test_bulk_transport_binds_each_configured_address_and_every_original_word(self):
        transport = self.manifest['fieldBufferTransport']
        self.assertEqual(transport['addressFields'], 10)
        for variant, entry in transport['entries'].items():
            width = self.manifest['flatPreparedPayloads'][variant]['fields']
            self.assertEqual(entry['systemFields'], 337 if variant == 'empty' else width)
            self.assertEqual(entry['backendFields'], width+10)
            self.assertEqual(entry['calldataFields'], width+11)
            self.assertEqual(self.system[entry['systemMethod']]['params'], [f'prepared_payload: FieldBuffer<{entry["systemFields"]}>'])
            self.assertEqual(self.backend[entry['backendMethod']]['params'], [f'prepared_payload: libs::field_buffer::FieldBuffer<{width+10}>'])
            forward = entry['forward']
            self.assertNotIn('for field_index', forward)
            self.assertEqual(re.findall(r'prepared_payload\.words\[(\d+)\]', forward),
                             [str(index) for index in range(width)])
            for address in entry['addresses']:
                self.assertIn(f'({address.strip()}).to_field(),', forward)
            self.assertIn('aztec::protocol::traits::Deserialize::deserialize(backend_returns.as_array())', forward)
            self.assertEqual(entry['signature'], f'{entry["backendMethod"]}(([Field;{width+10}]))')
            offsets = {int(index) for index in re.findall(r'prepared_payload\.words\[(\d+)\]', self.backend[entry['backendMethod']]['body'])}
            self.assertEqual(offsets, set(range(width+10)))

    def test_literal_calldata_changes_no_selector_prefix_return_or_fallback(self):
        for name, change in self.manifest['literalCalldataTransform']['entries'].items():
            recognition = self.manifest['systemConfigurationRecognition']['entries'][name]
            body = self.system[name]['body']
            if name == 'move_public_empty_prepared':
                body = MOVE.restore_empty_fallback_locations(body, self.manifest)
            body = body.replace(
                recognition['guardedInner'], recognition['originalInner'], 1)
            self.assertEqual(body.count(change['after']), 1)
            restored = body.replace(change['after'], change['before'], 1)
            self.assertEqual(MOVE.p.digest(restored), change['originalBodyHash'])
            literal = change['after']
            opening = literal.index('[', literal.index(' = '))
            closing = MOVE.p.closing(literal, opening, '[', ']')
            actual = [item.strip() for item in MOVE.p.split_arguments(literal[opening+1:closing])]
            expected = change['prefix'] + [f'prepared_payload.words[{i}]' for i in range(change['fields'])]
            self.assertEqual(actual, expected)

    def test_empty_fallback_retains_all120_location_fields_without_forwarding_them(self):
        record = self.manifest['emptyFallbackPayload']
        self.assertEqual([(item['name'],item['offset'],item['width']) for item in record['changes']], [
            ('new_source_arrival_artifact_locations',217,60),
            ('new_target_arrival_artifact_locations',277,60),
        ])
        body = self.system['move_public_empty_prepared']['body']
        forward, fallback = body.split('if !settled_by_backend {', 1)
        self.assertEqual([int(index) for index in re.findall(r'prepared_payload\.words\[(\d+)\]', forward)], list(range(217)))
        for side, change in zip(['source','target'],record['changes']):
            self.assertIn(change['after'], fallback)
            self.assertEqual([int(index) for index in re.findall(r'prepared_payload\.words\[(\d+)\]', change['after'])],
                             list(range(change['offset'],change['offset']+60)))
            self.assertIn(f'(new_{side}_arrival_artifact_locations).serialize()', record['append'])
        self.assertNotIn('[ArtifactLocation::zero(); 20]', fallback)
        self.assertEqual(self.system['move']['body'].count('self.enqueue_self.move_public_empty_prepared('),1)
        self.assertEqual(self.system['move']['body'].count('self.enqueue_self.move_public_prepared('),1)
        original_full = record['originalEnqueue'].split('} else {',1)[1]
        self.assertEqual(self.manifest['preparedEnqueue'].split('} else {',1)[1],original_full)


if __name__ == '__main__':
    unittest.main()
