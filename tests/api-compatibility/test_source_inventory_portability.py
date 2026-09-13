"""Source-only clones must retain complete API scans without Git or symlink traversal."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('portable_api_check',Path(__file__).with_name('check.py'))
check=importlib.util.module_from_spec(spec);spec.loader.exec_module(check)

class PortableSourceInventoryTests(unittest.TestCase):
    def test_no_git_source_copy_scans_regular_sources_and_skips_build_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for relative in ['contracts/system/demo/src/main.nr','contracts/system/demo/Nargo.toml','client/src/api.ts','packages/client/example.ts','server/src/api.mjs','contracts/target/old.nr','contracts/node_modules/foreign.nr']:
                target=root/relative;target.parent.mkdir(parents=True,exist_ok=True);target.write_text(relative)
            (root/'contracts/linked.nr').symlink_to(root/'contracts/system/demo/src/main.nr')
            with patch.object(check,'ROOT',root),patch.object(check,'git',side_effect=AssertionError('Git is not available in this source copy')):
                actual=check.source_files()
            expected={'contracts/system/demo/src/main.nr','contracts/system/demo/Nargo.toml','client/src/api.ts','packages/client/example.ts','server/src/api.mjs'}
            self.assertEqual(set(actual),expected)

    def test_reference_capture_still_uses_explicit_git_commit(self):
        def fake_git(*args):
            if args==('ls-tree','-r','--name-only','pinned'):return 'contracts/example.nr\n'
            if args==('show','pinned:contracts/example.nr'):return 'pinned contents'
            raise AssertionError(args)
        with patch.object(check,'git',side_effect=fake_git):
            self.assertEqual(check.source_files('pinned'),{'contracts/example.nr':'pinned contents'})

if __name__=='__main__':unittest.main()
