// Recover exactly one confirmed mined instance after a deployment wait timeout.
// Reads chain data and updates only the local address cache; never sends a tx.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createAztecNodeClient} from '@aztec/aztec.js/node';
import {ContractInstancePublishedEvent} from '@aztec/protocol-contracts/instance-registry';
const [variant,role,native,number]=process.argv.slice(2);assert(variant&&role&&native&&number);
const manifest=JSON.parse(fs.readFileSync(`${native}/build-provenance.json`));
const item=manifest.artifacts.find(item=>item.file.startsWith(`${role}-`));assert(item);
const node=createAztecNodeClient('http://127.0.0.1:8097');
const block=await node.getBlock(Number(number),{includeTransactions:true});assert(block?.body);
const matches=[];
for(const effect of block.body.txEffects)for(const event of ContractInstancePublishedEvent.extractContractInstanceEvents(effect.privateLogs)){
  if(event.contractClassId.toString()===item.classId)matches.push({event,txHash:effect.txHash});
}
assert.equal(matches.length,1,'Require exactly one mined instance of the expected frozen class');
const {event,txHash}=matches[0],receipt=await node.getTxReceipt(txHash);
assert.equal(receipt.executionResult,'success');assert.equal(receipt.blockNumber,Number(number));assert.equal(receipt.blockHash.toString(),block.hash.toString());
const live=await node.getContract(event.address);assert(live);assert.equal(live.currentContractClassId.toString(),item.classId);
const file=new URL(`.state/${variant}-deployments.json`,import.meta.url),saved=JSON.parse(fs.readFileSync(file));
assert(!saved[role]||saved[role]===event.address.toString(),'Refuse conflicting saved deployment');
saved[role]=event.address.toString();fs.writeFileSync(file,JSON.stringify(saved,null,2)+'\n');
const report={variant,role,address:event.address.toString(),classId:item.classId,blockNumber:Number(number),blockHash:block.hash.toString(),txHash:txHash.toString(),receipt,verified:true,noTransactionSent:true};
fs.writeFileSync(new URL(`results/${variant}-${role}-reconciled-deployment.json`,import.meta.url),JSON.stringify(report,(_key,value)=>typeof value==='bigint'?value.toString():value,2)+'\n');
console.log(JSON.stringify({verified:true,variant,role,address:saved[role],block:Number(number),txHash:txHash.toString(),noTransactionSent:true}));
