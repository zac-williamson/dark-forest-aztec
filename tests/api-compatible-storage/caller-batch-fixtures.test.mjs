import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {buildBatchVerifierCase,expectedVerifierBatches,batchFields,batchRoles} from './caller-batch-fixtures.mjs';
const bigint=value=>Array.isArray(value)?value.map(bigint):value&&typeof value==='object'
 ?Object.fromEntries(Object.entries(value).map(([key,item])=>[key,bigint(item)]))
 :typeof value==='string'&&/^(0x[0-9a-f]+|[0-9]+)$/i.test(value)?BigInt(value):value;
const read=(method,id='ordinary')=>bigint(JSON.parse(fs.readFileSync(new URL(`../../experiments/api-compatible-benchmark/.state/baseline-v2-${method}-${id}.json`,import.meta.url))).input);
// A minimal ABI suffices for the only nonzero states in these queue fixtures.
const arrival=JSON.parse(fs.readFileSync('/tmp/df-fee-tools/artifacts/baseline/arrival-ArrivalStorage.json'));
const stateTypes={arrival:[...arrival.functions,...(arrival.nonDispatchPublicFunctions??[])].find(f=>f.name==='set').abi.parameters.at(-1).type};
// These units inspect boundary field inclusion, not cryptographic hash values.
const hashFields=async fields=>fields.reduce((sum,value,index)=>sum+value*BigInt(index+1),0n);
for(const [role,method]of [['core','refresh_planet'],['artifact_valut','give_spaceships'],['move','move']])test(`${method} empty verifier observes all41 exact original fields despite inactive padding`,async()=>{
 const original=read(method),before=structuredClone(original),built=buildBatchVerifierCase(original,role,{timestamp:1234n});
 assert.deepEqual(original,before);assert.equal(built.input.planet_events_state?.count??built.input.source_planet_events_state.count,0n);
 const batches=await expectedVerifierBatches(built.input,role,{stateTypes,hashFields});
 for(const byStore of batches)for(const store of batchRoles){assert.deepEqual(batchFields(byStore[store]),Array(41).fill(0n));
  for(let index=0;index<41;index++){const changed=batchFields(byStore[store]);changed[index]=1n;assert.notDeepEqual(changed,Array(41).fill(0n));}
 }
 assert(built.seeds.some(seed=>seed.store==='planet_events'&&seed.state.events[19].id!==0n));
});
for(const shape of ['source0_target1','source1_target0'])test(`Move ${shape} keeps exact valid queue side and distinguishes a zero-ID count1 call`,async()=>{
 const original=read('move'),queuedMove=read('move','1'),built=buildBatchVerifierCase(original,'move',{queuedMove,shape,timestamp:1234n});
 const batches=await expectedVerifierBatches(built.input,'move',{stateTypes,hashFields});
 assert.deepEqual(batches.map(b=>b.arrival.count),shape==='source0_target1'?[0n,1n]:[1n,0n]);
 const nonzero=batches.find(b=>b.arrival.count===1n);
 assert.notEqual(nonzero.arrival.ids[0],0n);assert.notEqual(nonzero.arrival.hashes[0],0n);
 for(const role of ['artifact','artifact_location'])assert.deepEqual(batchFields(nonzero[role]),[...Array(40).fill(0n),1n]);
 const tampered=structuredClone(queuedMove);tampered.max_dist+=1n;
 assert.throws(()=>buildBatchVerifierCase(original,'move',{queuedMove:tampered,shape}),/max_dist/);
});
