"""Structural worker-boundary checks against the frozen original compiled ABIs.

Runtime state/fee tests remain necessary. These checks protect raw selector
encoding, exact legacy argument prefixes, and the delegated actor boundary.
"""
import importlib.util
import json
import re
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('plans', HERE / 'generate-backend-plans.py')
plans = importlib.util.module_from_spec(spec)
spec.loader.exec_module(plans)


def abi_type(type_):
    kind = type_['kind']
    if kind == 'field':
        return 'Field'
    if kind == 'boolean':
        return 'bool'
    if kind == 'integer':
        return ('u' if type_['sign'] == 'unsigned' else 'i') + str(type_['width'])
    if kind == 'array':
        return '[' + abi_type(type_['type']) + ';' + str(type_['length']) + ']'
    if kind == 'struct':
        return '(' + ','.join(abi_type(field['type']) for field in type_['fields']) + ')'
    raise AssertionError(type_)


def array_literals(source, name):
    arrays=[]
    for match in re.finditer(r'let\s+'+re.escape(name)+r'\s*=\s*\[',source):
        start=source.index('[',match.start())
        end=plans.p.closing(source,start,'[',']')
        arrays.append(plans.p.split_arguments(source[start+1:end]))
    return arrays


class WorkerTransformTests(unittest.TestCase):
    def test_raw_original_selectors_and_complete_prefix_match_frozen_abi(self):
        baseline = json.loads((HERE / 'baseline/artifacts.json').read_text())
        manifest = json.loads(plans.MANIFEST.read_text())
        count = 0
        for record in manifest['continuations']:
            package = record['package']
            if package not in plans.WORKERS:
                continue
            source = (plans.ROOT / 'contracts/system' / package / 'src/main.nr').read_text()
            function = plans.p.functions(source)[record['prepared']]
            original_name = record['prepared'].removesuffix('_prepared')
            contract = 'Core' if package == 'core' else 'ArtifactValut'
            frozen = baseline[contract]['functions'][original_name]
            schema = next(part['type']['fields'] for part in frozen['schema'] if part['name'] == 'parameters')
            signature = original_name + '(' + ','.join(abi_type(field['type']) for field in schema) + ')'
            self.assertIn('from_signature("' + signature + '")', function['body'])
            original = plans.original_definition(source, original_name)
            width = sum(plans.type_width(re.match(r'(?:mut\s+)?\w+\s*:\s*(.+)', arg).group(1)) for arg in original['params'])
            self.assertIn('original_calldata:[Field;' + str(width+1) + ']', function['body'])
            self.assertIn('for fallback_i in 0..' + str(width), function['body'])
            self.assertIn('original_calldata[0]=original_selector.to_field()', function['body'])
            self.assertIn('original_calldata[1+fallback_i]=prepared_payload[fallback_i]', function['body'])
            self.assertIn('::libs::public_call::call(self.context.this_address(),original_calldata)', function['body'])
            count += 1
        self.assertEqual(count, 3)

    def test_worker_authenticates_actual_system_before_decoding_and_derives_actor(self):
        for package, (directory, _, _) in plans.WORKERS.items():
            source = (plans.ROOT / 'contracts/settlement_workers' / directory / 'src/main.nr').read_text()
            self.assertNotIn('self.storage.', source)
            functions = plans.p.functions(source)
            for name, function in functions.items():
                if not name.startswith('try_'):
                    continue
                self.assertNotIn('actor:', ''.join(function['params']))
                prefix = function['body'].split('payload.words[', 1)[0]
                self.assertIn('get_contract_instance_current_class_id_avm(self.msg_sender())', prefix)
                self.assertIn('caller_class.unwrap().to_field()==super::system_class::SYSTEM_CLASS', re.sub(r'\s+','',prefix))
            commit = functions['_commit_plan_for_system']['body']
            self.assertIn('commit_plan_small(([Field;141]))', commit)
            self.assertIn('commit_plan(([Field;397]))', commit)
            self.assertEqual([fields[1] for fields in array_literals(commit,'calldata')], ['self.msg_sender().to_field()']*(2 if package=='core' else 3))
            if package=='core':
                self.assertIn('calldata[1]=self.msg_sender().to_field()',commit)

    def test_worker_raw_selector_schema_and_forwarding_order_are_fixed(self):
        for record in json.loads(plans.MANIFEST.read_text())['continuations']:
            if record['package'] not in plans.WORKERS:
                continue
            source = (plans.ROOT / 'contracts/system' / record['package'] / 'src/main.nr').read_text()
            body = plans.p.functions(source)[record['prepared']]['body']
            direct = {'give_spaceships_public_prepared':'try_settle_give_spaceships(([Field;186]))'}
            if record['prepared'] in direct:
                self.assertIn(direct[record['prepared']], body)
                self.assertNotIn('state_worker_address', body)
                continue
            signature = 'try_' + record['prepared'] + '(([Field;' + str(record['flatWidth'] + 12) + ']))'
            self.assertIn('from_signature("' + signature + '")', body)
            self.assertIn('worker_calldata[0]=worker_selector.to_field()', body)
            self.assertIn('worker_calldata[1]=state_backend_address.to_field()', body)
            self.assertIn('for worker_i in 0..10 { worker_calldata[2+worker_i]=plan_addresses[worker_i].to_field(); }', body)
            self.assertIn('worker_calldata[12]=system_admin.to_field()', body)
            self.assertIn('for worker_i in 0..'+str(record['flatWidth'])+' { worker_calldata[13+worker_i]=prepared_payload[worker_i]; }', body)
            self.assertIn('::libs::public_call::call(state_worker_address,worker_calldata)', body)

    def test_plan_raw_wire_prefix_matches_guarded_backend_decode(self):
        engine = plans.p.functions(plans.backend())
        for delegated in [False, True]:
            helper = plans.system_plan_helpers(delegated)
            for capacity in [128, 384]:
                offset = 1
                width = capacity + 12 + offset
                method = 'commit_plan' + ('_small' if capacity == 128 else '')
                body = engine[method]['body']
                self.assertIn(method + '(([Field;' + str(width) + ']))', helper)
                fields=array_literals(helper,'calldata')[0 if capacity==128 else 1]
                expected=['selector.to_field()','self.msg_sender().to_field()']
                expected += [f'addresses[{i}].to_field()' for i in range(10)]
                expected += ['required_mask as Field']+[f'plan.words[{i}]' for i in range(capacity)]+['plan.length as Field']
                self.assertEqual(fields,expected)
                self.assertIn('required_mask=payload.words[' + str(10 + offset) + '] as u16', body)
                self.assertIn('length=payload.words[' + str(width - 1) + '] as u32', body)
                guard = 'let actor = _resolve_plan_actor(self.context, AztecAddress::from_field(payload.words[0]));'
                self.assertTrue(body.strip().startswith(guard))
                self.assertIn('payload.words.as_slice(),length,actor', body)
                self.assertNotIn('[0;384]', body)

    def test_shared_slice_preserves_header_and_record_boundaries(self):
        engine = plans.p.functions(plans.backend())
        interpreter = engine['_commit_state_plan']['body']
        self.assertIn('let end = 12 + length;', interpreter)
        self.assertIn('let mut cursor = 12;', interpreter)
        self.assertIn('cursor + 3 <= end', interpreter)
        self.assertNotIn('cursor + 3 <= length', interpreter)

    def test_core_worker_large_plan_loop_retains_exact_original_wire(self):
        helper=plans.system_plan_helpers(delegated=True,full_literal=False)
        self.assertEqual(len(array_literals(helper,'calldata')),1)
        self.assertEqual(len(array_literals(helper,'calldata')[0]),142)
        for text in ['let mut calldata:[Field;398]=[0;398]',
                     'calldata[0]=selector.to_field()', 'calldata[1]=self.msg_sender().to_field()',
                     'for i in 0..10 { calldata[2+i]=addresses[i].to_field(); }',
                     'calldata[12]=required_mask as Field',
                     'for i in 0..384 { if i < plan.length { calldata[13+i]=plan.words[i]; } }',
                     'calldata[397]=plan.length as Field']:
            self.assertIn(text,helper)

    def test_medium_core_route_retains_actor_bounds_and_shared_interpreter(self):
        helper = plans.system_plan_helpers(delegated=True, full_literal=False, medium=True)
        body = plans.p.functions(plans.backend())['commit_plan_medium']['body']
        for token in ['if plan.length <= 128', 'else if plan.length <= 172',
                      'commit_plan_medium(([Field;185]))',
                      'commit_plan(([Field;397]))']:
            self.assertIn(token, helper)
        fields=array_literals(helper,'calldata')[1]
        expected=['selector.to_field()','self.msg_sender().to_field()']
        expected += [f'addresses[{i}].to_field()' for i in range(10)]
        expected += ['required_mask as Field']+[f'plan.words[{i}]' for i in range(172)]+['plan.length as Field']
        self.assertEqual(fields,expected)
        self.assertNotIn('for i in 0..172',helper)
        self.assertIn('assert(length <= 172', body)
        self.assertTrue(body.strip().startswith('let actor = _resolve_plan_actor'))
        self.assertIn('payload.words.as_slice(),length,actor', body)
        # The same full-width plan survives each routing threshold. No record
        # data is shortened or cast to integers by the transport.
        prefix=[-1]+list(range(10))+[65535]
        for length in [0,128,129,169,172,173,384]:
            capacity=128 if length<=128 else 172 if length<=172 else 384
            words=[(1<<200)+i for i in range(length)]
            packet=prefix+words+[0]*(capacity-length)+[length]
            self.assertEqual(packet[:12],prefix)
            self.assertEqual(packet[12:12+packet[-1]],words)
            self.assertEqual(len(packet),capacity+13)
        core=(plans.ROOT/'contracts/settlement_workers/core/src/main.nr').read_text()
        vault=(plans.ROOT/'contracts/settlement_workers/vault/src/main.nr').read_text()
        self.assertIn('commit_plan_medium(([Field;185]))',core)
        self.assertIn('commit_plan_medium(([Field;185]))',vault)
        find=(plans.ROOT/'contracts/system/artifact_find/src/main.nr').read_text()
        self.assertIn('commit_plan_medium(([Field;185]))',find)

    def test_original_core_init_carries_every_original_argument_without_worker(self):
        source=(plans.ROOT/'contracts/system/core/src/main.nr').read_text()
        current=plans.p.functions(source)
        original=plans.original_core.baseline(plans.p)
        v7=plans.p.functions(plans.selected_core.reference('v7-core.nr'))
        self.assertEqual(current['initialize_player']['full'],v7['initialize_player']['full'])
        self.assertEqual(plans.expanded_current_definition(source,'initialize_player_public')['body'],original['initialize_player_public']['body'])
        self.assertEqual(current['initialize_player_new_public_prepared']['full'],v7['initialize_player_new_public_prepared']['full'])
        self.assertIn('_initialize_player_public_local(self.context,',current['initialize_player_public_prepared']['body'])
        self.assertIn('#[only_self]',current['initialize_player_public_prepared']['header'])
        self.assertNotIn('state_worker',current['initialize_player_public']['body'])

    def test_only_worker_paths_using_config_guard_the_original_caller(self):
        guarded = []
        for record in json.loads(plans.MANIFEST.read_text())['continuations']:
            if record['package'] not in plans.WORKERS:
                continue
            source = (plans.ROOT / 'contracts/system' / record['package'] / 'src/main.nr').read_text()
            original = plans.original_definition(source, record['prepared'].removesuffix('_prepared'))
            body = plans.p.functions(source)[record['prepared']]['body']
            uses_config = bool(re.search(r'self\.view\(config\.', original['body']))
            self.assertEqual('::libs::config_recognition::supports_config(plan_addresses[0])' in body, uses_config)
            if uses_config:
                guarded.append(record['prepared'])
                self.assertLess(body.index('supports_config('), body.index('::libs::public_call::call(state_worker_address,'))
                self.assertIn('if !settled_by_backend', body)
                self.assertIn('::libs::public_call::call(self.context.this_address(),original_calldata)', body)
        self.assertEqual(len(guarded), 0)
        core=(plans.ROOT/'contracts/system/core/src/main.nr').read_text()
        for private,public in plans.original_core.ACTIONS['core']:
            original=plans.original_core.baseline(plans.p)[public]['body']
            definitions=plans.p.functions(core)
            current=definitions['_'+public+'_local']['body'] if '_'+public+'_local' in definitions else definitions[public]['body']
            # Core executes every Config view from its original contract caller.
            def config_calls(body):
                found=[]
                for match in re.finditer(r'self\.view\(config\.',body):
                    start=body.index('(',match.start())
                    end=plans.p.closing(body,start,'(',')')
                    found.append(body[match.start():end+1])
                return found
            original_calls=config_calls(original)
            current_calls=config_calls(current)
            self.assertEqual(current_calls,original_calls,public)
            self.assertNotIn('supports_config(',current)
            self.assertNotIn('state_worker',current)

    def test_original_refresh_keeps_full_arguments_and_empty_batch_authorization(self):
        source=(plans.ROOT/'contracts/system/core/src/main.nr').read_text()
        current=plans.p.functions(source)
        original=plans.original_core.baseline(plans.p)
        v7=plans.p.functions(plans.selected_core.reference('v7-core.nr'))
        self.assertEqual(current['refresh_planet']['full'],v7['refresh_planet']['full'])
        self.assertEqual(current['refresh_planet_empty_public_prepared']['full'],v7['refresh_planet_empty_public_prepared']['full'])
        self.assertIn('_refresh_planet_public_local(self.context,',current['refresh_planet_public_prepared']['body'])
        public='refresh_planet_public'
        restored=plans.expanded_current_definition(source,public)
        self.assertEqual(restored['body'],original[public]['body'])
        body=current['_'+public+'_local']['body']
        self.assertIn('set_arrival_locations_max20(',body)
        self.assertIn('new_arrival_artifact_locations',body)
        self.assertNotIn('if original_arrivals_count != 0',body)

    def test_every_plan_producer_only_appends_to_zero_initialized_words(self):
        paths=list((plans.ROOT/'contracts/system').glob('*/src/main.nr'))
        paths+=list((plans.ROOT/'contracts/settlement_workers').glob('*/src/main.nr'))
        producers=[]
        for path in paths:
            for name,function in plans.p.functions(path.read_text()).items():
                body=function['body']
                if 'let mut write_plan' not in body:
                    continue
                producers.append((path.relative_to(plans.ROOT).as_posix(),name))
                self.assertIn('let mut write_plan = ::libs::state_plan::WritePlan::new()',body)
                self.assertNotRegex(body,r'write_plan\.(words|length)\s*(\[[^\]]*\])?\s*=')
                self.assertLessEqual(set(re.findall(r'write_plan\.(\w+)\s*\(',body)),{'set','authorize_batch','start_batch','append_batch_item'})
        # V8 also restores Activate/Deactivate private enqueues; their original
        # public continuations build plans with public-computed roots.
        # Reveal and Safe Owner use typed writes; the unused Give Worker remains.
        prepared=[item for item in producers if item[1].endswith('_prepared')]
        original=[item for item in producers if not item[1].endswith('_prepared')]
        self.assertEqual(len(prepared),7)
        self.assertEqual(set(original),{
            ('contracts/system/artifact_prospect/src/main.nr','prospect_planet_public'),
            ('contracts/system/artifact_find/src/main.nr','find_artifact_public'),
            ('contracts/system/artifact_action/src/main.nr','activate_artifact_public'),
            ('contracts/system/artifact_action/src/main.nr','deactivate_artifact_public'),
        })
        self.assertEqual(len(original),4)
        self.assertEqual(len(producers),11)


if __name__ == '__main__':
    unittest.main()
