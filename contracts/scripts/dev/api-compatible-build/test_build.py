from pathlib import Path
import base64,gzip,hashlib,json,os,tempfile,unittest
import build

class BuildSafety(unittest.TestCase):
 def test_class_identity_does_not_claim_debug_metadata_byte_identity(self):
  a={'file':'Core.json','classId':'0x123','sha256':'initial'};b={**a,'sha256':'final'}
  r=build.identity_evidence(a,b);self.assertTrue(r['classIdStable']);self.assertFalse(r['artifactBytesIdentical'])
  with self.assertRaisesRegex(ValueError,'Class changed'):build.identity_evidence(a,{**b,'classId':'0x456'})
 def fixture(self):
  raw=b'authenticated private circuit\x00\xff';key=b'existing full cached key';enc=lambda b:base64.b64encode(b).decode()
  fn={'name':'original_method','is_unconstrained':False,'bytecode':enc(gzip.compress(raw)),'verification_key':enc(key),'custom_attributes':['abi_private']}
  artifact={'noir_version':'pinned','functions':[fn]};known={build.sha(raw):{'keySha256':build.sha(key)}}
  return artifact,json.loads(json.dumps(artifact)),known
 def test_exact_private_and_cached_key_accepted(self):
  a,b,k=self.fixture();self.assertEqual(len(build.check_private(a,b,k,True)),1)
 def test_raw_prefixed_name_matches_native_reference(self):
  a,b,k=self.fixture();a['functions'][0]['name']=build.PRIVATE_METHOD_PREFIX+'original_method'
  row=build.check_private(a,b,k,False)[0];self.assertEqual(row['method'],'original_method')
 def test_reference_prefix_is_normalized_symmetrically(self):
  a,b,k=self.fixture();b['functions'][0]['name']=build.PRIVATE_METHOD_PREFIX+'original_method'
  self.assertEqual(build.check_private(a,b,k,True)[0]['method'],'original_method')
 def test_normalized_duplicate_rejected_in_both_inventories(self):
  for side in ['current','reference']:
   with self.subTest(side=side):
    a,b,k=self.fixture();target=a if side=='current' else b
    twin={**target['functions'][0],'name':build.PRIVATE_METHOD_PREFIX+'original_method'};target['functions'].append(twin)
    with self.assertRaisesRegex(ValueError,'Duplicate normalized'):build.check_private(a,b,k,False)
 def test_changed_prefixed_method_name_still_rejected(self):
  a,b,k=self.fixture();a['functions'][0]['name']=build.PRIVATE_METHOD_PREFIX+'different_method'
  with self.assertRaisesRegex(ValueError,'inventory changed'):build.check_private(a,b,k,False)
 def test_unknown_or_repeated_prefix_is_not_fuzzily_stripped(self):
  for prefix in ['__other_internals__',build.PRIVATE_METHOD_PREFIX*2]:
   with self.subTest(prefix=prefix):
    a,b,k=self.fixture();a['functions'][0]['name']=prefix+'original_method'
    with self.assertRaisesRegex(ValueError,'inventory changed'):build.check_private(a,b,k,False)
 def test_prefixed_known_changed_bytecode_still_rejected(self):
  a,b,k=self.fixture();a['functions'][0]['name']=build.PRIVATE_METHOD_PREFIX+'original_method'
  other=b'other known prefixed circuit';a['functions'][0]['bytecode']=base64.b64encode(gzip.compress(other)).decode();k[build.sha(other)]={'keySha256':'irrelevant'}
  with self.assertRaisesRegex(ValueError,'Unexpected private identity'):build.check_private(a,b,k,False)
 def test_constrained_and_private_attribute_must_agree(self):
  for side in ['current','reference']:
   for change in [{'is_unconstrained':True},{'custom_attributes':['abi_public']}]:
    with self.subTest(side=side,change=change):
     a,b,k=self.fixture();target=a if side=='current' else b;target['functions'][0].update(change)
     with self.assertRaisesRegex(ValueError,'Constrained/abi_private disagreement'):build.check_private(a,b,k,False)
 def test_private_attribute_cannot_also_be_public_or_utility(self):
  for attr in ['abi_public','abi_utility']:
   a,b,k=self.fixture();a['functions'][0]['custom_attributes'].append(attr)
   with self.assertRaisesRegex(ValueError,'Conflicting private ABI'):build.check_private(a,b,k,False)
 def test_actual_stopped_admin_raw_matches_pinned_native_reference(self):
  pins=json.loads((build.HERE/'reference/admin-private-inventory-fixture.json').read_text())
  resolve=lambda row:{'path':str(build.HERE/'reference'/row['file']),'sha256':row['sha256']}
  raw=json.loads(build.pinned_file(resolve(pins['raw'])));reference=json.loads(build.pinned_file(resolve(pins['reference'])))
  self.assertEqual(pins['sourceArtifacts']['reference']['sha256'],'d7cee690534fffbb03bd33c8fa29dc7733ec69a3d99ba27e7a9fddf50ba9e894')
  known=json.loads((build.HERE/'reference/known-private-keys.json').read_text())['keys']
  result=build.check_private(raw,reference,known,False)
  self.assertEqual([row['method'] for row in result],['safe_set_owner'])
  self.assertEqual(result[0]['decompressedBytecodeSHA256'],'d6190a76e219729639a1cd1847c818908a90b2fcf8bc4682a7e23907183382b4')
  self.assertEqual(build.check_private(reference,reference,known,True),result)
 def test_unknown_circuit_rejected(self):
  a,b,k=self.fixture()
  with self.assertRaisesRegex(ValueError,'Unknown private'):build.check_private(a,b,{},False)
 def test_different_known_private_circuit_still_rejected(self):
  a,b,k=self.fixture();a['functions'][0]['bytecode']=base64.b64encode(gzip.compress(b'other known circuit')).decode();k[build.sha(b'other known circuit')]={'keySha256':'irrelevant'}
  with self.assertRaisesRegex(ValueError,'Unexpected private identity'):build.check_private(a,b,k,False)
 def test_missing_private_method_rejected(self):
  a,b,k=self.fixture();a['functions']=[]
  with self.assertRaisesRegex(ValueError,'inventory'):build.check_private(a,b,k,False)
 def test_changed_cached_key_rejected(self):
  a,b,k=self.fixture();a['functions'][0]['verification_key']=base64.b64encode(b'wrong key').decode()
  with self.assertRaisesRegex(ValueError,'Cached native key'):build.check_private(a,b,k,True)
 def test_wrong_compiler_rejected(self):
  a,b,k=self.fixture();a['noir_version']='other'
  with self.assertRaisesRegex(ValueError,'compiler version'):build.check_private(a,b,k,False)
 def test_public_only_classes_need_no_private_reference(self):
  self.assertEqual(build.check_private({'functions':[{'name':'public_dispatch','is_unconstrained':True,'custom_attributes':['abi_public']}]},None,{},True),[])
 def test_generated_binding_order_matches_actual_v8(self):
  p=json.loads((build.HERE/'reference/binding-fixture.json').read_text())
  rows={r['file']:r for r in p['classes']};out=build.codegen(rows)
  self.assertEqual(set(out),set(build.BINDINGS));self.assertEqual(len(out),5)
  for n,s in out.items():self.assertEqual(s,p['files'][n],n)
 def test_known_whitelist_guard_is_exact_and_never_forces_new_keys(self):
  s=(build.HERE/'cached-only.py').read_bytes();self.assertEqual(build.sha(s),build.GUARD_SHA)
  self.assertIn("len(args) == 3 and args[:2] == ['aztec_process', '-i']",s.decode())
  self.assertIn("key.is_file()",s.decode());self.assertIn('os.execv',s.decode())
 def test_all20_classes_and19_identity_targets(self):
  self.assertEqual(len(build.ENTRIES),20);self.assertEqual(len(set(map(build.filename,build.ENTRIES))),20)
  self.assertEqual(len(build.ORIGINAL)+len(build.WORKERS),19);self.assertEqual(build.ENTRIES[-1],build.BACKEND)
 def test_unlisted_source_file_rejected(self):
  with tempfile.TemporaryDirectory(prefix='df-tool-unit-') as d:
   r=Path(d);(r/'contracts').mkdir();(r/'vendor').mkdir();(r/'contracts/new.nr').write_text('unexpected')
   with self.assertRaisesRegex(ValueError,'Unlisted compiler'):build.sources(r,{})
 def test_pnpm_symlinks_are_outside_compiler_closure(self):
  with tempfile.TemporaryDirectory(prefix='df-tool-unit-') as d:
   r=Path(d);modules=r/'contracts/node_modules';modules.mkdir(parents=True)
   (modules/'example').symlink_to(r/'external-package',target_is_directory=True)
   self.assertEqual(build.sources(r,{}),{})
   (r/'contracts/unsafe').symlink_to(r/'external-package',target_is_directory=True)
   with self.assertRaisesRegex(ValueError,'Symlink in source'):build.sources(r,{})
 def test_input_drift_and_only_generated_binding_exception(self):
  with tempfile.TemporaryDirectory(prefix='df-tool-unit-') as d:
   r=Path(d);n=build.BINDINGS[0];(r/n).parent.mkdir(parents=True);(r/n).write_text('new binding');manifest={n:build.sha(b'old')}
   with self.assertRaisesRegex(ValueError,'Frozen input'):build.sources(r,manifest)
   self.assertEqual(build.sources(r,manifest,True)[n],build.sha(b'new binding'))
 def test_multiline_move_and_all_current_manual_selectors(self):
  r=Path(os.environ['DF_BUILD_TEST_ROOT']) if 'DF_BUILD_TEST_ROOT' in os.environ else build.HERE.parents[3];manifest=dict.fromkeys(json.loads((build.HERE/'reference/production-paths.json').read_text()));rows=build.literal_routes(r,manifest)
  self.assertEqual(len(rows),27);move=[row for row in rows if row['source'].endswith('/move/src/main.nr')]
  self.assertEqual([row['method'] for row in move],['try_settle_move_move','try_settle_move_move_empty'])
  self.assertTrue(all(row['target']==build.filename(build.BACKEND) for row in move))
 def test_v7_core_worker_routes_are_classified_without_v8_inactive_assumption(self):
  with tempfile.TemporaryDirectory(prefix='df-tool-unit-') as d:
   r=Path(d);n='contracts/system/core/src/main.nr';(r/n).parent.mkdir(parents=True)
   (r/n).write_text('from_signature("try_refresh_planet_public_prepared(([Field;257]))")')
   self.assertEqual(build.literal_routes(r,{n:'unused'})[0]['target'],build.filename(build.WORKERS[0]))
 def test_unknown_or_dynamic_selector_fails_closed(self):
  with tempfile.TemporaryDirectory(prefix='df-tool-unit-') as d:
   r=Path(d);n='contracts/system/core/src/main.nr';(r/n).parent.mkdir(parents=True)
   for body in ['from_signature("unreviewed_route(Field)")','from_signature(variable)']:
    (r/n).write_text(body)
    with self.assertRaises(ValueError):build.literal_routes(r,{n:'unused'})
 def test_349_source_closure_has_one_sdk_origin(self):
  r=Path(os.environ['DF_BUILD_TEST_ROOT']) if 'DF_BUILD_TEST_ROOT' in os.environ else build.HERE.parents[3];p=dict.fromkeys(json.loads((build.HERE/'reference/production-paths.json').read_text()));build.one_sdk_origin(r,p)
 def test_original_source_and_compiled_reference_metadata_authenticated(self):
  r=build.HERE/'reference';manifest=json.loads((r/'original-manifest.json').read_text())
  for name,reference in [('inventory.json','original-inventory.json'),('artifacts.json','original-artifacts.json')]:self.assertEqual(build.sha((r/reference).read_bytes()),manifest['metadataSha256'][name])

if __name__=='__main__':unittest.main(verbosity=2)
