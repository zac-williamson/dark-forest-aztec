// Read-only node inspection; no wallet, simulation, proof, key generation or send.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createAztecNodeClient} from '@aztec/aztec.js/node';
import {AztecAddress} from '@aztec/aztec.js/addresses';
import {Fr} from '@aztec/aztec.js/fields';
import {loadContractArtifact} from '@aztec/stdlib/abi';
import {getContractClassFromArtifact} from '@aztec/stdlib/contract';
import {deriveStorageSlotInMap} from '@aztec/stdlib/hash';
import {TxHash} from '@aztec/stdlib/tx';
import {validateCanonicalReceipt} from './resume-guards.mjs';

const directory=new URL('./',import.meta.url),variant='baseline-v2';
const addresses=JSON.parse(fs.readFileSync(new URL(`.state/${variant}-deployments.json`,directory)));
const allRows=JSON.parse(fs.readFileSync(new URL('results/transactions.json',directory)));
const rows=allRows.filter(row=>row.variant===variant&&row.verified);
const manifest=JSON.parse(fs.readFileSync(new URL('results/baseline-manifest.json',directory)));
const node=createAztecNodeClient('http://127.0.0.1:8097');
const deadline=setTimeout(()=>{console.error('Read-only baseline verification exceeded90s; no wallet was opened');process.exit(1);},90000);
const block=await node.getBlockNumber();
const latestSaved=allRows.filter(row=>['baseline-v2','candidate-v2','candidate-v3'].includes(row.variant)&&row.verified).sort((a,b)=>b.receipt.blockNumber-a.receipt.blockNumber)[0];
const recordedBlock=await node.getBlock(latestSaved.receipt.blockNumber);assert(recordedBlock,'Previously mined block must still exist');
assert.equal(recordedBlock.hash.toString(),latestSaved.receipt.blockHash,'Node must retain the exact benchmark chain');
const canonicalReceipts=[];
for(const row of allRows.filter(row=>['baseline-v2','candidate-v2','candidate-v3'].includes(row.variant)&&row.verified)){
  await validateCanonicalReceipt(row,{getReceipt:hash=>node.getTxReceipt(TxHash.fromString(hash)),
    getBlockHash:async number=>(await node.getBlock(number))?.hash});
  canonicalReceipts.push({variant:row.variant,method:row.method,caseId:row.caseId,blockNumber:row.receipt.blockNumber,
    blockHash:row.receipt.blockHash,canonical:true});
}
const raw={},classes=[];
for(const [file,entry] of Object.entries(manifest.artifacts)){
  const role=file.split('-')[0],bytes=fs.readFileSync(`/tmp/df-fee-tools/artifacts/baseline/${file}`);
  assert.equal(createHash('sha256').update(bytes).digest('hex'),entry.sha256);
  raw[role]=JSON.parse(bytes);
  const expected=await getContractClassFromArtifact(loadContractArtifact(raw[role]));
  const address=AztecAddress.fromStringUnsafe(addresses[role]),actual=await node.getContract(address);
  assert(actual,`${role} original deployment is absent`);
  assert.equal(actual.currentContractClassId.toString(),expected.id.toString(),`${role} class drift`);
  classes.push({role,address:address.toString(),classId:expected.id.toString(),unchanged:true});
}
function slot(role,field){
  const fields=raw[role].outputs.globals.storage[0].fields.find(item=>item.name==='fields').value.fields;
  const value=fields.find(item=>item.name===field)?.value.fields.find(item=>item.name==='slot').value.value;
  assert(value,`Missing compiled ${role}.${field} slot`);return new Fr(BigInt(`0x${value}`));
}
const read=(role,storageSlot)=>node.getPublicStorageAt(block,AztecAddress.fromStringUnsafe(addresses[role]),storageSlot);
const lastRoots=new Map();for(const row of rows.sort((a,b)=>a.receipt.blockNumber-b.receipt.blockNumber))for(const root of row.state.roots)lastRoots.set(`${root.store}:${root.id}`,root);
const checkedRoots=[];
for(const {store,id,root} of lastRoots.values()){
  const storageSlot=await deriveStorageSlotInMap(slot(store,'state_roots'),new Fr(BigInt(id)));
  const actual=await read(store,storageSlot);assert.equal(actual.toBigInt(),BigInt(root),`${store}/${id} root drift`);
  checkedRoots.push({store,id,root:String(root),unchanged:true});
}
const priorMoves=rows.filter(row=>row.method==='move').flatMap(row=>row.state.changes.filter(change=>change.store==='arrival').map(change=>BigInt(change.id)));
const expectedCounter=priorMoves.reduce((latest,id)=>id>latest?id:latest,1n);
const counter=await read('arrival',slot('arrival','event_id_counter'));
assert.equal(counter.toBigInt(),expectedCounter,'Original arrival counter drift');
const report={variant,readOnly:true,walletOpened:false,transactionsSent:0,proofsGenerated:0,keysGenerated:0,checkedAtBlock:block,
  lastRecordedBlock:latestSaved.receipt.blockNumber,chainUnchangedSinceLastRecordedAction:block===latestSaved.receipt.blockNumber,
  canonicalReceipts,classes,roots:checkedRoots,arrivalCounter:counter.toString(),passed:true};
const file=new URL(`results/baseline-drift-before-v4-block-${block}.json`,directory);
if(fs.existsSync(file))assert.deepEqual(JSON.parse(fs.readFileSync(file)),report,'Do not overwrite a different drift observation');
else fs.writeFileSync(file,JSON.stringify(report,null,2)+'\n');
clearTimeout(deadline);
console.log(JSON.stringify({passed:true,block,chainUnchanged:report.chainUnchangedSinceLastRecordedAction,canonicalReceipts:canonicalReceipts.length,classes:classes.length,roots:checkedRoots.length,arrivalCounter:counter.toString(),walletOpened:false}));
