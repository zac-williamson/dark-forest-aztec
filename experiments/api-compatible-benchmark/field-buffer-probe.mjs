// Diagnostic only. This does not simulate a full transaction or quote a Fee Juice cost.
import fs from 'node:fs';
import {pathToFileURL} from 'node:url';
import path from 'node:path';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const simulatorDirectory=path.dirname(require.resolve('@aztec/simulator/server'))+'/public/avm/';
import assert from 'node:assert/strict';
import {Fr} from '@aztec/foundation/curves/bn254';
import {AztecAddress} from '@aztec/stdlib/aztec-address';
import {GlobalVariables} from '@aztec/stdlib/tx';
import {FunctionSelector} from '@aztec/stdlib/abi';
const {AvmSimulator}=await import(pathToFileURL(simulatorDirectory+'avm_simulator.js'));
const {AvmExecutionEnvironment}=await import(pathToFileURL(simulatorDirectory+'avm_execution_environment.js'));
const {AvmMachineState}=await import(pathToFileURL(simulatorDirectory+'avm_machine_state.js'));
const {AvmContext}=await import(pathToFileURL(simulatorDirectory+'avm_context.js'));
const {CallDataArray}=await import(pathToFileURL(simulatorDirectory+'calldata.js'));
const artifact=JSON.parse(fs.readFileSync(process.argv[2]??'/tmp/df-buffer-gas-probe-native.json'));
const bytecode=Buffer.from(artifact.functions.find(f=>f.name==='public_dispatch').bytecode,'base64');
const records=[];
for(const count of [267])for(const variant of ['array','buffer','hybrid','unrolled']){
 const method=(process.env.DECODE_ONLY==='1'?'decode_':'')+variant+count;
 const selector=await FunctionSelector.fromSignature(`${method}(${variant!=='array'?'(':''}[Field;${count}]${variant!=='array'?')':''})`);
 const calldata=new CallDataArray([selector.toField(),...Array.from({length:count},(_,i)=>new Fr(i+1))]);
 const environment=new AvmExecutionEnvironment(AztecAddress.fromFieldUnsafe(new Fr(42)),AztecAddress.fromFieldUnsafe(new Fr(43)),Fr.ZERO,Fr.ZERO,GlobalVariables.empty(),false,calldata,{collectDebugLogs:false});
 const state={getPublicFunctionDebugName:async()=>method};
 const context=new AvmContext(state,environment,new AvmMachineState(100000000,10000000));
 const simulator=new AvmSimulator(context,undefined,true);
 const result=await simulator.executeBytecode(bytecode);
 assert.equal(result.reverted,false);
 const record={method,count,l2Gas:100000000-result.gasLeft.l2Gas,output:result.output.readAll().map(x=>x.toString()),opcodes:Object.fromEntries(simulator.opcodeTallies)};
 assert.deepEqual(result.output.readAll().map(x=>x.toBigInt()),(process.env.DECODE_ONLY==='1'?[268n]:Array.from({length:count},(_,i)=>BigInt(i+1)))); records.push(record); console.log(method,count,record.l2Gas,record.output.length);
}
fs.writeFileSync(process.argv[3]??'/tmp/df-buffer-results.json',JSON.stringify({scope:'Pure public calldata decode/return serialization only; no state, cross-contract calls, protocol fees, or transactions',records},null,2));
