/** Read full artifacts only. Never creates wallets, proofs, keys or node clients. */
import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const sha=b=>createHash('sha256').update(b).digest('hex');
const [mode,input,resolutionRoot,...rest]=process.argv.slice(2);
assert(['metadata','routes'].includes(mode),'Only read-only artifact checks are supported');
const require=createRequire(path.join(path.resolve(resolutionRoot),'package.json'));
const resolve=name=>require.resolve(name);
const entryNames=['@aztec/stdlib/abi','@aztec/stdlib/contract','@aztec/constants'];
const entries=Object.fromEntries(entryNames.map(name=>{const p=resolve(name);return[name,{path:fs.realpathSync(p),sha256:sha(fs.readFileSync(p))}];}));
const {loadContractArtifact,decodeFunctionSignature,FunctionSelector}=await import(pathToFileURL(resolve('@aztec/stdlib/abi')).href);
const {getContractClassFromArtifact}=await import(pathToFileURL(resolve('@aztec/stdlib/contract')).href);
const {MAX_PACKED_PUBLIC_BYTECODE_SIZE_IN_FIELDS,MAX_PUBLIC_BYTECODE_SIZE_IN_BYTES}=await import(pathToFileURL(resolve('@aztec/constants')).href);
const read=p=>JSON.parse(fs.readFileSync(p,'utf8'));
if(mode==='metadata'){
 const raw=read(input);assert.equal(raw.transpiled,true,'Require native-processed full artifact');
 const dispatch=raw.functions.filter(f=>f.name==='public_dispatch');assert.equal(dispatch.length,1);
 const publicBytes=Buffer.from(dispatch[0].bytecode,'base64').length;assert(publicBytes>0);
 const packedFields=1+Math.ceil(publicBytes/31);
 assert(publicBytes<=MAX_PUBLIC_BYTECODE_SIZE_IN_BYTES,`${publicBytes} native bytes exceed cap`);
 assert(packedFields<=MAX_PACKED_PUBLIC_BYTECODE_SIZE_IN_FIELDS,`${packedFields} packed fields exceed cap`);
 const actual=await getContractClassFromArtifact(loadContractArtifact(raw));assert(!actual.id.isZero());
 fs.writeFileSync(rest[0],JSON.stringify({passed:true,file:path.basename(input),name:raw.name,sha256:sha(fs.readFileSync(input)),classId:actual.id.toString(),publicBytes,packedFields,limits:{publicBytes:MAX_PUBLIC_BYTECODE_SIZE_IN_BYTES,packedFields:MAX_PACKED_PUBLIC_BYTECODE_SIZE_IN_FIELDS},sdkEntries:entries},null,2)+'\n');
}else{
 const [routeFile,output,protectionFile]=rest;const routes=read(routeFile);assert(routes.length>0);
 const loaded=new Map();const checked=[];
 for(const row of routes){
  if(!loaded.has(row.target)){
   const artifact=loadContractArtifact(read(path.join(input,row.target)));
   const functions=[...artifact.functions,...(artifact.nonDispatchPublicFunctions??[])];
   loaded.set(row.target,functions);
  }
  const matching=loaded.get(row.target).filter(f=>f.name===row.method);assert.equal(matching.length,1,`Ambiguous/missing ${row.target}:${row.method}`);
  const fn=matching[0];const signature=decodeFunctionSignature(fn.name,fn.parameters);
  assert.equal(row.signature,signature,`${row.source}: raw selector differs from actual ${row.target}`);
  const fromAbi=await FunctionSelector.fromNameAndParameters(fn);const fromLiteral=await FunctionSelector.fromSignature(row.signature);
  assert(fromAbi.equals(fromLiteral),'Actual compiled selector differs');
  if(row.method.endsWith('_public'))assert.equal(fn.isOnlySelf,true,'Original public fallback must remain only_self');
  checked.push({...row,selector:fromAbi.toString()});
 }
 const protections=read(protectionFile);assert(protections.length>0);
 for(const row of protections){
  const artifact=loadContractArtifact(read(path.join(input,row.file)));
  const found=[...artifact.functions,...(artifact.nonDispatchPublicFunctions??[])].filter(f=>f.name===row.method);
  assert.equal(found.length,1,`Missing/ambiguous protected function ${row.file}:${row.method}`);
  assert.equal(found[0].isOnlySelf,true,`Compiled only_self protection missing: ${row.file}:${row.method}`);
 }
 fs.writeFileSync(output,JSON.stringify({passed:true,scope:'Every frozen manual selector and all source only_self declarations checked against actual compiled targets; no execution or fee claim',checked,protections,sdkEntries:entries},null,2)+'\n');
}
