import {isDeepStrictEqual} from 'node:util';

const generated=new Set(['offchain_receive','public_dispatch','sync_state']);
export function callerParameters(fn){
  const parameters=fn.parameters??fn.abi.parameters;
  if((fn.custom_attributes??[]).includes('abi_private')&&parameters[0]?.type?.path?.endsWith('::PrivateContextInputs'))return parameters.slice(1);
  return parameters;
}
export function wireShape(value){
  if(Array.isArray(value))return value.map(wireShape);
  if(value&&typeof value==='object')return Object.fromEntries(Object.entries(value).filter(([name])=>name!=='path').map(([name,item])=>[name,wireShape(item)]));
  return value;
}
export function apiSurface(artifact){
  const functions=artifact.functions.filter(fn=>!generated.has(fn.name)).map(fn=>({name:fn.name,attributes:[...(fn.custom_attributes??[])].filter(a=>a.startsWith('abi_')).sort(),parameters:callerParameters(fn),returnType:fn.abi?.return_type??fn.returnTypes??null}));
  const events=(artifact.outputs?.structs?.events??[]).map(event=>({name:event.path.split('::').at(-1),fields:event.fields}));
  return {name:artifact.name,functions,events};
}
export function compareApi(original,candidate,{allowAdditional=false}={}){
  const before=apiSurface(original),after=apiSurface(candidate);
  const missing=[],changed=[],added=[],nativeSchemaChanged=[];
  for(const kind of ['functions','events']){
    for(const item of before[kind]){
      const other=after[kind].find(v=>v.name===item.name);
      if(!other)missing.push(`${kind}:${item.name}`);
      else if(!isDeepStrictEqual(wireShape(item),wireShape(other)))changed.push(`${kind}:${item.name}`);
      else if(!isDeepStrictEqual(item,other))nativeSchemaChanged.push(`${kind}:${item.name}`);
    }
    for(const item of after[kind])if(!before[kind].some(v=>v.name===item.name))added.push(`${kind}:${item.name}`);
  }
  return {compatible:missing.length===0&&changed.length===0&&(allowAdditional||added.length===0),sameContractName:before.name===after.name,missing,changed,added,nativeSchemaChanged,allowAdditional};
}

