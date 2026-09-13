// Offline validation against the exact original ABI and already saved fixtures.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {loadContractArtifact} from '@aztec/stdlib/abi';
import {AztecAddress} from '@aztec/aztec.js/addresses';
import {plan,phases,ordinaryCoverage,edgeCoverage,extensionCoverage,sponsorCoverage} from './run-plan-v4.mjs';
import {buildArtifactCase} from './artifact-fixtures.mjs';
import {revive,template,serializeFields} from './fixtures.mjs';
import {addressOptions} from './base-fixture.mjs';

const coverage=[...ordinaryCoverage,...edgeCoverage,...extensionCoverage,...sponsorCoverage];
assert.equal(ordinaryCoverage.length,28);assert.equal(coverage.length,45);
assert.equal(new Set(coverage.map(row=>JSON.stringify(row))).size,45);
const first=phases.first4;
assert(first.findIndex(step=>step.id==='initialize-first')<first.findIndex(step=>step.id==='fresh-find-candidate'),'Find writes Player; fresh initialization must precede it');
assert(first.findIndex(step=>step.id==='configure-identically')<first.findIndex(step=>step.env.BENCH_FIND_PAIR==='v4'),'Create the new seed only after final configuration');
for(const group of [phases.remaining28,phases.edges,phases.extended,phases.sponsored]){
  for(let i=0;i<group.length;i+=2){
    assert.equal(group[i].args[0],plan.baseline);assert.equal(group[i+1].args[0],plan.candidate);
    assert.deepEqual(group[i].env,group[i+1].env,'Each pair must use the same case/payment/seed controls');
  }
}

const raw=JSON.parse(fs.readFileSync('/tmp/df-fee-tools/artifacts/baseline/artifact_find-ArtifactFind.json'));
const artifact=loadContractArtifact(raw),abi=artifact.functions.find(fn=>fn.name==='find_artifact');
const saved=JSON.parse(fs.readFileSync(new URL('.state/baseline-v2-find_artifact-ordinary.json',import.meta.url)));
const input=Object.fromEntries(abi.parameters.map(p=>[p.name,revive(p.type,saved.input[p.name],addressOptions)]));
const admin=AztecAddress.fromStringUnsafe(saved.admin);
const base={...input,admin,location:input.location_id,perlin:input.biomebase,
  snark_config:input.provided_snark_config,planetArtifacts:input.planet_artifacts_state,
  planetEvents:input.planet_events_state,artifact:input.owned_artifacts[0],artifactLocation:input.owned_artifact_locations[0],
  seedBlock:{number:BigInt(saved.extra.fixedSeedBlock.number),hash:BigInt(saved.extra.fixedSeedBlock.hash)}};
const build=caseId=>buildArtifactCase({runtime:{admin},method:'find_artifact',caseId,base,input:template(raw,'find_artifact',addressOptions)});
const ordinary=build('ordinary');
for(const caseId of ['find_v4','find_v4_profile']){
  const fixture=build(caseId);
  for(const parameter of abi.parameters)assert.deepEqual(serializeFields(parameter.type,fixture.input[parameter.name]),serializeFields(parameter.type,ordinary.input[parameter.name]),`${caseId}: a bookkeeping label must not alter ${parameter.name}`);
  assert.deepEqual(fixture.seeds,ordinary.seeds);assert.deepEqual(fixture.configUpdates,ordinary.configUpdates);
  assert.equal(fixture.input.provided_snark_config.disable_zk_checks,false);
  assert.equal(fixture.extra.fixedSeedBlock.number,base.seedBlock.number);
}
console.log(JSON.stringify({offline:true,plannedPairs:coverage.length,ordinaryPairs:ordinaryCoverage.length,
  freshFindLabels:['find_v4','find_v4_profile'],findOriginalABIAndPayloadEquivalent:true,noNodeOrWalletOpened:true}));
