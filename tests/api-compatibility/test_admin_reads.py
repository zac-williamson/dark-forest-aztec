"""Protect exact original statements around the bounded public Admin read pass."""
import importlib.util
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('admin_reads_test', HERE / 'optimize-admin-reads.py')
reads = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reads)


class AdminReadTests(unittest.TestCase):
    def test_all_six_original_bodies_restore_exactly(self):
        reads.generate(False)
        self.assertEqual(len(reads.ACTIONS), 6)

    def test_unknown_namespaces_keep_typed_original_calls(self):
        for kind, (typ, store, key_type, namespace_kind) in reads.TYPES.items():
            helper = reads.p.functions(reads.helpers())[f'_verify_{kind}_for_admin']['body']
            self.assertIn(f'get_namespace_kind(backend,namespace) == {namespace_kind}', helper)
            self.assertIn('if backend.is_zero() { false }', helper)
            self.assertIn(f'if root == 0 {{ state == {typ}::zero() }} else {{ poseidon2_hash(state.serialize()) == root }}', helper)
            self.assertIn(f'self.view({store}::at(namespace).verify(id,state))', helper)
            self.assertNotIn('self.call(', helper)
            self.assertNotIn('.write(', helper)


if __name__ == '__main__':
    unittest.main()
