"""Safe Owner retains its original private proof work and original typed write."""
import importlib.util
import json
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('owner_plans', HERE / 'generate-backend-plans.py')
plans = importlib.util.module_from_spec(spec)
spec.loader.exec_module(plans)
p, direct = plans.p, plans.core_reveal


class OwnerTransportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (plans.ROOT / 'contracts/system/admin/src/main.nr').read_text()
        cls.functions = p.functions(cls.source)
        cls.baseline = direct.baseline_functions('admin', p)
        cls.body = cls.functions['safe_set_owner_public']['body']

    def test_private_body_and_enqueue_are_exact_original_without_extra_output_hash(self):
        self.assertEqual(self.functions['safe_set_owner']['body'], self.baseline['safe_set_owner']['body'])
        self.assertIn('self.enqueue_self.safe_set_owner_public(', self.functions['safe_set_owner']['body'])
        self.assertNotIn('prepared_', self.functions['safe_set_owner']['body'])
        self.assertNotIn('safe_set_owner_public_prepared', self.functions)
        self.assertNotIn('_legacy_safe_set_owner_public', self.functions)
        self.assertNotIn('safe_set_owner', [r['private'] for r in json.loads(plans.MANIFEST.read_text())['continuations']])

    def test_original_authorization_timestamp_config_root_checks_and_typed_write_restore_exactly(self):
        self.assertEqual(direct.restore_body('safe_set_owner_public', self.body), self.baseline['safe_set_owner_public']['body'])
        checks = ['assert(sender == self.storage.admin.read()', 'assert_public_timestamp(timestamp',
                  'self.view(config.verify_config_hashes', 'World state hash mismatch',
                  'Planet state hash mismatch', 'self.call(planet_storage.set(location_id, new_planet))']
        positions = [self.body.index(needle) for needle in checks]
        self.assertEqual(positions, sorted(positions))
        self.assertNotIn('write_plan', self.body)
        self.assertNotIn('commit_owner', self.body)
        self.assertNotIn('::libs::public_call::call', self.body)

    def test_unknown_stores_keep_original_admin_caller_and_full_range_inputs(self):
        for original, optimized in direct.read_expressions('safe_set_owner_public'):
            self.assertEqual(self.body.count(optimized), 1)
            self.assertIn('else { ' + original + ' }', optimized)
        self.assertIn('world_storage.target_contract) == 1', self.body)
        self.assertIn('planet_storage.target_contract) == 3', self.body)
        self.assertIn('planet_storage.target_contract, location_id) == planet_state_hash', self.body)
        self.assertNotIn(' as u', self.body)
        self.assertNotIn('if planet_state_hash != 0', self.body)

    def test_reapplication_is_idempotent_and_other_admin_optimizations_untouched(self):
        changed = direct.apply_original_path(self.source, 'admin', p)
        self.assertEqual(changed, self.source)
        self.assertTrue(set(self.baseline).issubset(self.functions))
        for name in plans.admin_reads.ACTIONS:
            restored = plans.admin_reads.restore_body(name, self.functions[name]['body'])
            self.assertEqual(p.digest(restored), p.digest(self.baseline[name]['body']))


if __name__ == '__main__':
    unittest.main()
