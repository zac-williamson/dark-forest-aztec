// Execute only in the coordinated mutation window. Setup uses isolated namespaces
// and System/Config clones; all gameplay calls deliberately revert in simulation.
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
import {GasFees} from '@aztec/stdlib/gas';
import {poseidon2Hash} from '@aztec/foundation/crypto/poseidon';
import {EmbeddedWallet} from '@aztec/wallets/embedded';
import {registerInitialLocalNetworkAccountsInWallet} from '@aztec/wallets/testing';
import {files,auxiliaryFiles,findFunction} from '../../experiments/api-compatible-benchmark/runtime.mjs';
import {revive,json} from '../../experiments/api-compatible-benchmark/fixtures.mjs';
import {storageInvocation} from './invocation.mjs';
import {buildInactiveLocationCase,locationFields} from './caller-location-fixtures.mjs';

assert.equal(process.env.RUN_CALLER_LOCATION,'1','Wait for the coordinated mutation window, then set RUN_CALLER_LOCATION=1');
const configuration=storageInvocation('location-caller-regressions');
const baselineArtifacts=process.env.CALLER_BASELINE_ARTIFACTS??'/tmp/df-fee-tools/artifacts/baseline';
const baselineVariant=process.env.CALLER_BASELINE_VARIANT??'baseline-v2';
const state=path.dirname(configuration.deployment),deployment=JSON.parse(fs.readFileSync(configuration.deployment));
const callerFile=process.env.CALLER_LOCATION_ARTIFACT??new URL('./caller-location/target/caller_sensitive_location-CallerSensitiveLocation.json',import.meta.url);
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const address=value=>AztecAddress.fromStringUnsafe(value);
const addressOptions={addressFromBigInt:value=>AztecAddress.fromBigIntUnsafe(value)};
const artifacts={original:{},candidate:{}},provenance={};
function load(file){const bytes=fs.readFileSync(file),raw=JSON.parse(bytes);assert.equal(raw.transpiled,true,'Use full native artifacts, never public-only diagnostics');
 return {artifact:loadContractArtifact(raw),file:String(file),sha256:hash(bytes)};}
for(const [variant,folder]of [['original',baselineArtifacts],['candidate',configuration.artifacts]]){
 provenance[variant]={};
 for(const role of variant==='original'?['core','move']:Object.keys({...files,...auxiliaryFiles})){
  const entry=load(path.join(folder,files[role]??auxiliaryFiles[role]));artifacts[variant][role]=entry.artifact;provenance[variant][role]={file:entry.file,sha256:entry.sha256};
 }
}
const caller=load(callerFile);provenance.customLocation={file:caller.file,sha256:caller.sha256};
const snapshots={};
for(const [role,method]of [['core','refresh_planet'],['move','move']]){
 const file=process.env[role==='core'?'CALLER_REFRESH_FIXTURE':'CALLER_MOVE_EMPTY_FIXTURE']??path.join(state,`${baselineVariant}-${method}-ordinary.json`);
 const bytes=fs.readFileSync(file),saved=JSON.parse(bytes);assert.equal(saved.system,role);assert.equal(saved.method,method);
 snapshots[role]={file,sha256:hash(bytes),saved,input:Object.fromEntries(findFunction(artifacts.original[role],method).parameters.map(p=>[p.name,revive(p.type,saved.input[p.name],addressOptions)]))};
}
assert(!fs.existsSync(configuration.output),'Choose a new output path to preserve previous evidence');
const checks=[],receipts=[],isolated={};
const report={status:'preparing',passed:false,configuration,proverEnabled:false,gameplayTransactionsSubmitted:0,
 scope:'Original private Refresh/Move APIs evaluated without transaction proofs, then publicly simulated through isolated original/final Systems. A custom location store checks actual caller, every inactive location field, and Move source/target batch order before a sentinel reverts all writes. Setup transactions are isolated; this is not fee or proof-latency evidence.',
 artifactProvenance:provenance,fixtures:Object.fromEntries(Object.entries(snapshots).map(([role,{file,sha256}])=>[role,{file,sha256}])),isolated,receipts,checks};
const save=()=>{fs.mkdirSync(path.dirname(configuration.output),{recursive:true});fs.writeFileSync(configuration.output+'.tmp',json(report)+'\n');fs.renameSync(configuration.output+'.tmp',configuration.output);};
const check=(label,evidence={})=>{checks.push({label,passed:true,...evidence});console.log('PASS',label);save();};
const node=createAztecNodeClient(configuration.nodeUrl);
const wallet=await EmbeddedWallet.create(node,{pxe:{dataDirectory:fs.mkdtempSync(path.join(os.tmpdir(),'df-api-location-caller-')),proverEnabled:false}});
try{
 const accounts=await registerInitialLocalNetworkAccountsInWallet(wallet),admin=accounts[0];
 for(const snapshot of Object.values(snapshots))assert.equal(snapshot.saved.admin,admin.toString(),'Use exact original fixture account');
 assert(snapshots.move.input.source_planet.owner.equals(admin));
 const opts={from:admin,fee:{gasSettings:{maxFeesPerGas:new GasFees(0n,100000000000000n)}},wait:{waitForStatus:'checkpointed',timeout:180}};
 const read=async(c,method,...args)=>(await c.methods[method](...args).simulate(opts)).result;
 async function sent(interaction,label){const result=await interaction.send(opts);receipts.push({label,txHash:result.receipt.txHash.toString()});save();return result;}
 async function batch(calls,label){for(let i=0;i<calls.length;i+=4)await sent(new BatchCall(wallet,calls.slice(i,i+4)),`${label} ${i/4}`);}
 async function deploy(artifact,args,label){
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
 // Authenticate the live final Backend/Worker and unused wired addresses. No
 // shared game state or configuration is changed by this suite.
 const shared={};
 for(const role of ['backend','core_settlement_worker','player','planet_revealed_coords']){
  const encoded=deployment[role]??(role==='backend'?(deployment.state_backend??deployment.game_state_backend):undefined);assert(encoded,`Missing ${role}`);
  const instance=await node.getContract(address(encoded)),expected=(await getContractClassFromArtifact(artifacts.candidate[role])).id;
  assert(instance&&instance.currentContractClassId.equals(expected),`${role} deployed class does not match final artifact`);
  await wallet.registerContract(instance,artifacts.candidate[role]);shared[role]=await Contract.at(instance.address,artifacts.candidate[role],wallet);
 }
 const stores={};
 for(const role of ['world','planet','planet_artifacts','planet_events','arrival','artifact'])stores[role]=await deploy(artifacts.candidate[role],[admin],'isolated '+role);
 await batch(Object.values(stores).map(store=>store.methods.set_state_backend(shared.backend.address)),'bind isolated namespaces');
 for(const [role,store]of Object.entries(stores))assert((await read(store,'get_state_backend_unconstrained')).equals(shared.backend.address),`${role} must be canonically bound`);
 const config=await deploy(artifacts.candidate.config,[admin],'isolated canonical Config');
 const moveInput=snapshots.move.input,configCalls=[];
 for(const key of ['snark_config','world_config','game_config_core','planet_level_thresholds','space_junk_config','artifacts_config'])configCalls.push(config.methods[`set_${key}`](moveInput[key]));
 await batch(configCalls,'isolated Move config');
 for(let tier=0;tier<4;tier++)await sent(config.methods.set_planet_type_weights_tier(BigInt(tier),moveInput[`planet_type_weights_tier_${tier}`]),`isolated config tier${tier}`);
 await sent(config.methods.set_planet_default_stats(moveInput.target_level,moveInput.planet_default_stats),'isolated target stats');
 const systems={original:{},candidate:{}};
 for(const variant of ['original','candidate'])for(const role of ['core','move']){
  const system=await deploy(artifacts[variant][role],[admin],`${variant} ${role}`);systems[variant][role]=system;
  if(variant==='candidate'){
   const calls=[system.methods.set_state_backend(shared.backend.address)];
   if(role==='core')calls.push(system.methods.set_state_worker(shared.core_settlement_worker.address));
   await batch(calls,`${variant} ${role} backend wiring`);
  }
  await batch(Object.values(stores).map(store=>store.methods.add_authorized_contract(system.address)),`${variant} ${role} writer grants`);
 }
 async function rejects(interaction,reason,label,evidence={}){
  let error;try{await interaction.simulate(opts);}catch(e){error=String(e.message??e);}
  assert(error?.includes(reason),`${label}: expected ${reason}, got ${error?.slice(0,1800)??'success'}`);
  check(label,{expectedRejection:reason,...evidence});
 }
 for(const [caseIndex,role]of ['core','move'].entries()){
  const method=role==='core'?'refresh_planet':'move';
  // Seed before selecting the shared action timestamp. The pending witness
  // timestamp affects only the expected action output, not these input roots.
  const seedCase=buildInactiveLocationCase(snapshots[role].input,role,caseIndex+1,0n);
  await batch(seedCase.seeds.map(seed=>stores[seed.store].methods.set(seed.id,seed.state)),`${method} isolated exact state seeds`);
  // Timestamp is frozen for both variants and all expected batches. Setup and
  // both private evaluations must remain inside the original five-minute window.
  const timestamp=BigInt((await node.getBlock('latest')).header.globalVariables.timestamp);
  const built=buildInactiveLocationCase(snapshots[role].input,role,caseIndex+1,timestamp);
  assert.deepEqual(built.seeds,seedCase.seeds,'Refreshing the action timestamp must not change any seeded witness');
  const expectedRoots=await Promise.all(built.batches.map(async b=>(await poseidon2Hash(locationFields(b.states))).toBigInt()));
  const custom={},wiring=[];
  for(const variant of ['original','candidate']){
   const system=systems[variant][role];
   custom[variant]=await deploy(caller.artifact,[system.address,expectedRoots[0],expectedRoots[1]??0n,BigInt(built.batches.length)],`${variant} ${role} caller-sensitive locations`);
   const args=findFunction(artifacts[variant][role],'set_all_storage_addresses').parameters.map(p=>{
    const key=p.name.replace(/_addr$/,'');
    if(key==='config')return config.address;if(key==='artifact_location')return custom[variant].address;
    return (stores[key==='arrivals'?'arrival':key]??shared[key]).address;
   });
   wiring.push(system.methods.set_all_storage_addresses(...args));
  }
  // Both independent Systems can be wired in one setup transaction. Keeping
  // this paired setup bounded matters because local slots advance by 60 seconds.
  await batch(wiring,`${role} original/candidate isolated wiring`);
  const snapshot=async()=>{
   const roots={};for(const seed of built.seeds)roots[`${seed.store}:${seed.id}`]=String(await read(stores[seed.store],'get_state_root_unconstrained',seed.id));
   const counter=BigInt(String(await read(stores.arrival,'get_event_id_counter_unconstrained')));
   roots.nextArrival=String(await read(stores.arrival,'get_state_root_unconstrained',counter+1n));
   return {roots,counter,customSeen:await Promise.all(Object.values(custom).map(c=>read(c,'get_seen_batches')))};
  };
  for(const variant of ['original','candidate']){
   const now=BigInt((await node.getBlock('latest')).header.globalVariables.timestamp);assert(now>=timestamp&&now-timestamp<=300n,'Refresh the isolated fixture timestamp instead of relaxing original freshness');
   const system=systems[variant][role],callee=custom[variant],abi=findFunction(artifacts[variant][role],method);
   await rejects(callee.methods.set_arrival_locations_max20(built.batches[0].ids,built.batches[0].states,0n),'Location caller changed',`${variant} ${method} custom store rejects direct account caller`);
   const before=await snapshot();
   await rejects(system.methods[method](...abi.parameters.map(p=>built.input[p.name])),'Original inactive locations observed',`${variant} ${method} preserves exact caller, inactive locations, and batch order`,{
    variant,method,originalPrivateApi:true,system:system.address.toString(),customLocation:callee.address.toString(),inputSha256:hash(json(built.input)),expectedLocationCommitments:expectedRoots,expectedBatches:built.batches,
   });
   assert.deepEqual(await snapshot(),before,'Sentinel simulation must roll back all isolated roots, allocated arrival ID and custom call counter');
   check(`${variant} ${method} sentinel leaves isolated state and counter unchanged`);
   // Hold the custom expected commitments fixed and alter one inactive witness
   // field; a distinct assertion proves this is not an unconditional sentinel.
   const tampered=buildInactiveLocationCase(snapshots[role].input,role,caseIndex+1,timestamp).input;
   tampered[role==='move'?'source_arrival_artifact_locations':'arrival_artifact_locations'][18].voyage_id+=1n;
   await rejects(system.methods[method](...abi.parameters.map(p=>tampered[p.name])),'Arrival location payload changed',`${variant} ${method} rejects an altered inactive location payload`);
   assert.deepEqual(await snapshot(),before,'Rejected payload simulation must roll back all isolated state');
   check(`${variant} ${method} altered-payload rejection leaves isolated state unchanged`);
  }
 }
 report.status='complete';report.passed=true;save();console.log('COMPLETE',checks.length,'custom location fallback checks');
}catch(error){report.status='failed';report.error=String(error.message??error).slice(0,2400);save();throw new Error(report.error.slice(0,800));}
finally{await wallet.stop();}
