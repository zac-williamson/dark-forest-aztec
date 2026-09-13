"""Maintain the selected Core: exact V7 private/compact paths and V8 full public bodies.

Rendering is deterministic from two SHA-authenticated native-build source inputs.
Only public wrappers share context and parse the authenticated prepared packet.
"""
from pathlib import Path
import hashlib, json, re
HERE=Path(__file__).resolve().parent
REF=HERE/'snapshots/selected-core'
CORE='contracts/system/core/src/main.nr'
ACTIONS={'initialize_player':(263,267),'refresh_planet':(242,245),'upgrade_planet':(248,251),'withdraw_silver':(254,258)}
PRIVATE=['initialize_player','refresh_planet','reveal_location','upgrade_planet','withdraw_silver']
COMPACT=['initialize_player_new_public_prepared','refresh_planet_empty_public_prepared']
PINS={'v7-core.nr':'9534c1bd5cc6db05f624752c8650d00bb40402d02028f25cec91be6afb748c19','v8-core.nr':'71f198d34a67d8f976b94fed15c242d06b4c3285fc7d865a4eacebb113a5ac2f'}
sha=lambda b:hashlib.sha256(b).hexdigest()
def reference(name):
 raw=(REF/name).read_bytes();assert sha(raw)==PINS[name],(name,'Unauthenticated reference');return raw.decode()
def width(typ):
 t=re.sub(r'\s+','',typ)
 if t in ['Field','u8','u32','u64','u128','bool','AztecAddress']:return 1
 if t in {'Planet':32,'PlanetArtifacts':22,'PlanetEvents':22,'ArtifactLocation':3,'Player':8}:return {'Planet':32,'PlanetArtifacts':22,'PlanetEvents':22,'ArtifactLocation':3,'Player':8}[t]
 match=re.fullmatch(r'\[([^;]+);(\d+)\]',t)
 assert match,('Unsupported original parameter type',typ)
 return width(match[1])*int(match[2])
def complete_transform(v7,v8):
 before=p.functions(v7);publics=p.functions(v8);edits=[];helpers=[];layouts={}
 for action,(prefix,total) in ACTIONS.items():
  name=action+'_public';prepared=name+'_prepared';old=before[name];entry=before[prepared];pub=publics[name]
  assert p.digest(old['header'])==p.digest(pub['header'])
  assert '#[only_self]' in old['header'] and '#[only_self]' in entry['header']
  assert f'FieldBuffer<{total}>' in entry['header']
  params=pub['params'];names=[x.split(':',1)[0].strip() for x in params]
  helper='_'+name+'_local';call=helper+'(self.context, '+', '.join(names)+');'
  typed='\n        '+call+'\n    '
  lines=['\n        let words = prepared_payload.words;'];offset=0;layout=[]
  for param in params:
   arg,typ=[x.strip() for x in param.split(':',1)];w=width(typ)
   literal='['+', '.join(f'words[{i}]' for i in range(offset,offset+w))+']'
   # Deserialize<Field-array> is the identity. Retain every exact source word.
   expr=literal if re.fullmatch(r'\[Field;\d+\]',re.sub(r'\s+','',typ)) else f'Deserialize::deserialize({literal})'
   lines.append(f'        let {arg}: {typ} = {expr};')
   layout.append({'name':arg,'type':typ,'offset':offset,'width':w,'expression':expr});offset+=w
  assert offset==prefix,(action,offset,prefix)
  lines+=['        '+call,'    '];decoded='\n'.join(lines)
  edits += [(old['body_start']+1,old['body_end'],typed),(entry['body_start']+1,entry['body_end'],decoded)]
  helpers.append('\n\n    // The same public context preserves the actual caller and storage authority.\n    #[inline_never]\n    #[contract_library_method]\n    unconstrained fn '+helper+'(\n        context: aztec::context::PublicContext,\n'+''.join('        '+param+',\n' for param in params)+'    ) {\n        let mut self = __aztec_nr_internals__create_public_self_from_context(context);'+pub['body']+'}\n')
  layouts[action]={'originalTypedWords':prefix,'preparedWords':total,'ignoredPreparedRootOffsets':list(range(prefix,total)),'arguments':layout,'bodySource':'exact frozen V8 '+name,'bodySha256':sha(pub['body'].encode()),'helper':helper}
 # Reveal has no prepared envelope in V7. Keep its direct exact V8 implementation.
 old=before['reveal_location_public'];pub=publics['reveal_location_public'];assert p.digest(old['header'])==p.digest(pub['header'])
 edits.append((old['body_start']+1,old['body_end'],pub['body']))
 source=v7
 for start,end,replacement in sorted(edits,reverse=True):source=source[:start]+replacement+source[end:]
 end=source.rfind('}');source=source[:end]+''.join(helpers)+source[end:]
 after=p.functions(source)
 assert set(after)==set(before)|{r['helper'] for r in layouts.values()}
 changed={a+'_public'+suffix for a in ACTIONS for suffix in ('','_prepared')}|{'reveal_location_public'}
 for name in before:
  assert before[name]['header']==after[name]['header'],name
  if name not in changed:assert before[name]['full']==after[name]['full'],name
 for action,row in layouts.items():
  actual=after[row['helper']]['body'];prefix='\n        let mut self = __aztec_nr_internals__create_public_self_from_context(context);'
  assert actual==prefix+publics[action+'_public']['body']
 return source,layouts
def helper():
 return '''

// Public-only parser helper. Share the five Field20 reads within each prepared
// Reader width without changing the pinned Field20 read/advance semantics.
#[inline_never]
unconstrained fn read_prepared_core_field20<let N: u32>(
    reader: &mut ::aztec::protocol::utils::reader::Reader<N>,
) -> [Field; 20] {
    let result = [
'''+''.join(f'        reader.peek_offset({i}),\n' for i in range(20))+'''    ];
    reader.advance_offset(20);
    result
}
'''

def stream_transform(source,layout,p):
 f=p.functions(source);edits=[];expressions={}
 for action,row in layout.items():
  fn=f[action+'_public_prepared'];lines=['\n        let mut reader = aztec::protocol::utils::reader::Reader::new(prepared_payload.words);'];exprs=[]
  assert f"FieldBuffer<{row['preparedWords']}>" in fn['header']
  for arg in row['arguments']:
   typ=arg['type'];expr='crate::read_prepared_core_field20(&mut reader)' if re.sub(r'\s+','',typ)=='[Field;20]' else 'Deserialize::stream_deserialize(&mut reader)'
   lines.append(f"        let {arg['name']}: {typ} = {expr};")
   exprs.append({'name':arg['name'],'expression':expr})
  # All consumed widths are authenticated against the unmodified V7 private
  # serializer. Only its appended prepared roots are left; no original tail is skipped.
  extra=row['preparedWords']-row['originalTypedWords'];assert extra in (3,4)
  lines.extend([f'        reader.advance_offset({extra});','        reader.finish();',f"        {row['helper']}(self.context, "+', '.join(x['name'] for x in row['arguments'])+');','    '])
  edits.append((fn['body_start']+1,fn['body_end'],'\n'.join(lines)));expressions[action]=exprs
 result=source
 for start,end,value in sorted(edits,reverse=True):result=result[:start]+value+result[end:]
 return result+helper(),expressions

def render(parser):
 global p
 p=parser
 complete,layouts=complete_transform(reference('v7-core.nr'),reference('v8-core.nr'))
 result,expressions=stream_transform(complete,layouts,p)
 assert sha(result.encode())=='c30f93ca7a3bcc02aa884846f42f7bea586dcad45987054a7b4b2bacb578fef4'
 return result,layouts

def validate(source,parser):
 expected,layouts=render(parser)
 assert source==expected,'Selected Core does not reproduce its authenticated public transformation'
 before=parser.functions(reference('v7-core.nr'));current=parser.functions(source)
 for name in PRIVATE+COMPACT:assert current[name]['full']==before[name]['full'],name
 return layouts

def expanded_definition(source,name,parser,original_provider):
 layouts=validate(source,parser)
 current=parser.functions(source)
 if name.removesuffix('_public') not in layouts:return None
 row=layouts[name.removesuffix('_public')]
 original=dict(current[name]);v8=parser.functions(reference('v8-core.nr'))[name]
 assert current[row['helper']]['body']=='\n        let mut self = __aztec_nr_internals__create_public_self_from_context(context);'+v8['body']
 original['body']=v8['body'];original['full']=original['header']+'{'+original['body']+'}'
 return original_provider.restore_original(source,original,parser)

def metadata(parser):
 _,layouts=render(parser)
 return {'scope':'V7 cached Core private definitions and compact paths; exact V8 full typed public bodies shared in process. Proof latency remains unmeasured.',
  'privateOrigin':'V7','privateMethods':PRIVATE,'compactExactV7':COMPACT,'fullPublicLayouts':layouts,'sourceSHA256':'c30f93ca7a3bcc02aa884846f42f7bea586dcad45987054a7b4b2bacb578fef4'}
