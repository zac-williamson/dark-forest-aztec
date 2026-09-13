import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {createAztecNodeClient} from '@aztec/aztec.js/node';
import {Contract} from '@aztec/aztec.js/contracts';
import {loadContractArtifact} from '@aztec/stdlib/abi';
import {getContractClassFromArtifact} from '@aztec/stdlib/contract';
import {resolveAssertionMessageFromRevertData} from '@aztec/simulator/client';
import {AztecAddress} from '@aztec/aztec.js/addresses';
import {GasFees} from '@aztec/stdlib/gas';
import {EmbeddedWallet} from '@aztec/wallets/embedded';
import {registerInitialLocalNetworkAccountsInWallet} from '@aztec/wallets/testing';
import {zeroValue,json} from '../../experiments/api-compatible-benchmark/fixtures.mjs';
import {storageInvocation} from './invocation.mjs';
import {assertSettlementCoverage,assertSystemPayloads,assertCallbackCoverage,trustVersion} from './trust-routes.mjs';
import {simulateGuardWithInjectedSender} from './guard-isolation.mjs';

// This suite only simulates hostile external calls. It does not send a single
// transaction, publish a class, alter a binding, or advance an action fixture.
const configuration=storageInvocation('trust-regressions');
const deployment=JSON.parse(fs.readFileSync(configuration.deployment));
const directory=configuration.artifacts;
const output=configuration.output;
assert(!fs.existsSync(output),'Choose a fresh output path to preserve previous trust evidence');
const files={backend:'game_state_backend-GameStateBackend.json',admin:'admin-Admin.json',
  core:'core-Core.json',move:'move-Move.json',artifact_action:'artifact_action-ArtifactAction.json',
  artifact_find:'artifact_find-ArtifactFind.json',artifact_prospect:'artifact_prospect-ArtifactProspect.json',
  artifact_valut:'artifact_valut-ArtifactValut.json',
  core_settlement_worker:'core_settlement_worker-CoreSettlementWorker.json',
  vault_settlement_worker:'vault_settlement_worker-VaultSettlementWorker.json',
  world:'world-WorldStorage.json',player:'player-PlayerStorage.json',
  planet:'planet-PlanetStorage.json',planet_revealed_coords:'planet_revealed_coords-PlanetRevealedCoordsStorage.json',
  planet_events:'planet_events-PlanetEventsStorage.json',planet_artifacts:'planet_artifacts-PlanetArtifactsStorage.json',
  arrival:'arrival-ArrivalStorage.json',artifact:'artifact-ArtifactStorage.json',
  artifact_location:'artifact_location-ArtifactLocationStorage.json'};
const facadeRoles=['world','player','planet','planet_revealed_coords','planet_events',
  'planet_artifacts','arrival','artifact','artifact_location'];
const node=createAztecNodeClient(configuration.nodeUrl);
const wallet=await EmbeddedWallet.create(node,{pxe:{dataDirectory:fs.mkdtempSync(path.join(os.tmpdir(),'df-api-trust-pxe-')),proverEnabled:false}});
const [admin,stranger]=await registerInitialLocalNetworkAccountsInWallet(wallet);
const options={from:admin,fee:{gasSettings:{maxFeesPerGas:new GasFees(0n,100000000000000n)}}};
const contracts={},artifacts={},provenance={},checks=[];
const functions=artifact=>[...artifact.functions,...(artifact.nonDispatchPublicFunctions??[])];
const abi=(role,name)=>{const fn=functions(artifacts[role]).find(fn=>fn.name===name);assert(fn,`${role}.${name} missing`);return fn;};
const zero=type=>zeroValue(type,{addressFromBigInt:v=>AztecAddress.fromBigIntUnsafe(v)});
const argsFor=(role,name,overrides={})=>abi(role,name).parameters.map(parameter=>
  Object.hasOwn(overrides,parameter.name)?overrides[parameter.name]:zero(parameter.type));
const fieldWord=value=>typeof value==='bigint'?value:value.toField().toBigInt();
function setBufferWord(args,index,value){
  assert.equal(args.length,1,'Expected the single v3 FieldBuffer argument');
  assert(Array.isArray(args[0].words)&&index<args[0].words.length,'Invalid typed FieldBuffer position');
  args[0].words[index]=fieldWord(value);
  return args;
}
async function reject(role,name,args,reason,label,from=admin){
  let observed;
  try{await contracts[role].methods[name](...args).simulate({...options,from});}
  catch(error){observed=String(error.message??error);}
  assert(observed?.includes(reason),`${label}: expected "${reason}", got ${observed?.slice(0,800)??'success'}`);
  checks.push({label,contract:role,method:name,caller:from.toString(),expectedRejection:reason,passed:true});
  console.log('PASS',label);
}
async function rejectInjected(name,args,reason,label,sender,claimedActor){
  let observed,revertData;
  try{await simulateGuardWithInjectedSender({node,wallet,interaction:contracts.backend.methods[name](...args),sender});}
  catch(error){
    observed=String(error.message??error);revertData=error.revertData?.map(value=>value.toString());
    const decoded=resolveAssertionMessageFromRevertData(error.revertData??[],artifacts.backend.functions.find(fn=>fn.name==='public_dispatch'));
    if(decoded&&!observed.includes(decoded))observed+=decoded;
  }
  assert(observed?.includes(reason),`${label}: expected "${reason}", got ${observed?.slice(0,800)??'success'}`);
  checks.push({label,contract:'backend',method:name,caller:sender.toString(),claimedActor:claimedActor.toString(),
    expectedRejection:reason,revertData,passed:true,simulationKind:'node-only injected msg_sender guard isolation',
    validAccountTransaction:false,transactionSubmitted:false});
  console.log('PASS',label);
}
try{
  for(const [role,file] of Object.entries(files)){
    const encoded=deployment[role]??(role==='backend'?(deployment.state_backend??deployment.game_state_backend):undefined);
    assert(encoded,`Deployment does not include ${role}; run only after all final candidate contracts are deployed`);
    const address=AztecAddress.fromStringUnsafe(encoded),bytes=fs.readFileSync(path.join(directory,file));
    const artifact=loadContractArtifact(JSON.parse(bytes)),instance=await node.getContract(address);
    assert(instance,`${role} deployment is not published`);
    const artifactClass=(await getContractClassFromArtifact(artifact)).id;
    assert(instance.currentContractClassId.equals(artifactClass),`${role} live class must match the exact tested artifact`);
    await wallet.registerContract(instance,artifact);
    artifacts[role]=artifact;contracts[role]=await Contract.at(address,artifact,wallet);
    provenance[role]={address:address.toString(),artifact:path.join(directory,file),
      sha256:crypto.createHash('sha256').update(bytes).digest('hex'),currentClassId:instance.currentContractClassId.toString(),artifactClassId:artifactClass.toString(),classMatchesArtifact:true};
  }
  const version=trustVersion(configuration.variant,functions(artifacts.backend),process.env.TRUST_VERSION);
  const settlementRoutes=assertSettlementCoverage(functions(artifacts.backend),version);
  const callbackSchemas=Object.fromEntries(facadeRoles.map(role=>[role,assertCallbackCoverage(role,functions(artifacts[role]),version)]));
  for(const role of ['core','move'])assertSystemPayloads(role,functions(artifacts[role]));
  for(const name of settlementRoutes.direct){
    const args=argsFor('backend',name,{length:0n});
    await reject('backend',name,args,'Only audited system',`Unaudited caller cannot enter ${name}`);
  }
  // The additional raw callback is as sensitive as the typed callback: accepting
  // a forged log could corrupt the original client/indexer state without a write.
  // Both endpoints must authenticate the configured backend before emitting.
  for(const role of facadeRoles){
    for(const suffix of ['update','fields']){
      const name=`emit_${role}_${suffix}`;
      await reject(role,name,argsFor(role,name),'Only state backend',
        `${role} ${suffix==='fields'?'raw':'typed'} event callback rejects a forged backend caller`);
    }
  }
  // Claiming an actual audited System address cannot turn an account into the
  // matching immutable worker. Conversely, an arbitrary actor is not accepted.
  for(const name of settlementRoutes.delegated){
    for(const [label,actor] of [['account',admin],['core',contracts.core.address],
                               ['vault',contracts.artifact_valut.address],['move',contracts.move.address]]){
      const args=argsFor('backend',name,{actor,length:0n});
      if(!abi('backend',name).parameters.some(p=>p.name==='actor'))setBufferWord(args,0,actor);
      await reject('backend',name,args,'Only audited settlement worker',`${name} rejects forged ${label} actor`);
    }
  }
  for(const name of settlementRoutes.unified){
    const width=abi('backend',name).parameters[0].type.fields[0].type.length;
    // A deliberately over-capacity length produces a distinctive assertion
    // immediately AFTER caller resolution, before any namespace read or write.
    const malformedPlan=actor=>setBufferWord(setBufferWord(argsFor('backend',name),0,actor),width-1,BigInt(width-12));
    const guardReason='Only audited settlement worker',postGuardReason='Write plan length exceeded';
    for(const [label,actor] of [['account',admin],['zero',AztecAddress.ZERO],['core',contracts.core.address],['vault',contracts.artifact_valut.address],['move',contracts.move.address]]){
      await reject('backend',name,malformedPlan(actor),guardReason,`${name} account cannot forge ${label} actor`);
    }
    for(const [worker,paired,other] of [['core_settlement_worker','core','artifact_valut'],['vault_settlement_worker','artifact_valut','core']]){
      const sender=contracts[worker].address;
      for(const [label,actor] of [['account',admin],['zero',AztecAddress.ZERO],['mismatched partner',contracts[other].address],['Move',contracts.move.address],['worker',sender]]){
        await rejectInjected(name,malformedPlan(actor),guardReason,`${name} injected ${worker} rejects ${label} actor`,sender,actor);
      }
      const actor=contracts[paired].address;
      await rejectInjected(name,malformedPlan(actor),postGuardReason,`${name} injected ${worker} admits only its paired System before rejecting malformed plan`,sender,actor);
    }
    for(const role of ['admin','core','move','artifact_action','artifact_find','artifact_prospect','artifact_valut']){
      await rejectInjected(name,malformedPlan(AztecAddress.ZERO),postGuardReason,
        `${name} injected audited ${role} ignores zero claimed actor before rejecting malformed plan`,contracts[role].address,AztecAddress.ZERO);
    }
    for(const actor of [admin,contracts.artifact_valut.address])await rejectInjected(name,malformedPlan(actor),postGuardReason,
      `${name} injected Core ignores foreign claimed actor ${actor}`,contracts.core.address,actor);
    await rejectInjected(name,malformedPlan(contracts.core.address),guardReason,
      `${name} injected facade cannot impersonate a settlement worker`,contracts.planet.address,contracts.core.address);
    // Exercise the RESOLVED actor, not only admission. This plan contains one
    // auth-only location batch with an invalid count. Correct resolution gets
    // through the actual namespace permission check, then reaches the precise
    // count assertion; using the claimed account/worker instead fails earlier.
    const location=contracts.artifact_location;
    const authorized=async actor=>(await location.methods.is_authorized_unconstrained(actor).simulate(options)).result;
    for(const actor of [stranger,AztecAddress.ZERO,contracts.core_settlement_worker.address,contracts.vault_settlement_worker.address])
      assert.equal(await authorized(actor),false,'Actor isolation requires an actually ungranted contrasting identity');
    for(const actor of [contracts.core.address,contracts.artifact_valut.address])
      assert.equal(await authorized(actor),true,'Actor isolation requires the actual configured System writer grant');
    const authOnlyPlan=actor=>{
      const args=argsFor('backend',name);
      for(const [index,value] of [[0,actor],[10,location.address],[11,512n],[12,41n],[13,6n],[14,5n],[width-1,3n]])setBufferWord(args,index,value);
      return args;
    };
    for(const actor of [stranger,AztecAddress.ZERO])await rejectInjected(name,authOnlyPlan(actor),'count exceeds batch size',
      `${name} injected Core uses its actual writer grant despite an ungranted claimed actor`,contracts.core.address,actor);
    for(const [worker,system] of [['core_settlement_worker','core'],['vault_settlement_worker','artifact_valut']])
      await rejectInjected(name,authOnlyPlan(contracts[system].address),'count exceeds batch size',
        `${name} injected ${worker} uses paired ${system} grant before rejecting invalid batch`,contracts[worker].address,contracts[system].address);
  }
  for(const role of ['core_settlement_worker','vault_settlement_worker']){
    const entrypoints=functions(artifacts[role]).filter(fn=>fn.name.startsWith('try_')&&fn.name.endsWith('_prepared'));
    assert(entrypoints.length>0,`${role} has no prepared entries`);
    for(const fn of entrypoints){
      assert(!fn.parameters.some(parameter=>parameter.name==='actor'),`${role}.${fn.name} must derive actor from msg_sender`);
      const args=argsFor(role,fn.name,{state_backend_address:contracts.backend.address,system_admin:admin});
      if(fn.parameters.length===1&&fn.parameters[0].type.kind==='struct'){
        setBufferWord(args,0,contracts.backend.address);
        setBufferWord(args,11,admin);
      }
      await reject(role,fn.name,args,
        'Only audited system',`${role}.${fn.name} rejects forged System caller before payload use`);
    }
  }
  for(const role of ['admin','core','move','artifact_action','artifact_find','artifact_prospect','artifact_valut']){
    const onlySelf=functions(artifacts[role]).filter(fn=>fn.functionType==='public'&&fn.isOnlySelf);
    assert(onlySelf.length>0,`${role} must expose its original protected continuations`);
    for(const fn of onlySelf)await reject(role,fn.name,argsFor(role,fn.name),
      `Function ${fn.name} can only be called by the same contract`,`${role}.${fn.name} cannot be forged externally`);
    for(const name of ['set_state_backend','set_state_worker'])if(contracts[role].methods[name]){
      await reject(role,name,argsFor(role,name),'Only admin',`${role}.${name} rejects an unauthorized wiring change`,stranger);
    }
  }
  for(const kind of [1n,2n,3n,4n,5n,6n,7n,8n,9n])await reject('backend','bind_namespace',[kind,admin],
    'Unrecognized facade',`Account cannot impersonate namespace kind ${kind}`);
  for(const kind of [0n,10n,255n])await reject('backend','bind_namespace',[kind,admin],
    'Unknown namespace kind',`Invalid namespace kind ${kind} rejected`);
  const legacyWriters=version==='v5'?['legacy_set_arrival']:['legacy_set_root','legacy_set_arrival'];
  if(version==='v5')assert(!functions(artifacts.backend).some(fn=>fn.name==='legacy_set_root'),
    'V5 authoritative facade roots must not retain a second Backend root writer');
  for(const name of legacyWriters)await reject('backend',name,
    argsFor('backend',name,{actor:admin}),'Wrong namespace kind',`${name} cannot spoof a bound facade`);
  for(const name of ['transfer_admin','add_authorized_contract','remove_authorized_contract','add_authorized_contracts_batch']){
    await reject('backend',name,argsFor('backend',name,{actor:admin}),'Unbound namespace',
      `${name} cannot use a supplied actor to administer another namespace`,stranger);
  }
  fs.mkdirSync(path.dirname(output),{recursive:true});
  fs.writeFileSync(output,json({passed:true,configuration,version,settlementRoutes,callbackSchemas,proverEnabled:false,transactionsSubmitted:0,
    scope:'Simulated hostile calls only; no sends or game state changes. V5 additionally isolates AVM caller/pair guards with clearly labelled injected msg_sender; those synthetic calls are not valid account transactions, proof evidence, or fee measurements. Exact live artifact classes recorded.',provenance,checks})+'\n');
  console.log('COMPLETE',checks.length,'trust-boundary rejection checks');
}finally{await wallet.stop();}
