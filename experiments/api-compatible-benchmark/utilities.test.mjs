import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {compareApi,callerParameters} from './abi-utils.mjs';
import {template,assertEquivalent,zeroValue,serializeFields,revive} from './fixtures.mjs';
const core=JSON.parse(fs.readFileSync('/tmp/df-fee-tools/artifacts/baseline/core-Core.json'));
const planet=JSON.parse(fs.readFileSync('/tmp/df-fee-tools/artifacts/baseline/planet-PlanetStorage.json'));
test('All exact original APIs pass; injected context is not a caller argument',()=>{
  assert(compareApi(core,core).compatible);
  const fn=core.functions.find(fn=>fn.name==='refresh_planet');
  assert.equal(fn.abi.parameters.length,9);assert.equal(callerParameters(fn).length,8);
  assert(!Object.hasOwn(template(core,'initialize_player'),'inputs'));
});
test('Private/public, only-self, array width and event changes are rejected',()=>{
  for(const mutation of [
    value=>{value.functions.find(fn=>fn.name==='initialize_player').custom_attributes=['abi_public'];},
    value=>{value.functions.find(fn=>fn.name==='initialize_player_public').custom_attributes=['abi_public'];},
    value=>{value.functions.find(fn=>fn.name==='refresh_planet').abi.parameters.find(p=>p.name==='arrivals').type.length=19;},
  ]){const candidate=structuredClone(core);mutation(candidate);assert(!compareApi(core,candidate).compatible);}
  const candidate=structuredClone(planet);candidate.outputs.structs.events[0].fields.reverse();assert(!compareApi(planet,candidate).compatible);
});
test('Separate nominal path changes from external field layout changes',()=>{
  const candidate=structuredClone(planet);candidate.outputs.structs.events[0].fields.find(field=>field.name==='state').type.path='other::Planet';
  const result=compareApi(planet,candidate);assert(result.compatible);assert(result.nativeSchemaChanged.length>0);
});
test('Typed arrays do not alias; padding and wide fields round-trip losslessly',()=>{
  const type={kind:'array',length:20,type:{kind:'struct',path:'Example',fields:[{name:'value',type:{kind:'integer',sign:'unsigned',width:128}}]}};
  const values=zeroValue(type);values[19].value=(1n<<128n)-1n;
  assert.equal(values[0].value,0n);assert.equal(serializeFields(type,values)[19],(1n<<128n)-1n);
  const wire=JSON.parse(JSON.stringify(values,(_,value)=>typeof value==='bigint'?value.toString():value));
  assert.deepEqual(revive(type,wire),values);
});
test('Differential checks preserve event order, IDs, nonzero tails and timestamp presence',()=>{
  const before={events:[{id:'4',time:'100',slots:['0','99']},{id:'5',time:'100',slots:['0','0']}]};
  const after=structuredClone(before);after.events[0].time='200';after.events[1].time='200';
  const beforeRules=[0,1].map(i=>({path:`events.${i}.time`,expected:'100',replacement:'@transaction_time'}));
  const afterRules=[0,1].map(i=>({path:`events.${i}.time`,expected:'200',replacement:'@transaction_time'}));
  assertEquivalent(before,after,{beforeRules,afterRules});
  for(const bad of [()=>{after.events.reverse();},()=>{after.events[0].slots[1]='0';},()=>{after.events[0].time='0';}]){
    const saved=structuredClone(after);bad();assert.throws(()=>assertEquivalent(before,after,{beforeRules,afterRules}));after.events=saved.events;
  }
});
