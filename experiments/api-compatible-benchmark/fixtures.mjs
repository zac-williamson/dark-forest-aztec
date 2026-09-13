import assert from 'node:assert/strict';
import {callerParameters} from './abi-utils.mjs';

const isAddress=type=>type.kind==='struct'&&type.path?.endsWith('::AztecAddress');
export function zeroValue(type,{addressFromBigInt=value=>value}={}){
  if(isAddress(type))return addressFromBigInt(0n);
  if(type.kind==='field'||type.kind==='integer')return 0n;
  if(type.kind==='boolean')return false;
  if(type.kind==='array')return Array.from({length:type.length},()=>zeroValue(type.type,{addressFromBigInt}));
  if(type.kind==='struct')return Object.fromEntries(type.fields.map(field=>[field.name,zeroValue(field.type,{addressFromBigInt})]));
  throw Error(`Unsupported ABI type ${type.kind}`);
}
export function template(artifact,method,options){
  const fn=artifact.functions.find(fn=>fn.name===method);assert(fn,`Missing method ${method}`);
  return Object.fromEntries(callerParameters(fn).map(parameter=>[parameter.name,zeroValue(parameter.type,options)]));
}
export function revive(type,value,{addressFromBigInt=number=>number}={}){
  if(isAddress(type))return addressFromBigInt(BigInt(value));
  if(type.kind==='field'||type.kind==='integer')return BigInt(value);
  if(type.kind==='boolean'){assert.equal(typeof value,'boolean');return value;}
  if(type.kind==='array'){assert.equal(value.length,type.length,'Fixed ABI array length');return value.map(item=>revive(type.type,item,{addressFromBigInt}));}
  if(type.kind==='struct')return Object.fromEntries(type.fields.map(field=>[field.name,revive(field.type,value[field.name],{addressFromBigInt})]));
  throw Error(`Unsupported ABI type ${type.kind}`);
}
export function serializeFields(type,value){
  if(isAddress(type))return [typeof value?.toBigInt==='function'?value.toBigInt():BigInt(value)];
  if(type.kind==='field'||type.kind==='integer')return [BigInt(value)];
  if(type.kind==='boolean')return [value?1n:0n];
  if(type.kind==='array'){assert.equal(value.length,type.length);return value.flatMap(item=>serializeFields(type.type,item));}
  if(type.kind==='struct')return type.fields.flatMap(field=>serializeFields(field.type,value[field.name]));
  throw Error(`Unsupported ABI type ${type.kind}`);
}
export const json=value=>JSON.stringify(value,(_,item)=>typeof item==='bigint'?item.toString():item,2);

// Deliberately no default timestamp, ID, owner, or inactive-slot normalization.
// Each exception must identify its full path and assert the expected source value.
export function normalizeExplicit(value,rules=[]){
  const result=JSON.parse(json(value));
  for(const {path,expected,replacement} of rules){
    const parts=path.split('.');let parent=result;
    for(const key of parts.slice(0,-1)){assert(parent&&Object.hasOwn(parent,key),`Missing normalization path ${path}`);parent=parent[key];}
    const key=parts.at(-1);assert(Object.hasOwn(parent,key),`Missing normalization path ${path}`);
    assert.deepEqual(parent[key],JSON.parse(json(expected)),`Unexpected value at ${path}`);
    parent[key]=JSON.parse(json(replacement));
  }
  return result;
}
export function assertEquivalent(before,after,{beforeRules=[],afterRules=[]}={}){
  assert.deepEqual(normalizeExplicit(after,afterRules),normalizeExplicit(before,beforeRules),'Complete ordered outcome/state must match');
}

