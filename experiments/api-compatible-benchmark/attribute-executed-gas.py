"""Map executed public PC gas to pinned native debug metadata, excluding nested CALL gas."""
import json,sys,base64,zlib,bisect,collections,hashlib
from pathlib import Path
prefix=Path(sys.argv[1]); artifacts=Path(sys.argv[2])
summary=json.loads(Path(str(prefix)+'.gas-attribution.json').read_text())
traces={d['callId']:d for d in map(json.loads,Path(str(prefix)+'.avm-calls.jsonl').read_text().splitlines())}
roles={'backend':'game_state_backend','core_settlement_worker':'core_settlement_worker'}
output=[]
for call in summary['calls']:
 matches=list(artifacts.glob(roles.get(call['role'],call['role'])+'-*.json'))
 if len(matches)!=1:continue
 p=matches[0];a=json.loads(p.read_text());fn=next(x for x in a['functions'] if x['name']=='public_dispatch')
 bytecode=base64.b64decode(fn['bytecode']);debug=json.loads(zlib.decompress(base64.b64decode(fn['debug_symbols']),-15))['debug_infos'][0]
 locations=debug['brillig_locations']['0'];tree=debug['location_tree']['locations'];files=a['file_map'];pcs=sorted(map(int,locations))
 def label(v):
  f=files.get(str(v['file']))
  if not f:return None
  span=v['span']; funcs=f.get('function_locations',[]);idx=bisect.bisect_right([x['start'] for x in funcs],span['start'])-1
  name=funcs[idx]['name'] if idx>=0 else '<preamble>'
  return (f['path'],name,f['source'].count('\n',0,span['start'])+1,f['source'][span['start']:span['end']])
 leaf=collections.Counter();origin=collections.Counter();sites=collections.Counter();exact_sites=collections.Counter();calls=0;unmapped=0;approx=0
 for pc,count,l2,da in traces[call['callId']]['pcGas']:
  if bytecode[pc] in (57,58):calls+=l2;continue
  if pc<pcs[0]:unmapped+=l2;continue
  if str(pc) not in locations:approx+=l2
  loc=locations[str(pcs[bisect.bisect_right(pcs,pc)-1])];stack=[]
  while loc is not None:
   node=tree[loc];info=label(node['value'])
   if info:stack.append(info)
   loc=node['parent']
  if not stack:unmapped+=l2;continue
  info=stack[0];leaf[info[:2]]+=l2;sites[info]+=l2
  if str(pc) in locations:exact_sites[info]+=l2
  game=[x for x in stack if '/dark-forest-aztec/contracts/' in x[0]]
  if game:origin[game[-1][:2]]+=l2
  else:origin[('<generated/sdk>','<no game frame>')]+=l2
 def compact(c):return [{'path':k[0],'function':k[1],'l2Gas':v,**({'line':k[2],'expression':k[3],'exactPcMappingL2':exact_sites[k]} if len(k)>2 else{})} for k,v in c.most_common()]
 child_gas=sum(c['inclusiveL2'] for c in summary['calls'] if c['parentId']==call['callId'])
 local_call_gas=calls-child_gas
 assert local_call_gas>=0
 assert sum(leaf.values())+unmapped+local_call_gas==call['exclusiveL2'], 'Mapped, unmapped and local CALL overhead must reconcile to executed exclusive gas'
 output.append({'role':call['role'],'method':call['method'],'callId':call['callId'],'artifactSha256':hashlib.sha256(p.read_bytes()).hexdigest(),'exclusiveL2':call['exclusiveL2'],'mappedNonCallL2':sum(leaf.values()),'unmappedL2':unmapped,'nearestPrecedingMappingL2':approx,'nestedCallOpcodeInclusiveL2':calls,'localCallOpcodeOverheadL2':local_call_gas,'leafFunctions':compact(leaf),'gameOrigin':compact(origin),'topExpressions':compact(sites)[:30]})
print(json.dumps({'scope':'Executed PC gas, not estimated byte spans. CALL/STATICCALL source attribution is excluded because instruction gas includes nested callees; local CALL overhead is reported separately and all gas reconciles exactly. Nonexact PC debug mappings use the nearest preceding location; expression labels may include generated loop/copy instructions and are not opcode names. Total fees are separate.','calls':output},indent=2))
