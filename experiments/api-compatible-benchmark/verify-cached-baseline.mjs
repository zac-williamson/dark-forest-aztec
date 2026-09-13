// Execution-only read preflight. Never opens a wallet or assumes historical
// action post-state remains current after later fixture writes/actions.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createAztecNodeClient} from '@aztec/aztec.js/node';
import {AztecAddress} from '@aztec/aztec.js/addresses';
import {Fr} from '@aztec/aztec.js/fields';
import {TxHash} from '@aztec/stdlib/tx';
import {loadContractArtifact} from '@aztec/stdlib/abi';
import {getContractClassFromArtifact} from '@aztec/stdlib/contract';
import {uniqueRow,validateSavedRow,validateCanonicalReceipt} from './resume-guards.mjs';
import {baselinePlanModule} from './baseline-plan-selection.mjs';
const {plan,ordinaryCoverage,edgeCoverage,extensionCoverage,sponsorCoverage,validateMoveOrder}=await import(baselinePlanModule(process.argv[3]));
assert.equal(process.argv[2],plan.baseline);assert.equal(process.argv[3],plan.candidate);
const dir=new URL('./',import.meta.url),all=JSON.parse(fs.readFileSync(new URL('results/transactions.json',dir)));
const addresses=JSON.parse(fs.readFileSync(new URL(`.state/${plan.baseline}-deployments.json`,dir)));
const schedule=JSON.parse(fs.readFileSync(new URL('../../docs/fee-benchmark/common-fee-schedule.json',dir)));
const originalManifest=JSON.parse(fs.readFileSync(new URL('results/baseline-manifest.json',dir)));
const expected=[...ordinaryCoverage,...edgeCoverage,...extensionCoverage,...sponsorCoverage];
const cached=expected.filter(key=>key.method!=='find_artifact').map(key=>{const row=uniqueRow(all,{variant:plan.baseline,...key});assert(row,'Every cached original comparison is required before candidate setup');validateSavedRow(row,{addresses,referenceSchedule:schedule});return row;});
assert.equal(cached.length,44);validateMoveOrder(all,plan.baseline);
const node=createAztecNodeClient(process.env.AZTEC_NODE_URL??'http://127.0.0.1:8097');
const deadline=setTimeout(()=>{console.error('Cached-baseline read preflight exceeded90s; no wallet opened or transaction sent');process.exit(1);},90000);
const block=await node.getBlockNumber(),canonicalReceipts=[];
for(const row of cached){await validateCanonicalReceipt(row,{getReceipt:hash=>node.getTxReceipt(TxHash.fromString(hash)),getBlockHash:async number=>(await node.getBlock(number))?.hash});canonicalReceipts.push({method:row.method,caseId:row.caseId,paymentMode:row.paymentMode,txHash:row.receipt.txHash,blockNumber:row.receipt.blockNumber,blockHash:row.receipt.blockHash});}
const classes=[];let arrivalRaw;
for(const [file,entry] of Object.entries(originalManifest.artifacts)){
  const bytes=fs.readFileSync(path.join(plan.originalArtifacts,file));assert.equal(createHash('sha256').update(bytes).digest('hex'),entry.sha256);
  const role=file.split('-')[0],raw=JSON.parse(bytes);if(role==='arrival')arrivalRaw=raw;
  const cls=await getContractClassFromArtifact(loadContractArtifact(raw)),instance=await node.getContract(AztecAddress.fromStringUnsafe(addresses[role]));
  assert(instance&&instance.currentContractClassId.equals(cls.id),`${role} original live class changed`);classes.push({role,address:addresses[role],classId:cls.id.toString()});
}
const moves=all.filter(row=>row.variant===plan.baseline&&row.method==='move');
const expectedCounter=moves.reduce((max,row)=>{validateSavedRow(row);const arrivals=row.state.changes.filter(change=>change.store==='arrival');assert.equal(arrivals.length,1);const id=BigInt(arrivals[0].id);return id>max?id:max;},1n);
const fields=arrivalRaw.outputs.globals.storage[0].fields.find(item=>item.name==='fields').value.fields;
const encoded=fields.find(item=>item.name==='event_id_counter').value.fields.find(item=>item.name==='slot').value.value;
const counter=await node.getPublicStorageAt(block,AztecAddress.fromStringUnsafe(addresses.arrival),new Fr(BigInt(`0x${encoded}`)));
assert.equal(counter.toBigInt(),expectedCounter,'Original Arrival counter advanced outside its cached Move receipts');
const report={passed:true,baseline:plan.baseline,candidate:plan.candidate,checkedAtBlock:block,readOnly:true,walletOpened:false,transactionsSubmitted:0,canonicalReceipts,classes,expectedArrivalCounter:expectedCounter.toString(),actualArrivalCounter:counter.toString(),historicalPostStateRequiredToRemainCurrent:false,newOriginalRunRequired:plan.freshBaselineRequired};
const output=new URL(`results/cached-baseline-before-${plan.candidate}-block-${block}.json`,dir);
if(fs.existsSync(output))assert.deepEqual(JSON.parse(fs.readFileSync(output)),report);else fs.writeFileSync(output,JSON.stringify(report,null,2)+'\n');
clearTimeout(deadline);
console.log('CACHED_BASELINE',cached.length,'canonical receipts,',classes.length,'classes, counter',counter.toString());
