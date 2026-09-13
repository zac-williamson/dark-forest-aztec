// Offline fixture reconstruction against original ABI; no node or wallet.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {loadContractArtifact} from '@aztec/stdlib/abi';
import {AztecAddress} from '@aztec/aztec.js/addresses';
import {plan,phases,ordinaryCoverage,edgeCoverage,extensionCoverage,sponsorCoverage,validateMoveOrder} from './run-plan-v5.mjs';
import {uniqueRow,validateSavedRow} from './resume-guards.mjs';
import {assertFixtureReplay} from './fixture-replay.mjs';
import {files} from './runtime.mjs';
import {makeBase,addressOptions} from './base-fixture.mjs';
import {template} from './fixtures.mjs';
import {buildCoreCase} from './core-fixtures.mjs';
import {buildQueueCase} from './queue-fixtures.mjs';
import {buildPublicCase,publicSpecs} from './public-fixtures.mjs';
import {buildArtifactCase} from './artifact-fixtures.mjs';
const coverage=[...ordinaryCoverage,...edgeCoverage,...extensionCoverage,...sponsorCoverage];
assert.equal(ordinaryCoverage.length,28);assert.equal(coverage.length,45);assert.equal(new Set(coverage.map(x=>JSON.stringify(x))).size,45);
assert(!Object.hasOwn(phases,'profileFixtures'));assert.equal(plan.transactionProofsEnabled,false);
const actions=Object.values(phases).flat().filter(step=>step.program==='run.mjs');
const originalSteps=actions.filter(step=>step.args[0]===plan.baseline);assert.equal(originalSteps.length,1);assert.equal(originalSteps[0].env.BENCH_METHODS,'find_artifact');
assert.equal(originalSteps[0].env.BENCH_CASES,plan.freshBaselineRequired[0].caseId);
assert(phases.first4.findIndex(s=>s.id==='initialize-first')<phases.first4.findIndex(s=>s.id==='fresh-find-candidate'));
for(const step of Object.values(phases).flat()){
 assert.equal(step.env.RAYON_NUM_THREADS,'2');assert.equal(step.env.HARDWARE_CONCURRENCY,'2');
}
for(const step of actions.filter(s=>s.args[0]!==plan.baseline)){
 assert.equal(step.args[0],plan.candidate);assert.equal(step.args[1],plan.candidateArtifacts);
 assert.equal(step.env.BENCH_ASSERT_BASELINE_FIXTURE,'1');assert(!Object.keys(step.env).some(k=>/PROFILE|PROVE|TRACE/.test(k)));
}
const dir=new URL('./',import.meta.url),state=new URL('.state/',dir);
const records=JSON.parse(fs.readFileSync(new URL('results/transactions.json',dir)));validateMoveOrder(records,plan.baseline);
const loadFixture=(method,caseId='ordinary',paymentMode='account')=>JSON.parse(fs.readFileSync(new URL(`${plan.baseline}-${method}-${caseId}${paymentMode==='sponsored'?'-sponsored':''}.json`,state)));
const account=caseId=>{const saved=loadFixture('initialize_player',caseId);return AztecAddress.fromStringUnsafe(saved.actor??saved.admin);};
const accounts=[account('ordinary'),account('init_unused_padding'),account('init_existing_planet')];
const rawArtifacts=Object.fromEntries(Object.entries(files).map(([role,file])=>[role,JSON.parse(fs.readFileSync(`${plan.originalArtifacts}/${file}`))]));
const artifacts=Object.fromEntries(Object.entries(rawArtifacts).map(([role,raw])=>[role,loadContractArtifact(raw)]));
const retained=['common-config.json','shared-seed-block-v4.json'];
const fingerprint=()=>Object.fromEntries(retained.map(file=>[file,createHash('sha256').update(fs.readFileSync(new URL(file,state))).digest('hex')]));
const originalFiles=fingerprint();process.env.BENCH_FIND_PAIR='v4';
const verified=[];
for(const key of coverage.filter(key=>key.method!=='find_artifact')){
 const row=uniqueRow(records,{variant:plan.baseline,...key});assert(row,`Missing original ${JSON.stringify(key)}`);validateSavedRow(row);
 const saved=loadFixture(key.method,key.caseId,key.paymentMode),system=saved.system;
 const runtime={artifacts,rawArtifacts,accounts,admin:accounts[0],node:{getBlock:async()=>({header:{globalVariables:{timestamp:BigInt(saved.input.timestamp??1001)-1n}}})}};
 const base=await makeBase(runtime),input=template(rawArtifacts[system],key.method,addressOptions);
 const builder=key.caseId!=='ordinary'&&['move','refresh_planet'].includes(key.method)?buildQueueCase:
   publicSpecs.some(([,method])=>method===key.method)?buildPublicCase:system.startsWith('artifact_')?buildArtifactCase:buildCoreCase;
 const fixture=await builder({runtime,system,method:key.method,caseId:key.caseId,base,input});
 const actor=Object.hasOwn(fixture,'actor')?fixture.actor:runtime.admin;
 assertFixtureReplay(fixture,saved,{...key,system,actor,contracts:row.contracts});
 verified.push({...key,actor:actor.toString()});
}
assert.equal(verified.length,44);assert.deepEqual(fingerprint(),originalFiles,'Offline reconstruction must not rewrite shared configuration/seed files');
console.log(JSON.stringify({passed:true,offline:true,noNodeOrWalletOpened:true,candidate:plan.candidate,nativeDirectory:plan.candidateArtifacts,pairs:45,cachedOriginalFixturesExactlyReconstructed:verified.length,newOriginalRequired:plan.freshBaselineRequired,moveAllocationIDs:Array.from({length:13},(_,i)=>i+2)}));
