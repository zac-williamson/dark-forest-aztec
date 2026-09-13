// Offline only: load compiled ABI schemas; no wallet, RPC, native prover or sends.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {loadContractArtifact} from '@aztec/stdlib/abi';
import {assertCallbackCoverage,assertSettlementCoverage,assertSystemPayloads,trustVersion} from './trust-routes.mjs';
const directory=process.argv[2]??'/tmp/df-api-compatible-v4-native',variant=process.argv[3]??'candidate-v4';
const load=file=>{const a=loadContractArtifact(JSON.parse(fs.readFileSync(path.join(directory,file))));return [...a.functions,...(a.nonDispatchPublicFunctions??[])];};
const backend=load('game_state_backend-GameStateBackend.json'),version=trustVersion(variant,backend);
const routes=assertSettlementCoverage(backend,version),callbacks={};
for(const file of fs.readdirSync(directory)){
 if(!/Storage\.json$/.test(file))continue;
 const f=load(file),cb=f.find(x=>/^emit_.*_fields$/.test(x.name));
 if(cb){const role=cb.name.slice(5,-7);callbacks[role]=assertCallbackCoverage(role,f,version);}
}
assert.equal(Object.keys(callbacks).length,9);
for(const [role,name] of [['core','Core'],['move','Move']])assertSystemPayloads(role,load(`${role}-${name}.json`));
console.log(JSON.stringify({passed:true,variant,version,offlineOnly:true,routes,callbacks}));
