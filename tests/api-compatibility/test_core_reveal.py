"""Reveal must save public execution work without adding private proof work."""
import importlib.util
import json
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('reveal_plans', HERE / 'generate-backend-plans.py')
plans = importlib.util.module_from_spec(spec)
spec.loader.exec_module(plans)
p, reveal = plans.p, plans.core_reveal


class CoreRevealTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (plans.ROOT / 'contracts/system/core/src/main.nr').read_text()
        cls.functions = p.functions(cls.source)
        cls.baseline = reveal.baseline_functions('core', p)
        cls.body = cls.functions[reveal.ORIGINAL]['body']

    def test_private_body_and_original_enqueue_are_byte_identical_to_original_git(self):
        current, old = self.functions['reveal_location'], self.baseline['reveal_location']
        self.assertEqual(current['body'], old['body'])
        self.assertEqual(p.digest(current['header']), p.digest(old['header']))
        self.assertIn('self.enqueue_self.reveal_location_public(', current['body'])
        self.assertNotIn('prepared_', current['body'])
        self.assertNotIn(reveal.PREPARED, self.functions)
        self.assertNotIn(reveal.HELPER, self.functions)
        records = json.loads(plans.MANIFEST.read_text())['continuations']
        self.assertNotIn('reveal_location', [r['private'] for r in records])

    def test_all_assertions_arguments_order_and_typed_writes_restore_to_original(self):
        restored = reveal.restore_original(self.source, self.functions[reveal.ORIGINAL], p)
        self.assertEqual(restored['body'], self.baseline[reveal.ORIGINAL]['body'])
        self.assertEqual(p.digest(restored['header']), p.digest(self.baseline[reveal.ORIGINAL]['header']))
        self.assertTrue(self.body.endswith(reveal.WRITES))
        self.assertNotIn('::libs::public_call::call(', self.body)
        self.assertNotIn('state_worker', self.body)
        self.assertNotIn('_set_', self.body)

    def test_every_unknown_store_view_and_config_call_keeps_original_core_caller(self):
        for original, optimized in reveal.read_expressions(reveal.ORIGINAL):
            self.assertEqual(self.body.count(optimized), 1)
            self.assertIn('else { ' + original + ' }', optimized)
            self.assertIn('state_backend_address.is_zero() { false }', optimized)
            self.assertIn('get_namespace_kind(', optimized)
        expected_kinds = [('planet_storage', 3), ('planet_revealed_coords_storage', 4),
                          ('player_storage', 2), ('world_storage', 1)]
        for store, kind in expected_kinds:
            self.assertIn(f'get_namespace_kind(state_backend_address, {store}.target_contract) == {kind}', self.body)
        self.assertEqual(self.body.count('self.view(config.verify_config_hashes('), 1)
        self.assertNotIn('supports_config', self.body)
        self.assertNotIn('Config::at(', self.body[self.body.index('self.view(config.verify_config_hashes('):])

    def test_zero_presence_full_field_keys_and_conditional_reads_are_unchanged(self):
        self.assertIn('if planet_state_hash != 0 {', self.body)
        self.assertIn('player_storage.target_contract, sender.to_field()) == player_state_hash', self.body)
        self.assertIn('planet_revealed_coords_storage.target_contract, location) != 0', self.body)
        self.assertIn('world_storage.target_contract, 0) == world_hash', self.body)
        self.assertNotIn(' as u', self.body)
        self.assertNotIn('poseidon2_hash', self.body)
        # The previously unused hash must not become a new check/precondition.
        self.assertNotIn('planet_revealed_coords_hash', self.body)

    def test_generator_is_idempotent_and_other_private_bodies_unchanged(self):
        changed = reveal.apply_original_path(self.source, 'core', p)
        self.assertEqual(changed, self.source)
        for name, fn in self.functions.items():
            if '#[external("private")]' in fn['header'] and name != 'reveal_location':
                self.assertEqual(p.functions(changed)[name]['body'], fn['body'])
        self.assertTrue(set(self.baseline).issubset(self.functions))

    def test_guard_argument_and_error_mutations_cannot_pass_baseline_restoration(self):
        for old, new in [
            ('planet_storage.target_contract) == 3', 'planet_storage.target_contract) == 2'),
            ('player_storage.target_contract, sender.to_field()', 'player_storage.target_contract, 0'),
            ('else { self.view(world_storage.verify_hash(0, world_hash)) }', 'else { true }'),
        ]:
            corrupted = self.body.replace(old, new, 1)
            self.assertNotEqual(corrupted, self.body)
            with self.assertRaises(AssertionError):
                reveal.restore_body(reveal.ORIGINAL, corrupted)
        altered = self.body.replace('"Planet already revealed"', '"Different error"', 1)
        self.assertNotEqual(p.digest(reveal.restore_body(reveal.ORIGINAL, altered)),
                            p.digest(self.baseline[reveal.ORIGINAL]['body']))


if __name__ == '__main__':
    unittest.main()
