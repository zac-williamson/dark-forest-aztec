import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {AztecAddress} from '@aztec/aztec.js/addresses';
import {callerParameters} from './abi-utils.mjs';
import {template,revive,serializeFields,zeroValue,json} from './fixtures.mjs';
import {buildArtifactCase} from './artifact-fixtures.mjs';
import {buildCarriedArtifactActionCase,carriedDepositFutureTime} from './carried-artifact-action-fixtures.mjs';

const roots=process.env.CARRIED_ACTION_ARTIFACTS??'/tmp/df-fee-tools/artifacts/baseline';
const v8=process.env.CARRIED_ACTION_V8_SOURCE??'/tmp/df-api-compatible-v8-core-worktree';
const opts={addressFromBigInt:value=>AztecAddress.fromBigIntUnsafe(value)};
const names={find_artifact:'artifact_find-ArtifactFind',deposit_artifact:'artifact_valut-ArtifactValut'};
const roles={find_artifact:'artifact_find',deposit_artifact:'artifact_valut'};
const raw=Object.fromEntries(Object.entries(names).map(([method,name])=>[method,JSON.parse(fs.readFileSync(`${roots}/${name}.json`))]));
function setup(method){
  // These files supply previously accepted typed base states only. The test uses
  // synthetic common entropy below; it never purports to execute historical Find.
  const saved=JSON.parse(fs.readFileSync(new URL(`./.state/baseline-v2-${method}-ordinary.json`,import.meta.url)));
  const params=callerParameters(raw[method].functions.find(f=>f.name===method));
  const input=Object.fromEntries(params.map(p=>[p.name,revive(p.type,saved.input[p.name],opts)]));
  const admin=AztecAddress.fromStringUnsafe(saved.admin);
  const base={...input,admin,location:input.location_id,perlin:input.biomebase??15n,biomebase:input.biomebase,
    snark_config:input.provided_snark_config,planetArtifacts:input.planet_artifacts_state,planetEvents:input.planet_events_state,
    artifact:input.artifact??input.owned_artifacts[0],artifactLocation:input.artifact_location??input.owned_artifact_locations[0],
    seedBlock:{number:12000n,hash:(1n<<200n)+456n}};
  const runtime={admin,rawArtifacts:{[roles[method]]:raw[method]},artifacts:{[roles[method]]:raw[method]}};
  return {runtime,method,base,input:template(raw[method],method,opts)};
}
const cases=[['find_artifact','carried_find_2',2,2,130],['find_artifact','carried_find_5',5,5,142],['deposit_artifact','carried_deposit_5',5,4,131]];
for(const [method,caseId,count,due,words] of cases)test(`${caseId}: original full ABI, exact seeds and capacity-safe heavy plan`,()=>{
  const args=setup(method),before=json(args.base),inputBefore=json(args.input);
  const ordinary=buildArtifactCase({...args,caseId:'ordinary'}),built=buildCarriedArtifactActionCase({...args,caseId});
  assert.equal(json(args.base),before);assert.equal(json(args.input),inputBefore);
  assert.equal(built.extra.queueCount,count);assert.equal(built.extra.dueCount,due);assert.equal(built.extra.futureCount,count-due);
  assert.equal(built.extra.canonicalV8PlanWords,words);assert(words>128);assert.equal(built.extra.canonicalV8ExpectedCommit,'commit_plan(([Field;397]))');
  const s=built.input,artKey=method==='find_artifact'?'arrival_artifacts':'artifacts',locKey=method==='find_artifact'?'arrival_artifact_locations':'artifact_locations';
  const seedMap=new Map(built.seeds.map(x=>[`${x.store}:${String(x.id)}`,x]));
  assert.equal(seedMap.size,built.seeds.length);
  assert.equal(s.planet_events_state.count,BigInt(count));
  assert.equal(s.arrivals.slice(0,count).filter(a=>a.arrival_time<=s.timestamp).length,due);
  assert.equal(Number(s.planet_artifacts_state.count)+due+1,built.extra.inventoryAfterActionCapacityBound);
  for(let i=0;i<count;i++){
    const a=s.arrivals[i];assert.equal(a.id,s.planet_events_state.events[i].id);assert.equal(a.to_planet,s.location_id);
    assert(a.player.equals(s.planet.owner));assert(a.id>(1n<<128n));assert(a.carried_artifact_id>(1n<<200n));
    assert.deepEqual(seedMap.get(`arrival:${a.id}`).state,a);
    assert.deepEqual(seedMap.get(`artifact:${a.carried_artifact_id}`).state,s[artKey][i]);
    assert.deepEqual(seedMap.get(`artifact_location:${a.carried_artifact_id}`).state,s[locKey][i]);
    assert.equal(s[locKey][i].voyage_id,a.id);assert.equal(s[locKey][i].planet_id,0n);
    assert.equal(s[artKey][i].artifact_type,13n);assert(s[artKey][i].controller.equals(args.runtime.admin));
  }
  for(let i=count;i<20;i++)for(const key of ['arrivals',artKey,locKey])assert.deepEqual(s[key][i],ordinary.input[key][i],'Inactive full-ABI inputs remain exact');
  assert.deepEqual(s.planet_artifacts_state,ordinary.input.planet_artifacts_state);
  assert.deepEqual(seedMap.get(`planet_events:${s.location_id}`).state,s.planet_events_state);
  assert.equal(built.unchangedSeeds.length,2*count);assert(built.unchangedSeeds.every(x=>['arrival','artifact'].includes(x.store)));
  for(const p of callerParameters(raw[method].functions.find(f=>f.name===method)))assert.equal(serializeFields(p.type,s[p.name]).length,serializeFields(p.type,zeroValue(p.type,opts)).length);
  assert.equal(built.extra.originalAcceptanceRequired,true);assert.equal(built.extra.gameplayOutputModeled,false);assert.equal(built.extra.newExtensionOutsideOriginal49,true);
  const firstSeed=built.seeds.find(x=>x.store==='artifact_location'&&x.id===s.arrivals[0].carried_artifact_id);firstSeed.state.last_updated=123n;assert.equal(s[locKey][0].last_updated,1n);
  if(method==='find_artifact'){
    assert.equal(s.provided_snark_config.disable_zk_checks,false);assert.equal(s.spaceships_config.gear,true);
    assert.equal(s.planet.prospected_block_number,12000n);assert.deepEqual(built.extra.fixedSeedBlock,args.base.seedBlock);
    assert.deepEqual(s.owned_artifacts,ordinary.input.owned_artifacts);assert.deepEqual(s.owned_artifact_locations,ordinary.input.owned_artifact_locations);
  }else{
    assert.equal(s.planet.planet_type,3n);assert(s.planet.planet_level>s.artifact.rarity);
    assert.equal(s.arrivals[4].arrival_time,carriedDepositFutureTime);assert.equal(s.planet_artifacts_state.count,0n);
    assert.equal(built.extra.inventoryAfterActionCapacityBound,5);
  }
});

test('original Find entropy is provided afresh and reused exactly, while fixture IDs are stable',()=>{
  const a=setup('find_artifact'),first=buildCarriedArtifactActionCase({...a,caseId:'carried_find_5'});
  const second=buildCarriedArtifactActionCase({...a,runtime:{...a.runtime,variant:'different-candidate'},base:{...a.base,timestamp:a.base.timestamp+17n},caseId:'carried_find_5'});
  assert.deepEqual(first.seeds,second.seeds);assert.deepEqual(first.configUpdates,second.configUpdates);assert.deepEqual(first.extra.fixedSeedBlock,second.extra.fixedSeedBlock);
  assert.deepEqual(first.extra.arrivalIds,second.extra.arrivalIds);assert.deepEqual(first.extra.carriedArtifactIds,second.extra.carriedArtifactIds);
  const fresh={...a.base,seedBlock:{number:12001n,hash:(1n<<201n)+22n}};
  const third=buildCarriedArtifactActionCase({...a,base:fresh,caseId:'carried_find_5'});
  assert.equal(third.input.planet.prospected_block_number,12001n);assert.deepEqual(third.extra.fixedSeedBlock,fresh.seedBlock);
  assert.equal(Object.hasOwn(third.input,'artifact_id'),false,'Generated artifact identity is left entirely to original private execution');
  assert.throws(()=>buildCarriedArtifactActionCase({...a,base:{...a.base,seedBlock:null},caseId:'carried_find_5'}),/historical/);
});

test('Deposit five-all-due cannot pass original inventory bound; four-due/future remains a full location batch',()=>{
  const b=buildCarriedArtifactActionCase({...setup('deposit_artifact'),caseId:'carried_deposit_5'}),s=b.input;
  const occupancy=Number(s.planet_artifacts_state.count),allDue=s.arrivals.slice(0,5).length;
  assert.equal(occupancy+allDue<5,false);
  const actualDue=s.arrivals.slice(0,5).filter(a=>a.arrival_time<=s.timestamp).length;assert(occupancy+actualDue<5);
  const originalBatchItems=s.arrivals.slice(0,Number(s.planet_events_state.count)).filter(a=>a.carried_artifact_id!==0n).length;
  assert.equal(originalBatchItems,5);assert.equal(b.extra.canonicalV8LocationBatchItems,5);
  const future=s.arrivals[4],futureLocation=s.artifact_locations[4];assert.equal(futureLocation.voyage_id,future.id);assert(future.arrival_time>s.timestamp);
});

function functionBody(source,name){
  const start=source.indexOf(`fn ${name}(`);assert(start>=0,name);const open=source.indexOf('{',start);let depth=1,i=open+1;
  for(;depth;i++){assert(i<source.length);if(source[i]==='{')depth++;if(source[i]==='}')depth--;}
  return source.slice(open+1,i-1);
}
test('original source requires due-time processing and Deposit strict capacity before insertion',()=>{
  const base=new URL('../../tests/api-compatibility/baseline/sources/contracts/',import.meta.url);
  const vault=fs.readFileSync(new URL('system/artifact_valut/src/main.nr',base),'utf8');
  const privateBody=functionBody(vault,'deposit_artifact'),publicBody=functionBody(vault,'deposit_artifact_public');
  assert(privateBody.indexOf('new_planet_artifacts_state.count < 5')<privateBody.indexOf('let put_artifact_on_planet_result'));
  assert(privateBody.includes('i < origin_arrivals_count & (arrivals[i].carried_artifact_id != 0)'));
  assert(publicBody.includes('set_arrival_locations_max20(\n            artifact_ids,\n            new_artifact_locations,\n            origin_arrivals_count as u32,'));
  const lazy=fs.readFileSync(new URL('libs/src/lazy_update.nr',base),'utf8');assert(lazy.includes('if arrivals[earliest_event_index].arrival_time <= current_timestamp'));
  const freshness=functionBody(fs.readFileSync(new URL('libs/src/batch_utils.nr',base),'utf8'),'assert_planet_timestamp_freshness');
  assert(freshness.includes('timestamp >= arrivals[i].departure_time'));assert(!freshness.includes('timestamp >= arrivals[i].arrival_time'));
});

test('V8 actual scalar schemas and compact batch source independently establish 130/142/131-word plans',()=>{
  for(const [method,caseId,,due,expected] of cases){
    const source=fs.readFileSync(`${v8}/contracts/${method==='find_artifact'?'system/artifact_find':'settlement_workers/vault'}/src/main.nr`,'utf8');
    const body=functionBody(source,method==='find_artifact'?'find_artifact_public':'try_deposit_artifact_public_prepared');
    const originalPublic=raw[method].functions.find(f=>f.name===`${method}_public`);assert(originalPublic);
    const params=callerParameters(originalPublic);let scalarWords=0,scalars=0;
    for(const match of body.matchAll(/write_plan\.set\([^;]*?([a-z_]+)\.serialize\(\)\);/g)){
      const param=params.find(p=>p.name===match[1]);assert(param,match[1]);scalarWords+=3+serializeFields(param.type,zeroValue(param.type,opts)).length;scalars++;
    }
    assert.equal(scalars,method==='find_artifact'?6:5);
    const batchCount=method==='find_artifact'?due:5;assert.equal(scalarWords+4+batchCount*4,expected,caseId);
    assert(body.includes('write_plan.append_batch_item'));
    if(method==='deposit_artifact')assert(body.includes('start_batch(9, origin_arrivals_count as u32, 20)'));
    else assert(body.includes('start_batch(9, change_artifact_location_count, 20)'));
    assert(source.includes('if plan.length <= 128'));assert(source.includes('commit_plan(([Field;397]))'));
  }
  const plan=fs.readFileSync(`${v8}/contracts/libs/src/state_plan.nr`,'utf8');
  assert(plan.includes('self.append([(namespace as u32 + 64) as Field,count as Field,maximum as Field,0])'));
  assert(plan.includes('self.append([key]);\n        self.append(state);'));
});

test('invalid labels, Gear disabling, owner changes and expired future interval fail closed',()=>{
  const f=setup('find_artifact');assert.throws(()=>buildCarriedArtifactActionCase({...f,caseId:'ordinary'}),/distinct/);
  assert.throws(()=>buildCarriedArtifactActionCase({...f,caseId:'carried_find_5',base:{...f.base,spaceships_config:{...f.base.spaceships_config,gear:false}}}),/Gear/);
  const d=setup('deposit_artifact');assert.throws(()=>buildCarriedArtifactActionCase({...d,caseId:'carried_deposit_5',base:{...d.base,timestamp:carriedDepositFutureTime}}),/future/);
  assert.throws(()=>buildCarriedArtifactActionCase({...d,method:'move',caseId:'carried_deposit_5'}),/Only original/);
});
