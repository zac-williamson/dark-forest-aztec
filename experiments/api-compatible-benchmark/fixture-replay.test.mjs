import test from 'node:test';
import assert from 'node:assert/strict';
import {assertFixtureReplay} from './fixture-replay.mjs';
const saved={system:'move',method:'move',caseId:'ordinary',admin:'admin',contracts:{move:'original'},input:{timestamp:'20',arrival:{id:'2',last_updated:'7'},padding:['0','9']},seeds:[{store:'arrival',id:'2',state:{owner:'admin',id:'2'}}]};
const args={system:'move',method:'move',caseId:'ordinary',actor:'admin',contracts:saved.contracts};
const fixture=()=>({input:{...structuredClone(saved.input),timestamp:90n},seeds:structuredClone(saved.seeds)});
test('only current action time can change when cached input and seed records replay',()=>{
 assert.equal(assertFixtureReplay(fixture(),saved,args).exactOriginalInputAndSeeds,true);
 for(const mutate of [f=>f.input.arrival.id='3',f=>f.input.arrival.last_updated='8',f=>f.input.padding[1]='0',f=>f.seeds[0].state.owner='other',f=>f.seeds[0].id='3']){
  const f=fixture();mutate(f);assert.throws(()=>assertFixtureReplay(f,saved,args));
 }
});
test('original deployment, action identity and actor cannot be silently substituted',()=>{
 for(const change of [{actor:'other'},{caseId:'different'},{contracts:{move:'candidate'}}])assert.throws(()=>assertFixtureReplay(fixture(),saved,{...args,...change}));
});
