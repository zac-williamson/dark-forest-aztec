import copy
import importlib.util
from pathlib import Path
import unittest

spec=importlib.util.spec_from_file_location('compat',Path(__file__).with_name('check.py'))
compat=importlib.util.module_from_spec(spec);spec.loader.exec_module(compat)
BASE={
 'contracts/storage/example/src/main.nr': '''
 #[aztec] pub contract Example {
 #[storage] struct Storage<Context> { root: PublicMutable<Field, Context>, }
 #[event] struct Changed { id: Field, state: State, }
 #[external("public")] #[initializer]
 fn constructor(admin: AztecAddress) { assert(!admin.is_zero(), "keep // literal"); }
 #[external("public")] #[only_self]
 fn commit(id: Field, state: State) { self.storage.root.write(id); }
 #[external("private")]
 fn act(states: [State; 20]) { self.enqueue_self.commit(0, states[0]); }
 #[external("utility")]
 unconstrained fn read() -> Field { self.storage.root.read() }
 }''',
 'contracts/types/src/storage.nr':'pub struct State { amount: u128, owner: AztecAddress, tail: [Field; 5], }'
}

def result(modify):
 after=copy.deepcopy(BASE);modify(after)
 return compat.compare(compat.inventory(BASE),compat.inventory(after))

class CompatibilityRegressionTests(unittest.TestCase):
 def test_comments_do_not_change_surface_or_behavior(self):
  r=result(lambda x:x.update({next(iter(x)):x[next(iter(x))].replace('self.storage.root.write(id);','/* { nested /* comment */ } */ self.storage.root.write(id);')}))
  self.assertTrue(r['compatible']);self.assertFalse(r['behaviorChangesRequiringReview'])
 def test_removed_method_is_breaking(self):
  r=result(lambda x:x.update({next(iter(x)):x[next(iter(x))].replace('fn read()', 'fn replacement()')}));self.assertFalse(r['compatible'])
 def test_parameter_name_is_preserved_for_named_sdk_arguments(self):
  r=result(lambda x:x.update({next(iter(x)):x[next(iter(x))].replace('fn commit(id:', 'fn commit(key:')}));self.assertFalse(r['compatible'])
 def test_only_self_removal_is_detected(self):
  r=result(lambda x:x.update({next(iter(x)):x[next(iter(x))].replace('#[only_self]','')}));self.assertFalse(r['compatible'])
 def test_nested_integer_width_is_breaking(self):
  r=result(lambda x:x.update({'contracts/types/src/storage.nr':x['contracts/types/src/storage.nr'].replace('u128','u64')}));self.assertFalse(r['compatible'])
 def test_array_tail_width_is_breaking(self):
  r=result(lambda x:x.update({'contracts/types/src/storage.nr':x['contracts/types/src/storage.nr'].replace('[Field; 5]','[Field; 4]')}));self.assertFalse(r['compatible'])
 def test_event_field_order_is_breaking(self):
  r=result(lambda x:x.update({next(iter(x)):x[next(iter(x))].replace('id: Field, state: State,','state: State, id: Field,')}));self.assertFalse(r['compatible'])
 def test_constructor_auth_change_requires_behavior_review(self):
  r=result(lambda x:x.update({next(iter(x)):x[next(iter(x))].replace('assert(!admin.is_zero(), "keep // literal");','')}))
  self.assertTrue(r['compatible']);self.assertEqual(r['behaviorChangesRequiringReview'][0]['function'],'constructor')
 def test_storage_layout_changes_are_explicit_not_assumed_abi_breaks(self):
  r=result(lambda x:x.update({next(iter(x)):x[next(iter(x))].replace('root: PublicMutable<Field, Context>,','backend: PublicMutable<AztecAddress, Context>,')}))
  self.assertTrue(r['compatible']);self.assertFalse(r['storageLayoutChanges'][0]['appendOnly'])
 def test_private_to_public_writer_edge_is_preserved(self):
  inv=compat.inventory(BASE);f=next(f for f in inv['contracts'][0]['functions'] if f['name']=='act')
  self.assertEqual(f['selfCalls'],[{'mode':'enqueue_self','method':'commit'}])
 def test_artifact_source_provenance_rejects_stale_build(self):
  inv=compat.inventory(BASE);a={'Example':{'functions':{},'events':{},'owningSource':[{'sha256':'old'}],'file':'Example.json'}}
  r=compat.compare_artifacts(a,a,inv);self.assertEqual(len(r['staleArtifacts']),1)
 def test_direct_contract_call_is_resolved(self):
  files=copy.deepcopy(BASE);files[next(iter(files))]=files[next(iter(files))].replace('self.storage.root.write(id);','self.call(Other::at(self.context.this_address()).set(id));')
  inv=compat.inventory(files);f=next(f for f in inv['contracts'][0]['functions'] if f['name']=='commit')
  self.assertEqual((f['externalCalls'][0]['targetContract'],f['externalCalls'][0]['method']),('Other','set'))

if __name__=='__main__':unittest.main()
