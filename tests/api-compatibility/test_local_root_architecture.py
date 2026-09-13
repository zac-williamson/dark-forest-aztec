"""Local-root trust/order checks, complementary to actual storage API executions.

Generate only into a temporary source tree. These tests do not compile, open a
wallet, send a transaction, or pretend source checks prove runtime equivalence.
"""
from pathlib import Path
import importlib.util
import shutil
import subprocess
import sys
import tempfile
import unittest
import check
import generate_facades
import typed_facade_logs
from verify_facade_layout import storage_slots, EXPECTED

ROOT=Path(__file__).resolve().parents[2]

def body(source,name):
    import re
    m=re.search(r'\bfn\s+'+name+r'\s*\(',source)
    end=check.balanced(check.clean(source),m.end()-1)
    start=source.index('{',end);stop=check.balanced(check.clean(source),start,'{','}')
    return source[start+1:stop]

class LocalRootArchitectureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp=tempfile.TemporaryDirectory(prefix='df-local-root-source-test-')
        cls.root=Path(cls.tmp.name)
        def source_only(directory,names):
            excluded={'target','.git','node_modules','artifacts'}
            return [name for name in names if name in excluded or (Path(directory)/name).is_symlink()]
        shutil.copytree(ROOT/'contracts',cls.root/'contracts',ignore=source_only)
        fragments=cls.root/'tests/api-compatibility/generated';fragments.mkdir(parents=True)
        for name in ['backend-plans.nr','backend-move.nr']:
            shutil.copy2(ROOT/'tests/api-compatibility/generated'/name,fragments/name)
        for slug,kind in generate_facades.KINDS.items():generate_facades.generate(slug,kind,cls.root)
        subprocess.run([sys.executable,str(ROOT/'tests/api-compatibility/build-backend.py'),'--root',str(cls.root)],check=True,capture_output=True)
        cls.backend=(cls.root/'contracts/state_backend/src/main.nr').read_text()

    @classmethod
    def tearDownClass(cls):cls.tmp.cleanup()

    def test_all_original_facade_api_headers_and_event_schemas_survive(self):
        for slug in generate_facades.KINDS:
            path=Path(f'contracts/storage/{slug}/src/main.nr')
            old=check.parse_source(str(path),(check.BASE/'sources'/path).read_text())
            new=check.parse_source(str(path),(self.root/path).read_text())
            actual={f['name']:f for f in new['functions']}
            for expected in old['functions']:
                got=actual[expected['name']]
                for key in ['parameters','returnType','attributes','kind','unconstrained']:
                    self.assertEqual(got.get(key),expected.get(key),(slug,expected['name'],key))
            schema=lambda events:[{k:v for k,v in event.items()if k!='line'}for event in events]
            self.assertEqual(schema(new['events']),schema(old['events']),slug)

    def test_every_root_writer_keeps_authorization_before_write_and_event(self):
        for slug in generate_facades.KINDS:
            source=(self.root/f'contracts/storage/{slug}/src/main.nr').read_text()
            parsed=check.parse_source(slug,source)
            self.assertEqual([f['name']for f in parsed['storage']],list(EXPECTED))
            self.assertEqual(parsed['storage'][2]['type'],check.norm('Map<Field,PublicMutable<Field,Context>,Context>'))
            for name in [f'emit_{slug}_update',f'emit_{slug}_fields']:
                text=body(source,name)
                self.assertLess(text.index('assert('),text.index('local_roots.at('))
                self.assertLess(text.index('local_roots.at('),text.index('emit'))
                self.assertIn('self.msg_sender() == backend_address',text)
            setter=body(source,'set')
            event_emit='aztec::oracle::avm::emit_public_log(' if slug in typed_facade_logs.SPECS else 'self.emit('
            self.assertLess(setter.index('local_roots.at('),setter.index(event_emit))
            if slug=='arrival':
                self.assertLess(setter.index('legacy_set_arrival('),setter.index('local_roots.at('))
            else:
                self.assertLess(setter.index('self.internal.assert_authorized()'),setter.index('local_roots.at('))
                self.assertNotIn('self.call(',setter,'Single typed setters must not gain another storage hop')

    def test_typed_setters_hash_full_state_without_zero_normalization(self):
        for slug in generate_facades.KINDS:
            source=(self.root/f'contracts/storage/{slug}/src/main.nr').read_text()
            state='planet' if slug=='planet' else 'state'
            key='id.to_field()' if slug=='player' else 'id'
            setter=body(source,'set')
            if slug in typed_facade_logs.SPECS:
                self.assertIn(f'let fields = {state}.serialize();',setter)
                self.assertIn('let root = poseidon2_hash(fields);',setter)
                self.assertEqual(setter.count('.serialize()'),1)
            else:
                self.assertIn(f'poseidon2_hash({state}.serialize())',setter)
            self.assertIn(f'local_roots.at({key}).write(',setter)
            self.assertNotIn('::zero()',setter.split('local_roots.at(')[1])
        world=(self.root/'contracts/storage/world/src/main.nr').read_text()
        constructor=body(world,'constructor')
        self.assertLess(constructor.index('world.misc_nonce = 1'),constructor.index('local_roots.at(0).write'))
        self.assertLess(constructor.index('local_roots.at(0).write'),constructor.index('self.emit('))

    def test_batches_restore_exact_original_body_with_local_root_name_only(self):
        methods={'artifact':['set_spaceships_max5'],
                 'artifact_location':['set_arrival_locations_max20','set_spaceship_locations_max5']}
        for slug,names in methods.items():
            path=Path(f'contracts/storage/{slug}/src/main.nr')
            original=(check.BASE/'sources'/path).read_text()
            current=(self.root/path).read_text()
            for name in names:
                expected=body(original,name).replace('self.storage.state_roots','self.storage.local_roots')
                actual=body(current,name)
                self.assertEqual(check.norm(actual),check.norm(expected),(slug,name))
                self.assertNotIn('self.call(',actual)
                self.assertLess(actual.index('assert_authorized'),actual.index('count <='))
                self.assertLess(actual.index('local_roots.at('),actual.index('self.emit('))
                self.assertNotIn(f'fn {name}(',self.backend)
            authorization=body(current,'assert_authorized')
            self.assertEqual(check.norm(authorization),check.norm(body(original,'assert_authorized')))
            self.assertNotIn('self.call(',authorization)
            self.assertNotIn('self.view(',authorization)
        self.assertNotIn('fn assert_write_authorized(',self.backend)
        self.assertIn('fn _set_arrival_locations_max20(',self.backend,'Move still needs its internal batch helper')

    def test_backend_has_one_root_authority_and_arrival_payload_is_atomic_until_callback(self):
        self.assertNotIn('self.storage.roots',self.backend)
        self.assertNotIn('fn legacy_set_root(',self.backend)
        self.assertEqual([f['name']for f in check.parse_source('backend',self.backend)['storage']],
            ['kinds','arrivals','counters'])
        for name in ['legacy_set_arrival','_write_arrival','_store_arrival_payload']:
            self.assertNotIn('self.call(',body(self.backend,name),name)
        self.assertLess(body(self.backend,'legacy_set_arrival').index('_assert_authorized'),body(self.backend,'legacy_set_arrival').index('id == state_id'))
        arrival=body(self.backend,'_set_arrival')
        self.assertLess(arrival.index('_write_arrival'),arrival.index('emit_arrival_fields(id,root,'))
        for slug in generate_facades.KINDS:
            self.assertIn(f'emit_{slug}_fields(id,root,',body(self.backend,f'_set_{slug}'))

    def test_root_and_permission_readers_target_live_facade(self):
        public=(self.root/'contracts/state_backend_readonly/src/public_read.nr').read_text()
        utility=(self.root/'contracts/state_backend_readonly/src/lib.nr').read_text()
        self.assertIn('derive_storage_slot_in_map(super::FACADE_ROOTS,key)',body(public,'get_state_root'))
        self.assertIn('storage_read(slot,namespace.to_field())',body(public,'get_state_root'))
        self.assertIn('storage_read(context.block_header(), namespace, slot)',body(utility,'get_state_root'))
        self.assertIn('if storage_read(slot,namespace.to_field())!=0 { true } else { actor==get_admin(backend,namespace) }',body(public,'is_authorized'))
        for name,slot in [('ARRIVALS',2),('COUNTERS',3),('FACADE_ROOTS',3),('FACADE_ADMIN',1),('FACADE_AUTHORIZED',4),('FACADE_LISTS',6),('FACADE_COUNT',7)]:
            self.assertIn(f'pub global {name}: Field = {slot};',utility)

    def test_original_local_permission_bodies_and_explicit_grants_are_preserved(self):
        names=['assert_admin','assert_authorized','transfer_admin','add_authorized_contract',
               'remove_authorized_contract','add_authorized_contracts_batch',
               'get_admin','is_authorized','get_authorized_count','get_authorized_contract']
        for slug in generate_facades.KINDS:
            path=Path(f'contracts/storage/{slug}/src/main.nr')
            original=(check.BASE/'sources'/path).read_text()
            current=(self.root/path).read_text()
            functions={f['name']for f in check.parse_source(slug,original)['functions']}
            for name in names:
                if name in functions:self.assertEqual(check.norm(body(current,name)),check.norm(body(original,name)),(slug,name))
            binding=body(current,'set_state_backend')
            self.assertIn('self.msg_sender() == self.storage.admin.read()',binding)
            self.assertLess(binding.index('state_backend.write'),binding.index('self.call('))
            self.assertNotIn('bootstrap_admin',current)
            for name in ['add_authorized_contract','remove_authorized_contract','add_authorized_contracts_batch']:
                self.assertIn('self.storage.authorized_map',body(current,name))
                self.assertNotIn('is_authorized(',body(current,name))
        for name in ['admins','authorized','indexes','lists','counts']:
            self.assertNotIn('self.storage.'+name,self.backend)
        auth=body(self.backend,'_assert_authorized')
        self.assertIn('derive_storage_slot_in_map(4,actor)',auth)
        self.assertIn('storage_read(slot,ns.to_field())',auth)
        self.assertIn('storage_read(1,ns.to_field())',auth)

    def test_original_nonarrival_bodies_restore_with_only_explicit_event_transform(self):
        for slug in generate_facades.KINDS:
            if slug=='arrival':continue
            path=Path(f'contracts/storage/{slug}/src/main.nr')
            original=(check.BASE/'sources'/path).read_text();current=(self.root/path).read_text()
            for function in check.parse_source(slug,original)['functions']:
                if function['name']=='constructor':continue
                expected=body(original,function['name']).replace('self.storage.state_roots','self.storage.local_roots')
                if slug=='player':expected=expected.replace('local_roots.at(id)','local_roots.at(id.to_field())')
                actual=body(current,function['name'])
                if function['name']=='set' and slug in typed_facade_logs.SPECS:
                    actual=typed_facade_logs.restore_setter(slug,actual)
                self.assertEqual(check.norm(actual),check.norm(expected),(slug,function['name']))

    def test_batch_callbacks_authenticate_backend_before_any_write(self):
        for slug,maximum in [('artifact_location',5),('artifact_location',20),('artifact',5)]:
            source=(self.root/f'contracts/storage/{slug}/src/main.nr').read_text()
            callback=body(source,f'emit_{slug}_batch_max{maximum}')
            self.assertIn('self.msg_sender() == backend_address',callback)
            self.assertLess(callback.index('Only state backend'),callback.index('count <= '))
            self.assertLess(callback.index('count <= '),callback.index('for i in 0..count'))
            self.assertIn('if ids[i] != 0',callback)
            self.assertIn('poseidon2_hash(fields[i])',callback)
            self.assertLess(callback.index('local_roots.at(ids[i]).write'),callback.index('emit_public_log'))
            self.assertNotIn('self.call(',callback)
            self.assertNotIn('self.view(',callback)

    def test_compiler_layout_parser_rejects_missing_or_duplicate_contract(self):
        def entry(name):return {'fields':[{'name':'contract_name','value':{'value':name}},
            {'name':'fields','value':{'fields':[{'name':k,'value':{'fields':[{'name':'slot','value':{'value':hex(v)}}]}}for k,v in EXPECTED.items()]}}]}
        artifact={'outputs':{'globals':{'storage':[entry('PlanetStorage')]}}}
        self.assertEqual(storage_slots(artifact,'PlanetStorage'),EXPECTED)
        with self.assertRaises(AssertionError):storage_slots(artifact,'OtherStorage')
        artifact['outputs']['globals']['storage'].append(entry('PlanetStorage'))
        with self.assertRaises(AssertionError):storage_slots(artifact,'PlanetStorage')

if __name__=='__main__':unittest.main()
