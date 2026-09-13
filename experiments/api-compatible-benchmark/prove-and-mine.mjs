// Replay a seeded original-API fixture with a real native proof, then verify its mined state and fee.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createAztecNodeClient,waitForTx} from '@aztec/aztec.js/node';
import {Contract} from '@aztec/aztec.js/contracts';
import {AztecAddress} from '@aztec/aztec.js/addresses';
import {Fr} from '@aztec/aztec.js/fields';
import {loadContractArtifact} from '@aztec/stdlib/abi';
import {poseidon2Hash} from '@aztec/foundation/crypto/poseidon';
import {GasFees} from '@aztec/stdlib/gas';
import {TxHash,Tx} from '@aztec/stdlib/tx';
import {EmbeddedWallet} from '@aztec/wallets/embedded';
import {registerInitialLocalNetworkAccountsInWallet} from '@aztec/wallets/testing';
import {files,auxiliaryFiles,findFunction} from './runtime.mjs';
import {json} from './fixtures.mjs';

const variant=process.env.PROVED_VARIANT??'candidate-v2',method=process.env.PROVED_METHOD??'move';
const directory=process.env.PROVED_ARTIFACTS??'/tmp/df-api-compatible-v2-native';
const prepared=JSON.parse(fs.readFileSync(new URL(`.state/${variant}-${method}-ordinary.json`,import.meta.url)));
const rows=JSON.parse(fs.readFileSync(new URL('results/transactions.json',import.meta.url)));
const measured=rows.find(r=>r.variant===variant&&r.method===method&&r.caseId==='ordinary'&&r.paymentMode==='account');
const original=rows.find(r=>r.variant===(process.env.BENCH_BASELINE_VARIANT??measured?.baselineVariant??'baseline')&&r.method===method&&r.caseId==='ordinary'&&r.paymentMode==='account');
assert(original?.verified&&measured?.verified&&measured?.originalStateEquivalent,'Complete verified fee pair required before proof replay');
const node=createAztecNodeClient(process.env.AZTEC_NODE_URL??'http://127.0.0.1:8097');
const wallet=await EmbeddedWallet.create(node,{pxe:{dataDirectory:process.env.PROVED_WALLET_DIRECTORY??`/tmp/df-api-compatible-proved-${variant}-wallet52`,proverEnabled:true,proverOrOptions:{bbPath:'/tmp/df-fee-tools/node_modules/@aztec/bb.js/build/arm64-macos/bb',threads:4}}});
const [admin]=await registerInitialLocalNetworkAccountsInWallet(wallet);assert.equal(admin.toString(),prepared.admin);
const opts={from:admin,fee:{gasSettings:{maxFeesPerGas:new GasFees(0n,100000000000000n)}},wait:{waitForStatus:'checkpointed',timeout:180}};
const artifacts={},raw={},contracts={};
for(const [role,file] of Object.entries({...files,...auxiliaryFiles})){
 if(!prepared.contracts[role])continue;
 raw[role]=JSON.parse(fs.readFileSync(path.join(directory,file)));artifacts[role]=loadContractArtifact(raw[role]);
 const address=AztecAddress.fromStringUnsafe(prepared.contracts[role]);
 await wallet.registerContract(await node.getContract(address),artifacts[role]);
 contracts[role]=await Contract.at(address,artifacts[role],wallet);
}
function revive(t,v){if(t.kind==='field'||t.kind==='integer')return BigInt(v);if(t.kind==='boolean')return v;if(t.kind==='array')return v.map(x=>revive(t.type,x));if(t.path.endsWith('AztecAddress'))return AztecAddress.fromStringUnsafe(v);return Object.fromEntries(t.fields.map(f=>[f.name,revive(f.type,v[f.name])]));}
const abi=findFunction(artifacts[prepared.system],method);
assert(raw[prepared.system].functions.find(fn=>fn.name===method)?.custom_attributes.includes('abi_private'),'Proof replay must target an original private game method');
const input=Object.fromEntries(abi.parameters.map(p=>[p.name,revive(p.type,prepared.input[p.name])]));
const artifactHash=createHash('sha256').update(fs.readFileSync(path.join(directory,files[prepared.system]))).digest('hex');
const rawPath=new URL(`../../docs/api-compatibility/proved-${variant}-${method}-raw.json`,import.meta.url);
const reportPath=new URL(`../../docs/api-compatibility/proved-${variant}-${method}.json`,import.meta.url);
const transactionPath=new URL(`../../docs/api-compatibility/proved-${variant}-${method}.tx.bin`,import.meta.url);
fs.mkdirSync(new URL('./',rawPath),{recursive:true});
const saveCheckpoint=value=>{const temp=new URL(rawPath.href+'.tmp');fs.writeFileSync(temp,json(value));fs.renameSync(temp,rawPath);};
let proof;
const prove=wallet.pxe.proveTx.bind(wallet.pxe);
wallet.pxe.proveTx=async(...args)=>{const result=await prove(...args);assert.equal(result.chonkProof.isEmpty(),false);assert(result.stats?.timings?.proving>0);proof={nonempty:true,fields:result.chonkProof.fields.length,serializedBytes:result.chonkProof.toBuffer().length,sha256:createHash('sha256').update(result.chonkProof.toBuffer()).digest('hex'),timings:result.stats.timings};return result;};
let broadcastContext;
const broadcast=wallet.aztecNode.sendTx.bind(wallet.aztecNode);
wallet.aztecNode.sendTx=async(tx,...args)=>{
 assert(broadcastContext,'Broadcast must follow the measured prepared fixture');assert(proof?.nonempty,'Refuse to broadcast an empty proof');
 assert(!fs.existsSync(rawPath),'Existing proof checkpoint must resume, never create another transaction');
 const txHash=tx.getTxHash().toString(),bytes=tx.toBuffer();fs.writeFileSync(transactionPath,bytes);
 const checkpoint={...broadcastContext,proof,txHash,transactionSha256:createHash('sha256').update(bytes).digest('hex'),phase:'ready_to_broadcast'};saveCheckpoint(checkpoint);
 const result=await broadcast(tx,...args);checkpoint.phase='submitted';saveCheckpoint(checkpoint);return result;
};
function paths(t,p='state'){if(t.kind==='struct'&&t.path.endsWith('::AztecAddress'))return[p];if(t.kind==='struct')return t.fields.flatMap(f=>paths(f.type,`${p}.${f.name}`));if(t.kind==='array')return Array.from({length:t.length},(_,i)=>paths(t.type,`${p}.${i}`)).flat();return[p];}
const timeFields=new Set(['last_updated','created_at','init_timestamp','last_reveal_timestamp','minted_at_timestamp','last_activated','last_deactivated','departure_time']);
try{
 let receipt,gas,counterBefore,sendMs;
 if(fs.existsSync(rawPath)){
  const saved=JSON.parse(fs.readFileSync(rawPath));assert.equal(saved.artifactHash,artifactHash);assert.equal(saved.method,method);
  if(saved.contracts)assert.deepEqual(saved.contracts,prepared.contracts,'Resume must use the same deployed contracts');
  if(saved.input)for(const parameter of abi.parameters)input[parameter.name]=revive(parameter.type,saved.input[parameter.name]);
  gas=saved.gas;proof=saved.proof;counterBefore=BigInt(saved.counterBefore);input.timestamp=BigInt(saved.inputTimestamp);sendMs=saved.sendMs;
  const txHash=TxHash.fromString(saved.txHash??saved.receipt.txHash);
  receipt=await node.getTxReceipt(txHash,{includeTxEffect:true});
  if(!receipt.isMined()||String(receipt.status)==='proposed'){
    if(String(receipt.status)==='dropped'){
      const bytes=fs.readFileSync(transactionPath);assert.equal(createHash('sha256').update(bytes).digest('hex'),saved.transactionSha256);
      const tx=Tx.fromBuffer(bytes);assert.equal(tx.getTxHash().toString(),txHash.toString());
      // An interrupted pre-broadcast checkpoint may not have reached the node.
      // Re-send only the identical proved transaction; never generate a new nonce.
      await broadcast(tx);
    }
    await waitForTx(node,txHash,opts.wait);receipt=await node.getTxReceipt(txHash,{includeTxEffect:true});
  }
  saveCheckpoint({...saved,receipt,phase:'mined'});
 }else{
  input.timestamp=BigInt((await node.getBlock('latest')).header.globalVariables.timestamp);
  for(const name of ['snark_config','provided_snark_config'])if(input[name])assert.equal(input[name].disable_zk_checks,false);
  counterBefore=BigInt(String((await contracts.arrival.methods.get_event_id_counter_unconstrained().simulate(opts)).result));
  const call=contracts[prepared.system].methods[method](...abi.parameters.map(p=>input[p.name]));
  const simulation=await wallet.simulateTx(await call.request(opts),{from:admin,fee:opts.fee});gas=simulation.gasUsed;
  broadcastContext={artifactHash,variant,method,gas,counterBefore,inputTimestamp:input.timestamp,input,contracts:prepared.contracts,admin:prepared.admin};
  const start=performance.now(),sent=await call.send(opts);sendMs=performance.now()-start;
  assert(proof?.nonempty,'A real private proof is required');receipt=await node.getTxReceipt(sent.receipt.txHash,{includeTxEffect:true});
  const saved=JSON.parse(fs.readFileSync(rawPath));saveCheckpoint({...saved,proof,sendMs,receipt,phase:'mined'});
 }
 assert.equal(String(receipt.executionResult),'success');assert(proof.nonempty&&proof.timings.proving>0);
 const block=await node.getBlock(receipt.blockNumber),price=block.header.globalVariables.gasFees;
 const actual=BigInt(gas.billedGas.daGas)*price.feePerDaGas+BigInt(gas.billedGas.l2Gas)*price.feePerL2Gas;assert.equal(actual,BigInt(receipt.transactionFee));
 const schedule=JSON.parse(fs.readFileSync(new URL('../../docs/fee-benchmark/common-fee-schedule.json',import.meta.url)));
 const common=BigInt(gas.billedGas.daGas)*BigInt(schedule.feePerDaGas)+BigInt(gas.billedGas.l2Gas)*BigInt(schedule.feePerL2Gas);
 assert.equal(common,BigInt(measured.feeAtObservedLivePriceWei),'Actual proved transaction must retain the measured complete fee');
 const roles=Object.fromEntries(Object.entries(prepared.contracts).map(([r,a])=>[a,r])),changes=[],latest=new Map();
 const newId=counterBefore+1n,oldId=BigInt(original.state.changes.find(c=>c.store==='arrival')?.id??0);
 if(method==='move')assert(oldId>0n,'Verified original Move must contain its allocated arrival ID');
 for(const log of receipt.txEffect.publicLogs){
  const role=roles[log.contractAddress.toString()];assert(role,'Unexpected event emitter');
  const wire=log.fields.map(f=>BigInt(String(f)));assert.equal(wire[2],BigInt(receipt.blockNumber));
  assert((raw[role].outputs.structs.events??[]).length,'Unexpected public event from a non-store');
  const event=raw[role].outputs.structs.events[0],leaves=paths(event.fields.find(f=>f.name==='state').type),fields=wire.slice(3);assert.equal(fields.length,leaves.length);
  const normalized=fields.map((v,i)=>{const name=leaves[i].split('.').at(-1);if(timeFields.has(name)&&v===input.timestamp)return'@transaction_time';if(role==='arrival'&&name==='arrival_time')return`@arrival_after:${v-input.timestamp}`;if(method==='prospect_planet'&&name==='prospected_block_number'&&v===BigInt(receipt.blockNumber))return'@transaction_block';if(method==='move'&&v===newId&&((role==='arrival'&&name==='id')||(role==='planet_events'&&leaves[i].startsWith('state.events.')&&name==='id')))return String(oldId);return String(v);});
  const id=method==='move'&&role==='arrival'?(assert.equal(wire[1],newId),String(oldId)):String(wire[1]);
  changes.push({store:role,tag:String(wire[0]),id,fields:normalized});latest.set(`${role}:${wire[1]}`,{role,id:wire[1],fields});
 }
 assert.deepEqual(changes,original.state.changes,'Original ordered state must match; only explicit replay time/block and newly allocated arrival ID are normalized');
 const rootChecks=[];
 for(const {role,id,fields} of latest.values()){
  const expected=(await poseidon2Hash(fields.map(v=>new Fr(v)))).toBigInt(),getter=findFunction(artifacts[role],'get_state_root_unconstrained');
  const key=getter.parameters[0].type.kind==='struct'?AztecAddress.fromBigIntUnsafe(id):id;
  for(const name of ['get_state_root','get_state_root_unconstrained'])assert.equal(BigInt(String((await contracts[role].methods[name](key).simulate(opts)).result)),expected);
  rootChecks.push({role,id,root:expected,publicAndUtilityMatched:true});
 }
 if(method==='move'){
  assert.equal(BigInt(String((await contracts.arrival.methods.get_event_id_counter_unconstrained().simulate(opts)).result)),newId);
  const pub=(await contracts.arrival.methods.get_arrival(newId).simulate(opts)).result,util=(await contracts.arrival.methods.get_arrival_unconstrained(newId).simulate(opts)).result;
  assert.deepEqual(pub,util);assert.equal(BigInt(pub.id),newId);
 }
 const report={passed:true,scope:'Full native Aztec5.2 private transaction proof generated and internally verified, submitted to isolated local node and mined; original ordered events and both getter kinds verified. Only replay time/block and new arrival ID are normalized. No live funds.',variant,method,artifactHash,proof,sendMs,coordinateChecksEnabled:(input.snark_config??input.provided_snark_config)?.disable_zk_checks===false,orderedEventsMatched:changes.length,rootChecks,counterBefore,newArrivalId:method==='move'?newId:null,gas,actualBlockPrices:price,actualReceiptFeeWei:actual,commonPriceFeeWei:common,commonPriceFeeJuice:Number(common)/1e18,receipt};
 fs.writeFileSync(reportPath,json(report));console.log('PROVED_AND_MINED',variant,method,Number(common)/1e18,'Fee Juice');
}finally{await wallet.stop();}
