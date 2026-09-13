import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createHash} from 'node:crypto';
import {AztecAddress} from '@aztec/aztec.js/addresses';
import {callerParameters} from './abi-utils.mjs';
import {revive,template} from './fixtures.mjs';
import {buildArtifactCase} from './artifact-fixtures.mjs';

const addressOptions={addressFromBigInt:value=>AztecAddress.fromBigIntUnsafe(value)};
const FIELD_MODULUS=21888242871839275222246405745257275088548364400416034343698204186575808495617n;
// A fixed full-u64 future time is the same for every member of a comparison.
// It must not be derived from each variant's current clock.
export const carriedDepositFutureTime=1n<<63n;
const clone=value=>value&&typeof value.toBigInt==='function'?value:Array.isArray(value)?value.map(clone)
  :value&&typeof value==='object'?Object.fromEntries(Object.entries(value).map(([key,item])=>[key,clone(item)])):value;
const sourceHashes=Object.freeze({
  'fixture-5-account.json':'83428c8ced441e58f45a18c2ee32223ad37c5b5e5d889992682fd789cc12e7ba',
  'fixture-artifact_arrival-account.json':'bf34eeaf5ed1c2cf12e500d403a8a53715c941f8577fc3074869b5d38a58ec61',
});
const read=name=>{
  const bytes=fs.readFileSync(new URL(`./seed-fixtures/${name}`,import.meta.url));
  const sha256=createHash('sha256').update(bytes).digest('hex');
  assert.equal(sha256,sourceHashes[name],`Frozen source fixture changed: ${name}`);
  return {wire:JSON.parse(bytes),sha256};
};
const asBigInt=value=>typeof value?.toBigInt==='function'?value.toBigInt():BigInt(value);
const seed=(store,id,state)=>({store,id,state:clone(state)});
const roles={find_artifact:'artifact_find',deposit_artifact:'artifact_valut'};

/** Offline fixtures only: retains the full original private function input.
 * No transition output, generated Find ID, state root, or fee is substituted.
 * Each new case requires original acceptance before V8/chunk comparisons.
 * Find seedBlock must be fresh and SHARED by the orchestrator for the entire pair.
 */
export function buildCarriedArtifactActionCase({runtime,method,caseId,base,input}){
  const role=roles[method];assert(role,'Only original Find and Deposit are supported');
  const findMatch=/^carried_find_(2|5)$/.exec(caseId??'');
  const deposit=method==='deposit_artifact';
  assert(deposit?caseId==='carried_deposit_5':!!findMatch,'Use a distinct carried_find_2/5 or carried_deposit_5 label');
  const count=deposit?5:Number(findMatch[1]),dueCount=deposit?4:count;
  const abiArtifact=runtime.rawArtifacts?.[role]??runtime.artifacts?.[role];
  assert(abiArtifact,`Missing original ${role} ABI`);
  const params=callerParameters(abiArtifact.functions.find(fn=>fn.name===method));
  const zeroInput=input??template(abiArtifact,method,addressOptions);
  const original=buildArtifactCase({runtime,method,caseId:'ordinary',base,input:zeroInput});
  const state=original.input;
  assert.equal(asBigInt(state.planet.owner),asBigInt(runtime.admin),'Friendly planet owner must be the transaction actor');
  assert.equal(state.planet.last_updated,1n);
  assert.equal(state.planet_events_state.count,0n,'Compose only onto the original empty queue fixture');
  const ownedCount=Number(state.planet_artifacts_state.count);
  if(deposit)assert.equal(ownedCount,0,'Deposit starts with no inventory');
  else{
    assert.equal(state.spaceships_config.gear,true,'Keep original enabled Gear check');
    assert.equal(ownedCount,1,'Retain exactly the original owned Gear');
    assert.equal(state.owned_artifacts[0].artifact_type,13n);
    assert.equal(asBigInt(state.owned_artifacts[0].controller),asBigInt(runtime.admin));
    assert(base.seedBlock&&BigInt(base.seedBlock.number)>0n&&BigInt(base.seedBlock.hash)>0n,'Find needs the complete common historical seed');
  }
  assert(ownedCount+dueCount+1<=20,'Original fixed inventory must fit refresh plus the new artifact');
  if(deposit)assert(ownedCount+dueCount<5,'Original Deposit checks refreshed inventory <5 before adding the artifact');

  const queue=read('fixture-5-account.json'),carried=read('fixture-artifact_arrival-account.json');
  const arrivalType=params.find(p=>p.name==='arrivals')?.type.type;
  const artifactKey=deposit?'artifacts':'arrival_artifacts',locationKey=deposit?'artifact_locations':'arrival_artifact_locations';
  const artifactType=params.find(p=>p.name===artifactKey)?.type.type;
  assert(arrivalType&&artifactType,'Missing original arrival/artifact types');
  const gear=revive(artifactType,carried.wire.source_arrival_artifacts[0],addressOptions);
  assert.equal(gear.artifact_type,13n,'Already executed carried fixture is a neutral Gear');
  assert.equal(asBigInt(gear.owner),asBigInt(runtime.admin),'Do not silently reassign frozen carried ownership');
  assert.equal(asBigInt(gear.controller),asBigInt(runtime.admin));
  assert.equal(state.arrivals.length,20);assert.equal(state[artifactKey].length,20);assert.equal(state[locationKey].length,20);
  const arrivals=[],ids=[],extraSeeds=[];
  // Separate deterministic Field domains for Find2, Find5 and Deposit5. No IDs
  // depend on contract addresses, clock, candidate label or block-number drift.
  const domain=BigInt((deposit?200:100)+count);
  for(let i=0;i<count;i++){
    const arrival=revive(arrivalType,queue.wire.target_arrivals[i],addressOptions);
    assert.equal(arrival.to_planet,BigInt(base.location),'Use the original target location / geometry');
    assert.equal(asBigInt(arrival.player),asBigInt(state.planet.owner),'All arrivals must remain friendly');
    assert.equal(arrival.carried_artifact_id,0n);
    assert(arrival.arrival_time>0n&&arrival.arrival_time<=state.timestamp,'Original source arrival must be due');
    const arrivalId=(1n<<190n)+(domain<<32n)+BigInt(i+1);
    const artifactId=(1n<<210n)+(domain<<32n)+BigInt(i+1);
    assert(arrivalId<FIELD_MODULUS&&artifactId<FIELD_MODULUS);
    arrival.id=arrivalId;arrival.carried_artifact_id=artifactId;
    if(deposit&&i===count-1){
      assert(state.timestamp<carriedDepositFutureTime,'The fifth Deposit voyage must still be in the future');
      arrival.arrival_time=carriedDepositFutureTime;
    }
    const location={planet_id:0n,voyage_id:arrivalId,last_updated:1n};
    state.arrivals[i]=arrival;state[artifactKey][i]=clone(gear);state[locationKey][i]=location;
    state.planet_events_state.events[i].id=arrivalId;
    arrivals.push(arrivalId);ids.push(artifactId);
    extraSeeds.push(seed('arrival',arrivalId,arrival),seed('artifact',artifactId,gear),seed('artifact_location',artifactId,location));
  }
  state.planet_events_state.count=BigInt(count);
  assert.equal(new Set(ids.map(String)).size,count);assert.equal(new Set(arrivals.map(String)).size,count);
  for(const id of ids){
    assert(!state.planet_artifacts_state.ids.some(owned=>owned===id),'Carried and owned IDs must not alias');
    if(deposit)assert.notEqual(id,state.artifact_id,'Carried and deposited IDs must not alias');
  }
  // Refresh does not write Arrival or Artifact preimages. Their real seeds must
  // remain unchanged; the real original action determines all updated locations.
  const unchangedSeeds=extraSeeds.filter(s=>s.store==='arrival'||s.store==='artifact').map(clone);
  const seeds=original.seeds.map(s=>s.store==='planet_events'&&asBigInt(s.id)===state.location_id
    ?seed(s.store,s.id,state.planet_events_state):clone(s));
  seeds.push(...extraSeeds);
  assert.equal(new Set(seeds.map(s=>`${s.store}:${asBigInt(s.id)}`)).size,seeds.length,'Never seed conflicting preimages for one namespace/key');
  // V8 compact batch layout: scalar (descriptor,key,root,state) records plus
  // four-word nonempty batch header and four words per nonzero Location item.
  // Find writes only due changes; Deposit writes all nonzero origin-count items,
  // including the future fifth Location with its original voyage retained.
  const locationBatchItems=deposit?count:dueCount;
  const scalarWords=deposit?(35+25+25+16+6):(35+25+25+16+6+11);
  const planWords=scalarWords+4+4*locationBatchItems;
  assert(planWords>128&&planWords<=384,'Fixture must target retained full397 commit transport');
  return {input:state,seeds,unchangedSeeds,configUpdates:original.configUpdates,extra:{...original.extra,
    caseId,newExtensionOutsideOriginal49:true,queueCount:count,carriedCount:count,dueCount,futureCount:count-dueCount,
    initialInventoryCount:ownedCount,inventoryAfterDueArrivals:ownedCount+dueCount,inventoryAfterActionCapacityBound:ownedCount+dueCount+1,
    carriedArtifactIds:ids,arrivalIds:arrivals,immutableFullFieldIds:true,
    depositFutureArrivalTime:deposit?carriedDepositFutureTime:undefined,
    sourceQueueFixture:'fixture-5-account.json',sourceQueueFixtureSha256:queue.sha256,
    artifactTemplateFixture:'fixture-artifact_arrival-account.json',artifactTemplateFixtureSha256:carried.sha256,
    canonicalV8LocationBatchItems:locationBatchItems,canonicalV8PlanWords:planWords,canonicalV8ExpectedCommit:'commit_plan(([Field;397]))',
    entropyPolicy:deposit?'No Find entropy involved':'Fresh common seedBlock number+hash for original/V8/chunk; no artifact-ID normalization',
    originalAcceptanceRequired:true,gameplayOutputModeled:false,
    capacityExplanation:deposit?'Four due carried artifacts fill inventory to4; future fifth remains in voyage; deposited artifact fills slot5. Five all-due would violate original count<5.':'Original owned Gear + due carried artifacts + discovered artifact fit the20-slot inventory.'}};
}
