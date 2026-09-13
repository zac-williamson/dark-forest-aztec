"""Source-only V8 candidate; compiled identity and runtime costs are separate gates."""
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('action_plans', HERE / 'generate-backend-plans.py')
plans = importlib.util.module_from_spec(spec); spec.loader.exec_module(plans)
p, candidate = plans.p, plans.original_artifact_actions


_selected_spec=importlib.util.spec_from_file_location('selected_dependency_checks',HERE/'selected-source-checks.py')
selected=importlib.util.module_from_spec(_selected_spec);_selected_spec.loader.exec_module(selected)

class ArtifactActionsOriginalPrivateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (plans.ROOT / 'contracts/system/artifact_action/src/main.nr').read_text()
        cls.functions = p.functions(cls.source)
        cls.original = candidate.baseline_functions(p)

    def test_both_private_bodies_and_original_enqueues_are_byte_identical(self):
        for private, public in candidate.ACTIONS['artifact_action']:
            current, original = self.functions[private], self.original[private]
            self.assertEqual(current['body'], original['body'], private)
            self.assertEqual(p.digest(current['header']), p.digest(original['header']))
            self.assertEqual(current['body'].count('self.enqueue_self.' + public + '('), 1)
            self.assertNotIn('prepared_', current['body'])
            self.assertNotIn(public + '_prepared', self.functions)

    def test_every_original_external_api_and_other_function_stays_present(self):
        self.assertTrue(set(self.original).issubset(self.functions))
        for name, original in self.original.items():
            self.assertEqual(p.digest(self.functions[name]['header']), p.digest(original['header']), name)

    def test_exactly_five_scalar_records_per_action_move_to_public_hashing(self):
        for _, public in candidate.ACTIONS['artifact_action']:
            body = self.functions[public]['body']
            self.assertEqual(p.digest(body), p.digest(candidate.route_body(public, p)))
            for namespace, key, state in candidate.ROOT_STATES:
                self.assertEqual(body.count(f'write_plan.set({namespace}, {key}, 0, false, {state}.serialize())'), 1)
            self.assertEqual(body.count('write_plan.set('), 5)
            self.assertNotIn('prepared_payload', body)
            self.assertNotIn('prepared_new_', body)
            self.assertNotIn('state_worker', body)

    def test_batch_records_and_namespace_guards_are_retained(self):
        for _, public in candidate.ACTIONS['artifact_action']:
            body = self.functions[public]['body']
            self.assertIn('public_read::can_settle(state_backend_address, plan_addresses, 1002)', body)
            self.assertIn('write_plan.start_batch(9, change_artifact_location_count, 20)', body)
            self.assertIn('change_artifact_location_ids[plan_i] != 0', body)
            self.assertIn('change_artifact_locations[plan_i].serialize()', body)
            self.assertLess(body.index('public_read::can_settle('), body.index('let mut write_plan'))
            self.assertLess(body.index('write_plan.set(6,'), body.index('write_plan.start_batch('))
            self.assertLess(body.index('write_plan.start_batch('), body.index('write_plan.set(8,'))

    def test_original_fallback_calls_and_full_input_arguments_cannot_recurse(self):
        for _, public in candidate.ACTIONS['artifact_action']:
            body = self.functions[public]['body']
            self.assertEqual(body.count('self.internal._legacy_' + public + '('), 1)
            self.assertNotIn('self.context.this_address()', body)
            fallback = self.functions['_legacy_' + public]['body']
            self.assertEqual(p.digest(fallback), p.digest(self.original[public]['body']))
            self.assertEqual(p.digest(plans.expanded_current_definition(self.source, public)['full']), p.digest(self.original[public]['full']))
            self.assertIn('verify_hashes_batch(', fallback)
            self.assertIn('set_arrival_locations_max20(', fallback)

    def test_activate_custom_config_still_observes_actual_artifact_action_caller(self):
        body = self.functions['activate_artifact_public']['body']
        first = 'self.view(config.verify_world_config_hash(world_config_hash))'
        second = 'self.view(config.verify_planet_default_stats_hash('
        self.assertEqual(body.count(first), 1)
        self.assertEqual(body.count(second), 1)
        self.assertLess(body.index(first), body.index(second))
        self.assertLess(body.index(second), body.index('write_plan.set('))
        self.assertNotIn('config.', self.functions['deactivate_artifact_public']['body'])

    def test_original_private_dependency_closure_reuses_authenticated_restored_package(self):
        report = json.loads((plans.ROOT / 'docs/api-compatibility/v7-prospect-private-dependencies.json').read_text())
        for row in report['files']:
            self.assertEqual(hashlib.sha256(selected.restore_dependency(row['current'],(plans.ROOT / row['current']).read_text()).encode()).hexdigest(), row['currentSha256'], row['current'])
        manifest = (plans.ROOT / 'contracts/system/artifact_action/Nargo.toml').read_text()
        self.assertIn('libs = { path = "../../prospect_original_libs" }', manifest)
        self.assertEqual(plans.original_private_actions('artifact_action'), candidate.ACTIONS['artifact_action'])

    def test_reapplication_is_idempotent_and_two_actions_are_not_overwritten(self):
        self.assertEqual(candidate.apply_original_path(self.source, 'artifact_action', p), self.source)
        metadata = json.loads(plans.MANIFEST.read_text())
        originals = {(x['package'], x['private'], x['public']) for x in metadata['originalPrivateActions']}
        for private, public in candidate.ACTIONS['artifact_action']:
            self.assertIn(('artifact_action', private, public), originals)
        self.assertEqual(originals,{('core','reveal_location','reveal_location_public'),('admin','safe_set_owner','safe_set_owner_public'),('artifact_prospect','prospect_planet','prospect_planet_public'),('artifact_find','find_artifact','find_artifact_public'),('artifact_action','activate_artifact','activate_artifact_public'),('artifact_action','deactivate_artifact','deactivate_artifact_public')})
        self.assertEqual(metadata['selectedCore']['privateMethods'],plans.selected_core.PRIVATE)
        self.assertEqual(len(metadata['continuations']), 3)
        self.assertFalse(any(x['package'] == 'artifact_action' for x in metadata['continuations']))

    def test_canonical_or_fallback_mutations_fail_restoration(self):
        public = 'activate_artifact_public'
        definition = dict(self.functions[public])
        definition['body'] = definition['body'].replace('write_plan.set(3, location_id, 0, false,', 'write_plan.set(3, location_id, 1, false,', 1)
        with self.assertRaises(AssertionError):
            candidate.restore_original(self.source, definition, p)
        altered = self.source.replace('self.call(artifact_location_storage.set_arrival_locations_max20(', 'self.call(artifact_location_storage.set_spaceship_locations_max5(', 1)
        with self.assertRaises(AssertionError):
            candidate.restore_original(altered, self.functions[public], p)

    def test_unrelated_production_sources_remain_exact_frozen_base_bytes(self):
        # The selected closure authenticates every source. Medium helpers, Core,
        # SDK origins/markers, five derived IDs and the exact reviewed touch
        # transformation may differ; every exception is independently checked.
        allowed={selected.CORE,'contracts/state_backend_readonly/src/public_read.nr',
                 *selected.P['mediumFiles'],*selected.P['markerOnlyFiles'],
                 *selected.P['nargoRewrites'],*selected.P['toolingFiles'],*selected.BINDINGS['files']}
        touch=plans.artifact_touch
        touch_facades={f'contracts/storage/{slug}/src/main.nr':slug for slug in touch.SPECS}
        for relative,digest in selected.P['v8SourceFiles'].items():
            if relative==touch.VAULT:
                restored=touch.restore_vault((plans.ROOT/relative).read_text(),p)
                self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(),digest,relative)
            elif relative in touch_facades:
                source=(plans.ROOT/relative).read_text();slug=touch_facades[relative]
                self.assertTrue(touch.validate_facade(source,slug,p))
                self.assertEqual(hashlib.sha256(source.replace(touch.touch_block(slug,p),'',1).encode()).hexdigest(),digest,relative)
            elif relative not in allowed:
                self.assertEqual(hashlib.sha256((plans.ROOT/relative).read_bytes()).hexdigest(),digest,relative)



if __name__ == '__main__':
    unittest.main()
