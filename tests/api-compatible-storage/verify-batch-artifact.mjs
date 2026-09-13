// Native artifact/selector check only. No wallet, node, transaction, or proof.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {loadContractArtifact,FunctionSelector,decodeFunctionSignature} from '@aztec/stdlib/abi';

const fixtureFile=process.argv[2]??new URL('./caller-batch/target/caller_sensitive_batch-CallerSensitiveBatch.json',import.meta.url);
const baselineDirectory=process.argv[3]??'/tmp/df-fee-tools/artifacts/baseline';
const reportFile=process.argv[4]??new URL('../../docs/api-compatibility/batch-caller-native-v5.json',import.meta.url);
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
function load(file){const bytes=fs.readFileSync(file),raw=JSON.parse(bytes);assert.equal(raw.transpiled,true);
 return {file:String(file),sha256:hash(bytes),raw,artifact:loadContractArtifact(raw)};}
const custom=load(fixtureFile);
const privateFunctions=custom.raw.functions.filter(fn=>fn.custom_attributes.some(attribute=>attribute.includes('private')));
assert.equal(privateFunctions.length,0,'Test fixture must have no private constrained functions');
const find=(artifact,name)=>[...artifact.functions,...(artifact.nonDispatchPublicFunctions??[])].find(fn=>fn.name===name);
const fn=find(custom.artifact,'verify_hashes_batch');assert(fn&&fn.isStatic,'Original verifier is a public view');
const signature=decodeFunctionSignature(fn.name,fn.parameters),selector=await FunctionSelector.fromNameAndParameters(fn);
const originals=[];
for(const [role,file]of [['arrival','arrival-ArrivalStorage.json'],['artifact','artifact-ArtifactStorage.json'],['artifact_location','artifact_location-ArtifactLocationStorage.json']]){
 const baseline=load(path.join(baselineDirectory,file)),original=find(baseline.artifact,'verify_hashes_batch');
 const originalSelector=await FunctionSelector.fromNameAndParameters(original);
 assert.equal(decodeFunctionSignature(original.name,original.parameters),signature);assert(originalSelector.equals(selector));
 assert.deepEqual(original.parameters.map(p=>p.type),fn.parameters.map(p=>p.type));
 assert.deepEqual(original.returnTypes,fn.returnTypes);assert.equal(original.isStatic,fn.isStatic);
 originals.push({role,file:baseline.file,sha256:baseline.sha256,selector:originalSelector.toString(),sameInputTypes:true,sameReturnType:true,sameViewSemantics:true});
}
const dispatcher=custom.raw.functions.find(f=>f.name==='public_dispatch');
const report={status:'passed',runtimeExecuted:false,proverEnabled:false,privateFunctionCount:0,transactionProofsGenerated:0,
 sourceSha256:hash(fs.readFileSync(new URL('./caller-batch/src/main.nr',import.meta.url))),
 artifact:{file:custom.file,sha256:custom.sha256,nativePublicBytes:Buffer.from(dispatcher.bytecode,'base64').length},signature,selector:selector.toString(),originals};
fs.writeFileSync(reportFile,JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report,null,2));
