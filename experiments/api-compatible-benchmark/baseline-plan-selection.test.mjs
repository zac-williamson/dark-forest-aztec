import test from 'node:test';
import assert from 'node:assert/strict';
import {baselinePlanModule} from './baseline-plan-selection.mjs';

test('cached baseline preflight selects the requested generation without V5 leakage',()=>{
  assert.equal(baselinePlanModule('candidate-v5'),'./run-plan-v5.mjs');
  assert.equal(baselinePlanModule('candidate-v6'),'./run-plan-v6.mjs');
  assert.equal(baselinePlanModule('candidate-v6-replay'),'./run-plan-v6.mjs');
  for(const candidate of [undefined,'baseline-v2','candidate-v4','candidate-v60','candidate-v6/other'])assert.throws(()=>baselinePlanModule(candidate));
});
