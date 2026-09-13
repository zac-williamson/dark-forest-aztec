import fs from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {storageRoleFromParameter,validateBatchResume} from './batch-runtime-utils.mjs';
test('every pinned original and V5 Core/Vault/Move address parameter resolves',()=>{
 for(const folder of ['/tmp/df-fee-tools/artifacts/baseline','/tmp/df-api-compatible-v5-native'])for(const file of ['core-Core.json','artifact_valut-ArtifactValut.json','move-Move.json']){
  const artifact=JSON.parse(fs.readFileSync(`${folder}/${file}`));
  const fn=artifact.functions.find(fn=>fn.name==='set_all_storage_addresses');
  const parameters=fn.abi?.parameters??fn.parameters;
  const actual=parameters.map(p=>storageRoleFromParameter(p.name));
  assert.equal(actual.length,new Set(actual).size);assert(actual.includes('arrival'));assert(actual.includes('config'));
 }
 assert.equal(storageRoleFromParameter('arrivals_storage_address'),'arrival');
 assert.equal(storageRoleFromParameter('planet_events_addr'),'planet_events');
 assert.throws(()=>storageRoleFromParameter('unknown_storage_address'),/Unrecognized/);
});
test('resume requires the exact completed Core boundary and immutable evidence',()=>{
 const file=new URL('../../docs/api-compatibility/batch-caller-regressions-candidate-v5-wiring-failed.json',import.meta.url);
 const old=JSON.parse(fs.readFileSync(file)),expected={configuration:old.configuration,provenance:old.artifactProvenance,fixtures:old.fixtures};
 assert.equal(validateBatchResume(old,expected),old);
 for(const mutate of [x=>x.checks.pop(),x=>x.proverEnabled=true,x=>x.receipts.pop(),x=>x.error='Different error',x=>x.artifactProvenance.original.core.sha256='wrong',x=>x.configuration.deployment='wrong']){
  const changed=structuredClone(old);mutate(changed);assert.throws(()=>validateBatchResume(changed,expected));
 }
});
