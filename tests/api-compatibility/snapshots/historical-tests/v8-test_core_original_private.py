"""V8 Core source compatibility; native identity and whole-transaction fees remain gates."""
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import unittest

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('core_original_plans',HERE/'generate-backend-plans.py')
plans=importlib.util.module_from_spec(spec);spec.loader.exec_module(plans)
p,core=plans.p,plans.original_core

class CoreOriginalPrivateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source=(plans.ROOT/'contracts/system/core/src/main.nr').read_text()
        cls.current=p.functions(cls.source)
        cls.original=core.baseline(p)

    def test_five_private_bodies_and_enqueues_equal_the_immutable_original(self):
        self.assertEqual(len(core.ACTIONS['core']),5)
        for private,public in core.ACTIONS['core']:
            old,new=self.original[private],self.current[private]
            self.assertEqual(new['body'],old['body'],private)
            self.assertEqual(p.digest(new['header']),p.digest(old['header']))
            self.assertEqual(new['body'].count('self.enqueue_self.'+public+'('),1)
            self.assertNotIn('prepared_',new['body'])
            self.assertNotIn(public+'_prepared',self.current)
        self.assertNotIn('initialize_player_new_public_prepared',self.current)
        self.assertNotIn('refresh_planet_empty_public_prepared',self.current)

    def test_every_original_api_stays_present_with_exact_signature_attributes(self):
        self.assertTrue(set(self.original).issubset(self.current))
        for name,old in self.original.items():
            self.assertEqual(p.digest(self.current[name]['header']),p.digest(old['header']),name)

    def test_29_remaining_live_reads_have_exact_individual_custom_store_fallbacks(self):
        counts={}
        for _,public in core.ACTIONS['core']:
            if public=='reveal_location_public':continue
            old=self.original[public]['body']
            expected,records=core.optimize_public(old)
            body=self.current[public]['body']
            self.assertEqual(p.digest(body),p.digest(expected),public)
            counts[public]=len(records)
            for record in records:
                self.assertEqual(body.count(record['replacement']),1)
                self.assertIn('else { '+record['original']+' }',record['replacement'])
                self.assertIn('state_backend_address.is_zero() { false }',record['replacement'])
                self.assertIn(f"get_namespace_kind(state_backend_address, {record['store']}.target_contract) == {record['kind']}",record['replacement'])
                self.assertNotIn(' as u',record['replacement'])
                if record['kind']==2:
                    self.assertIn(record['arguments'][0]+'.to_field()',record['replacement'])
        self.assertEqual(counts,{'refresh_planet_public':6,'upgrade_planet_public':7,'withdraw_silver_public':8,'initialize_player_public':8})

    def test_full_public_bodies_restore_original_assertion_call_and_write_order(self):
        for _,public in core.ACTIONS['core']:
            restored=plans.expanded_current_definition(self.source,public)
            self.assertEqual(restored['body'],self.original[public]['body'],public)
            current=[(call['store'],call['method'],call['args']) for call in plans.calls(self.current[public]['body']) if call['mode']=='call']
            original=[(call['store'],call['method'],call['args']) for call in plans.calls(self.original[public]['body']) if call['mode']=='call']
            self.assertEqual(current,original,public)
            self.assertNotIn('state_worker',self.current[public]['body'])
            self.assertNotIn('WritePlan',self.current[public]['body'])
            self.assertNotIn('::libs::public_call::call(',self.current[public]['body'])

    def test_no_conditional_empty_batch_shortcut_or_inactive_input_projection(self):
        for _,public in core.ACTIONS['core']:
            if public=='reveal_location_public':continue
            body=self.current[public]['body']
            self.assertNotIn('has_nonzero_ids',body)
            self.assertNotIn('if original_arrivals_count != 0',body)
            self.assertNotIn('if origin_arrivals_count != 0',body)
            records=core.optimize_public(self.original[public]['body'])[1]
            for record in records:
                if record['method']=='verify_hashes_batch':
                    self.assertIn(record['original'],body)
            # The original batch setter receives the complete original typed array.
            writes=[x for x in plans.calls(body) if x['mode']=='call' and x['method']=='set_arrival_locations_max20']
            old=[x for x in plans.calls(self.original[public]['body']) if x['mode']=='call' and x['method']=='set_arrival_locations_max20']
            self.assertEqual([x['args'] for x in writes],[x['args'] for x in old])

    def test_config_calls_stay_at_core_with_the_original_arguments(self):
        def calls(body):
            result=[]
            for match in re.finditer(r'self\.view\(config\.',body):
                start=body.index('(',match.start());end=p.closing(body,start,'(',')')
                result.append(body[match.start():end+1])
            return result
        total=0
        for _,public in core.ACTIONS['core']:
            self.assertEqual(calls(self.current[public]['body']),calls(self.original[public]['body']))
            total+=len(calls(self.original[public]['body']))
            self.assertNotIn('supports_config(',self.current[public]['body'])
        self.assertGreater(total,0)

    def test_dependency_closure_uses_restored_original_code(self):
        nargo=(plans.ROOT/'contracts/system/core/Nargo.toml').read_text()
        self.assertIn('libs = { path = "../../prospect_original_libs" }',nargo)
        self.assertNotIn('libs = { path = "../../libs" }',nargo)
        report=json.loads((plans.ROOT/'docs/api-compatibility/v7-prospect-private-dependencies.json').read_text())
        for row in report['files']:
            self.assertEqual(hashlib.sha256((plans.ROOT/row['current']).read_bytes()).hexdigest(),row['currentSha256'],row['current'])

    def test_retained_worker_cannot_be_reached_by_core_and_vault_is_unchanged(self):
        core.verify_retained_worker(plans.ROOT)
        self.assertNotIn('CoreSettlementWorker::at(',self.source)
        self.assertNotIn('GameStateBackend::at(',self.source)
        self.assertNotRegex(self.source,r'from_signature\("(?:try_|commit_plan)')
        snapshot=json.loads((plans.ROOT/'docs/api-compatibility/v8-core-base-snapshot.json').read_text())
        for relative in ['contracts/system/artifact_valut/src/main.nr','contracts/system/artifact_valut/Nargo.toml','contracts/settlement_workers/vault/src/main.nr','contracts/settlement_workers/vault/Nargo.toml']:
            self.assertEqual(hashlib.sha256((plans.ROOT/relative).read_bytes()).hexdigest(),snapshot['copiedFiles'][relative],relative)

    def test_reapplication_is_idempotent_and_records_exclude_all_core_prepared_paths(self):
        self.assertEqual(core.apply_original_path(self.source,'core',p),self.source)
        manifest=json.loads(plans.MANIFEST.read_text())
        actual={(x['private'],x['public']) for x in manifest['originalPrivateActions'] if x['package']=='core'}
        self.assertEqual(actual,set(core.ACTIONS['core']))
        self.assertFalse(any(x['package']=='core' for x in manifest['continuations']))

    def test_wrong_kind_key_missing_fallback_and_omitted_write_are_detected(self):
        public='refresh_planet_public';definition=self.current[public]
        record=core.optimize_public(self.original[public]['body'])[1][0]
        for changed in [record['replacement'].replace(' == 3',' == 2'),record['replacement'].replace(record['arguments'][0]+',','0,',1),record['replacement'].replace('else { '+record['original']+' }','else { true }')]:
            self.assertNotEqual(changed,record['replacement'])
            broken=dict(definition);broken['body']=definition['body'].replace(record['replacement'],changed,1)
            with self.assertRaises(AssertionError):core.restore_original(self.source,broken,p)
        broken=dict(definition);broken['body']=definition['body'].replace('set_arrival_locations_max20(','set_spaceship_locations_max5(',1)
        restored=core.restore_original(self.source,broken,p)
        self.assertNotEqual(p.digest(restored['body']),p.digest(self.original[public]['body']))

if __name__=='__main__':unittest.main()
