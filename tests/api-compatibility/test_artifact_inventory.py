"""A completed native output directory must remain valid on subsequent builds."""
import json
from pathlib import Path
import tempfile
import unittest

import check


class ArtifactInventoryTests(unittest.TestCase):
    def test_validation_reports_do_not_become_contracts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = {'name': 'Example', 'functions': [], 'outputs': {'structs': {}}}
            (root / 'example-Example.json').write_text(json.dumps(artifact))
            (root / 'raw-selectors.json').write_text(json.dumps({'passed': True, 'checked': []}))
            (root / 'build-provenance.json').write_text(json.dumps({'passed': True, 'artifacts': []}))
            self.assertEqual(set(check.artifact_inventory(root)), {'Example'})

    def test_damaged_artifact_is_not_silently_treated_as_report(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'example-Example.json').write_text(json.dumps({'name': 'Example', 'outputs': {}}))
            with self.assertRaisesRegex(ValueError, 'Invalid compiler artifact'):
                check.artifact_inventory(root)


if __name__ == '__main__':
    unittest.main()
