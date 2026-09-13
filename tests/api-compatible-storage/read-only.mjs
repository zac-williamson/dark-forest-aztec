import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {createAztecNodeClient} from '@aztec/aztec.js/node';
import {Contract} from '@aztec/aztec.js/contracts';
import {loadContractArtifact} from '@aztec/stdlib/abi';
import {getContractClassFromArtifact} from '@aztec/stdlib/contract';
import {AztecAddress} from '@aztec/aztec.js/addresses';
import {GasFees} from '@aztec/stdlib/gas';
import {EmbeddedWallet} from '@aztec/wallets/embedded';
import {registerInitialLocalNetworkAccountsInWallet} from '@aztec/wallets/testing';
import {zeroValue,serializeFields,json} from '../../experiments/api-compatible-benchmark/fixtures.mjs';
import {storageInvocation} from './invocation.mjs';

// A fresh reader registers only the nine original facade classes. In particular,
// it never loads/registers the backend artifact and provides no nested utility hook.
const configuration=storageInvocation('reader-regressions');
const addresses=JSON.parse(fs.readFileSync(configuration.deployment));
const expectedBackendAddress=AztecAddress.fromStringUnsafe(addresses.backend??addresses.state_backend??addresses.game_state_backend);
const artifactDirectory=configuration.artifacts;
const out=configuration.output;
const node=createAztecNodeClient(configuration.nodeUrl);
const dataDirectory=fs.mkdtempSync(path.join(os.tmpdir(),'df-api-readonly-pxe-'));
const wallet=await EmbeddedWallet.create(node,{pxe:{dataDirectory,proverEnabled:false}});
const [admin,stranger]=await registerInitialLocalNetworkAccountsInWallet(wallet);
const opts={from:admin,fee:{gasSettings:{maxFeesPerGas:new GasFees(0n,100000000000000n)}}};
const files={player:'PlayerStorage',planet:'PlanetStorage',planet_revealed_coords:'PlanetRevealedCoordsStorage',planet_events:'PlanetEventsStorage',planet_artifacts:'PlanetArtifactsStorage',arrival:'ArrivalStorage',artifact:'ArtifactStorage',artifact_location:'ArtifactLocationStorage',world:'WorldStorage'};
const checks=[],classes={};let backendAddress;
const record=(label,evidence={})=>{checks.push({label,passed:true,...evidence});console.log('PASS',label);};
const eq=(a,b,label)=>{assert.deepEqual(JSON.parse(json(a)),JSON.parse(json(b)),label);record(label);};
try{
 for(const [role,name] of Object.entries(files)){
  const artifactPath=path.join(artifactDirectory,`${role}-${name}.json`),text=fs.readFileSync(artifactPath),artifact=loadContractArtifact(JSON.parse(text));
  classes[role]={artifactPath,sha256:crypto.createHash('sha256').update(text).digest('hex')};
  const address=AztecAddress.fromStringUnsafe(addresses[role]);
  const instance=await node.getContract(address);assert(instance,`${role} deployment is not published`);
  const artifactClass=(await getContractClassFromArtifact(artifact)).id;
  assert(instance.currentContractClassId.equals(artifactClass),`${role} live class must match the exact tested artifact`);
  Object.assign(classes[role],{address:address.toString(),currentClassId:instance.currentContractClassId.toString(),artifactClassId:artifactClass.toString(),classMatchesArtifact:true});
  await wallet.registerContract(instance,artifact);
  const c=await Contract.at(address,artifact,wallet),read=async(name,...args)=>(await c.methods[name](...args).simulate(opts)).result;
  const configured=await read('get_state_backend_unconstrained');
  assert(!configured.isZero(),`${role} must be bound before testing`);
  assert(configured.equals(expectedBackendAddress),`${role} must use the selected deployment's backend`);
  if(backendAddress)assert(backendAddress.equals(configured),'All namespaces share one canonical backend');else backendAddress=configured;
  const backendInstance=await node.getContract(backendAddress);
  assert.equal((await wallet.getContractClassMetadata(backendInstance.currentContractClassId)).isArtifactRegistered,false,'Backend artifact must remain unregistered');
  const stateType=[...artifact.functions,...(artifact.nonDispatchPublicFunctions??[])].find(f=>f.name==='set').parameters[1].type;
  const state=zeroValue(stateType,{addressFromBigInt:v=>AztecAddress.fromBigIntUnsafe(v)});
  // The original World::zero() sentinel has radius 53_000, not numeric zero.
  if(role==='world')state.radius=53000n;
  const zeroKey=role==='player'?AztecAddress.ZERO:0n;
  const absentKey=role==='player'?AztecAddress.fromBigIntUnsafe(987654321123456789n):987654321123456789n;
  for(const key of [zeroKey,absentKey]){
   const root=await read('get_state_root_unconstrained',key);
   eq(root,await read('get_state_root',key),`${role} public/utility exact root ${key}`);
   eq(await read('verify_unconstrained',key,state),await read('verify',key,state),`${role} public/utility zero witness ${key}`);
   eq(await read('is_initialized_unconstrained',key),BigInt(root.toString())!==0n,`${role} initialized follows actual root ${key}`);
   if(c.methods.is_initialized)eq(await read('is_initialized',key),BigInt(root.toString())!==0n,`${role} public initialized matches root ${key}`);
  }
  eq(await read('compute_state_hash_unconstrained',state),await read('compute_state_hash',state),`${role} exact zero-hash API behavior`);
  const defaultMethod=role==='planet'?'get_default_planet_unconstrained':'get_default_state_unconstrained';
  eq(serializeFields(stateType,await read(defaultMethod)),serializeFields(stateType,state),`${role} full default state schema`);
  const currentAdmin=await read('get_admin_unconstrained');
  eq(await read('is_authorized_unconstrained',currentAdmin),true,`${role} canonical admin is authorized`);
  for(const actor of [admin,stranger,AztecAddress.ZERO])eq(await read('is_authorized_unconstrained',actor),await read('is_authorized',actor),`${role} authorization view parity ${actor}`);
  const count=await read('get_authorized_count_unconstrained');
  eq(count,await read('get_authorized_count'),`${role} grant count view parity`);
  for(const index of new Set([0n,BigInt(count)]))eq(await read('get_authorized_contract_unconstrained',index),await read('get_authorized_contract',index),`${role} grant list view parity ${index}`);
  if(role==='arrival')for(const id of [0n,987654321123456789n])eq(await read('get_arrival_unconstrained',id),await read('get_arrival',id),`arrival complete raw reader parity ${id}`);
  assert.equal((await wallet.getContractClassMetadata(backendInstance.currentContractClassId)).isArtifactRegistered,false);
  record(`${role} utilities require no backend artifact registration or cross-utility permission hook`);
 }
 const report={passed:true,configuration,scope:'Read-only original store methods on a fresh SDK5.2 wallet registering only the nine facade artifacts; no backend artifact, no utility authorization hook, no sends.',backendAddress:backendAddress.toString(),classes,checks};
 fs.mkdirSync(path.dirname(out),{recursive:true});fs.writeFileSync(out,json(report)+'\n');console.log('COMPLETE',checks.length,'read-only API checks');
}finally{await wallet.stop();}
