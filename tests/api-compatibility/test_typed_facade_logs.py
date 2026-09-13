"""Source/ABI checks for exact typed logs; not runtime or measured fee evidence."""
import json
from pathlib import Path
import re
import shutil
import tempfile
import unittest
import check
import generate_facades
import typed_facade_logs as logs

P=21888242871839275222246405745257275088548364400416034343698204186575808495617
CONTRACTS={'planet':'PlanetStorage','planet_artifacts':'PlanetArtifactsStorage',
           'artifact':'ArtifactStorage','artifact_location':'ArtifactLocationStorage'}

def leaves(t):
    if t['kind']=='struct':return [x for f in t['fields'] for x in leaves(f['type'])]
    if t['kind']=='array':return leaves(t['type'])*t['length']
    assert t['kind'] in ('field','integer','boolean'),t
    return [t]

def flatten(t,values):
    if t['kind']=='struct':return sum((flatten(f['type'],values) for f in t['fields']),[])
    if t['kind']=='array':return sum((flatten(t['type'],values) for _ in range(t['length'])),[])
    return [next(values)]

class TypedFacadeLogTests(unittest.TestCase):
    def test_exact_four_setters_no_private_or_permission_change(self):
        self.assertEqual(set(logs.SPECS),set(CONTRACTS))
        for slug in generate_facades.KINDS:
            path=Path('contracts/storage')/slug/'src/main.nr'
            old=(check.BASE/'sources'/path).read_text();new=(check.ROOT/path).read_text()
            self.assertNotIn('#[external("private")]',new)
            for name in ['assert_authorized','assert_admin','transfer_admin','add_authorized_contract',
                         'remove_authorized_contract','add_authorized_contracts_batch']:
                self.assertEqual(check.norm(logs.function_body(old,name)),check.norm(logs.function_body(new,name)),(slug,name))
            if slug in logs.SPECS:
                self.assertEqual(check.norm(logs.restore_setter(slug,logs.function_body(new,'set'))),
                                 check.norm(logs.function_body(old,'set').replace('state_roots','local_roots')))
            elif slug!='arrival':
                expected=logs.function_body(old,'set').replace('state_roots','local_roots')
                if slug=='player':expected=expected.replace('local_roots.at(id)','local_roots.at(id.to_field())')
                self.assertEqual(check.norm(logs.function_body(new,'set')),check.norm(expected))

    def test_all_original_headers_and_typed_event_schemas_unchanged(self):
        for slug in logs.SPECS:
            path=Path('contracts/storage')/slug/'src/main.nr'
            old=check.parse_source(str(path),(check.BASE/'sources'/path).read_text())
            new=check.parse_source(str(path),(check.ROOT/path).read_text())
            actual={f['name']:f for f in new['functions']}
            for expected in old['functions']:
                for key in ['parameters','returnType','attributes','kind','unconstrained']:
                    self.assertEqual(actual[expected['name']].get(key),expected.get(key),(slug,expected['name'],key))
            schema=lambda es:[{k:v for k,v in e.items() if k!='line'} for e in es]
            self.assertEqual(schema(old['events']),schema(new['events']))

    def test_single_full_hash_and_exact_log_after_authorization_and_write(self):
        for slug,(_,event,state,width) in logs.SPECS.items():
            source=(check.ROOT/f'contracts/storage/{slug}/src/main.nr').read_text();b=logs.function_body(source,'set')
            sequence=['self.internal.assert_authorized();','let block_number = self.context.block_number();',
                      f'let fields = {state}.serialize();','let root = poseidon2_hash(fields);',
                      'self.storage.local_roots.at(id).write(root);',f'{event}::get_event_type_id().to_field()',
                      'let log = [tag, id, block_number as Field,','aztec::oracle::avm::emit_public_log(log.as_vector());']
            positions=[b.index(s) for s in sequence];self.assertEqual(positions,sorted(positions))
            for token in ['.serialize()','poseidon2_hash(','.write(']:self.assertEqual(b.count(token),1)
            self.assertIn('DOM_SEP__EVENT_LOG_TAG',b)
            self.assertIn('comptime { aztec::protocol::hash::compute_log_tag(',b)
            self.assertEqual([int(i) for i in re.findall(r'fields\[(\d+)\]',b)],list(range(width)))
            for token in ['self.call(','self.view(','if ','::zero()','as u','count']:self.assertNotIn(token,b)

    def test_original_abi_full_width_boundary_and_basis_vectors(self):
        artifacts=json.loads((check.BASE/'artifacts.json').read_text());total=0
        for slug,(_,event,_,width) in logs.SPECS.items():
            fields=artifacts[CONTRACTS[slug]]['events'][event]
            self.assertEqual([f['name'] for f in fields],['id','block_number','state'])
            event_type={'kind':'struct','fields':fields};ts=leaves(fields[2]['type']);self.assertEqual(len(ts),width)
            maxima=[P-1 if t['kind']=='field' else ((1<<t['width'])-1 if t['kind']=='integer' else 1) for t in ts]
            vectors=[[0]*width,maxima]
            for i,t in enumerate(ts):
                for bit in range(254 if t['kind']=='field' else t.get('width',1)):
                    value=1<<bit
                    if value<=maxima[i]:v=[0]*width;v[i]=value;vectors.append(v)
            for state in vectors:
                tag,identity,block=P-2,P-1,(1<<32)-1
                original=[tag]+flatten(event_type,iter([identity,block]+state))
                candidate=[tag,identity,block]+[state[i] for i in range(width)]
                self.assertEqual(original,candidate);total+=1
        self.assertEqual(total,10240)

    def test_tampered_transform_or_original_input_fails_closed(self):
        for slug in logs.SPECS:
            original=logs.original_setter_body(slug);expected=logs.rewrite_setter(slug,original)
            self.assertEqual(check.norm(logs.restore_setter(slug,expected)),check.norm(original))
            for before,after in [('assert_authorized()','assert_admin()'),('write(root)','write(0)'),
                                 ('fields[0]','fields[1]'),('[tag, id, block_number','[id, tag, block_number'),
                                 ('DOM_SEP__EVENT_LOG_TAG','0')]:
                with self.assertRaises(AssertionError):logs.restore_setter(slug,expected.replace(before,after))
            with self.assertRaises(AssertionError):logs.rewrite_setter(slug,original+'\nassert(id != 0);')

    def test_original_batch_order_and_empty_authorization_are_exact(self):
        for slug,methods in [('artifact',['set_spaceships_max5']),
                             ('artifact_location',['set_arrival_locations_max20','set_spaceship_locations_max5'])]:
            path=Path('contracts/storage')/slug/'src/main.nr'
            old=(check.BASE/'sources'/path).read_text();new=(check.ROOT/path).read_text()
            for name in methods:
                expected=logs.function_body(old,name).replace('state_roots','local_roots');actual=logs.function_body(new,name)
                self.assertEqual(check.norm(actual),check.norm(expected))
                self.assertLess(actual.index('assert_authorized'),actual.index('count <='))
                self.assertLess(actual.index('local_roots.at('),actual.index('self.emit('))

    def test_minimal_source_regeneration_idempotent_and_matches_output(self):
        with tempfile.TemporaryDirectory(prefix='df-typed-log-source-check-') as tmp:
            root=Path(tmp)
            for slug in logs.SPECS:
                path=Path('contracts/storage')/slug/'src/main.nr';(root/path.parent).mkdir(parents=True)
                manifest=path.parents[1]/'Nargo.toml';shutil.copy2(check.ROOT/manifest,root/manifest)
                generate_facades.generate(slug,generate_facades.KINDS[slug],root)
                first=(root/path).read_bytes();self.assertEqual(first,(check.ROOT/path).read_bytes())
                generate_facades.generate(slug,generate_facades.KINDS[slug],root)
                self.assertEqual(first,(root/path).read_bytes())

if __name__=='__main__':unittest.main()
