// Run only after the coordinated local mutation window is released. Setup writes
// affect isolated System/Config clones; every gameplay call is a reverting simulation.
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
import {resolveAssertionMessageFromRevertData} from '@aztec/simulator/client';
import {GasFees} from '@aztec/stdlib/gas';
import {EmbeddedWallet} from '@aztec/wallets/embedded';
import {registerInitialLocalNetworkAccountsInWallet} from '@aztec/wallets/testing';
import {files,auxiliaryFiles,findFunction} from '../../experiments/api-compatible-benchmark/runtime.mjs';
import {revive,zeroValue,json} from '../../experiments/api-compatible-benchmark/fixtures.mjs';
import {clone} from '../../experiments/api-compatible-benchmark/base-fixture.mjs';
import {buildCoreCase} from '../../experiments/api-compatible-benchmark/core-fixtures.mjs';
import {storageInvocation} from './invocation.mjs';

const configuration=storageInvocation('config-caller-regressions');
const state=path.dirname(configuration.deployment),baselineVariant=process.env.CALLER_BASELINE_VARIANT??'baseline-v2';
const baselineArtifacts=process.env.CALLER_BASELINE_ARTIFACTS??'/tmp/df-fee-tools/artifacts/baseline';
const callerArtifact=process.env.CALLER_CONFIG_ARTIFACT??new URL('./caller-config/target/caller_sensitive_config-CallerSensitiveConfig.json',import.meta.url);
const paths={fresh:process.env.CALLER_INITIALIZE_FIXTURE??path.join(state,`${baselineVariant}-initialize_player-ordinary.json`),
 empty:process.env.CALLER_MOVE_EMPTY_FIXTURE??path.join(state,`${baselineVariant}-move-ordinary.json`),
 full:process.env.CALLER_MOVE_FULL_FIXTURE??path.join(state,'baseline-move-20.json'),
 upgrade:process.env.CALLER_UPGRADE_FIXTURE??path.join(state,'baseline-upgrade_planet-ordinary.json'),
 withdraw:process.env.CALLER_WITHDRAW_FIXTURE??path.join(state,'baseline-withdraw_silver-ordinary.json'),
 reveal:process.env.CALLER_REVEAL_FIXTURE??path.join(state,'baseline-reveal_location-ordinary.json')};
const deployment=JSON.parse(fs.readFileSync(configuration.deployment));
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const address=value=>AztecAddress.fromStringUnsafe(value);
const addressOptions={addressFromBigInt:value=>AztecAddress.fromBigIntUnsafe(value)};
const snapshots=Object.fromEntries(Object.entries(paths).map(([name,file])=>{
 const bytes=fs.readFileSync(file);return[name,{file,sha256:hash(bytes),fixture:JSON.parse(bytes)}];
}));
assert(!fs.existsSync(configuration.output),'Choose a new output path to preserve earlier caller evidence');
const checks=[],receipts=[],artifacts={},contracts={};
const report={status:'preparing',passed:false,configuration,proverEnabled:false,gameplayTransactionsSubmitted:0,
 scope:'Original private APIs evaluated and publicly simulated through isolated original/candidate System instances with caller-sensitive Config. Distinctive reverts occur before game-state writes; Upgrade first executes its original state-root checks against isolated seeded namespaces. This checks caller preservation, not successful settlement, proof cost or Fee Juice.',
 fixtures:Object.fromEntries(Object.entries(snapshots).map(([key,{file,sha256}])=>[key,{file,sha256}])),
 artifactProvenance:{},sharedContracts:{},isolatedContracts:{},receipts,checks};
const save=()=>{fs.mkdirSync(path.dirname(configuration.output),{recursive:true});fs.writeFileSync(configuration.output+'.tmp',json(report)+'\n');fs.renameSync(configuration.output+'.tmp',configuration.output);};
const record=(label,evidence={})=>{checks.push({label,passed:true,...evidence});console.log('PASS',label);save();};
function load(file){const bytes=fs.readFileSync(file),raw=JSON.parse(bytes);assert.equal(raw.transpiled,true,'Use native processed artifacts');return {artifact:loadContractArtifact(raw),file:String(file),sha256:hash(bytes)};}
for(const [variant,folder]of [['original',baselineArtifacts],['candidate',configuration.artifacts]]){
 artifacts[variant]={};report.artifactProvenance[variant]={};
 for(const role of ['core','move']){const entry=load(path.join(folder,files[role]));artifacts[variant][role]=entry.artifact;report.artifactProvenance[variant][role]={file:entry.file,sha256:entry.sha256};}
}
const caller=load(callerArtifact);report.artifactProvenance.callerConfig={file:caller.file,sha256:caller.sha256};
const node=createAztecNodeClient(configuration.nodeUrl);
const wallet=await EmbeddedWallet.create(node,{pxe:{dataDirectory:fs.mkdtempSync(path.join(os.tmpdir(),'df-api-config-caller-')),proverEnabled:false}});
try{
 const accounts=await registerInitialLocalNetworkAccountsInWallet(wallet),admin=accounts[0];
 const opts={from:admin,fee:{gasSettings:{maxFeesPerGas:new GasFees(0n,100000000000000n)}},wait:{waitForStatus:'checkpointed',timeout:180}};
 const sharedArtifacts={};
 for(const [role,file]of Object.entries({...files,...auxiliaryFiles})){
  const entry=load(path.join(configuration.artifacts,file)),encoded=deployment[role]??(role==='backend'?(deployment.state_backend??deployment.game_state_backend):undefined);
  assert(encoded,`Missing final ${role} deployment`);const instance=await node.getContract(address(encoded));assert(instance,`Missing deployed ${role}`);
  const expected=(await getContractClassFromArtifact(entry.artifact)).id;
  assert(instance.currentContractClassId.equals(expected),`${role} final deployed class does not match artifact`);
  await wallet.registerContract(instance,entry.artifact);sharedArtifacts[role]=entry.artifact;
  report.sharedContracts[role]={address:encoded,artifact:entry.file,sha256:entry.sha256,currentClassId:expected.toString()};
 }
 assert(!(await getContractClassFromArtifact(caller.artifact)).id.equals((await getContractClassFromArtifact(sharedArtifacts.config)).id),'Caller-sensitive Config must be a distinct implementation');
 const sent=async(interaction,label)=>{const result=await interaction.send(opts);receipts.push({label,txHash:result.receipt.txHash.toString()});save();return result;};
 async function deploy(artifact,args,label){
  let contract;
  try{contract=(await sent(Contract.deploy(wallet,artifact,args),label)).contract;}
  catch(error){if(!String(error.message).includes('network only admits'))throw error;
   await sent(await publishContractClass(wallet,artifact),label+' class publication');
   const result=await Contract.deploy(wallet,artifact,args).send({...opts,skipClassPublication:true});receipts.push({label,txHash:result.receipt.txHash.toString()});save();contract=result.contract;
  }
  const instance=await node.getContract(contract.address),artifactClass=(await getContractClassFromArtifact(artifact)).id;
  assert(instance&&instance.currentContractClassId.equals(artifactClass),`${label} new deployment must match the exact tested artifact`);
  (report.deploymentClasses??=[]).push({label,address:contract.address.toString(),currentClassId:instance.currentContractClassId.toString(),artifactClassId:artifactClass.toString(),classMatchesArtifact:true});save();
  return contract;
 }
 async function rejects(interaction,reason,label,from=admin,evidence={}){
  let error,revertData;try{await interaction.simulate({...opts,from});}catch(e){
   error=String(e.message??e);revertData=e.revertData?.map(value=>value.toString());
   // SDK 5.2 directly simulates public static calls on the node, bypassing
   // PXE assertion-message enrichment. Decode the actual marker with the
   // verified custom fixture ABI; an unrelated rejection still fails below.
   const decoded=resolveAssertionMessageFromRevertData(e.revertData??[],caller.artifact.functions.find(f=>f.name==='public_dispatch'));
   if(decoded&&!error.includes(decoded))error+=decoded;
  }
  assert(error?.includes(reason),`${label}: expected ${reason}; got ${error?.slice(0,1800)??'success'}`);
  record(label,{expectedRejection:reason,revertData,...evidence});
 }
 const inputs={};
 for(const [name,role,method]of [['fresh','core','initialize_player'],['empty','move','move'],['full','move','move'],['upgrade','core','upgrade_planet'],['withdraw','core','withdraw_silver'],['reveal','core','reveal_location']]){
  const fixture=snapshots[name].fixture;assert.equal(fixture.method,method);assert.equal(fixture.system,role);
  if(fixture.admin)assert.equal(fixture.admin,admin.toString(),'Use the exact legacy fixture account');
  else assert(['full','upgrade','withdraw','reveal'].includes(name),'Only the named original archived fixtures omit account metadata');
  inputs[name]=Object.fromEntries(findFunction(artifacts.original[role],method).parameters.map(p=>[p.name,revive(p.type,fixture.input[p.name],addressOptions)]));
  const snark=inputs[name].snark_config??inputs[name].provided_snark_config;if(snark)assert.equal(snark.disable_zk_checks,false);
  if(['upgrade','withdraw','reveal'].includes(name))assert(inputs[name].planet_state.owner.equals(admin),'Original Core fixture owner must match the actual sender');
  if(role==='move')assert(inputs[name].source_planet.owner.equals(admin),'Move source owner must equal the actual fixture account');
 }
 assert.equal(inputs.empty.source_planet_events_state.count,0n);assert.equal(inputs.empty.target_planet_events_state.count,0n);
 assert(inputs.full.source_planet_events_state.count>0n||inputs.full.target_planet_events_state.count>0n,'Full Move case must select its nonempty private continuation');
 const zeroState=role=>zeroValue(findFunction(sharedArtifacts[role],'set').parameters.at(-1).type,addressOptions);
 const planet=clone(inputs.empty.target_planet);Object.assign(planet,{owner:admin,planet_level:2n,planet_type:0n,space_type:0n,perlin:15n,silver:100000n,silver_cap:100000n,population:50000n,population_cap:100000n});
 const planetArtifacts=zeroState('planet_artifacts');planetArtifacts.last_updated=1n;
 const planetEvents=zeroState('planet_events');planetEvents.last_updated=1n;
 const base={...clone(inputs.fresh),location:inputs.fresh.location_id,snark_config:clone(inputs.fresh.provided_snark_config),
  admin,planet,planetArtifacts,planetEvents,player:zeroState('player'),zeroState};
 const coreCases=[{name:'fresh',method:'initialize_player',input:inputs.fresh,actor:admin}];
 for(const caseId of ['init_existing_planet','init_unused_padding']){
  const built=await buildCoreCase({runtime:{accounts},method:'initialize_player',caseId,base,input:clone(inputs.fresh)});
  coreCases.push({name:caseId,method:'initialize_player',input:built.input,actor:built.actor});
 }
 assert(coreCases[1].input.planet_state.is_initialized,'General initialization must retain an existing planet');
 assert.equal(coreCases[2].input.planet_artifacts_state.count,0n);assert.notEqual(coreCases[2].input.planet_artifacts_state.ids[19],0n);
 report.fixtureDerivation={coreCases:coreCases.map(c=>({caseId:c.name,actor:c.actor.toString(),inputSha256:hash(json(c.input))})),
  generator:'experiments/api-compatible-benchmark/core-fixtures.mjs',generatorSha256:hash(fs.readFileSync(new URL('../../experiments/api-compatible-benchmark/core-fixtures.mjs',import.meta.url))),
  note:'Historical Move20 contributes only its valid private witness; none of its old-chain addresses are used. All System wiring points at the final deployment, and Config stops before state-root checks.'};save();
 // Upgrade reaches Config only after its original state checks. Fresh canonical
 // namespaces keep those checks intact without touching the fee fixtures.
 const upgradeStores={},backend=address(deployment.backend??deployment.state_backend??deployment.game_state_backend);
 const upgradeStates={planet:inputs.upgrade.planet_state,planet_artifacts:inputs.upgrade.planet_artifacts_state,
  planet_events:inputs.upgrade.planet_events_state,world:inputs.upgrade.world};
 assert.equal(inputs.upgrade.planet_events_state.count,0n,'Use the original empty-queue Upgrade witness');
 report.upgradeVerificationState={};
 for(const role of Object.keys(upgradeStates)){
  const store=await deploy(sharedArtifacts[role],[admin],'isolated Upgrade '+role);upgradeStores[role]=store;
  await sent(store.methods.set_state_backend(backend),'bind isolated Upgrade '+role);
  assert((await store.methods.get_state_backend_unconstrained().simulate(opts)).result.equals(backend),'Upgrade namespace must bind to the exact final Backend');
  const key=role==='world'?0n:inputs.upgrade.location;
  await sent(store.methods.set(key,upgradeStates[role]),'seed isolated Upgrade '+role);
  report.upgradeVerificationState[role]={address:store.address.toString(),key,state:upgradeStates[role],
   root:String((await store.methods.get_state_root_unconstrained(key).simulate(opts)).result)};save();
 }
 coreCases.push({name:'reveal',method:'reveal_location',input:inputs.reveal,actor:admin});
 report.fixtureDerivation.additionalCoreCases=['upgrade','withdraw','reveal'].map(name=>({name,inputSha256:hash(json(inputs[name]))}));save();
 const modeCases=stop=>stop===1n?coreCases:[{name:stop===3n?'withdraw':'upgrade',method:stop===3n?'withdraw_silver':'upgrade_planet',input:stop===3n?inputs.withdraw:inputs.upgrade,actor:admin}];
 const reasons={1:'Original Config caller observed',2:'Original artifact Config caller observed',3:'Original world Config caller observed',4:'Original upgrade Config caller observed',5:'Original branch upgrade Config caller observed'};
 for(const variant of ['original','candidate']){contracts[variant]={};report.isolatedContracts[variant]={};for(const role of ['core','move']){
  const system=await deploy(artifacts[variant][role],[admin],variant+' '+role);contracts[variant][role]=system;
  report.isolatedContracts[variant][role]={system:system.address.toString(),configs:[]};save();
  if(variant==='candidate'){
   const calls=[system.methods.set_state_backend(address(deployment.backend??deployment.state_backend??deployment.game_state_backend))];
   if(role==='core')calls.push(system.methods.set_state_worker(address(deployment.core_settlement_worker)));
   await sent(new BatchCall(wallet,calls),variant+' '+role+' isolated backend/worker wiring');
  }
  for(const stop of role==='move'?[1n,2n]:[1n,3n,4n,5n]){
   const custom=await deploy(caller.artifact,[system.address,stop],variant+' '+role+' caller-sensitive Config '+stop);
   report.isolatedContracts[variant][role].configs.push({address:custom.address.toString(),stopAfter:stop});save();
   const wireArgs=findFunction(artifacts[variant][role],'set_all_storage_addresses').parameters.map(p=>{
    const key=p.name.replace(/_addr$/,'');
    if(key==='config')return custom.address;
    if(role==='core'&&stop>=4n&&upgradeStores[key])return upgradeStores[key].address;
    return address(deployment[key==='arrivals'?'arrival':key]);
   });
   await sent(system.methods.set_all_storage_addresses(...wireArgs),variant+' '+role+' isolated storage wiring');
   const direct=stop===1n?custom.methods.verify_config_hashes(0n,0n,Array(9).fill(0n))
    :stop===2n?custom.methods.verify_artifacts_config_hash(0n)
    :stop===3n?custom.methods.verify_world_config_hash(0n)
    :stop===4n?custom.methods.verify_upgrade_config_hash(0n)
    :custom.methods.verify_upgrade_hash_by_branch_level(0n,0n,0n);
   await rejects(direct,'Config caller changed',`${variant} ${role} Config mode${stop} rejects direct account caller`);
   const cases=role==='core'?modeCases(stop):[{name:'empty',method:'move',input:inputs.empty,actor:admin},{name:'full',method:'move',input:inputs.full,actor:admin}];
   for(const fixture of cases){
    const method=fixture.method,abi=findFunction(artifacts[variant][role],method);
    const input=clone(fixture.input);input.timestamp=BigInt((await node.getBlock('latest')).header.globalVariables.timestamp);
    const reason=reasons[Number(stop)];
    await rejects(system.methods[method](...abi.parameters.map(p=>input[p.name])),reason,
     `${variant} ${method}/${fixture.name} preserves original Config caller at selector${stop}`,fixture.actor,
     {variant,method,caseId:fixture.name,system:system.address.toString(),config:custom.address.toString(),inputSha256:hash(json(input)),timestamp:input.timestamp});
   }
  }
 }}
 report.status='complete';report.passed=true;save();console.log('COMPLETE',checks.length,'caller preservation checks');
}catch(error){report.status='failed';report.error=String(error.message??error).slice(0,2400);save();throw new Error(report.error.slice(0,600));}
finally{await wallet.stop();}
