import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {AztecAddress} from '@aztec/aztec.js/addresses';
import {buildCarriedArrivalCase} from './carried-arrival-fixtures.mjs';
import {callerParameters} from './abi-utils.mjs';
import {serializeFields,json} from './fixtures.mjs';
const artifactRoot=process.env.CARRIED_FIXTURE_ARTIFACTS??'/tmp/df-fee-tools/artifacts/baseline';
const load=name=>JSON.parse(fs.readFileSync(`${artifactRoot}/${name}.json`));
const artifacts={move:load('move-Move'),core:load('core-Core')};
const fixture=name=>new URL(`./seed-fixtures/${name}`,import.meta.url);
const original=JSON.parse(fs.readFileSync(fixture('fixture-5-account.json')));
const runtime={artifacts,admin:AztecAddress.fromBigIntUnsafe(BigInt(original.source_planet.owner))};
const base={timestamp:1800000000n};
for(const method of ['move','refresh_planet'])for(const count of [5,20])test(`${method} ${count} distinct carried arrivals preserves original witnesses and seeds full typed preimages`,()=>{
  const filename=`fixture-${count}-account.json`,before=fs.readFileSync(fixture(filename),'utf8');
  const snapshot=json(base),built=buildCarriedArrivalCase({runtime,method,caseId:`carried_arrivals_${count}`,base});
  assert.equal(fs.readFileSync(fixture(filename),'utf8'),before);assert.equal(json(base),snapshot);
  const expectedSides=method==='move'?2:1;
  assert.equal(built.seeds.filter(s=>s.store==='artifact').length,count*expectedSides);
  assert.equal(built.seeds.filter(s=>s.store==='artifact_location').length,count*expectedSides);
  assert.equal(built.seeds.filter(s=>s.store==='arrival').length,count*expectedSides);
  const ids=built.seeds.filter(s=>s.store==='artifact').map(s=>s.id);
  assert.equal(new Set(ids).size,count*expectedSides);assert(ids.every(id=>id>1n<<128n));
  const bySeed=new Map(built.seeds.map(s=>[`${s.store}:${s.id}`,s.state]));
  for(const side of method==='move'?['source','target']:['single']){
    const key=suffix=>side==='single'?suffix:`${side}_${suffix}`;
    const arr=built.input[key('arrivals')],pe=built.input[key('planet_events_state')],pa=built.input[key('planet_artifacts_state')];
    assert.equal(pe.count,BigInt(count));assert.equal(pa.count,0n);
    for(let i=0;i<count;i++){
      assert.equal(arr[i].id,pe.events[i].id);assert(arr[i].arrival_time<=base.timestamp);
      assert.deepEqual(bySeed.get(`arrival:${arr[i].id}`),arr[i]);
      assert.deepEqual(bySeed.get(`artifact:${arr[i].carried_artifact_id}`),built.input[key('arrival_artifacts')][i]);
      assert.deepEqual(bySeed.get(`artifact_location:${arr[i].carried_artifact_id}`),built.input[key('arrival_artifact_locations')][i]);
      assert.equal(built.input[key('arrival_artifact_locations')][i].voyage_id,arr[i].id);
    }
    // Only carried identity/preimages were changed; original arrival timing,
    // combat, active ordering, and inactive arrays remain identical.
    const frozen=JSON.parse(before),prefix=side==='single'?'source':side;
    for(let i=0;i<20;i++){
      const got=JSON.parse(json(arr[i])),wanted={...frozen[`${prefix}_arrivals`][i]};
      if(i<count)wanted.carried_artifact_id=got.carried_artifact_id;
      got.player='0x'+BigInt(got.player).toString(16).padStart(64,'0');
      wanted.player='0x'+BigInt(wanted.player).toString(16).padStart(64,'0');
      assert.deepEqual(got,wanted);
    }
  }
  const fn=artifacts[method==='move'?'move':'core'].functions.find(f=>f.name===method);
  for(const parameter of callerParameters(fn))assert(serializeFields(parameter.type,built.input[parameter.name]).length>0);
  const seedArtifact=built.seeds.find(s=>s.store==='artifact');seedArtifact.state.last_updated=77n;
  const key=method==='move'?'source_arrival_artifacts':'arrival_artifacts';assert.equal(built.input[key][0].last_updated,1n);
  assert.equal(built.extra.gameplayOutputModeled,false);assert.equal(built.extra.requiresOriginalAcceptance,true);
});
test('unknown labels and not-yet-due frozen inputs fail before producing seeds',()=>{
 assert.throws(()=>buildCarriedArrivalCase({runtime,method:'move',caseId:'5',base}),/distinct/);
 assert.throws(()=>buildCarriedArrivalCase({runtime,method:'move',caseId:'carried_arrivals_5',base:{timestamp:1n}}),/due/);
});
