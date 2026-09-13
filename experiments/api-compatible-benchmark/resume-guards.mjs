import assert from 'node:assert/strict';

export function uniqueRow(records,key){
  const matches=records.filter(row=>Object.entries(key).every(([name,value])=>row[name]===value));
  assert(matches.length<=1,`Duplicate saved transaction identity: ${JSON.stringify(key)}`);
  return matches[0];
}

export function validateSavedRow(row,{addresses,referenceSchedule,artifactHashes,baselineVariant}={}){
  assert.equal(row.verified,true,`Saved mined row needs verification; stop before another action: ${row.variant}/${row.method}/${row.caseId}`);
  assert.equal(row.proofsEnabled,false,'Fee evidence must retain its explicit proof-disabled scope');
  assert.equal(row.receipt?.executionResult,'success','Saved receipt must contain successful mined execution');
  assert(Number.isSafeInteger(row.receipt.blockNumber)&&row.receipt.blockNumber>0&&row.receipt.blockHash,'Saved receipt must identify its mined block');
  assert(row.receipt.txEffect?.publicLogs?.length>0&&row.state?.changes?.length>0&&row.state?.roots?.length>0,'Saved receipt needs original state/effect evidence');
  if(addresses)assert.deepEqual(row.contracts,addresses,'Saved row belongs to different deployed contracts');
  if(referenceSchedule)assert.deepEqual(row.observedLiveFeeSchedule,referenceSchedule,'Saved row uses a different comparison fee schedule');
  if(artifactHashes&&row.artifactHashes)assert.deepEqual(row.artifactHashes,artifactHashes,'Saved row belongs to different compiled artifacts');
  if(baselineVariant&&row.variant!==baselineVariant){
    assert.equal(row.baselineVariant,baselineVariant,'Saved row uses a different original comparison');
    assert.equal(row.originalStateEquivalent,true,'Saved candidate state comparison must have passed');
  }
  const billed=row.gas?.billedGas;assert(billed,'Saved row needs complete billed gas');
  const calculate=prices=>BigInt(billed.daGas)*BigInt(prices.feePerDaGas)+BigInt(billed.l2Gas)*BigInt(prices.feePerL2Gas);
  assert.equal(calculate(row.actualBlockFeeSchedule),BigInt(row.receipt.transactionFee),'Saved billed gas must still reconcile exactly to the mined fee');
  assert.equal(calculate(row.observedLiveFeeSchedule),BigInt(row.feeAtObservedLivePriceWei),'Saved comparison fee must use the full billed gas');
  return row;
}

export function assertNoOrphanSubmission(hasSubmittedBytes,row,label){
  assert(!hasSubmittedBytes||row,`Unreconciled submitted transaction exists for ${label}; inspect its exact saved bytes and receipt before retrying, never create a new transaction automatically`);
}

export async function validateCanonicalReceipt(row,{getReceipt,getBlockHash}){
  const label=`${row.variant}/${row.method}/${row.caseId}`;
  const live=await getReceipt(row.receipt.txHash);
  assert(live?.executionResult==='success',`Saved transaction is no longer successfully mined: ${label}`);
  assert.equal(live.blockNumber,row.receipt.blockNumber,`Saved transaction changed blocks: ${label}`);
  assert.equal(live.blockHash?.toString(),row.receipt.blockHash,`Saved transaction block changed: ${label}`);
  assert.equal(BigInt(live.transactionFee),BigInt(row.receipt.transactionFee),`Saved transaction fee changed: ${label}`);
  const blockHash=await getBlockHash(row.receipt.blockNumber);
  assert.equal(blockHash?.toString(),row.receipt.blockHash,`Saved transaction block was pruned or replaced: ${label}`);
}
