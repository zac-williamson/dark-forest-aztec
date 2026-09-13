from pathlib import Path
import importlib.util,json,tempfile,unittest
spec=importlib.util.spec_from_file_location('prepare_plan',Path(__file__).parent/'prepare-plan.py')
plan=importlib.util.module_from_spec(spec);spec.loader.exec_module(plan)

class PlanTests(unittest.TestCase):
    def test_named_package_is_found_above_versionless_module_marker(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);entry=root/'dest/node/index.js';entry.parent.mkdir(parents=True);entry.write_text('')
            (root/'dest/node/package.json').write_text('{"type":"module"}')
            (root/'package.json').write_text('{"name":"@aztec/bb.js","version":"5.0.1"}')
            self.assertEqual(plan.find_package(entry,'@aztec/bb.js'),root/'package.json')
    def test_different_named_package_is_not_accepted(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);(root/'package.json').write_text('{"name":"other","version":"5.0.1"}')
            with self.assertRaisesRegex(ValueError,'Missing installed'):plan.find_package(root/'index.js','@aztec/bb.js')
    def test_dependency_identity_ignores_only_local_absolute_roots(self):
        a={'packages':{'x':{'root':'/old','files':{'a':'hash'}}},'repositories':{'r':{'root':'/old','tag':'t','commit':'c'}},'fileCount':1}
        b=json.loads(json.dumps(a));b['packages']['x']['root']='/new';b['repositories']['r']['root']='/new'
        self.assertEqual(plan.body_identity(a),plan.body_identity(b))
        b['packages']['x']['files']['a']='changed';self.assertNotEqual(plan.body_identity(a),plan.body_identity(b))

if __name__=='__main__':unittest.main()
