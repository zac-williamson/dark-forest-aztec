import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createAztecNodeClient} from '@aztec/aztec.js/node';
import {Contract,BatchCall,getContractInstanceFromInstantiationParams} from '@aztec/aztec.js/contracts';
import {loadContractArtifact} from '@aztec/stdlib/abi';
import {publishContractClass} from '@aztec/aztec.js/deployment';
import {AztecAddress} from '@aztec/aztec.js/addresses';
import {GasFees} from '@aztec/stdlib/gas';
import {Fr} from '@aztec/aztec.js/fields';
import {SponsoredFeePaymentMethod} from '@aztec/aztec.js/fee';
import {SPONSORED_FPC_SALT} from '@aztec/constants';
import {SponsoredFPCContract} from '@aztec/noir-contracts.js/SponsoredFPC';
import {EmbeddedWallet} from '@aztec/wallets/embedded';
import {registerInitialLocalNetworkAccountsInWallet} from '@aztec/wallets/testing';
import {json} from './fixtures.mjs';
export const stateDirectory=new URL('./.state/',import.meta.url);
export const resultsDirectory=new URL('./results/',import.meta.url);
fs.mkdirSync(stateDirectory,{recursive:true});fs.mkdirSync(resultsDirectory,{recursive:true});
export const files={admin:'admin-Admin.json',arrival:'arrival-ArrivalStorage.json',artifact:'artifact-ArtifactStorage.json',artifact_action:'artifact_action-ArtifactAction.json',artifact_find:'artifact_find-ArtifactFind.json',artifact_location:'artifact_location-ArtifactLocationStorage.json',artifact_prospect:'artifact_prospect-ArtifactProspect.json',artifact_valut:'artifact_valut-ArtifactValut.json',config:'config-Config.json',core:'core-Core.json',move:'move-Move.json',planet:'planet-PlanetStorage.json',planet_artifacts:'planet_artifacts-PlanetArtifactsStorage.json',planet_events:'planet_events-PlanetEventsStorage.json',planet_revealed_coords:'planet_revealed_coords-PlanetRevealedCoordsStorage.json',player:'player-PlayerStorage.json',world:'world-WorldStorage.json'};
export const auxiliaryFiles={backend:'game_state_backend-GameStateBackend.json',core_settlement_worker:'core_settlement_worker-CoreSettlementWorker.json',vault_settlement_worker:'vault_settlement_worker-VaultSettlementWorker.json'};
export const findFunction=(artifact,name)=>[...artifact.functions,...(artifact.nonDispatchPublicFunctions??[])].find(fn=>fn.name===name);
export async function openRuntime(variant='baseline',artifactDirectory='/tmp/df-fee-tools/artifacts/baseline'){
  const node=createAztecNodeClient(process.env.AZTEC_NODE_URL??'http://127.0.0.1:8097');
  const gateEnabled=process.env.BENCH_FINAL_TX_GATE==='1';
  if(gateEnabled)assert(/^candidate-v6(?:-[a-z0-9_-]+)?$/.test(variant),'Final transaction gate is opt-in for the new V6 candidate only');
  const finalTxGate=gateEnabled?(await import('./final-tx-gate.mjs')).createFinalTxGate(node):undefined;
  const wallet=await EmbeddedWallet.create(finalTxGate?.node??node,{pxe:{dataDirectory:process.env.BENCH_WALLET_DIRECTORY??'/tmp/df-api-compatible-wallet52',proverEnabled:false}});
  const accounts=await registerInitialLocalNetworkAccountsInWallet(wallet),admin=accounts[0];
  const opts={from:admin,fee:{gasSettings:{maxFeesPerGas:new GasFees(0n,100000000000000n)}},wait:{waitForStatus:'checkpointed',timeout:180}};
  const paymentMode=process.env.BENCH_SPONSORED==='1'?'sponsored':'account';
  if(paymentMode==='sponsored'){
    const instance=await getContractInstanceFromInstantiationParams(SponsoredFPCContract.artifact,{salt:new Fr(SPONSORED_FPC_SALT)});
    await wallet.registerContract(instance,SponsoredFPCContract.artifact);opts.fee.paymentMethod=new SponsoredFeePaymentMethod(instance.address);
  }
  const saved=new URL(`${variant}-deployments.json`,stateDirectory);
  const addresses=fs.existsSync(saved)?JSON.parse(fs.readFileSync(saved)):{};
  const backendFile='game_state_backend-GameStateBackend.json';
  const deploymentFiles=fs.existsSync(path.join(artifactDirectory,backendFile))?{...auxiliaryFiles,...files}:files;
  const contracts={},artifacts={},rawArtifacts={};
  for(const [name,file] of Object.entries(deploymentFiles)){
    rawArtifacts[name]=JSON.parse(fs.readFileSync(path.join(artifactDirectory,file)));
    const artifact=loadContractArtifact(rawArtifacts[name]);artifacts[name]=artifact;
    if(addresses[name]){
      const address=AztecAddress.fromStringUnsafe(addresses[name]);
      await wallet.registerContract(await node.getContract(address),artifact);
      contracts[name]=await Contract.at(address,artifact,wallet);
    }
  }
  async function deployAll(){
    for(const name of Object.keys(deploymentFiles)){
      if(contracts[name])continue;
      const pendingFile=new URL(`${variant}-${name}-deployment-pending.json`,stateDirectory);
      if(fs.existsSync(pendingFile))throw Error(`Unreconciled deployment journal for ${variant}/${name}; verify the exact saved address and mined receipt before retrying`);
      // Lock the deployer up front so a wait timeout cannot lose the address/salt.
      const deployment=Contract.deploy(wallet,artifacts[name],Object.hasOwn(files,name)?[admin]:[],undefined,{deployer:admin});
      const instance=await deployment.getInstance();
      const journal={variant,name,address:instance.address.toString(),salt:instance.salt.toString(),deployer:admin.toString(),classId:instance.currentContractClassId.toString(),phase:'sending'};
      const checkpoint=()=>fs.writeFileSync(pendingFile,json(journal));checkpoint();
      let result;
      try{result=await deployment.send(opts);}
      catch(error){
        if(!String(error.message).includes('network only admits'))throw error;
        journal.phase='class-publication';checkpoint();
        await (await publishContractClass(wallet,artifacts[name])).send(opts);
        journal.phase='sending-with-class-published';checkpoint();
        result=await deployment.send({...opts,skipClassPublication:true});
      }
      contracts[name]=result.contract;addresses[name]=result.contract.address.toString();
      journal.phase='mined';journal.receipt=result.receipt;
      fs.writeFileSync(new URL(`${variant}-${name}-deployment.json`,resultsDirectory),json(journal));
      fs.writeFileSync(saved,json(addresses));console.log('DEPLOYED',variant,name);
      fs.unlinkSync(pendingFile);
    }
    if(contracts.backend){
      for(const [name,artifact] of Object.entries(artifacts)){
        if(!findFunction(artifact,'set_state_backend'))continue;
        const getter=findFunction(artifact,'get_state_backend_unconstrained')?'get_state_backend_unconstrained':'get_state_backend';
        const current=(await contracts[name].methods[getter]().simulate(opts)).result;
        if(current.equals(contracts.backend.address))continue;
        if(!current.equals(AztecAddress.ZERO))throw Error(`${name} bound to unexpected backend`);
        await contracts[name].methods.set_state_backend(contracts.backend.address).send(opts);console.log('BOUND',variant,name);
      }
      for(const [system,worker] of [['core','core_settlement_worker'],['artifact_valut','vault_settlement_worker']]){
        const current=(await contracts[system].methods.get_state_worker().simulate(opts)).result;
        if(current.equals(contracts[worker].address))continue;
        if(!current.equals(AztecAddress.ZERO))throw Error(`${system} bound to unexpected settlement worker`);
        await contracts[system].methods.set_state_worker(contracts[worker].address).send(opts);console.log('WORKER_BOUND',variant,system);
      }
    }
  }
  async function batch(calls){const size=paymentMode==='sponsored'?4:5;for(let i=0;i<calls.length;i+=size)await new BatchCall(wallet,calls.slice(i,i+size)).send(opts);}
  return {variant,paymentMode,artifactDirectory,node,wallet,finalTxGate,accounts,admin,opts,contracts,artifacts,rawArtifacts,addresses,deployAll,batch,close:()=>wallet.stop()};
}
