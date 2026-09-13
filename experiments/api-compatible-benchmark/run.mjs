import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {Fr} from '@aztec/aztec.js/fields';
import {TxHash} from '@aztec/stdlib/tx';
import {poseidon2Hash} from '@aztec/foundation/crypto/poseidon';
import {openRuntime,stateDirectory,resultsDirectory,findFunction,files,auxiliaryFiles} from './runtime.mjs';
import {makeBase,configure,addressOptions} from './base-fixture.mjs';
import {template,json,serializeFields} from './fixtures.mjs';
import {buildCoreCase} from './core-fixtures.mjs';
import {buildPublicCase,publicSpecs} from './public-fixtures.mjs';
import {buildQueueCase} from './queue-fixtures.mjs';
import {uniqueRow,validateSavedRow,assertNoOrphanSubmission,validateCanonicalReceipt} from './resume-guards.mjs';
import {assertFixtureReplay} from './fixture-replay.mjs';
import {decodeActionEvents} from './event-effects.mjs';

const specs=[['core','initialize_player'],['core','reveal_location'],['core','upgrade_planet'],['core','withdraw_silver'],['core','refresh_planet'],['admin','safe_set_owner'],['move','move'],['artifact_prospect','prospect_planet'],['artifact_find','find_artifact'],['artifact_valut','deposit_artifact'],['artifact_valut','withdraw_artifact'],['artifact_valut','give_spaceships'],['artifact_action','activate_artifact'],['artifact_action','deactivate_artifact']];
const runtime=await openRuntime(process.argv[2]??'baseline',process.argv[3]??'/tmp/df-fee-tools/artifacts/baseline');
const reportPath=new URL('transactions.json',resultsDirectory),records=fs.existsSync(reportPath)?JSON.parse(fs.readFileSync(reportPath)):[];
const schedule=JSON.parse(fs.readFileSync(new URL('../../docs/fee-benchmark/common-fee-schedule.json',import.meta.url)));
const selected=process.env.BENCH_METHODS?.split(',');
const prepareOnly=process.env.BENCH_PREPARE_ONLY==='1';
const traceOnly=process.env.BENCH_TRACE_ONLY==='1';
if(runtime.finalTxGate){
  assert(!traceOnly&&!prepareOnly,'Final transaction gate is reserved for actual V6 fee transactions');
  assert(!process.env.BENCH_PROFILE_NODE_PID,'Final transaction gate keeps diagnostic profiling disabled');
}
const baselineVariant=process.env.BENCH_BASELINE_VARIANT??'baseline';
const execFileAsync=promisify(execFile);
const profileMethods=(process.env.BENCH_PROFILE_METHODS??'initialize_player,refresh_planet,move').split(',');
const roleByAddress=Object.fromEntries(Object.entries(runtime.addresses).map(([role,address])=>[address,role]));
const artifactFiles={...files,...auxiliaryFiles};
const artifactHashes=Object.fromEntries(Object.keys(runtime.rawArtifacts).map(role=>[role,createHash('sha256').update(fs.readFileSync(path.join(runtime.artifactDirectory,artifactFiles[role]))).digest('hex')]));
const cases=(process.env.BENCH_CASES??'ordinary').split(',');
const selectedCases=(process.env.BENCH_PUBLIC==='1'?publicSpecs:specs).flatMap(([system,method])=>cases.map(caseId=>[system,method,caseId])).filter(([,method])=>!selected||selected.includes(method));
const canonicalReader={
  getReceipt:hash=>runtime.node.getTxReceipt(TxHash.fromString(hash)),
  // SDK5.2 getBlock returns BlockResponse (hash property); getBlockData is a
  // separate API whose BlockData response uses blockHash.
  getBlockHash:async number=>(await runtime.node.getBlock(number))?.hash,
};
if(!prepareOnly&&!traceOnly){
  // Check the entire selected batch before setup or fixture mutations. A failed
  // row or uncertain earlier broadcast must not be hidden by normal skip logic.
  for(const [,method,caseId] of selectedCases){
    const existing=uniqueRow(records,{variant:runtime.variant,method,caseId,paymentMode:runtime.paymentMode});
    const submitted=new URL(`traces/${runtime.variant}-${method}-${caseId}-${runtime.paymentMode}.submitted-tx.bin`,resultsDirectory);
    assertNoOrphanSubmission(fs.existsSync(submitted),existing,`${runtime.variant}/${method}/${caseId}`);
    if(existing){
      validateSavedRow(existing,{addresses:runtime.addresses,referenceSchedule:schedule,artifactHashes,baselineVariant});
      await validateCanonicalReceipt(existing,canonicalReader);
    }
    if(runtime.variant!==baselineVariant){
      const original=uniqueRow(records,{variant:baselineVariant,method,caseId,paymentMode:runtime.paymentMode});
      assert(original?.verified,`Verified original pair required before configuration: ${method}/${caseId}`);
      await validateCanonicalReceipt(original,canonicalReader);
    }
  }
}
await configure(runtime,await makeBase(runtime));

async function inspect(receipt,timestamp,method,{verifyStoredRoots=true}={}){
  const {changes,latest}=decodeActionEvents(receipt,timestamp,method,{roleByAddress,rawArtifacts:runtime.rawArtifacts});
  const roots=[];
  for(const {role,id,fields} of latest.values()){
    const expected=(await poseidon2Hash(fields.map(value=>new Fr(value)))).toBigInt();
    if(verifyStoredRoots){
      const getter=runtime.artifacts[role].functions.find(fn=>fn.name==='get_state_root_unconstrained');
      const key=getter.parameters[0].type.kind==='struct'?addressOptions.addressFromBigInt(id):id;
      const actual=(await runtime.contracts[role].methods.get_state_root_unconstrained(key).simulate(runtime.opts)).result;
      assert.equal(BigInt(actual.toString()),expected,`${role} stored root must equal every exact event state field`);
    }
    roots.push({store:role,id,root:expected});
  }
  return {changes,roots};
}

for(const [system,method,caseId] of selectedCases){
  if(!prepareOnly&&!traceOnly&&uniqueRow(records,{variant:runtime.variant,method,caseId,paymentMode:runtime.paymentMode}))continue;
  if(runtime.variant!==baselineVariant&&!prepareOnly&&!traceOnly){
    const original=uniqueRow(records,{variant:baselineVariant,method,caseId,paymentMode:runtime.paymentMode});
    assert(original?.verified,`Verified original pair required before fixture mutation: ${method}/${caseId}`);
    await validateCanonicalReceipt(original,canonicalReader);
  }
  const base=await makeBase(runtime),input=template(runtime.rawArtifacts[system],method,addressOptions);
  const builder=/^carried_arrivals_(5|20)$/.test(caseId)?(await import('./carried-arrival-fixtures.mjs')).buildCarriedArrivalCase:caseId!=='ordinary'&&['move','refresh_planet'].includes(method)?buildQueueCase:process.env.BENCH_PUBLIC==='1'?buildPublicCase:system.startsWith('artifact_')?(await import('./artifact-fixtures.mjs')).buildArtifactCase:buildCoreCase;
  const fixture=await builder({runtime,system,method,caseId,base,input});
  const actor=Object.hasOwn(fixture,'actor')?fixture.actor:runtime.admin;assert(actor,'Fixture requires an available funded test actor');
  if(process.env.BENCH_ASSERT_BASELINE_FIXTURE==='1'&&runtime.variant!==baselineVariant){
    const original=uniqueRow(records,{variant:baselineVariant,method,caseId,paymentMode:runtime.paymentMode});
    assert(original?.verified,'Exact fixture replay requires its verified original receipt');
    const filename=`${baselineVariant}-${method}-${caseId}${runtime.paymentMode==='sponsored'?'-sponsored':''}.json`;
    const bytes=fs.readFileSync(new URL(filename,stateDirectory)),saved=JSON.parse(bytes);
    fixture.replay={...assertFixtureReplay(fixture,saved,{method,system,caseId,actor,contracts:original.contracts}),
      originalFixture:filename,originalFixtureSHA256:createHash('sha256').update(bytes).digest('hex')};
  }
  const actionOptions={...runtime.opts,from:actor};
  if(method==='move'&&!prepareOnly&&!traceOnly){
    const previous=records.filter(row=>row.variant===runtime.variant&&row.method==='move');
    const lastAllocated=previous.reduce((latest,row)=>{
      validateSavedRow(row,{addresses:runtime.addresses,referenceSchedule:schedule,artifactHashes,baselineVariant});
      const arrivals=row.state.changes.filter(change=>change.store==='arrival');assert.equal(arrivals.length,1,'Move must retain one exact allocated arrival');
      const id=BigInt(arrivals[0].id);return id>latest?id:latest;
    },1n);
    const actual=BigInt(String((await runtime.contracts.arrival.methods.get_event_id_counter_unconstrained().simulate(runtime.opts)).result));
    assert.equal(actual,lastAllocated,'Arrival counter advanced outside the saved benchmark receipts; reconcile it before seeding or sending another Move');
    if(runtime.variant!==baselineVariant){
      const original=uniqueRow(records,{variant:baselineVariant,method,caseId,paymentMode:runtime.paymentMode});
      assert(original?.verified,'Move requires its verified original pair before any fixture mutation');
      const expected=original.state.changes.filter(change=>change.store==='arrival');assert.equal(expected.length,1);
      assert.equal(actual+1n,BigInt(expected[0].id),'Next candidate arrival ID must exactly match its original pair');
    }
  }
  if(method==='find_artifact'){
    const remaining=BigInt(await runtime.node.getBlockNumber())-base.seedBlock.number+BigInt((fixture.configUpdates??[]).length+Math.ceil(fixture.seeds.length/(runtime.paymentMode==='sponsored'?4:5))+2);
    assert(remaining<256n,'Find historical block would expire during setup; run both variants with a new identical BENCH_FIND_PAIR and BENCH_CASES label');
  }
  for(const update of fixture.configUpdates??[])await runtime.contracts.config.methods[update.method](...update.args).send(runtime.opts);
  await runtime.batch(fixture.seeds.map(seed=>runtime.contracts[seed.store].methods.set(seed.id,seed.state)));
  // Only time itself changes after setup. Seeded planet/arrival timestamps remain exact witnesses.
  const latest=await runtime.node.getBlock('latest');fixture.input.timestamp=BigInt(latest.header.globalVariables.timestamp)+1n;
  fs.writeFileSync(new URL(`${runtime.variant}-${method}-${caseId}${runtime.paymentMode==='sponsored'?'-sponsored':''}.json`,stateDirectory),json({system,method,caseId,input:fixture.input,seeds:fixture.seeds,unchangedSeeds:fixture.unchangedSeeds,extra:fixture.extra,replay:fixture.replay,contracts:runtime.addresses,admin:runtime.admin,actor}));
  if(prepareOnly){console.log('PREPARED',runtime.variant,method,caseId);continue;}
  const abi=findFunction(runtime.artifacts[system],method);
  const call=runtime.contracts[system].methods[method](...abi.parameters.map(parameter=>fixture.input[parameter.name]));
  const diagnosticPublicSimulation=!!process.env.BENCH_PROFILE_NODE_PID&&profileMethods.includes(method);
  const toggleProfile=mode=>execFileAsync(process.execPath,[fileURLToPath(new URL('./set-owned-node-profile.mjs',import.meta.url)),process.env.BENCH_PROFILE_NODE_PID,mode]);
  const diagnosticFile='/tmp/df-api-compatible-avm-calls.jsonl';
  const diagnosticOffset=(traceOnly||diagnosticPublicSimulation)&&fs.existsSync(diagnosticFile)?fs.statSync(diagnosticFile).size:0;
  const traceDirectory=new URL('traces/',resultsDirectory);fs.mkdirSync(traceDirectory,{recursive:true});
  const traceStem=`${runtime.variant}-${method}-${caseId}-${runtime.paymentMode}`;
  let sim,simulationMs,simulatedOriginalStateEquivalent,finalTransactionGate;
  async function checkPublicOutput(){
    fs.writeFileSync(new URL(`${traceStem}.public-output.json`,traceDirectory),json({gas:sim.gasUsed,publicOutput:sim.publicOutput,simulationMs,diagnosticPublicSimulation,contracts:runtime.addresses,finalTransactionGate}));
    if(process.env.BENCH_ASSERT_BASELINE_FIXTURE==='1'&&runtime.variant!==baselineVariant){
      const original=uniqueRow(records,{variant:baselineVariant,method,caseId,paymentMode:runtime.paymentMode});
      assert(sim.publicOutput?.txEffect,'Whole transaction simulation must expose actual prospective public effects');
      const global=sim.publicOutput.globalVariables;
      const preview=await inspect({blockNumber:Number(global.blockNumber),txEffect:sim.publicOutput.txEffect},
        process.env.BENCH_PUBLIC==='1'?BigInt(global.timestamp):fixture.input.timestamp,method,{verifyStoredRoots:false});
      assert.deepEqual(preview.changes,original.state.changes,
        'Prospective whole-transaction effects differ from the historical pair; preserve the fixture and measure a fresh original pair before sending this candidate');
      simulatedOriginalStateEquivalent=true;
    }
  }
  if(!runtime.finalTxGate){
    if(diagnosticPublicSimulation)await toggleProfile('on');
    const simulationStart=performance.now();
    try{sim=await runtime.wallet.simulateTx(await call.request(actionOptions),{from:actor,fee:runtime.opts.fee});}
    finally{if(diagnosticPublicSimulation)await toggleProfile('off');}
    simulationMs=performance.now()-simulationStart;
    fs.writeFileSync(new URL(`${traceStem}.simulated-tx.bin`,traceDirectory),(await sim.toSimulatedTx()).toBuffer());
    await checkPublicOutput();
  }
  if((traceOnly||diagnosticPublicSimulation)&&fs.existsSync(diagnosticFile))fs.writeFileSync(new URL(`${traceStem}.avm-calls.jsonl`,traceDirectory),fs.readFileSync(diagnosticFile).subarray(diagnosticOffset));
  if(traceOnly){
    console.log('TRACED',runtime.variant,method,'publicL2',sim.gasUsed.publicGas.l2Gas);continue;
  }
  const originalSend=runtime.finalTxGate?undefined:runtime.wallet.aztecNode.sendTx.bind(runtime.wallet.aztecNode);
  if(runtime.finalTxGate){
    assert.equal(process.env.BENCH_ASSERT_BASELINE_FIXTURE,'1','The final transaction must pass the full original-effect gate');
    runtime.finalTxGate.arm({beforeSend:async({tx,hash,publicOutput,billedGas})=>{
      sim={publicOutput,gasUsed:publicOutput.gasUsed};
      assert.equal(BigInt(sim.gasUsed.billedGas.daGas),billedGas.daGas);assert.equal(BigInt(sim.gasUsed.billedGas.l2Gas),billedGas.l2Gas);
      finalTransactionGate={transactionHash:hash.toString(),feeEnforcementEnabled:true,standalonePrivateSimulation:false,scope:'Exact final transaction public execution before broadcast',
        comparisonScope:'Before broadcast: normalized ordered original game event fields. After mining: exact stored roots against complete emitted state and exact unchanged seeded roots.'};
      await checkPublicOutput();
      assert.equal(simulatedOriginalStateEquivalent,true);
      // This is the genuine final wallet transaction, not an earlier stub-account
      // estimate. The adapter verifies its bytes/hash and forwards this same object.
      fs.writeFileSync(new URL(`${traceStem}.submitted-tx.bin`,traceDirectory),tx.toBuffer());
      fs.writeFileSync(new URL(`${traceStem}.final-tx-gate.json`,traceDirectory),json({method,caseId,...finalTransactionGate,billedGas,normalizedOrderedOriginalEventsEquivalent:true}));
    }});
  }else runtime.wallet.aztecNode.sendTx=async tx=>{
    fs.writeFileSync(new URL(`${traceStem}.submitted-tx.bin`,traceDirectory),tx.toBuffer());return originalSend(tx);
  };
  const sendStart=performance.now();let sent;
  try{sent=await call.send(actionOptions);}
  finally{if(runtime.finalTxGate)runtime.finalTxGate.disarm();else runtime.wallet.aztecNode.sendTx=originalSend;}
  const sendMs=performance.now()-sendStart;
  const receipt=await runtime.node.getTxReceipt(sent.receipt.txHash,{includeTxEffect:true});
  if(runtime.finalTxGate){assert(finalTransactionGate&&sim);assert.equal(receipt.txHash.toString(),finalTransactionGate.transactionHash,'Mined receipt must belong to the exact transaction gated and journaled before send');}
  const billed=sim.gasUsed.billedGas,block=await runtime.node.getBlock(receipt.blockNumber),actualPrice=block.header.globalVariables.gasFees;
  const actualFee=BigInt(billed.daGas)*actualPrice.feePerDaGas+BigInt(billed.l2Gas)*actualPrice.feePerL2Gas;
  assert.equal(actualFee,BigInt(receipt.transactionFee),'Full billed fee must equal mined receipt fee');
  const fee=BigInt(billed.daGas)*BigInt(schedule.feePerDaGas)+BigInt(billed.l2Gas)*BigInt(schedule.feePerL2Gas);
  const record=JSON.parse(json({variant:runtime.variant,baselineVariant,system,method,caseId,actor,paymentMode:runtime.paymentMode,proofsEnabled:false,diagnosticPublicSimulation,inputTimestamp:fixture.input.timestamp,gas:sim.gasUsed,observedLiveFeeSchedule:schedule,feeAtObservedLivePriceWei:fee,actualBlockFeeSchedule:actualPrice,receipt,contracts:runtime.addresses,artifactHashes,simulationMs,sendMs,verified:false}));
  if(finalTransactionGate)record.finalTransactionGate=finalTransactionGate;
  if(fixture.replay)record.fixtureReplay=fixture.replay;
  if(simulatedOriginalStateEquivalent)record.simulatedOriginalStateEquivalent=true;
  records.push(record);fs.writeFileSync(reportPath,json(records));
  try{
    record.state=JSON.parse(json(await inspect(receipt,process.env.BENCH_PUBLIC==='1'?BigInt(block.header.globalVariables.timestamp):fixture.input.timestamp,method)));
    if(fixture.unchangedSeeds?.length){
      record.state.unchangedRoots=[];
      for(const seed of fixture.unchangedSeeds){
        const type=findFunction(runtime.artifacts[seed.store],'set').parameters.at(-1).type;
        const expected=await poseidon2Hash(serializeFields(type,seed.state).map(value=>new Fr(value)));
        const actual=(await runtime.contracts[seed.store].methods.get_state_root_unconstrained(seed.id).simulate(runtime.opts)).result;
        assert.equal(BigInt(actual.toString()),expected.toBigInt(),`${seed.store}: unused original state must remain unchanged`);
        record.state.unchangedRoots.push({store:seed.store,id:seed.id.toString(),root:expected.toString()});
      }
    }
    const original=records.find(row=>row.variant===baselineVariant&&row.method===method&&row.caseId===caseId&&row.paymentMode===runtime.paymentMode);
    if(runtime.variant!==baselineVariant){
      assert(original?.verified,`A verified original comparison is required for ${method}/${caseId}`);
      assert.deepEqual(record.state.changes,original.state.changes,`Exact original ordered state ${method}`);record.originalStateEquivalent=true;
      assert.deepEqual(record.state.unchangedRoots,original.state.unchangedRoots,`Exact original unchanged state ${method}`);
    }
    record.verified=true;
  }catch(error){record.verificationError=error.message;fs.writeFileSync(reportPath,json(records));throw error;}
  fs.writeFileSync(reportPath,json(records));console.log('ACTION',runtime.variant,method,'FJ',Number(fee)/1e18,'exact roots verified');
}
await runtime.close();
