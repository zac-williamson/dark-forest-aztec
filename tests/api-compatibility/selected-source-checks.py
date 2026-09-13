"""Read-only semantic validation of the selected source and its authenticated origins."""
from pathlib import Path
import hashlib, importlib.util, json, re, subprocess, tempfile, tomllib, unittest
import artifact_touch
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
REF=HERE/'snapshots/selected-source'
sha=lambda b:hashlib.sha256(b).hexdigest()
def module(name,file):
 spec=importlib.util.spec_from_file_location(name,file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
p=module('selected_parser',HERE/'prepare-system-writes.py')
core=module('selected_core_provider',HERE/'optimize-core-selected.py')
api=module('selected_api',HERE/'check.py')
fb=module('selected_field_buffer',HERE/'generate-field-buffer.py')
P=json.loads((REF/'manifest.json').read_text())
CORE='contracts/system/core/src/main.nr'
BINDINGS=json.loads((HERE/'generated/selected-bindings.json').read_text())

def production_files(root=ROOT):
 return {n:sha((root/n).read_bytes()) for n in P['sourceFiles'] if n not in P['toolingFiles']}

def baseline_text(name):return (REF/'v8'/name).read_text()

def restore_dependency(name,source):
 """Undo only the exact additive marker or reviewed SDK manifest origin."""
 if name in P['markerOnlyFiles']:
  marker='\n'+(REF/'marker-impl.txt').read_text();assert source.count(marker)==1;source=source.replace(marker,'',1)
 if name in P['nargoRewrites']:
  old=baseline_text(name);a=tomllib.loads(source);b=tomllib.loads(old)
  a['dependencies'].pop('aztec');b['dependencies'].pop('aztec')
  if name=='contracts/system/core/Nargo.toml':b['dependencies']['libs']={'path':'../../libs'}
  assert a==b,(name,'Unexpected dependency change')
  # Preserve exact historical formatting rather than guessing it from TOML.
  source=old
 return source

class SelectedSourceTests(unittest.TestCase):
 def test_347_selected_inputs_and_five_authenticated_native_binding_references(self):
  self.assertEqual(len(P['sourceFiles']),349)
  self.assertEqual(len(production_files()),347)
  self.assertEqual(production_files(),{n:h for n,h in P['sourceFiles'].items() if n not in P['toolingFiles']})
  self.assertEqual(len(BINDINGS['files']),5)
  for n,h in BINDINGS['files'].items():self.assertEqual(sha((ROOT/n).read_bytes()),h,n)
  self.assertEqual(sha((REF/'admitted-build.json').read_bytes()),P['admittedBuildSHA256'])
  admitted=json.loads((REF/'admitted-build.json').read_text())
  self.assertEqual(BINDINGS['classIds'],admitted['classIds'])
  self.assertEqual(BINDINGS['files'],{n:admitted['sourceFiles'][n] for n in BINDINGS['files']})
  if P['sourceSelection']['status']=='provisional':
   provenance=HERE/'snapshots/artifact-touch/order-provenance.json'
   self.assertEqual(sha(provenance.read_bytes()),P['sourceSelection']['orderProvenanceSHA256'])
   self.assertEqual(P['sourceFiles'],json.loads(provenance.read_text())['sourceFiles'])
  else:
   self.assertEqual(P['sourceSelection']['status'],'admitted')
   self.assertEqual(P['sourceFiles'],admitted['sourceFiles'])

 def test_reviewed_touch_changes_only_original_update_dispatch_and_additive_facades(self):
  vault=(ROOT/artifact_touch.VAULT).read_text()
  self.assertTrue(artifact_touch.validate_vault(vault,p))
  self.assertEqual(artifact_touch.restore_vault(vault,p),baseline_text(artifact_touch.VAULT))
  for slug in artifact_touch.SPECS:
   self.assertTrue(artifact_touch.validate_facade((ROOT/f'contracts/storage/{slug}/src/main.nr').read_text(),slug,p))


 def test_source_origins_are_authenticated(self):
  self.assertEqual(len(P['v8SourceFiles']),110)
  for n,h in P['v8SourceFiles'].items():self.assertEqual(sha((REF/'v8'/n).read_bytes()),h,n)
  core.reference('v7-core.nr');core.reference('v8-core.nr')

 def test_core_is_reproducibly_generated_from_two_exact_inputs(self):
  actual=(ROOT/CORE).read_text();expected,layouts=core.render(p)
  self.assertEqual(actual,expected);self.assertEqual(len(layouts),4)
  self.assertEqual(core.validate(actual,p),layouts)

 def test_five_private_and_two_compact_definitions_remain_exact_v7(self):
  old=p.functions(core.reference('v7-core.nr'));new=p.functions((ROOT/CORE).read_text())
  for name in core.PRIVATE+core.COMPACT:self.assertEqual(new[name]['full'],old[name]['full'],name)
  self.assertEqual(len([n for n,f in old.items() if '#[external("private")]' in f['header']]),5)

 def test_other_nine_private_definitions_remain_exact_v8(self):
  count=0
  for n in P['v8SourceFiles']:
   if not n.endswith('/src/main.nr') or n==CORE:continue
   before=p.functions(baseline_text(n));after=p.functions((ROOT/n).read_text())
   for name,fn in before.items():
    if '#[external("private")]' in fn['header']:self.assertEqual(after[name]['full'],fn['full'],(n,name));count+=1
  self.assertEqual(count,9)

 def test_helper_context_full_typed_inputs_and_call_order_are_exact_v8(self):
  current=p.functions((ROOT/CORE).read_text());old=p.functions(core.reference('v8-core.nr'));_,layouts=core.render(p)
  for action,row in layouts.items():
   fn=current[row['helper']];original=old[action+'_public']
   self.assertEqual(fn['body'],'\n        let mut self = __aztec_nr_internals__create_public_self_from_context(context);'+original['body'])
   self.assertEqual(fn['params'],['context: aztec::context::PublicContext']+original['params'])
   for suffix in ['','_prepared']:
    wrapper=current[action+'_public'+suffix];self.assertIn('#[only_self]',wrapper['header']);self.assertIn(row['helper']+'(self.context,',wrapper['body']);self.assertNotIn('self.call(',wrapper['body'])
   self.assertEqual(next(x['width'] for x in row['arguments'] if x['name']=='new_arrival_artifact_locations'),60)

 def test_stream_decode_preserves_cursor_tails_and_typed_deserializers(self):
  current=p.functions((ROOT/CORE).read_text());_,layouts=core.render(p)
  for action,row in layouts.items():
   body=current[action+'_public_prepared']['body'];declarations=[]
   for arg in row['arguments']:
    expr='crate::read_prepared_core_field20(&mut reader)' if re.sub(r'\s+','',arg['type'])=='[Field;20]' else 'Deserialize::stream_deserialize(&mut reader)'
    declarations.append(f"let {arg['name']}: {arg['type']} = {expr};")
   actual=[l.strip() for l in body.splitlines() if l.strip().startswith('let ') and not l.strip().startswith('let mut reader =')]
   self.assertEqual(actual,declarations);self.assertEqual(sum(x['width'] for x in row['arguments']),row['originalTypedWords'])
   self.assertIn(f"reader.advance_offset({row['preparedWords']-row['originalTypedWords']});\n        reader.finish();",body)
  helper=core.helper();self.assertEqual((ROOT/CORE).read_text().count(helper),1)
  self.assertEqual([int(n) for n in re.findall(r'peek_offset\((\d+)\)',helper)],list(range(20)))

 def test_medium_changes_only_two_helpers_and_preserves_bounded_literal_packet(self):
  medium=json.loads((REF/'medium-provenance.json').read_text())
  ref=(ROOT/medium['referenceMediumBranch']['path']).read_text();body=p.functions(ref)['_commit_plan_for_system']['body']
  begin=body.index('        } else if plan.length <= 172 {\n');end=body.index('        } else {\n',begin);branch=body[begin:end]
  self.assertEqual(sha(branch.encode()),medium['referenceMediumBranch']['branchSha256'])
  for n in P['mediumFiles']:
   actual=(ROOT/n).read_text();self.assertEqual(actual.count(branch),1);self.assertEqual(actual.replace(branch,'',1),baseline_text(n))
   self.assertIn('plan.words[171]',branch);self.assertNotIn('plan.words[172]',branch)
  for length,expected in [(0,141),(128,141),(129,185),(172,185),(173,397),(384,397)]:self.assertEqual(141 if length<=128 else 185 if length<=172 else 397,expected)

 def test_both_fieldbuffer_generators_keep_exact_codec_bodies_and_marker_only(self):
  for prefix,count in [('libs',27),('prospect_original_libs',26)]:
   n=f'contracts/{prefix}/src/field_buffer.nr';source=(ROOT/n).read_text();manifest=json.loads((HERE/f'generated/field-buffer-{prefix}.json').read_text())
   self.assertEqual(len(manifest['widths']),count);self.assertEqual(fb.render(set(manifest['widths']),set(manifest['unrolled'])),source)
   self.assertEqual(restore_dependency(n,source),baseline_text(n))

 def test_all26_local_sdk_origins_are_coherent(self):
  origins=[]
  for n in P['sourceFiles']:
   if not n.endswith('Nargo.toml') or n.startswith('vendor/'):continue
   file=ROOT/n
   for key,dep in tomllib.loads(file.read_text()).get('dependencies',{}).items():
    if key=='aztec':self.assertEqual(set(dep),{'path'});origins.append((file.parent/dep['path']).resolve())
    if 'path' in dep:self.assertTrue((file.parent/dep['path']/'Nargo.toml').is_file(),(n,key))
  self.assertEqual(len(origins),26);self.assertEqual(set(origins),{(ROOT/'vendor/aztec').resolve()})
  self.assertEqual(tomllib.loads((ROOT/'contracts/system/core/Nargo.toml').read_text())['dependencies']['libs'],{'path':'../../libs'})

 def test_sdk_changed_only_public_dispatch_and_conditions_are_disjoint(self):
  direct=json.loads((REF/'direct-provenance.json').read_text());changed=[]
  for n,h in direct['originalSdkFiles'].items():
   if sha((ROOT/'vendor/aztec'/n).read_bytes())!=h:changed.append(n)
  self.assertEqual(changed,['src/macros/dispatch.nr'])
  s=(ROOT/'vendor/aztec/src/macros/dispatch.nr').read_text();self.assertEqual(sha(s.encode()),P['combinedDispatchSHA256'])
  marker=(REF/'dispatch-marker-trait.nr').read_text();self.assertIn(marker,s)
  for token in ['parameters.len() != 1','param_type.implements(marker)','param_type.as_data_type()','fields.len() == 1','element.is_field()']:self.assertIn(token,marker)
  self.assertNotIn('.name()',marker);self.assertEqual(s.count('aztec::oracle::avm::calldata_copy(1, $params_len_quote)'),4)
  self.assertNotIn('reader.finish',s);self.assertNotIn('calldata_size',s)

 def test_only_shared_kind_annotation_changes_reader_library(self):
  n='contracts/state_backend_readonly/src/public_read.nr';actual=(ROOT/n).read_text();old=baseline_text(n)
  self.assertEqual(actual.replace('#[inline_never]\npub unconstrained fn get_namespace_kind','pub unconstrained fn get_namespace_kind',1),old)
  self.assertEqual(actual,(HERE/'templates/state_backend_readonly/public_read.nr').read_text())

 def test_original447_api_modifiers_typed_arguments_events_and_calls(self):
  baseline=json.loads((REF/'original-inventory.json').read_text())
  actual=api.inventory({n:(ROOT/n).read_text() for n in P['sourceFiles'] if n.endswith(('.nr','.toml'))})
  report=api.compare(baseline,actual)
  self.assertEqual(sum(len(s['functions']) for s in baseline['surfaces'].values()),447)
  self.assertTrue(report['compatible'],report['breakingChanges']);self.assertEqual(actual['unresolvedExternalCalls'],[])

 def test_mutations_to_private_context_tail_and_root_guard_are_rejected(self):
  source=(ROOT/CORE).read_text()
  for old,new in [('reader.advance_offset(3);','reader.advance_offset(4);'),('create_public_self_from_context(context)','create_public_self_from_context(self.context)'),('get_namespace_kind(state_backend_address, planet_storage.target_contract) == 3','get_namespace_kind(state_backend_address, planet_storage.target_contract) == 4')]:
   self.assertIn(old,source)
   with self.assertRaises(AssertionError):core.validate(source.replace(old,new,1),p)

 def test_fresh347_source_replay_from_v8_and_original_sdk(self):
  patch=REF/'selected-source.patch';self.assertEqual(sha(patch.read_bytes()),P['patchSHA256'])
  with tempfile.TemporaryDirectory(prefix='df-selected-source-replay-') as tmp:
   target=Path(tmp)
   for n in P['sourceFiles']:
    if n in P['toolingFiles']:continue
    out=target/n;out.parent.mkdir(parents=True,exist_ok=True)
    raw=(REF/'v8'/n).read_bytes() if n in P['v8SourceFiles'] else ((REF/'original-dispatch.nr').read_bytes() if n=='vendor/aztec/src/macros/dispatch.nr' else (ROOT/n).read_bytes())
    out.write_bytes(raw)
   run=subprocess.run(['git','apply',str(patch)],cwd=target,capture_output=True,text=True)
   self.assertEqual(run.returncode,0,run.stderr)
   self.assertEqual(production_files(target),production_files())
