import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {loadContractArtifact,FunctionSelector} from '@aztec/stdlib/abi';
import {files,auxiliaryFiles} from './runtime.mjs';

const input=process.argv[2];assert(input,'Pass a saved .avm-calls.jsonl path');
const artifacts=process.argv[3]??'/tmp/df-api-compatible-v1/native';
const output=input.replace(/\.avm-calls\.jsonl$/,'.gas-attribution.json');assert(output!==input);
const metadata=JSON.parse(fs.readFileSync(input.replace(/\.avm-calls\.jsonl$/,'.public-output.json')));
const roles=Object.fromEntries(Object.entries(metadata.contracts).map(([role,address])=>[address,role]));
const selectors={};
for(const [role,file] of Object.entries({...files,...auxiliaryFiles})){
 if(!fs.existsSync(path.join(artifacts,file)))continue;
 const artifact=loadContractArtifact(JSON.parse(fs.readFileSync(path.join(artifacts,file))));
 selectors[role]={};
 for(const fn of [...artifact.functions,...artifact.nonDispatchPublicFunctions??[]]){
  selectors[role][BigInt((await FunctionSelector.fromNameAndParameters(fn.name,fn.parameters)).toString()).toString()]=fn.name;
 }
}
const entries=fs.readFileSync(input,'utf8').trim().split('\n').filter(Boolean).map(line=>JSON.parse(line)).sort((a,b)=>a.callId-b.callId);
const stack=[],calls=[];
for(const entry of entries){
 const depth=Number(BigInt(entry.depth));while(stack.length&&stack.at(-1).depth>=depth)stack.pop();
 const parent=stack.at(-1),role=roles[entry.address]??entry.address;
 const call={callId:entry.callId,parentId:parent?.callId??null,depth,role,method:selectors[role]?.[BigInt(entry.selector).toString()]??entry.selector,selector:entry.selector,inclusiveL2:entry.inclusiveGas.l2Gas,exclusiveL2:entry.inclusiveGas.l2Gas,instructions:entry.instructions,reverted:entry.reverted,opcodes:entry.opcodes};
 if(parent)parent.exclusiveL2-=call.inclusiveL2;
 calls.push(call);stack.push(call);
}
const rootGas=calls.filter(call=>call.parentId===null).reduce((sum,call)=>sum+call.inclusiveL2,0);
assert.equal(rootGas,metadata.gas.publicGas.l2Gas,'Sum of executed root calls must exactly reproduce public gas');
assert.equal(calls.reduce((sum,call)=>sum+call.exclusiveL2,0),rootGas,'Exclusive call costs must reconcile without double counting');
const aggregate={};for(const call of calls){const key=`${call.role}.${call.method}`;const row=aggregate[key]??={calls:0,exclusiveL2:0};row.calls++;row.exclusiveL2+=call.exclusiveL2;}
const report={scope:'Diagnostic public execution only. Existing SDK CppVsTsPublicTxSimulator asserts exact TS/C++ gas and effects. Complete mined fees are recorded separately.',publicL2:rootGas,calls,aggregate:Object.fromEntries(Object.entries(aggregate).sort((a,b)=>b[1].exclusiveL2-a[1].exclusiveL2)),pcDetails:input};
fs.writeFileSync(output,JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({output,publicL2:rootGas,calls:calls.length,top:Object.entries(report.aggregate).slice(0,8)}));
