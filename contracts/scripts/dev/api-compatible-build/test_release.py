from pathlib import Path
import importlib.util,os,subprocess,tarfile,tempfile,unittest
import publish
import test_publication as fixtures
from build import BINDINGS
root=Path(os.environ['DF_BUILD_TEST_ROOT']) if 'DF_BUILD_TEST_ROOT' in os.environ else Path(__file__).resolve().parents[4]
file=root/'tests/api-compatibility/package-release.py'
spec=importlib.util.spec_from_file_location('package_release',file)
release=importlib.util.module_from_spec(spec);spec.loader.exec_module(release)

class ReleaseTests(unittest.TestCase):
    def native_fixture(self):
        fixture=fixtures.Publication();fixture.setUp();self.addCleanup(fixture.doCleanups);return fixture
    def test_extracted_archive_installs_against_final_source_patch(self):
        fixture=self.native_fixture();bundle=fixture.native.parent/'release.tar.gz'
        release.write_native_archive(fixture.native,fixture.report,bundle)
        extracted=fixture.native.parent/'extracted';extracted.mkdir()
        with tarfile.open(bundle) as tar:
            names=tar.getnames();self.assertEqual(len(names),370)
            self.assertEqual(sum(n.startswith('build-source/') for n in names),349)
            tar.extractall(extracted,filter='data')
        for n in BINDINGS:fixtures.write(fixture.root/n,(extracted/'build-source'/n).read_bytes())
        self.assertTrue(publish.publish(fixture.root,extracted)['passed'])
    def test_missing_or_changed_archive_source_fails_before_bundle_creation(self):
        fixture=self.native_fixture();source=fixture.native/'build-source/contracts/fixture-1.nr';bundle=fixture.native.parent/'bad.tar.gz'
        source.write_text('changed')
        with self.assertRaisesRegex(AssertionError,'Build source changed'):release.write_native_archive(fixture.native,fixture.report,bundle)
        self.assertFalse(bundle.exists());source.unlink()
        with self.assertRaisesRegex(AssertionError,'Missing regular'):release.write_native_archive(fixture.native,fixture.report,bundle)
        self.assertFalse(bundle.exists())
    def test_python_caches_excluded_without_any_global_gitignore(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);subprocess.run(['git','init','-q',str(root)],check=True)
            names=['contracts/tool.py','contracts/__pycache__/tool.cpython-314.pyc','contracts/old.pyc','vendor/aztec/Nargo.toml']
            for name in names:
                p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b'\x00\xff' if name.endswith('.pyc') else b'fixture\n')
            args=['git','-c','core.excludesFile=/dev/null','ls-files','--others','-z','--',*release.PACKAGE_PATHS]
            included=set(filter(None,subprocess.check_output(args,cwd=root).decode().split('\0')))
            self.assertEqual(included,{'contracts/tool.py','vendor/aztec/Nargo.toml'})

if __name__=='__main__':unittest.main()
