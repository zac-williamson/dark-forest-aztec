"""Selected Core validation; V8 original-private tests are retained under snapshots/historical-tests.
The selected private policy is V7 cache identity; full public semantics remain V8.
"""
import importlib.util
from pathlib import Path
spec=importlib.util.spec_from_file_location('selected_source_tests',Path(__file__).with_name('selected-source-checks.py'))
checks=importlib.util.module_from_spec(spec);spec.loader.exec_module(checks)
SelectedCoreTests=checks.SelectedSourceTests
