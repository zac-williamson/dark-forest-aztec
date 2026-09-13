import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {buildInactiveLocationCase,locationFields} from './caller-location-fixtures.mjs';
const bigint=value=>Array.isArray(value)?value.map(bigint):value&&typeof value==='object'
 ?Object.fromEntries(Object.entries(value).map(([key,item])=>[key,bigint(item)]))
 :typeof value==='string'&&/^(0x[0-9a-f]+|[0-9]+)$/i.test(value)?BigInt(value):value;
for(const [role,method]of [['core','refresh_planet'],['move','move']])test(`${method} retains all60 location fields and distinct source/target order`,()=>{
 const raw=JSON.parse(fs.readFileSync(new URL(`../../experiments/api-compatible-benchmark/.state/baseline-v2-${method}-ordinary.json`,import.meta.url)));
 const original=bigint(raw.input),before=structuredClone(original),built=buildInactiveLocationCase(original,role,7,1234n);
 assert.deepEqual(original,before,'Input template is not mutated');
 assert.equal(built.batches.length,role==='move'?2:1);
 for(const batch of built.batches){
  const fields=locationFields(batch.states);assert.equal(fields.length,60);assert(fields.every(field=>field!==0n));
  if(role==='core')assert.equal(batch.states[19].last_updated,1234n);
  else assert(batch.states[19].last_updated>(1n<<63n),'Move retains inactive timestamps');
  assert(batch.states[18].last_updated>(1n<<63n));assert.deepEqual(batch.ids,Array(20).fill(0n));assert.equal(batch.count,0n);
 }
 if(role==='move')assert.notDeepEqual(locationFields(built.batches[0].states),locationFields(built.batches[1].states));
});
