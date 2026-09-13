import assert from 'node:assert/strict';
import {serializeFields} from '../../experiments/api-compatible-benchmark/fixtures.mjs';
import {clone} from '../../experiments/api-compatible-benchmark/base-fixture.mjs';
import {buildInactiveLocationCase} from './caller-location-fixtures.mjs';

export const batchRoles=['arrival','artifact','artifact_location'];
export function batchFields({ids,hashes,count}){
 assert.equal(ids.length,20);assert.equal(hashes.length,20);return [...ids,...hashes,count];
}

// Exact boundary algorithm in original libs/batch_utils.nr::compute_planet_hashes.
// No game calculations are reproduced: the real private entry point does those.
// Inactive witnesses never enter these five arrays, including all count0 slots.
export async function expectedVerifierBatches(input,role,{stateTypes,hashFields}){
 const sides=role==='move'?['source','target']:[''];
 const batches=[];
 for(const side of sides){
  const key=name=>side?`${side}_${name}`:name;
  const pe=input[key('planet_events_state')],arrivals=input[key('arrivals')];
  const artifacts=input[key(role==='artifact_valut'?'artifacts':'arrival_artifacts')];
  const locations=input[key(role==='artifact_valut'?'artifact_locations':'arrival_artifact_locations')];
  const result=Object.fromEntries(batchRoles.map(store=>[store,{side:side||'planet',ids:Array(20).fill(0n),hashes:Array(20).fill(0n),count:pe.count}]));
  for(let i=0;i<Number(pe.count);i++){
   const id=pe.events[i].id,artifactId=arrivals[i].carried_artifact_id;
   result.arrival.ids[i]=id;result.artifact.ids[i]=artifactId;result.artifact_location.ids[i]=artifactId;
   if(id!==0n)result.arrival.hashes[i]=await hashFields(serializeFields(stateTypes.arrival,arrivals[i]));
   if(artifactId!==0n){
    result.artifact.hashes[i]=await hashFields(serializeFields(stateTypes.artifact,artifacts[i]));
    result.artifact_location.hashes[i]=await hashFields(serializeFields(stateTypes.artifact_location,locations[i]));
   }
  }
  batches.push(result);
 }
 return batches;
}

export function buildBatchVerifierCase(original,role,{queuedMove,shape='empty',timestamp=0n}={}){
 assert(['core','artifact_valut','move'].includes(role));
 let input,seeds;
 if(role==='artifact_valut'){
  const mapped={...clone(original),location:original.location_id,arrival_artifact_locations:clone(original.artifact_locations)};
  const built=buildInactiveLocationCase(mapped,'core',19,timestamp);
  input=built.input;input.artifact_locations=input.arrival_artifact_locations;
  delete input.arrival_artifact_locations;delete input.location;seeds=built.seeds;
 }else{
  ({input,seeds}=buildInactiveLocationCase(original,role,role==='move'?17:18,timestamp));
 }
 if(role==='move'&&shape!=='empty'){
  assert(['source0_target1','source1_target0'].includes(shape));assert(queuedMove);
  for(const side of ['source','target'])assert.equal(queuedMove[`${side}_planet_events_state`].count,1n);
  // The saved original cases differ only in queue state and timestamp. Refuse
  // incompatible coordinates/configs/owners rather than weakening the witness.
  for(const key of Object.keys(original))if(!['timestamp','source_planet_events_state','source_arrivals','target_planet_events_state','target_arrivals'].includes(key))assert.deepEqual(queuedMove[key],original[key],`Original queue fixture changed ${key}`);
  const side=shape==='source0_target1'?'target':'source';
  for(const name of ['planet_events_state','arrivals'])input[`${side}_${name}`]=clone(queuedMove[`${side}_${name}`]);
  for(const arrival of input[`${side}_arrivals`])assert.equal(arrival.carried_artifact_id,0n,'Nonzero-count/all-zero artifact-ID case is required');
  // Restore inactive records on the nonempty side to the exact old witness too.
  for(const name of ['planet_artifacts_state','arrival_artifacts','arrival_artifact_locations'])input[`${side}_${name}`]=clone(queuedMove[`${side}_${name}`]);
  seeds=seeds.filter(seed=>!(seed.id===input[`${side}_loc`]&&['planet_artifacts','planet_events'].includes(seed.store)));
  seeds.push({store:'planet_artifacts',id:input[`${side}_loc`],state:input[`${side}_planet_artifacts_state`]},
   {store:'planet_events',id:input[`${side}_loc`],state:input[`${side}_planet_events_state`]});
  for(let i=0;i<Number(input[`${side}_planet_events_state`].count);i++)seeds.push({store:'arrival',id:input[`${side}_planet_events_state`].events[i].id,state:input[`${side}_arrivals`][i]});
 }
 return {input,seeds,shape};
}
