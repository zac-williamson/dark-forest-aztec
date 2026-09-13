"""Original private Find and six public-hashed scalar records: source-only checks."""
import hashlib
import importlib.util
import json
import re
from pathlib import Path
import unittest
from unittest.mock import patch

HERE=Path(__file__).resolve().parent

def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module

p=load('find_source_parser',HERE/'prepare-system-writes.py')
find=load('find_original_private',HERE/'optimize-find-original-private.py')

_selected_spec=importlib.util.spec_from_file_location('selected_dependency_checks',HERE/'selected-source-checks.py')
selected=importlib.util.module_from_spec(_selected_spec);_selected_spec.loader.exec_module(selected)

class FindOriginalPrivateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source=(p.ROOT/'contracts/system/artifact_find/src/main.nr').read_text()
        cls.functions=p.functions(cls.source);cls.original=find.baseline_functions(p)

    def test_original_private_body_enqueue_and_every_original_header_exact(self):
        current=self.functions[find.PRIVATE];original=self.original[find.PRIVATE]
        self.assertEqual(current['body'],original['body'])
        self.assertIn('self.enqueue_self.find_artifact_public(',current['body'])
        self.assertNotIn('prepared_',current['body']);self.assertNotIn(find.PREPARED,self.functions)
        for name,original in self.original.items():
            self.assertIn(name,self.functions)
            self.assertEqual(p.digest(self.functions[name]['header']),p.digest(original['header']),name)

    def test_historical_witness_seed_id_and_public_expiry_validation_preserved(self):
        body=self.functions[find.PRIVATE]['body']
        statements=['get_block_header_at(new_planet.prospected_block_number, *self.context)',
                    'let block_hash: Field = header.hash();',
                    'let artifact_seed = poseidon2_hash([location_id, block_hash]);',
                    'let artifact_id = artifact_seed;','self.enqueue_self.find_artifact_public(']
        positions=[body.index(s) for s in statements];self.assertEqual(positions,sorted(positions))
        for name in [find.PUBLIC,find.LEGACY]:
            public=self.functions[name]['body']
            self.assertIn('new_planet.prospected_block_number < block_number',public)
            self.assertIn('(block_number - new_planet.prospected_block_number) < 256',public)
        self.assertIn('biome_proof(',body)
        self.assertIn('refresh_planet_v2(',body)

    def test_only_six_scalar_root_preparation_flags_change_in_frozen_route(self):
        body=self.functions[find.PUBLIC]['body']
        self.assertEqual(p.digest(body),p.digest(find.route_body(find.PUBLIC,p)))
        frozen=find.frozen_functions(p)[find.PREPARED]['body']
        marker='        let state_backend_address = self.storage.state_backend.read();'
        expected='\n'+frozen[frozen.index(marker):];restored=body
        for namespace,key,state in find.ROOT_STATES:
            updated=f'write_plan.set({namespace}, {key}, 0, false, {state}.serialize())'
            old=f'write_plan.set({namespace}, {key}, prepared_{state}_root, true, {state}.serialize())'
            self.assertEqual(body.count(updated),1)
            restored=restored.replace(updated,old,1)
        self.assertEqual(p.digest(restored),p.digest(expected))
        self.assertNotIn('prepared_',body);self.assertNotIn('self.enqueue_self.',body)
        self.assertIn('write_plan.start_batch(',body);self.assertIn('write_plan.append_batch_item(',body)
        self.assertIn('public_read::can_settle(',body)

    def test_original_config_caller_and_full_local_custom_store_fallback(self):
        public=self.functions[find.PUBLIC]['body'];legacy=self.functions[find.LEGACY]['body']
        self.assertEqual(public.count('self.internal.'+find.LEGACY+'('),1)
        self.assertEqual(p.digest(legacy),p.digest(self.original[find.PUBLIC]['body']))
        config_calls=re.findall(r'self\.view\(config\.([a-z_]+)\((\w+)\)\)',self.original[find.PUBLIC]['body'])
        self.assertEqual(len(config_calls),4)
        original_positions=[public.index(f'self.view(config.{method}({argument}))') for method,argument in config_calls]
        self.assertEqual(original_positions,sorted(original_positions))
        self.assertIn('arrival_storage.verify_hashes_batch(',legacy)
        self.assertNotIn('self.context.this_address()',public)
        self.assertNotIn('self.enqueue_self.',legacy)
        restored=find.restore_original(self.source,self.functions[find.PUBLIC],p)
        self.assertEqual(restored['body'],self.original[find.PUBLIC]['body'])

    def test_existing_original_dependency_closure_and_build_capture(self):
        report=json.loads((p.ROOT/'docs/api-compatibility/v8-find-private-dependencies.json').read_text())
        self.assertEqual(len(report['files']),36)
        for record in report['files']:
            self.assertEqual(hashlib.sha256(selected.restore_dependency(record['current'],(p.ROOT/record['current']).read_text()).encode()).hexdigest(),record['currentSha256'],record['current'])
        manifest=(p.ROOT/'contracts/system/artifact_find/Nargo.toml').read_text()
        self.assertIn('libs = { path = "../../prospect_original_libs" }',manifest)
        self.assertNotIn('libs = { path = "../../libs" }',manifest)
        lazy=p.ROOT/'contracts/prospect_original_libs/src/lazy_update.nr'
        self.assertEqual(hashlib.sha256(lazy.read_bytes()).hexdigest(),'e299bbe30510a1aa6ab4edb72f5b6e59ee8d8087b4a1b5e077883997ef0eabd5')
        # The checked builder consumes the exact source manifest, independent of
        # whether its entrypoint is Python or JavaScript. Every restored library
        # source and manifest must be included; no dependency is an implicit cache.
        files={str(file.relative_to(p.ROOT)) for file in (p.ROOT/'contracts/prospect_original_libs').rglob('*') if file.is_file() and file.suffix in {'.nr','.toml'}}
        self.assertTrue(files)
        self.assertLessEqual(files,set(selected.P['sourceFiles']))
        for name in files:self.assertEqual(hashlib.sha256((p.ROOT/name).read_bytes()).hexdigest(),selected.P['sourceFiles'][name],name)

    def test_transform_is_idempotent_and_preserves_unrelated_find_functions(self):
        self.assertEqual(find.apply_original_path(self.source,'artifact_find',p),self.source)
        frozen=find.frozen_functions(p)
        for name in self.original:
            if name not in [find.PRIVATE,find.PUBLIC]:
                self.assertEqual(p.digest(self.functions[name]['body']),p.digest(frozen[name]['body']),name)
        self.assertEqual(find.apply_original_path('unrelated','artifact_action',p),'unrelated')

    def test_mutated_snapshot_route_cannot_silently_drop_one_root(self):
        frozen=find.frozen_functions(p)
        original_body=frozen[find.PREPARED]['body']
        for _,_,state in find.ROOT_STATES:
            changed={**frozen,find.PREPARED:{**frozen[find.PREPARED],
                     'body':original_body.replace(f'prepared_{state}_root, true',f'prepared_{state}_root, false',1)}}
            with patch.object(find,'frozen_functions',return_value=changed):
                with self.assertRaises(AssertionError):find.route_body(find.PUBLIC,p)

if __name__=='__main__':unittest.main()
