"""V7 Prospect source-only experiment: no compiled or runtime claims."""
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('prospect_plans',HERE/'generate-backend-plans.py')
plans=importlib.util.module_from_spec(spec);spec.loader.exec_module(plans)
p,prototype=plans.p,plans.original_prospect

class ProspectOriginalPrivateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source=(plans.ROOT/'contracts/system/artifact_prospect/src/main.nr').read_text()
        cls.functions=p.functions(cls.source)
        cls.original=prototype.baseline_functions(p)

    def test_private_body_enqueue_and_original_api_are_exact(self):
        self.assertEqual(self.functions[prototype.PRIVATE]['body'],self.original[prototype.PRIVATE]['body'])
        self.assertIn('self.enqueue_self.prospect_planet_public(',self.functions[prototype.PRIVATE]['body'])
        self.assertNotIn('prepared_',self.functions[prototype.PRIVATE]['body'])
        self.assertNotIn(prototype.PREPARED,self.functions)
        self.assertTrue(set(self.original).issubset(self.functions))
        for name,old in self.original.items():
            self.assertEqual(p.digest(self.functions[name]['header']),p.digest(old['header']),name)

    def test_only_two_v6_scalar_root_records_move_to_public_hashing(self):
        body=self.functions[prototype.PUBLIC]['body']
        self.assertEqual(p.digest(body),p.digest(prototype.route_body(p)))
        for namespace,state in prototype.ROOT_STATES:
            self.assertEqual(body.count(f'write_plan.set({namespace}, location_id, 0, false, {state}.serialize())'),1)
        self.assertNotIn('prepared_new_',body)
        self.assertIn('write_plan.start_batch(',body)
        self.assertIn('write_plan.append_batch_item(',body)
        self.assertIn('public_read::can_settle(',body)
        self.assertNotIn('state_worker',body)
        self.assertNotIn('self.context.this_address()',body)

    def test_custom_store_fallback_is_local_exact_and_cannot_recurse(self):
        body=self.functions[prototype.PUBLIC]['body']
        self.assertEqual(body.count('self.internal.'+prototype.LEGACY+'('),1)
        fallback=self.functions[prototype.LEGACY]['body']
        self.assertEqual(p.digest(fallback),p.digest(self.original[prototype.PUBLIC]['body']))
        self.assertNotIn('self.enqueue_self.',fallback)
        self.assertNotIn('self.context.this_address()',fallback)
        restored=prototype.restore_original(self.source,self.functions[prototype.PUBLIC],p)
        self.assertEqual(restored['body'],self.original[prototype.PUBLIC]['body'])

    def test_private_dependency_restore_is_scoped_to_audited_original_private_actions(self):
        provenance=json.loads(prototype.PROVENANCE.read_text())
        for name,digest in provenance['restoredOriginalFiles'].items():
            self.assertEqual(hashlib.sha256((plans.ROOT/name).read_bytes()).hexdigest(),digest)
        nargo=(plans.ROOT/'contracts/system/artifact_prospect/Nargo.toml').read_text()
        self.assertIn('libs = { path = "../../prospect_original_libs" }',nargo)
        consumers={manifest.parent.name for manifest in (plans.ROOT/'contracts/system').glob('*/Nargo.toml') if 'prospect_original_libs' in manifest.read_text()}
        self.assertEqual(consumers,{'artifact_prospect','artifact_action','artifact_find'})
        self.assertIn('libs = { path = "../../libs" }',(plans.ROOT/'contracts/system/core/Nargo.toml').read_text())
        plans.selected_core.validate((plans.ROOT/'contracts/system/core/src/main.nr').read_text(),p)
        original_lib=plans.ROOT/'contracts/libs/src/lazy_update.nr'
        restored_lib=plans.ROOT/'contracts/prospect_original_libs/src/lazy_update.nr'
        self.assertNotEqual(original_lib.read_bytes(),restored_lib.read_bytes())

    def test_transform_reapplication_is_idempotent(self):
        self.assertEqual(prototype.apply_original_path(self.source,'artifact_prospect',p),self.source)

    def test_generator_does_not_rewrite_unrelated_blank_lines(self):
        old='contract Example {\n    fn value() { 1 }\n\n}\n'
        added=old.replace('\n}\n','\n\n}\n')
        self.assertEqual(plans.preserve_blank_line_layout(old,added),old)
        changed=added.replace('{ 1 }','{ 2 }')
        self.assertEqual(plans.preserve_blank_line_layout(old,changed),changed)

    def test_native_build_provenance_covers_restored_dependency_package(self):
        build=plans.ROOT/'contracts/scripts/dev/api-compatible-build'
        paths=json.loads((build/'reference/production-paths.json').read_text())
        expected={str(file.relative_to(plans.ROOT)) for file in (plans.ROOT/'contracts/prospect_original_libs').rglob('*') if file.is_file() and file.suffix in {'.nr','.toml'}}
        self.assertTrue(expected)
        self.assertEqual(len(paths),349)
        self.assertLessEqual(expected,set(paths))
        selected=json.loads((HERE/'snapshots/selected-source/manifest.json').read_text())['sourceFiles']
        for name in expected:
            file=plans.ROOT/name
            self.assertFalse(file.is_symlink())
            self.assertEqual(hashlib.sha256(file.read_bytes()).hexdigest(),selected[name],name)

if __name__=='__main__':unittest.main()
