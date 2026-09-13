import fs from 'node:fs';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {AztecAddress} from '@aztec/aztec.js/addresses';
import {callerParameters} from './abi-utils.mjs';
import {revive} from './fixtures.mjs';

const addressOptions={addressFromBigInt:value=>AztecAddress.fromBigIntUnsafe(value)};
const clone=value=>value instanceof AztecAddress?value:Array.isArray(value)?value.map(clone)
  :value&&typeof value==='object'?Object.fromEntries(Object.entries(value).map(([key,item])=>[key,clone(item)])):value;
const read=name=>{
  const bytes=fs.readFileSync(new URL(`./seed-fixtures/${name}`,import.meta.url));
  return {wire:JSON.parse(bytes),sha256:createHash('sha256').update(bytes).digest('hex')};
};

/** Offline input/seeding only. No game transition, expected output, hash, or fee is modeled.
 * The 20-carried boundary must first be accepted by the original private entrypoint.
 * Original 45-case files and case labels are never changed by this helper.
 */
export function buildCarriedArrivalCase({runtime,method,caseId,base}){
  assert(['move','refresh_planet'].includes(method),'Carried arrivals require Move or Refresh');
  const match=/^carried_arrivals_(5|20)$/.exec(caseId);
  assert(match,'Use a distinct carried_arrivals_5 or carried_arrivals_20 label');
  const count=Number(match[1]),filename=`fixture-${count}-account.json`;
  const queue=read(filename),carried=read('fixture-artifact_arrival-account.json');
  const role=method==='move'?'move':'core';
  const fn=runtime.artifacts[role].functions.find(fn=>fn.name===method);
  assert(fn,`Missing original ${method} ABI`);
  const input=Object.fromEntries(callerParameters(fn).map(parameter=>{
    const key=method==='move'?parameter.name:parameter.name==='location'?'source_loc':parameter.name==='timestamp'?'timestamp':`source_${parameter.name}`;
    assert(Object.hasOwn(queue.wire,key),`Missing frozen witness ${key}`);
    return [parameter.name,revive(parameter.type,queue.wire[key],addressOptions)];
  }));
  for(const key of Object.keys(input))if(/config|planet_default_stats|planet_type_weights|planet_level_thresholds/.test(key)&&Object.hasOwn(base,key))input[key]=clone(base[key]);
  input.timestamp=BigInt(base.timestamp);
  const moveFn=runtime.artifacts.move.functions.find(fn=>fn.name==='move');
  const artifactType=callerParameters(moveFn).find(p=>p.name==='source_arrival_artifacts').type.type;
  // Copy the already executed Gear arrival's complete typed Artifact. Gear does
  // not change planet growth/pauser counters; its original owner/controller stay exact.
  const artifactTemplate=revive(artifactType,carried.wire.source_arrival_artifacts[0],addressOptions);
  assert.equal(artifactTemplate.artifact_type,13n);
  assert(artifactTemplate.owner.equals(runtime.admin),'Frozen carried owner must match funded actor');
  const seeds=[],sideMetadata=[],allIds=[];
  const seed=(store,id,state)=>seeds.push({store,id,state:clone(state)});
  for(const [side,sideIndex]of(method==='move'?[['source',0],['target',1]]:[['single',0]])){
    const key=suffix=>side==='single'?suffix:`${side}_${suffix}`;
    const location=input[side==='single'?'location':`${side}_loc`];
    const planet=input[key('planet')],pa=input[key('planet_artifacts_state')],pe=input[key('planet_events_state')];
    const arrivals=input[key('arrivals')],artifacts=input[key('arrival_artifacts')],locations=input[key('arrival_artifact_locations')];
    assert.equal(pa.count,0n,'Maximum boundary starts with empty inventory');
    assert(pa.ids.every(id=>id===0n),'Frozen empty inventory has no hidden IDs');
    assert.equal(pe.count,BigInt(count));
    assert.equal(arrivals.length,20);assert.equal(artifacts.length,20);assert.equal(locations.length,20);
    const ids=[];
    for(let i=0;i<count;i++){
      const arrival=arrivals[i];
      assert.equal(arrival.id,pe.events[i].id,'Original queue index/arrival identity must agree');
      assert.equal(arrival.to_planet,location);
      assert(arrival.player.equals(planet.owner),'Original friendly arrivals preserve ownership');
      assert.equal(arrival.carried_artifact_id,0n,'Never overwrite an existing carried fixture');
      assert(arrival.arrival_time>0n&&arrival.arrival_time<=input.timestamp,'Frozen arrivals must be due');
      const id=(1n<<200n)+BigInt(count*1000+sideIndex*100+i+1);
      arrival.carried_artifact_id=id;
      artifacts[i]=clone(artifactTemplate);
      locations[i]={planet_id:0n,voyage_id:arrival.id,last_updated:1n};
      assert(input.timestamp>=artifacts[i].last_updated&&input.timestamp>=locations[i].last_updated);
      ids.push(id);allIds.push(id);
      seed('arrival',arrival.id,arrival);seed('artifact',id,artifacts[i]);seed('artifact_location',id,locations[i]);
    }
    seed('planet',location,planet);seed('planet_artifacts',location,pa);seed('planet_events',location,pe);
    sideMetadata.push({side,queueCount:count,carriedCount:count,initialInventoryCount:0,artifactIds:ids,dueTimes:arrivals.slice(0,count).map(a=>a.arrival_time)});
  }
  assert.equal(new Set(allIds.map(String)).size,allIds.length,'Each carried Artifact has one distinct root/preimage');
  if(method==='move'){
    assert(input.source_planet.owner.equals(runtime.admin));
    for(const name of ['moved_artifact_id','source_activated_artifact_id','target_activated_artifact_id'])assert.equal(input[name],0n,`Frozen ${name} must remain zero`);
    seed('world',0n,input.world);
  }
  return {input,seeds,extra:{sourceFixture:filename,sourceFixtureSha256:queue.sha256,
    artifactTemplateFixture:'fixture-artifact_arrival-account.json',artifactTemplateSha256:carried.sha256,
    caseId,carriedArrivalBoundary:count,sourceQueueCount:count,sourceCarriedCount:count,
    targetQueueCount:method==='move'?count:undefined,targetCarriedCount:method==='move'?count:undefined,
    queueCount:method==='refresh_planet'?count:undefined,initialInventoryCount:0,
    movedArtifactId:method==='move'?input.moved_artifact_id:undefined,distinctCarriedIds:true,
    stableOriginalDueTimes:true,sides:sideMetadata,gameplayOutputModeled:false,
    requiresOriginalAcceptance:true,administrativeStateBoundary:count===20}};
}
