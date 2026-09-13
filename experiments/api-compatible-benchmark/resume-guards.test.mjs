import fs from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {uniqueRow,validateSavedRow,assertNoOrphanSubmission,validateCanonicalReceipt} from './resume-guards.mjs';
import {validateMoveOrder} from './run-plan-v4.mjs';

const rows=JSON.parse(fs.readFileSync(new URL('results/transactions.json',import.meta.url)));
const originals=rows.filter(row=>row.variant==='baseline-v2');
const move=originals.find(row=>row.method==='move'&&row.caseId==='ordinary'&&row.paymentMode==='account');
const addresses=JSON.parse(fs.readFileSync(new URL('.state/baseline-v2-deployments.json',import.meta.url)));

test('Existing real current-chain receipts and sequential Move IDs remain resumable',()=>{
  for(const row of originals)validateSavedRow(row,{addresses});
  validateMoveOrder(rows,'baseline-v2');
  assert.equal(move.state.changes.find(change=>change.store==='arrival').id,'2');
});

test('A failed saved receipt cannot be silently skipped during resume',()=>{
  const failed=structuredClone(move);failed.verified=false;
  assert.throws(()=>validateSavedRow(failed,{addresses}),/needs verification/);
  const duplicate={variant:move.variant,method:move.method,caseId:move.caseId,paymentMode:move.paymentMode};
  assert.throws(()=>uniqueRow([move,structuredClone(move)],duplicate),/Duplicate saved transaction/);
});

test('Stale deployments and one-base-unit fee discrepancies cannot count as a verified pair',()=>{
  const stale={...addresses,move:'0x01'};
  assert.throws(()=>validateSavedRow(move,{addresses:stale}),/different deployed contracts/);
  const wrongMined=structuredClone(move);wrongMined.receipt.transactionFee=(BigInt(wrongMined.receipt.transactionFee)+1n).toString();
  assert.throws(()=>validateSavedRow(wrongMined,{addresses}),/reconcile exactly/);
  const wrongCompared=structuredClone(move);wrongCompared.feeAtObservedLivePriceWei=(BigInt(wrongCompared.feeAtObservedLivePriceWei)+1n).toString();
  assert.throws(()=>validateSavedRow(wrongCompared,{addresses}),/full billed gas/);
});

test('An interrupted submission and skipped Move predecessor stop before another transaction',()=>{
  assert.throws(()=>assertNoOrphanSubmission(true,undefined,'Move ordinary'),/Unreconciled submitted transaction/);
  assertNoOrphanSubmission(true,move,'Move ordinary');
  const outOfOrder=structuredClone(move);outOfOrder.caseId='1';outOfOrder.state.changes.find(change=>change.store==='arrival').id='3';
  assert.throws(()=>validateMoveOrder([move,outOfOrder],'baseline-v2'),/prefix of the planned/);
});

test('Pruned or replaced blocks cannot reuse previously successful fee receipts',async()=>{
  const reader={getReceipt:async()=>structuredClone(move.receipt),getBlockHash:async()=>move.receipt.blockHash};
  await validateCanonicalReceipt(move,reader);
  await assert.rejects(validateCanonicalReceipt(move,{...reader,getBlockHash:async()=>undefined}),/pruned or replaced/);
  await assert.rejects(validateCanonicalReceipt(move,{...reader,getBlockHash:async()=>'0x01'}),/pruned or replaced/);
  await assert.rejects(validateCanonicalReceipt(move,{...reader,getReceipt:async()=>({executionResult:undefined})}),/no longer successfully mined/);
  await assert.rejects(validateCanonicalReceipt(move,{...reader,getReceipt:async()=>({...move.receipt,blockNumber:move.receipt.blockNumber+1})}),/changed blocks/);
});
