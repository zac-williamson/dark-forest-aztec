"""Guard the trust boundary which permits prepared roots without rehashing.

These structural checks complement hostile runtime calls; they do not replace
class provenance or execution tests.
"""
from pathlib import Path
import re
import unittest
import check

ROOT = Path(__file__).resolve().parents[2]


class BackendTrustTests(unittest.TestCase):
    def _write_route_audit(self, source):
        clean = check.clean(source)
        contract = check.parse_source('backend', source)
        functions = {f['name']: f for f in contract['functions']}
        guarded = set()
        local_calls = {}
        callback_writers = {
            function['name'] for function in functions.values()
            if any(call['targetContract'] == 'StateFacadeInterface'
                   and call['method'].startswith('emit_')
                   for call in function['externalCalls'])
        }
        expected = 'assert(self.internal._is_prepared_writer(self.msg_sender()), "Only audited system");'
        resolved_actor = 'let actor = _resolve_plan_actor(self.context, AztecAddress::from_field(payload.words[0]));'
        for name in functions:
            match = re.search(r'\bfn\s+' + re.escape(name) + r'\s*\(', clean)
            params_end = check.balanced(clean, match.end() - 1)
            start = clean.index('{', params_end)
            end = check.balanced(clean, start, '{', '}')
            # Contract-library helpers are plain calls, unlike self.internal.
            # Include both forms when following paths to prepared writes.
            local_calls[name] = set(re.findall(r'(?<![\w.:])([A-Za-z_]\w*)\s*\(', clean[start + 1:end])) & functions.keys()
            if any(check.norm(clean[start + 1:end]).startswith(check.norm(guard)) for guard in (expected, resolved_actor)):
                guarded.add(name)
        self.assertGreaterEqual(len(guarded), 3, 'Both Move paths and plan commits must authenticate before parsing')

        def visit(name, route):
            if name in guarded:
                return
            # Facade callbacks now store the authoritative root before emitting.
            # Typed callbacks are writes too, even though their helper does not
            # use a _write_* or _set_*_fields primitive. Namespace authorization
            # alone cannot authenticate a caller-supplied actor argument.
            sensitive = (name.startswith('_write_')
                         or (name.startswith('_set_') and name.endswith('_fields'))
                         or name in callback_writers)
            self.assertFalse(sensitive, 'Unguarded prepared write route: ' + ' -> '.join(route + [name]))
            if name in route:
                return
            for edge in functions[name]['selfCalls']:
                if edge['method'] in functions:
                    visit(edge['method'], route + [name])
            for target in local_calls[name]:
                visit(target, route + [name])

        for function in functions.values():
            if function['kind'] in ('public', 'private'):
                visit(function['name'], [])
        return functions, local_calls, guarded, callback_writers, visit

    def test_every_public_route_to_prepared_writes_crosses_a_guard(self):
        source = (ROOT / 'contracts/state_backend/src/main.nr').read_text()
        functions, local_calls, guarded, callback_writers, visit = self._write_route_audit(source)
        self.assertIn('_emit_artifact_location_batch_max20', callback_writers)
        # Ensure factoring into a plain library call cannot hide a missing guard.
        for name in ('commit_plan', 'commit_plan_small', 'commit_plan_medium'):
            targets = local_calls[name] | {edge['method'] for edge in functions[name]['selfCalls']}
            self.assertIn('_commit_state_plan', targets)
            guarded.remove(name)
            try:
                with self.assertRaisesRegex(AssertionError, 'Unguarded prepared write route'):
                    visit(name, [])
            finally:
                guarded.add(name)

    def test_unguarded_public_wrapper_through_typed_callback_helper_is_rejected(self):
        source = (ROOT / 'contracts/state_backend/src/main.nr').read_text()
        wrapper = '''
    #[external("public")]
    fn untrusted_batch(ns:AztecAddress, actor:AztecAddress,
        ids:[Field;20], states:[ArtifactLocation;20], count:u32) {
        self.internal._set_arrival_locations_max20(ns,actor,ids,states,count);
    }
'''
        point = source.rfind('}')
        unsafe = source[:point] + wrapper + source[point:]
        with self.assertRaisesRegex(AssertionError,
                r'Unguarded prepared write route: untrusted_batch -> _set_arrival_locations_max20'):
            self._write_route_audit(unsafe)
        guarded_wrapper = wrapper.replace(
            '        self.internal._set_arrival_locations_max20',
            '        assert(self.internal._is_prepared_writer(self.msg_sender()), "Only audited system");\n'
            '        self.internal._set_arrival_locations_max20',
        )
        # A dominating first-statement guard restores the same protected route.
        self._write_route_audit(source[:point] + guarded_wrapper + source[point:])

    def test_unified_plan_actor_cannot_be_chosen_by_a_direct_system_caller(self):
        source = (ROOT / 'contracts/state_backend/src/main.nr').read_text()
        match = re.search(r'\bfn\s+_resolve_plan_actor\s*\(', source)
        params_end = check.balanced(source, match.end() - 1)
        start = source.index('{', params_end)
        end = check.balanced(source, start, '{', '}')
        body = source[start + 1:end]
        direct_branch = re.search(r'if super::trusted_classes::contains\(caller_id\)\s*\{([^{}]+)\}', body)
        self.assertIsNotNone(direct_branch)
        self.assertEqual(check.norm(direct_branch[1]), 'caller')
        self.assertIn('let caller = self.msg_sender()', body)
        self.assertEqual(body.count('get_contract_instance_current_class_id_avm(caller)'), 1)
        self.assertIn('get_contract_instance_current_class_id_avm(claimed_actor)', body)
        for required in ['WORKER_CLASSES[0]', 'SYSTEM_CLASSES[1]', 'WORKER_CLASSES[1]', 'SYSTEM_CLASSES[6]']:
            self.assertIn(required, body)
        self.assertLess(body.index('assert('), body.index('current.unwrap()'))
        self.assertGreaterEqual(body.count('assert('), 4)

    def test_facades_have_no_class_update_or_arbitrary_forwarding(self):
        for source in (ROOT / 'contracts/storage').glob('*/src/main.nr'):
            parsed = check.parse_source(str(source), source.read_text())
            self.assertNotIn('update_contract_class', source.read_text())
            for function in parsed['functions']:
                for call in function['externalCalls']:
                    self.assertEqual(call['targetContract'], 'GameStateBackend', (source, function['name'], call))

    def test_raw_callbacks_keep_original_event_and_backend_guard(self):
        for path in (ROOT / 'contracts/storage').glob('*/src/main.nr'):
            source = path.read_text()
            parsed = check.parse_source(str(path), source)
            event = parsed['events'][0]['name']
            name = 'emit_' + path.parents[1].name + '_fields'
            match = re.search(r'\bfn\s+' + name + r'\s*\(', source)
            self.assertIsNotNone(match, path)
            end_params = check.balanced(source, match.end() - 1)
            start = source.index('{', end_params)
            end = check.balanced(source, start, '{', '}')
            body = source[start + 1:end]
            self.assertIn('self.msg_sender() == backend_address', body)
            self.assertIn('!backend_address.is_zero()', body)
            self.assertIn(event + '::get_event_type_id()', body)
            self.assertIn('DOM_SEP__EVENT_LOG_TAG', body)
            self.assertIn('[tag, id, self.context.block_number() as Field, field_0', body)
            self.assertLess(body.index('assert('), body.index('emit_public_log('))


if __name__ == '__main__':
    unittest.main()
