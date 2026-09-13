"""Check the actual fallback bodies against the original Git source snapshot.

Historical transform manifests are deliberately not the authority for originals:
they captured an earlier optimization that incorrectly omitted custom count0
contract calls. Runtime marker fixtures test this boundary separately.
"""
import importlib.util
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('baseline_plans',Path(__file__).with_name('generate-backend-plans.py'))
plans=importlib.util.module_from_spec(spec);spec.loader.exec_module(plans)

class LegacyBaselineTests(unittest.TestCase):
    def test_all_thirteen_actual_expanded_public_bodies_equal_immutable_original(self):
        catalog=plans.continuation_sources()
        self.assertEqual(len(catalog),13)
        for name,entry in catalog.items():
            source=(ROOT/entry['source']).read_text()
            actual=plans.expanded_current_definition(source,name)
            self.assertEqual(plans.p.digest(actual['full']),plans.p.digest(entry['original']['full']),name)

    def test_canonical_only_guard_changes_are_bounded_to_the_eleven_audited_functions(self):
        changed=[]
        for name,entry in plans.continuation_sources().items():
            original=entry['original']['body'];canonical=entry['canonical']['body']
            if plans.p.digest(original)!=plans.p.digest(canonical):changed.append(name)
            self.assertEqual(plans.p.digest(plans.remove_canonical_batch_guards(canonical)),plans.p.digest(original),name)
        self.assertEqual(set(changed),{
            'refresh_planet_public','upgrade_planet_public','withdraw_silver_public','initialize_player_public',
            'activate_artifact_public','deactivate_artifact_public','find_artifact_public','prospect_planet_public',
            'deposit_artifact_public','withdraw_artifact_public','give_spaceships_public'})

    def test_original_refresh_has_exact_custom_zero_count_verifier_and_setter_fallbacks(self):
        source=(ROOT/'contracts/system/core/src/main.nr').read_text()
        functions=plans.p.functions(source)
        v7=plans.p.functions(plans.selected_core.reference('v7-core.nr'))
        self.assertEqual(functions['refresh_planet_empty_public_prepared']['full'],v7['refresh_planet_empty_public_prepared']['full'])
        body=functions['_refresh_planet_public_local']['body']
        original=plans.original_core.baseline(plans.p)['refresh_planet_public']['body']
        self.assertEqual(plans.expanded_current_definition(source,'refresh_planet_public')['body'],original)
        _,reads=plans.original_core.optimize_public(original)
        batch=[record for record in reads if record['method']=='verify_hashes_batch']
        self.assertEqual(len(batch),3)
        for record in batch:
            self.assertIn('else { '+record['original']+' }',body)
            self.assertIn(record['replacement'],body)
        self.assertNotIn('if original_arrivals_count != 0',body)
        self.assertIn('new_arrival_artifact_locations',body)

    def test_guard_normalizer_rejects_non_view_effects(self):
        invalid='if origin_arrivals_count != 0 { self.call(planet_storage.set(id,state)); }'
        with self.assertRaises(AssertionError):plans.remove_canonical_batch_guards(invalid)

if __name__=='__main__':unittest.main()
