#!/usr/bin/env python3
"""Validate the selected candidate without generation, compilation, keys or chain access."""
from pathlib import Path
import argparse,importlib.util,unittest
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--root',type=Path,required=True)
args=parser.parse_args()
file=Path(__file__).with_name('selected-source-checks.py')
spec=importlib.util.spec_from_file_location('selected_source_checks',file)
checks=importlib.util.module_from_spec(spec);spec.loader.exec_module(checks)
checks.ROOT=args.root.resolve()
touch_file=Path(__file__).with_name('test_artifact_touch.py')
spec=importlib.util.spec_from_file_location('selected_touch_checks',touch_file)
touch=importlib.util.module_from_spec(spec);spec.loader.exec_module(touch)
touch.ROOT=args.root.resolve()
suite=unittest.TestSuite([unittest.defaultTestLoader.loadTestsFromTestCase(checks.SelectedSourceTests),unittest.defaultTestLoader.loadTestsFromTestCase(touch.ArtifactTouchTests)])
result=unittest.TextTestRunner(verbosity=2).run(suite)
raise SystemExit(0 if result.wasSuccessful() else 1)
