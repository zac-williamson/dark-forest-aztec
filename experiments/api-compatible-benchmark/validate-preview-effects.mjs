// Test the pre-send event comparator on all45 immutable V4 public simulations.
// Files only: no wallet, network request, key generation or proof.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {decodeActionEvents} from './event-effects.mjs';
import {files} from './runtime.mjs';
import {publicSpecs} from './public-fixtures.mjs';
const directory=new URL('./',import.meta.url),variant='candidate-v4';
const coverage=JSON.parse(fs.readFileSync(new URL(`results/coverage-${variant}.json`,directory))).rows;
const rows=JSON.parse(fs.readFileSync(new URL('results/transactions.json',directory)));
const rawArtifacts=Object.fromEntries(Object.entries(files).map(([role,file])=>[role,JSON.parse(fs.readFileSync(`/tmp/df-api-compatible-v4-native/${file}`))]));
for(const key of coverage){
 const row=rows.find(r=>r.variant===variant&&r.method===key.method&&r.caseId===key.caseId&&r.paymentMode===key.paymentMode);assert(row?.verified);
 const sim=JSON.parse(fs.readFileSync(new URL(`results/traces/${variant}-${key.method}-${key.caseId}-${key.paymentMode}.public-output.json`,directory))).publicOutput;
 const roleByAddress=Object.fromEntries(Object.entries(row.contracts).map(([role,address])=>[address,role]));
 const timestamp=publicSpecs.some(([,method])=>method===row.method)?BigInt(sim.globalVariables.timestamp):BigInt(row.inputTimestamp);
 const actual=decodeActionEvents({blockNumber:Number(sim.globalVariables.blockNumber),txEffect:sim.txEffect},timestamp,row.method,{roleByAddress,rawArtifacts});
 assert.deepEqual(actual.changes,row.state.changes,`${row.method}/${row.caseId}: prospective effects must match the actually verified paired output`);
}
console.log(JSON.stringify({passed:true,offline:true,immutableV4WholeTransactionPreviewsMatched:coverage.length,noWalletOrNode:true}));
