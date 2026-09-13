// Verify manual internal-call selectors and widths against actual compiled ABIs.
// This is a local artifact check: no wallet, node, simulation or proof is opened.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {loadContractArtifact,FunctionSelector,decodeFunctionSignature} from '@aztec/stdlib/abi';

const root=fileURLToPath(new URL('../../',import.meta.url));
const manifest=JSON.parse(fs.readFileSync(path.join(root,'tests/api-compatibility/generated/backend-move-transform.json')));
const backendPath=process.argv[2]??path.join(root,'contracts/target/game_state_backend-GameStateBackend.json');
const movePath=process.argv[3]??path.join(root,'contracts/target/move-Move.json');
const backend=loadContractArtifact(JSON.parse(fs.readFileSync(backendPath)));
const move=loadContractArtifact(JSON.parse(fs.readFileSync(movePath)));
const find=(artifact,name)=>{
  const fn=[...artifact.functions,...(artifact.nonDispatchPublicFunctions??[])].find(fn=>fn.name===name);
  assert(fn,`Missing compiled ${artifact.name}.${name}`);
  return fn;
};
function checkBuffer(fn,width){
  assert.equal(fn.parameters.length,1,'Transport must use exactly one typed parameter');
  assert.equal(fn.parameters[0].name,'prepared_payload');
  const type=fn.parameters[0].type;
  assert.equal(type.kind,'struct');assert(type.path.endsWith('::FieldBuffer'));
  assert.equal(type.fields.length,1);assert.equal(type.fields[0].name,'words');
  assert.deepEqual(type.fields[0].type,{kind:'array',length:width,type:{kind:'field'}});
}
for(const entry of Object.values(manifest.fieldBufferTransport.entries)){
  const target=find(backend,entry.backendMethod),sender=find(move,entry.systemMethod);
  checkBuffer(target,entry.backendFields);checkBuffer(sender,entry.systemFields);
  assert.equal(sender.isOnlySelf,true,'Prepared System entry must remain only_self');
  assert.equal(decodeFunctionSignature(target.name,target.parameters),entry.signature);
  const compiledSelector=await FunctionSelector.fromNameAndParameters(target);
  const forwardedSelector=await FunctionSelector.fromSignature(entry.signature);
  assert(compiledSelector.equals(forwardedSelector),'Manual selector differs from actual compiled target');
  console.log('PASS',entry.backendMethod,entry.backendFields,'fields',compiledSelector.toString());
}
