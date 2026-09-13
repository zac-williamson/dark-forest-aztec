import fs from 'node:fs';
import assert from 'node:assert/strict';
import {revive} from './fixtures.mjs';
import {addressOptions,clone} from './base-fixture.mjs';

// Reuse the previously executed original-contract witnesses. No game transition is
// reproduced by this harness: both deployed implementations execute that logic.
export function buildQueueCase({runtime,method,caseId,base}){
  assert(['move','refresh_planet'].includes(method));
  const system=method==='move'?'move':'core';
  const filename=method==='move'?`fixture-${caseId}-account.json`:caseId==='refresh_unused_padding'?'refresh-fixture-baseline-0.json':caseId==='1'?'fixture-1-account.json':`refresh-fixture-baseline-${caseId}.json`;
  const wire=JSON.parse(fs.readFileSync(new URL(`./seed-fixtures/${filename}`,import.meta.url)));
  const abi=runtime.artifacts[system].functions.find(fn=>fn.name===method);
  const input=Object.fromEntries(abi.parameters.map(p=>{
    const key=method==='refresh_planet'&&caseId==='1'?(p.name==='location'?'source_loc':p.name==='timestamp'?'timestamp':`source_${p.name}`):p.name;
    return [p.name,revive(p.type,wire[key],addressOptions)];
  }));
  for(const key of Object.keys(input))if(/config|planet_default_stats|planet_type_weights|planet_level_thresholds/.test(key)&&Object.hasOwn(base,key))input[key]=clone(base[key]);
  input.timestamp=base.timestamp;
  const seeds=[],unchangedSeeds=[],seed=(store,id,state)=>seeds.push({store,id,state});
  if(method==='refresh_planet'&&caseId==='refresh_unused_padding'){
    assert.equal(input.planet_events_state.count,0n);assert.equal(input.planet_artifacts_state.count,0n);
    input.planet_artifacts_state.ids[19]=(1n<<200n)+923n;
    input.planet_events_state.events[19].id=(1n<<220n)+117n;
    const ignoredId=(1n<<210n)+713n;
    input.arrivals[19].id=(1n<<230n)+317n;
    input.arrivals[19].carried_artifact_id=ignoredId;
    input.arrival_artifact_locations[19]={planet_id:(1n<<190n)+41n,voyage_id:(1n<<205n)+53n,last_updated:1n};
    // The original empty-count batch authorizes the writer but never updates this
    // out-of-count location. Seed a different value so an accidental write fails.
    const ignoredLocation={planet_id:(1n<<180n)+67n,voyage_id:(1n<<195n)+79n,last_updated:2n};
    const unchanged={store:'artifact_location',id:ignoredId,state:ignoredLocation};
    seeds.push(unchanged);unchangedSeeds.push(unchanged);
  }
  const seedPlanet=(location,planet,pa,pe,arrivals,artifacts,locations)=>{
    seed('planet',location,planet);seed('planet_artifacts',location,pa);seed('planet_events',location,pe);
    for(let i=0;i<Number(pe.count);i++){
      const arrival=arrivals[i];
      if(caseId==='future_queue')arrival.arrival_time=4102444800n;
      seed('arrival',arrival.id,arrival);
      if(arrival.carried_artifact_id!==0n){seed('artifact',arrival.carried_artifact_id,artifacts[i]);seed('artifact_location',arrival.carried_artifact_id,locations[i]);}
    }
  };
  if(method==='move'){
    // Deterministically funded development accounts match the original fixtures;
    // assert that assumption instead of silently changing combat ownership.
    assert(input.source_planet.owner.equals(runtime.admin),'Source owner must match actual transaction sender');
    for(const side of ['source','target'])seedPlanet(input[side+'_loc'],input[side+'_planet'],input[side+'_planet_artifacts_state'],input[side+'_planet_events_state'],input[side+'_arrivals'],input[side+'_arrival_artifacts'],input[side+'_arrival_artifact_locations']);
    for(const role of ['moved_artifact','source_activated_artifact','target_activated_artifact'])if(input[role+'_id']!==0n)seed('artifact',input[role+'_id'],input[role]);
    seed('world',0n,input.world);
  }else seedPlanet(input.location,input.planet,input.planet_artifacts_state,input.planet_events_state,input.arrivals,input.arrival_artifacts,input.arrival_artifact_locations);
  return {input,seeds,unchangedSeeds:unchangedSeeds.length?unchangedSeeds:undefined,extra:{sourceFixture:filename,sourceQueueCount:input.source_planet_events_state?.count,targetQueueCount:input.target_planet_events_state?.count,queueCount:input.planet_events_state?.count,allOriginalWitnessFieldsPreserved:caseId!=='refresh_unused_padding',unusedNonzeroPadding:caseId==='refresh_unused_padding'}};
}
