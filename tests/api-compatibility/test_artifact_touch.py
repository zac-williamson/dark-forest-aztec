"""Portable source and mutation gates for the paired genuine-facade touch path.

These checks validate the reviewed transformation and event/state predicates.
They do not substitute for native compilation, hostile runtime or fee tests.
"""
from pathlib import Path
import hashlib,importlib.util,json,re,tempfile,unittest
import artifact_touch as touch

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
p=touch.parser()
sha=lambda b:hashlib.sha256(b).hexdigest()

def module(name,path):
 spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
api=module('touch_api',HERE/'check.py')

class ArtifactTouchTests(unittest.TestCase):
 def test_exact_original_setters_and_every_other_facade_function(self):
  for slug,typ in touch.SPECS.items():
   source=(ROOT/f'contracts/storage/{slug}/src/main.nr').read_text();old=touch.baseline(f'contracts/storage/{slug}/src/main.nr')
   self.assertTrue(touch.validate_facade(source,slug,p))
   before=p.functions(old);after=p.functions(source)
   self.assertEqual(set(after)-set(before),{'touch'})
   for name,fn in before.items():self.assertEqual(fn['full'],after[name]['full'],(slug,name))
   self.assertEqual(after['touch']['params'],[f'state: {typ}','id: Field'])
   self.assertIn('#[external("public")]',after['touch']['header'])

 def test_authorization_is_first_and_same_hash_event_are_emitted_without_write(self):
  for slug in touch.SPECS:
   current=p.functions((ROOT/f'contracts/storage/{slug}/src/main.nr').read_text())
   body=current['touch']['body'];old=current['set']['body']
   write='self.storage.local_roots.at(id).write(root);'
   check='assert(self.storage.local_roots.at(id).read() == root, "State changed after verification");'
   self.assertEqual(body,old.replace(write,check,1))
   self.assertTrue(body.lstrip().startswith('self.internal.assert_authorized();'))
   self.assertNotIn('.write(',body);self.assertNotIn('self.call(',body)
   self.assertEqual(body.count('emit_public_log('),1)
   self.assertEqual(body[body.index('let tag ='):],old[old.index('let tag ='):])

 def test_update_changes_only_two_final_dispatches(self):
  source=(ROOT/touch.VAULT).read_text();baseline=touch.baseline(touch.VAULT)
  self.assertTrue(touch.validate_vault(source,p))
  self.assertEqual(touch.restore_vault(source,p),baseline)
  a=p.functions(source)['update_artifact'];b=p.functions(baseline)['update_artifact']
  self.assertEqual(a['header'],b['header'])
  self.assertEqual(a['body'].split('// Both exact current classes')[0],b['body'].split('self.call(artifact_storage.set')[0])
  self.assertEqual(a['body'].count('self.view('),2)
  self.assertEqual(re.findall(r'self\.view\(([^\n]*)',a['body']),re.findall(r'self\.view\(([^\n]*)',b['body']))
  self.assertIn('artifact_storage.touch(artifact, id)',a['body'])
  self.assertIn('artifact_location_storage.touch(location, id)',a['body'])

 def test_both_exact_classes_distinct_addresses_and_all_or_nothing_fallback(self):
  body=p.functions((ROOT/touch.VAULT).read_text())['update_artifact']['body']
  for guard in ['ARTIFACT_TOUCH_CLASS == 0','LOCATION_TOUCH_CLASS == 0','artifact_storage.target_contract == artifact_location_storage.target_contract','artifact_class.is_some() & location_class.is_some()','artifact_class.unwrap().to_field() == ::libs::config_class::ARTIFACT_TOUCH_CLASS','location_class.unwrap().to_field() == ::libs::config_class::LOCATION_TOUCH_CLASS']:
   self.assertIn(guard,body)
  self.assertNotIn('state_backend',body);self.assertNotIn('get_namespace_kind',body)
  tail=body[body.index('        if use_touch {'):]
  self.assertEqual(tail.count('} else {'),1)
  self.assertEqual(p.digest(tail.split('} else {')[1]),p.digest(touch.ORIGINAL_SETS+'\n        }'))

 def test_current_class_flags_are_live_and_no_caller_root_is_accepted(self):
  body=p.functions((ROOT/touch.VAULT).read_text())['update_artifact']['body']
  self.assertEqual(body.count('get_contract_instance_current_class_id_avm('),2)
  self.assertNotIn('get_contract_instance_class_id',body)
  for slug in touch.SPECS:
   fn=p.functions((ROOT/f'contracts/storage/{slug}/src/main.nr').read_text())['touch']
   self.assertNotIn('root:',','.join(fn['params']))
   self.assertIn('let fields = state.serialize();\n        let root = poseidon2_hash(fields);',fn['body'])

 def test_mutated_class_guard_order_auth_event_and_fallback_fail_closed(self):
  src=(ROOT/touch.VAULT).read_text()
  changes=[('artifact_class.is_some() & location_class.is_some()','artifact_class.is_some() | location_class.is_some()'),
   ('artifact_storage.target_contract == artifact_location_storage.target_contract','false'),
   ('ARTIFACT_TOUCH_CLASS == 0','ARTIFACT_TOUCH_CLASS == 1'),
   ('artifact_storage.set(id, artifact)','artifact_storage.touch(artifact, id)'),
   ('artifact_location_storage.touch(location, id)','artifact_location_storage.touch(id, location)')]
  for a,b in changes:
   self.assertIn(a,src)
   with self.assertRaises(AssertionError):touch.restore_vault(src.replace(a,b,1),p)
  for slug in touch.SPECS:
   source=(ROOT/f'contracts/storage/{slug}/src/main.nr').read_text();fn=p.functions(source)['touch']
   for a,b in [('self.internal.assert_authorized();',''),('== root','!= root'),('block_number as Field','0'),('fields[0]','fields[1]')]:
    self.assertIn(a,fn['body']);bad=source[:fn['body_start']+1]+fn['body'].replace(a,b,1)+source[fn['body_end']:]
    with self.assertRaises(AssertionError):touch.validate_facade(bad,slug,p)

 def test_reversed_signature_keeps_original_unpack_group_below_threshold(self):
  sdk=(ROOT/'vendor/aztec/src/macros/dispatch.nr').read_text()
  threshold=int(re.search(r'global EXTRACTION_THRESHOLD: u32 = (\d+);',sdk)[1]);self.assertEqual(threshold,4)
  for slug,typ in touch.SPECS.items():
   funcs=p.functions((ROOT/f'contracts/storage/{slug}/src/main.nr').read_text())
   matching=[n for n,f in funcs.items() if '#[external("public")]' in f['header'] and f['params']==['id: Field',f'state: {typ}']]
   self.assertEqual(set(matching),{'set','verify',f'emit_{slug}_update'})
   self.assertLess(len(matching),threshold)
   self.assertEqual(funcs['touch']['params'],[f'state: {typ}','id: Field'])

 def test_apply_and_restore_are_idempotent_on_complete_production_sources(self):
  source=(ROOT/touch.VAULT).read_text()
  self.assertEqual(touch.apply_vault(source,p),source)
  self.assertEqual(touch.apply_vault(touch.restore_vault(source,p),p),source)
  for slug in touch.SPECS:
   source=(ROOT/f'contracts/storage/{slug}/src/main.nr').read_text()
   self.assertEqual(touch.apply_facade(source,slug,p),source)
   self.assertEqual(touch.apply_facade(touch.baseline(f'contracts/storage/{slug}/src/main.nr'),slug,p),source)

 def test_all_original447_api_and_zero_unresolved_calls(self):
  selected=json.loads((HERE/'snapshots/selected-source/manifest.json').read_text())
  baseline=json.loads((HERE/'snapshots/selected-source/original-inventory.json').read_text())
  actual=api.inventory({n:(ROOT/n).read_text() for n in selected['sourceFiles'] if n.endswith(('.nr','.toml'))})
  comparison=api.compare(baseline,actual)
  self.assertEqual(sum(len(v['functions']) for v in baseline['surfaces'].values()),447)
  self.assertTrue(comparison['compatible'],comparison['breakingChanges']);self.assertEqual(actual['unresolvedExternalCalls'],[])

if __name__=='__main__':unittest.main()
