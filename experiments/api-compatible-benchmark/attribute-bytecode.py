"""Read-only native AVM byte-span attribution using transpiled debug PC mappings."""
import sys,json,base64,zlib,bisect,collections,hashlib
p=sys.argv[1]; a=json.load(open(p));fn=next(x for x in a['functions'] if x['name']=='public_dispatch')
b=base64.b64decode(fn['bytecode']);j=json.loads(zlib.decompress(base64.b64decode(fn['debug_symbols']),-15))['debug_infos'][0]
locations=j['brillig_locations']['0'];tree=j['location_tree']['locations']; files=a['file_map']; pcs=sorted(map(int,locations));by_leaf=collections.Counter();by_game=collections.Counter();by_site=collections.Counter();by_origin=collections.Counter()
def label(v):
 f=files.get(str(v['file']));
 if not f:return None
 span=v['span']; functions=f.get('function_locations',[]); starts=[x['start'] for x in functions];index=bisect.bisect_right(starts,span['start'])-1
 name=functions[index]['name'] if index>=0 else '<preamble>'
 path=f['path'];line=f['source'].count('\n',0,span['start'])+1
 return (path,name,line,f['source'][span['start']:span['end']])
for i,pc in enumerate(pcs):
 size=(pcs[i+1] if i+1<len(pcs) else len(b))-pc
 n=locations[str(pc)]; stack=[]
 while n is not None:
  node=tree[n]; info=label(node['value']);
  if info:stack.append(info)
  n=node['parent']
 if not stack:continue
 leaf=stack[0];by_leaf[(leaf[0],leaf[1])]+=size;by_site[leaf]+=size
 game=[x for x in stack if '/dark-forest-aztec/contracts/' in x[0]]
 if game:by_game[(game[0][0],game[0][1])]+=size;by_origin[(game[-1][0],game[-1][1])]+=size
 else:by_game[('<generated/sdk>','<no game frame>')]+=size;by_origin[('<generated/sdk>','<no game frame>')]+=size
compact=lambda c:[{'path':k[0],'function':k[1],'byteSpan':v,**({'line':k[2],'expression':k[3]} if len(k)>2 else {})} for k,v in c.most_common()]
result={'artifact':p,'sha256':hashlib.sha256(open(p,'rb').read()).hexdigest(),'contract':a['name'],'nativeBytecodeBytes':len(b),'mappedPCs':len(pcs),'prefixWithoutSourceMappingBytes':pcs[0],'method':'Each debug PC owns bytes until next mapped PC. This is static source-span attribution, not executed gas. Generated/unmapped instructions can lie within a mapped span.','topGameOrigin':compact(by_origin),'nearestGameFunction':compact(by_game),'leafFunctions':compact(by_leaf),'leafExpressions':compact(by_site)[:60]}
print(json.dumps(result,indent=2))
