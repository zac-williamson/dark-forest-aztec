// Coordinated local runtime regression. No gameplay transaction is broadcast:
// the real original private APIs run with proving disabled and every public
// continuation must stop at a particular custom-verifier rejection.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createAztecNodeClient} from '@aztec/aztec.js/node';
import {Contract,BatchCall} from '@aztec/aztec.js/contracts';
import {publishContractClass} from '@aztec/aztec.js/deployment';
import {AztecAddress} from '@aztec/aztec.js/addresses';
import {loadContractArtifact} from '@aztec/stdlib/abi';
import {getContractClassFromArtifact} from '@aztec/stdlib/contract';
import {TxHash} from '@aztec/stdlib/tx';
import {resolveAssertionMessageFromRevertData} from '@aztec/simulator/client';
import {GasFees} from '@aztec/stdlib/gas';
import {poseidon2Hash} from '@aztec/foundation/crypto/poseidon';
import {EmbeddedWallet} from '@aztec/wallets/embedded';
import {registerInitialLocalNetworkAccountsInWallet} from '@aztec/wallets/testing';
import {files,auxiliaryFiles,findFunction} from '../../experiments/api-compatible-benchmark/runtime.mjs';
import {revive,json} from '../../experiments/api-compatible-benchmark/fixtures.mjs';
import {clone} from '../../experiments/api-compatible-benchmark/base-fixture.mjs';
import {storageInvocation} from './invocation.mjs';
import {buildBatchVerifierCase,expectedVerifierBatches,batchFields,batchRoles} from './caller-batch-fixtures.mjs';
import {decodeKnownRevert} from './known-revert.mjs';
import {storageRoleFromParameter,validateBatchResume} from './batch-runtime-utils.mjs';

assert.equal(process.env.RUN_CALLER_BATCH,'1','Wait for the coordinated mutation window, then set RUN_CALLER_BATCH=1');
const configuration=storageInvocation('batch-caller-regressions');
const baselineArtifacts=process.env.CALLER_BASELINE_ARTIFACTS??'/tmp/df-fee-tools/artifacts/baseline';
const baselineVariant=process.env.CALLER_BASELINE_VARIANT??'baseline-v2';
const state=path.dirname(configuration.deployment),deployment=JSON.parse(fs.readFileSync(configuration.deployment));
const callerFile=process.env.CALLER_BATCH_ARTIFACT??new URL('./caller-batch/target/caller_sensitive_batch-CallerSensitiveBatch.json',import.meta.url);
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const address=value=>AztecAddress.fromStringUnsafe(value);
const addressOptions={addressFromBigInt:value=>AztecAddress.fromBigIntUnsafe(value)};
const artifacts={original:{},candidate:{}},provenance={};
function load(file){const bytes=fs.readFileSync(file),raw=JSON.parse(bytes);assert.equal(raw.transpiled,true,'Use genuine native artifacts');
 return {artifact:loadContractArtifact(raw),file:String(file),sha256:hash(bytes),raw};}
for(const [variant,folder]of [['original',baselineArtifacts],['candidate',configuration.artifacts]]){
 provenance[variant]={};
 for(const role of variant==='original'?['core','move','artifact_valut']:Object.keys({...files,...auxiliaryFiles})){
  const entry=load(path.join(folder,files[role]??auxiliaryFiles[role]));artifacts[variant][role]=entry.artifact;provenance[variant][role]={file:entry.file,sha256:entry.sha256};
 }
}
const caller=load(callerFile);provenance.customBatch={file:caller.file,sha256:caller.sha256};
assert.equal(caller.artifact.functions.filter(f=>f.functionType==='private').length,0,'Fixture must have zero private functions');
const snapshots={};
for(const [key,role,method,caseId]of [['core','core','refresh_planet','ordinary'],['move','move','move','ordinary'],['queuedMove','move','move','1'],['artifact_valut','artifact_valut','give_spaceships','ordinary']]){
 const file=process.env[`CALLER_BATCH_${key.toUpperCase()}_FIXTURE`]??path.join(state,`${baselineVariant}-${method}-${caseId}.json`);
 const bytes=fs.readFileSync(file),saved=JSON.parse(bytes);assert.equal(saved.system,role);assert.equal(saved.method,method);
 snapshots[key]={file,sha256:hash(bytes),saved,input:Object.fromEntries(findFunction(artifacts.original[role],method).parameters.map(p=>[p.name,revive(p.type,saved.input[p.name],addressOptions)]))};
}
assert(!fs.existsSync(configuration.output),'Choose a new output path to preserve previous evidence');
const fixtureProvenance=Object.fromEntries(Object.entries(snapshots).map(([role,{file,sha256}])=>[role,{file,sha256}]));
const resumePath=process.env.CALLER_BATCH_RESUME_FROM;
const resume=resumePath?validateBatchResume(JSON.parse(fs.readFileSync(resumePath)),{configuration,provenance,fixtures:fixtureProvenance}):undefined;
const checks=clone(resume?.checks??[]),receipts=clone(resume?.receipts??[]),isolated=clone(resume?.isolated??{});
const report={status:'preparing',passed:false,configuration,proverEnabled:false,gameplayTransactionsSubmitted:0,
 scope:'Original private Refresh/Give/Move entry points, proof-disabled public execution with isolated System/store clones. Custom view verifier checks actual caller and every original batch word, returns false or a distinctive sentinel. Asymmetric queues distinguish Move source and target; no static-call counter is assumed. This is compatibility evidence, not Fee Juice or proof evidence.',
 artifactProvenance:provenance,fixtures:fixtureProvenance,isolated,receipts,checks,
 resumedFrom:resume?{file:resumePath,sha256:hash(fs.readFileSync(resumePath)),retainedChecks:76,retainedSetupReceipts:61,pendingRoles:['artifact_valut','move']}:undefined};
const save=()=>{fs.mkdirSync(path.dirname(configuration.output),{recursive:true});fs.writeFileSync(configuration.output+'.tmp',json(report)+'\n');fs.renameSync(configuration.output+'.tmp',configuration.output);};
const check=(label,evidence={})=>{checks.push({label,passed:true,...evidence});console.log('PASS',label);save();};
const node=createAztecNodeClient(configuration.nodeUrl);
const wallet=await EmbeddedWallet.create(node,{pxe:{dataDirectory:fs.mkdtempSync(path.join(os.tmpdir(),'df-api-batch-caller-')),proverEnabled:false}});
try{
 const accounts=await registerInitialLocalNetworkAccountsInWallet(wallet),admin=accounts[0];
 for(const snapshot of Object.values(snapshots))assert.equal(snapshot.saved.admin,admin.toString(),'Use exact original fixture account');
 const opts={from:admin,fee:{gasSettings:{maxFeesPerGas:new GasFees(0n,100000000000000n)}},wait:{waitForStatus:'checkpointed',timeout:180}};
 if(resume)for(const saved of receipts){
  const receipt=await node.getTxReceipt(TxHash.fromString(saved.txHash));assert.equal(receipt.executionResult,'success',`Resume receipt failed: ${saved.label}`);
  const block=await node.getBlock(receipt.blockNumber);assert.equal(block.hash.toString(),receipt.blockHash.toString(),`Resume receipt not canonical: ${saved.label}`);
 }
 const read=async(c,method,...args)=>(await c.methods[method](...args).simulate(opts)).result;
 async function sent(interaction,label){const result=await interaction.send(opts);receipts.push({label,txHash:result.receipt.txHash.toString()});save();return result;}
 async function batch(calls,label){for(let i=0;i<calls.length;i+=4)await sent(new BatchCall(wallet,calls.slice(i,i+4)),`${label} ${i/4}`);}
 async function deploy(artifact,args,label){
  if(resume){
   const saved=isolated[label];assert(saved,`Missing resumed deployment: ${label}`);
   const instance=await node.getContract(address(saved.address)),expected=(await getContractClassFromArtifact(artifact)).id;
   assert(instance&&instance.currentContractClassId.equals(expected),`${label} resumed class mismatch`);assert.equal(saved.currentClassId,expected.toString());
   await wallet.registerContract(instance,artifact);return Contract.at(instance.address,artifact,wallet);
  }
  let contract;
  try{contract=(await sent(Contract.deploy(wallet,artifact,args),label)).contract;}
  catch(error){if(!String(error.message).includes('network only admits'))throw error;
   await sent(await publishContractClass(wallet,artifact),label+' class publication');
   const result=await Contract.deploy(wallet,artifact,args).send({...opts,skipClassPublication:true});contract=result.contract;receipts.push({label,txHash:result.receipt.txHash.toString()});save();
  }
  const instance=await node.getContract(contract.address),expected=(await getContractClassFromArtifact(artifact)).id;
  assert(instance&&instance.currentContractClassId.equals(expected),`${label} exact class mismatch`);
  isolated[label]={address:contract.address.toString(),currentClassId:expected.toString()};save();return contract;
 }
 const shared={};
 for(const role of ['backend','core_settlement_worker','vault_settlement_worker','planet_revealed_coords']){
  const encoded=deployment[role]??(role==='backend'?(deployment.state_backend??deployment.game_state_backend):undefined);assert(encoded,`Missing ${role}`);
  const instance=await node.getContract(address(encoded)),expected=(await getContractClassFromArtifact(artifacts.candidate[role])).id;
  assert(instance&&instance.currentContractClassId.equals(expected),`${role} deployed class does not match final artifact`);
  await wallet.registerContract(instance,artifacts.candidate[role]);shared[role]=await Contract.at(instance.address,artifacts.candidate[role],wallet);
 }
 const stores={};
 for(const role of ['world','planet','planet_artifacts','planet_events','arrival','artifact','artifact_location','player'])stores[role]=await deploy(artifacts.candidate[role],[admin],'isolated '+role);
 if(!resume)await batch(Object.values(stores).map(store=>store.methods.set_state_backend(shared.backend.address)),'bind isolated namespaces');
 for(const [role,store]of Object.entries(stores))assert((await read(store,'get_state_backend_unconstrained')).equals(shared.backend.address),`${role} must be canonically bound`);
 const config=await deploy(artifacts.candidate.config,[admin],'isolated canonical Config');
 const moveInput=snapshots.move.input,configCalls=[];
 for(const key of ['snark_config','world_config','game_config_core','planet_level_thresholds','space_junk_config','artifacts_config'])configCalls.push(config.methods[`set_${key}`](moveInput[key]));
 if(!resume){
  await batch(configCalls,'isolated Move config');
  for(let tier=0;tier<4;tier++)await sent(config.methods.set_planet_type_weights_tier(BigInt(tier),moveInput[`planet_type_weights_tier_${tier}`]),`isolated config tier${tier}`);
  await sent(config.methods.set_planet_default_stats(moveInput.target_level,moveInput.planet_default_stats),'isolated target stats');
 }
 const systems={original:{},candidate:{}},custom={};
 for(const variant of ['original','candidate']){
  custom[variant]=await deploy(caller.artifact,[admin],`${variant} custom batch verifier`);
  for(const role of ['core','move','artifact_valut']){
   const system=await deploy(artifacts[variant][role],[admin],`${variant} ${role}`);systems[variant][role]=system;
   if(variant==='candidate'&&!resume){
    const calls=[system.methods.set_state_backend(shared.backend.address)];
    if(role!=='move')calls.push(system.methods.set_state_worker(shared[role==='core'?'core_settlement_worker':'vault_settlement_worker'].address));
    await batch(calls,`${variant} ${role} backend wiring`);
   }
   if(!resume)await batch(Object.values(stores).map(store=>store.methods.add_authorized_contract(system.address)),`${variant} ${role} writer grants`);
  }
 }
 async function rejects(interaction,reason,label,evidence={}){
  let error,revertData;try{await interaction.simulate(opts);}catch(e){
   error=String(e.message??e);revertData=e.revertData?.map(value=>value.toString());
   // Static public simulations bypass normal PXE error enrichment. Resolve
   // actual returned selectors only, using the fixture's verified native ABI.
   if(!error.includes(reason)){
    const role={refresh_planet:'core',give_spaceships:'artifact_valut',move:'move'}[evidence.method];
    const abis=[caller.artifact.functions.find(f=>f.name==='public_dispatch')];
    if(role&&evidence.variant)abis.push(artifacts[evidence.variant][role].functions.find(f=>f.name==='public_dispatch'));
    const decoded=decodeKnownRevert(e,abis,resolveAssertionMessageFromRevertData);
    if(decoded&&!error.includes(decoded))error+=decoded;
   }
  }
  assert(error?.includes(reason),`${label}: expected ${reason}; got ${error?.slice(0,1800)??'success'}`);
  check(label,{expectedRejection:reason,revertData,...evidence});
 }
 // The test contract's initial caller is the real admin. Independently check
 // both complete zero arrays, including every inactive index, before gameplay.
 for(const arrayName of resume?[]:['ids','hashes'])for(let index=0;index<20;index++){
  const ids=Array(20).fill(0n),hashes=Array(20).fill(0n);(arrayName==='ids'?ids:hashes)[index]=1n;
  await rejects(custom.original.methods.verify_hashes_batch(ids,hashes,0n),arrayName==='ids'?'Zero batch IDs changed':'Zero batch hashes changed',`fixture observes ${arrayName}[${index}] at count0`);
 }
 const stateTypes=Object.fromEntries(batchRoles.map(role=>[role,findFunction(artifacts.candidate[role],'set').parameters.at(-1).type]));
 const hashFields=async fields=>(await poseidon2Hash(fields)).toBigInt();
 const snapshotState=async seeds=>({roots:await Promise.all(seeds.map(async seed=>[seed.store,String(seed.id),String(await read(stores[seed.store],'get_state_root_unconstrained',seed.id))])),
  arrivalCounter:String(await read(stores.arrival,'get_event_id_counter_unconstrained'))});
 const mismatch=(role,store,side='Source')=>role==='move'?`${side} ${store==='arrival'?'arrival':store==='artifact'?'artifact':'artifact location'} hash mismatch`
  :role==='core'?`${store==='arrival'?'Arrival':store==='artifact'?'Artifact':'Artifact location'} hash mismatch`
  :`${store==='arrival'?'arrivals':store==='artifact'?'artifacts':'artifact locations'} hash mismatch`;
 for(const role of resume?['artifact_valut','move']:['core','artifact_valut','move'])for(const shape of role==='move'?['empty','source0_target1','source1_target0']:['empty']){
  const method=role==='core'?'refresh_planet':role==='move'?'move':'give_spaceships';
  const built=buildBatchVerifierCase(snapshots[role].input,role,{shape,queuedMove:snapshots.queuedMove.input});
  await batch(built.seeds.map(seed=>stores[seed.store].methods.set(seed.id,seed.state)),`${method}/${shape} exact isolated seeds`);
  const expected=await expectedVerifierBatches(built.input,role,{stateTypes,hashFields});
  for(const store of batchRoles){
   const nonzero=expected.find(b=>b[store].count!==0n)?.[store];
   const nonzeroCommitment=nonzero?await hashFields(batchFields(nonzero)):0n;
   const modes=shape==='empty'?[{name:'false',zero:1n,nonzero:0n,reason:mismatch(role,store)},{name:'sentinel',zero:2n,nonzero:0n,reason:'Original zero batch observed'}]
    :shape==='source0_target1'?[{name:'source-first',zero:2n,nonzero:2n,reason:'Original zero batch observed'},
     {name:'target-nonzero-false',zero:0n,nonzero:1n,reason:mismatch(role,store,'Target')}]
    :[{name:'target-zero',zero:2n,nonzero:0n,reason:'Original zero batch observed'},
     {name:'source-first',zero:2n,nonzero:2n,reason:'Original nonzero batch observed'},
     {name:'target-zero-false',zero:1n,nonzero:0n,reason:mismatch(role,store,'Target')}];
   for(const variant of ['original','candidate']){
    const system=systems[variant][role],callee=custom[variant];
    const wireArgs=findFunction(artifacts[variant][role],'set_all_storage_addresses').parameters.map(p=>{
     const key=storageRoleFromParameter(p.name);
     return key===store?callee.address:key==='config'?config.address:(stores[key]??shared[key]).address;
    });
    await sent(system.methods.set_all_storage_addresses(...wireArgs),`${variant} ${method}/${shape} replace only ${store}`);
    for(const mode of modes){
     await sent(callee.methods.set_expectations(system.address,mode.zero,mode.nonzero,nonzero?.count??1n,nonzeroCommitment),`${variant} ${method}/${shape}/${store} ${mode.name}`);
     const before=await snapshotState(built.seeds),input=clone(built.input);
     // Seed/configure before freezing freshness. The batch preimage consists of
     // original historical witnesses; the top-level action time never enters it.
     input.timestamp=BigInt((await node.getBlock('latest')).header.globalVariables.timestamp);
     await rejects(callee.methods.verify_hashes_batch(Array(20).fill(0n),Array(20).fill(0n),0n),'Batch verifier caller changed',`${variant} ${method}/${shape}/${store}/${mode.name} rejects direct account caller`);
     const abi=findFunction(artifacts[variant][role],method);
     await rejects(system.methods[method](...abi.parameters.map(p=>input[p.name])),mode.reason,`${variant} ${method}/${shape}/${store}/${mode.name} preserves original verifier behavior`,{
      variant,method,shape,store,mode,originalPrivateApi:true,system:system.address.toString(),customVerifier:callee.address.toString(),inputSha256:hash(json(input)),
      expectedBatches:expected.map(b=>b[store]),nonzeroCommitment,nonzeroCountWithAllZeroIds:!!nonzero&&nonzero.ids.every(id=>id===0n),timestamp:input.timestamp,
     });
     assert.deepEqual(await snapshotState(built.seeds),before,'Reverting simulations must leave every isolated seeded root and Arrival counter unchanged');
     check(`${variant} ${method}/${shape}/${store}/${mode.name} preserves isolated state and counter`);
    }
   }
  }
 }
 report.status='complete';report.passed=true;save();console.log('COMPLETE',checks.length,'custom verifier fallback checks');
}catch(error){report.status='failed';report.error=String(error.message??error).slice(0,2400);save();throw new Error(report.error.slice(0,800));}
finally{await wallet.stop();}
