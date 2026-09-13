import assert from 'node:assert/strict';
import {json} from './fixtures.mjs';

// Compare the full actual input and seed records. Only the top-level action time
// is refreshed; historical state times, IDs, owners and inactive padding are exact.
export function assertFixtureReplay(generated,saved,{method,system,caseId,actor,contracts}){
  assert.equal(saved.method,method);assert.equal(saved.system,system);assert.equal(saved.caseId,caseId);
  assert.deepEqual(saved.contracts,contracts,'Original fixture and original receipt must identify the same deployment');
  assert.equal((saved.actor??saved.admin),actor.toString(),'Replay requires the original transaction actor');
  const input=value=>{const copy=JSON.parse(json(value));delete copy.timestamp;return copy;};
  assert.deepEqual(input(generated.input),input(saved.input),'Every original action input except its current timestamp must be replayed exactly');
  assert.deepEqual(JSON.parse(json(generated.seeds)),saved.seeds,'Every original seeded record must be replayed exactly');
  assert.deepEqual(generated.unchangedSeeds?JSON.parse(json(generated.unchangedSeeds)):undefined,saved.unchangedSeeds,'Every preserved original record must be replayed exactly');
  return {exactOriginalInputAndSeeds:true,onlyRefreshedInputField:Object.hasOwn(saved.input,'timestamp')?'timestamp':null};
}
