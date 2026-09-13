/** Executed AVM attribution only. These isolated callback costs are not fees for
 * complete transactions and must never replace the mined Fee Juice report. */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {Fr} from '@aztec/foundation/curves/bn254';
import {AztecAddress} from '@aztec/stdlib/aztec-address';
import {GlobalVariables} from '@aztec/stdlib/tx';
import {FunctionSelector,loadContractArtifact} from '@aztec/stdlib/abi';
const moduleBase=new URL('./public/avm/',import.meta.resolve('@aztec/simulator/server'));
const {AvmSimulator}=await import(new URL('avm_simulator.js',moduleBase));
const {AvmExecutionEnvironment}=await import(new URL('avm_execution_environment.js',moduleBase));
const {AvmMachineState}=await import(new URL('avm_machine_state.js',moduleBase));
const {AvmContext}=await import(new URL('avm_context.js',moduleBase));
const {CallDataArray}=await import(new URL('calldata.js',moduleBase));
const directory=process.argv[2]??'/tmp/df-api-v2-facades';
const output=process.argv[3]??'docs/api-compatibility/event-encoding-profile.json';
const entries=[['world','WorldStorage',4],['player','PlayerStorage',8],['planet','PlanetStorage',32],
  ['planet_revealed_coords','PlanetRevealedCoordsStorage',4],['planet_events','PlanetEventsStorage',22],
  ['planet_artifacts','PlanetArtifactsStorage',22],['arrival','ArrivalStorage',11],['artifact','ArtifactStorage',13],
  ['artifact_location','ArtifactLocationStorage',3]];
const address=AztecAddress.fromBigIntUnsafe(42n),sender=AztecAddress.fromBigIntUnsafe(43n),records=[];
for(const [slug,name,width] of entries){
  const file=path.join(directory,`${slug}-${name}.json`),bytes=fs.readFileSync(file),raw=JSON.parse(bytes),artifact=loadContractArtifact(raw);
  const bytecode=Buffer.from(raw.functions.find(f=>f.name==='public_dispatch').bytecode,'base64'),pair=[];
  for(const suffix of ['update','fields']){
    const method=`emit_${slug}_${suffix}`;
    const fn=[...artifact.functions,...(artifact.nonDispatchPublicFunctions??[])].find(f=>f.name===method);
    assert(fn,`${method} missing`);
    const selector=await FunctionSelector.fromNameAndParameters(fn);
    const calldata=new CallDataArray([selector.toField(),new Fr(7),...Array.from({length:width},()=>Fr.ZERO)]);
    const logs=[],reads=[];
    const state={getPublicFunctionDebugName:async()=>method,
      checkSiloedNullifierExists:async()=>true,
      readStorage:async(target,slot)=>{assert(target.equals(address));assert(slot.equals(new Fr(2)));reads.push(slot.toString());return sender.toField();},
      writePublicLog:(target,fields)=>{assert(target.equals(address));logs.push(fields.map(f=>f.toString()));}};
    const environment=new AvmExecutionEnvironment(address,sender,Fr.ZERO,Fr.ZERO,GlobalVariables.empty(),false,calldata,{collectDebugLogs:false});
    const context=new AvmContext(state,environment,new AvmMachineState(100000000,10000000));
    const simulator=new AvmSimulator(context,undefined,true),result=await simulator.executeBytecode(bytecode);
    assert.equal(result.reverted,false,`${method} reverted`);assert.equal(logs.length,1);assert.equal(reads.length,1);
    const record={method,l2Gas:100000000-result.gasLeft.l2Gas,logs,opcodes:Object.fromEntries(simulator.opcodeTallies)};
    pair.push(record);
  }
  assert.deepEqual(pair[0].logs,pair[1].logs,`${slug} event bytes changed`);
  records.push({contract:name,artifactSha256:crypto.createHash('sha256').update(bytes).digest('hex'),identicalEvent:true,
    l2GasReduction:pair[0].l2Gas-pair[1].l2Gas,executions:pair});
  console.log(name,pair[0].l2Gas,'->',pair[1].l2Gas,'identical event');
}
fs.mkdirSync(path.dirname(output),{recursive:true});
fs.writeFileSync(output,JSON.stringify({scope:'Isolated executed AVM callback attribution with mocked initialization and binding reads. Not a complete transaction or Fee Juice saving.',records},null,2)+'\n');
