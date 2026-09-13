/** Compare raw-call selectors to the actual native ABI, never a handwritten schema. */
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {loadContractArtifact,decodeFunctionSignature} from '@aztec/stdlib/abi';

const repository=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const directory=path.resolve(process.argv[2]??'contracts/target/native');
const backendDirectory=path.resolve(process.argv[3]??directory);
const load=(file,base=directory)=>loadContractArtifact(JSON.parse(fs.readFileSync(path.join(base,file),'utf8')));
const functions=artifact=>[...artifact.functions,...(artifact.nonDispatchPublicFunctions??[])];
const signatures=artifact=>new Map(functions(artifact).map(fn=>[fn.name,decodeFunctionSignature(fn.name,fn.parameters)]));
const source=relative=>fs.readFileSync(path.join(repository,relative),'utf8');
const literals=text=>[...text.matchAll(/from_signature\("([^"]+)"\)/g)].map(match=>match[1]);
const checked=[];
const workerRoutes={
  core:[],
  vault:['try_deposit_artifact_public_prepared','try_withdraw_artifact_public_prepared'],
};
const unusedWorkerRoutes={core:['try_refresh_planet_public_prepared','try_upgrade_planet_public_prepared','try_withdraw_silver_public_prepared','try_initialize_player_public_prepared'],vault:['try_give_spaceships_public_prepared']};
for(const [system,worker] of [['core','core'],['artifact_valut','vault']]){
  const file=worker==='core'?'core_settlement_worker-CoreSettlementWorker.json':'vault_settlement_worker-VaultSettlementWorker.json';
  const target=signatures(load(file));
  const sourceFile=`contracts/system/${system}/src/main.nr`;
  const strings=literals(source(sourceFile));
  assert.deepEqual([...target.keys()].filter(method=>method.startsWith('try_')).sort(),
    [...workerRoutes[worker],...unusedWorkerRoutes[worker]].sort(),'Unexpected compiled Worker route inventory');
  for(const unused of unusedWorkerRoutes[worker])assert(!strings.some(signature=>signature.startsWith(unused+'(')),
    `${sourceFile}: obsolete Worker route must remain unreachable from the System`);
  for(const method of workerRoutes[worker]){
    const signature=target.get(method);assert(signature,`Missing compiled Worker method ${method}`);
    assert(strings.includes(signature),`${sourceFile}: raw Worker call does not match compiled ${signature}`);
    checked.push({kind:'worker',source:sourceFile,target:file,method,signature});
  }
}
assert.equal(checked.filter(row=>row.kind==='worker').length,2,'Expected both active audited Vault Worker routes');
const backendFile='game_state_backend-GameStateBackend.json';
const backend=signatures(load(backendFile,backendDirectory));
const callerFiles=['admin','core','artifact_valut','artifact_action','artifact_find','artifact_prospect'].map(system=>`contracts/system/${system}/src/main.nr`)
  .concat(['core','vault'].map(worker=>`contracts/settlement_workers/${worker}/src/main.nr`));
const backendRoutes=['commit_plan_small','commit_plan_medium','commit_plan','try_settle_give_spaceships','try_settle_initialize_new','try_settle_refresh_empty'];
const unusedBackendRoutes=[]; // Selected V7 compact Core routes call both retained endpoints.
for(const method of unusedBackendRoutes){
  assert(backend.has(method),`Missing retained unused Backend route ${method}`);
  for(const file of callerFiles)assert(!literals(source(file)).some(value=>value.startsWith(method+'(')),
    `${file}: retained Backend route must remain unreachable: ${method}`);
}
for(const obsolete of ['commit_plan_small_for_system','commit_plan_for_system','commit_owner','commit_reveal'])assert(!backend.has(obsolete),`Obsolete Backend route ${obsolete}`);
for(const method of backendRoutes){
  const signature=backend.get(method);assert(signature,`Missing compiled Backend method ${method}`);
  const callers=callerFiles.filter(file=>literals(source(file)).some(value=>value.startsWith(method+'(')));
  assert(callers.length,`No generated caller of ${method}`);
  for(const file of callers){
    const matching=literals(source(file)).filter(value=>value.startsWith(method+'('));
    assert(matching.every(value=>value===signature),`${file}: raw Backend call does not match compiled ${signature}`);
  }
  checked.push({kind:'backend',sources:callers,target:backendFile,method,signature});
}
for(const [system,contract] of [['core','Core'],['artifact_valut','ArtifactValut']]){
  const target=signatures(load(`${system}-${contract}.json`));
  const file=`contracts/system/${system}/src/main.nr`;
  const fallback=literals(source(file)).filter(signature=>{
    const method=signature.slice(0,signature.indexOf('('));
    return !method.startsWith('try_')&&!backendRoutes.includes(method);
  });
  for(const signature of fallback){
    const method=signature.slice(0,signature.indexOf('('));
    assert.equal(signature,target.get(method),`${file}: original fallback selector ${method} changed`);
    checked.push({kind:'original-fallback',source:file,target:`${system}-${contract}.json`,method,signature});
  }
}
// Every manual selector in these callers must be covered, including new direct
// routes. An unexpected prefix must not silently escape the inventory checks.
for(const file of callerFiles)for(const signature of literals(source(file))){
  assert(checked.some(row=>row.signature===signature&&(row.source===file||row.sources?.includes(file))),
    `${file}: unchecked raw selector ${signature}`);
}
const report={passed:true,scope:'Native ABI selector comparison only; does not replace authorization or state-equivalence execution tests',workerTargets:2,backendTargets:6,unusedWorkerRoutes,unusedBackendRoutes,checked};
if(process.argv[4])fs.writeFileSync(process.argv[4],JSON.stringify(report,null,2)+'\n');
console.log(`PASS: ${report.workerTargets} Worker targets, ${report.backendTargets} Backend targets, and ${checked.filter(row=>row.kind==='original-fallback').length} original fallback selectors match compiled native ABIs.`);
