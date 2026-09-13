import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {createAztecNodeClient} from '@aztec/aztec.js/node';
import {Contract,BatchCall} from '@aztec/aztec.js/contracts';
import {Fr} from '@aztec/aztec.js/fields';
import {loadContractArtifact} from '@aztec/stdlib/abi';
import {getContractClassFromArtifact} from '@aztec/stdlib/contract';
import {AztecAddress} from '@aztec/aztec.js/addresses';
import {GasFees} from '@aztec/stdlib/gas';
import {poseidon2Hash} from '@aztec/foundation/crypto/poseidon';
import {EmbeddedWallet} from '@aztec/wallets/embedded';
import {registerInitialLocalNetworkAccountsInWallet} from '@aztec/wallets/testing';
import {zeroValue,serializeFields,json} from '../../experiments/api-compatible-benchmark/fixtures.mjs';
import {storageInvocation} from './invocation.mjs';
import {assertPhysicalStorageLayout,physicalStorageChecks} from './physical-storage-checks.mjs';

// New isolated namespaces on the deployed candidate backend and fresh legacy
// stores. No fee fixture, shared Config/World namespace, or action counter changes.
const configuration=storageInvocation('storage-regressions');
const deployment=JSON.parse(fs.readFileSync(configuration.deployment));
const directory=configuration.artifacts;
const output=configuration.output;
assert(!fs.existsSync(output),'Choose a new storage output path; preserve previous runtime evidence');
const files={world:'WorldStorage',player:'PlayerStorage',planet:'PlanetStorage',planet_revealed_coords:'PlanetRevealedCoordsStorage',planet_events:'PlanetEventsStorage',planet_artifacts:'PlanetArtifactsStorage',arrival:'ArrivalStorage',artifact:'ArtifactStorage',artifact_location:'ArtifactLocationStorage'};
const physicalLayout=assertPhysicalStorageLayout({variant:configuration.variant,
 backendRaw:JSON.parse(fs.readFileSync(path.join(directory,'game_state_backend-GameStateBackend.json'))),
 facades:Object.fromEntries(Object.entries(files).map(([role,name])=>[role,JSON.parse(fs.readFileSync(path.join(directory,`${role}-${name}.json`)))]))});
const backendAddress=AztecAddress.fromStringUnsafe(deployment.state_backend??deployment.backend??deployment.game_state_backend);
const node=createAztecNodeClient(configuration.nodeUrl);
const dataDirectory=fs.mkdtempSync(path.join(os.tmpdir(),'df-api-storage-pxe-'));
const wallet=await EmbeddedWallet.create(node,{pxe:{dataDirectory,proverEnabled:false}});
const [admin,stranger,third]=await registerInitialLocalNetworkAccountsInWallet(wallet);
const opts={from:admin,fee:{gasSettings:{maxFeesPerGas:new GasFees(0n,100000000000000n)}},wait:{waitForStatus:'checkpointed',timeout:180}};
const stores={},types={},artifacts={},hashes={},checks=[],receipts=[];
const check=(label,evidence={})=>{checks.push({label,passed:true,...evidence});console.log('PASS',label);};
const physical=physicalStorageChecks({node,backend:backendAddress,layout:physicalLayout,record:check});
const expectedPhysicalRoots=new Map();
async function physicalRoot(role,id,expectedRoot,label,block){
 expectedPhysicalRoots.set(`${role}:${id}`,{role,id,expectedRoot});
 await physical.root({namespace:stores[role][1].address,key:id,expectedRoot,block:block??await node.getBlockNumber(),label});
}
async function physicalPermissions(label,expectedAdmin,grants){
 if(!physicalLayout.localRoots)return;
 const block=await node.getBlockNumber();
 for(const [role,[,store]]of Object.entries(stores))for(const actor of [admin,stranger,third,AztecAddress.ZERO])
  await physical.permission({namespace:store.address,actor,expectedAdmin,expectedGranted:grants.some(granted=>granted.equals(actor)),block,label:`${role} physical ${label} for ${actor}`});
 // Permission/admin mutations must not alter any previously seeded gameplay
 // root. Expectations remain the hashes of our typed states, never getter data.
 for(const {role,id,expectedRoot}of expectedPhysicalRoots.values())
  await physical.root({namespace:stores[role][1].address,key:id,expectedRoot,block,label:`${role} physical state survives ${label} at ${id}`});
}
const normalized=value=>JSON.parse(json(value));
const compare=(before,after,label)=>{assert.deepEqual(normalized(after),normalized(before),label);check(label);};
const read=async(c,name,...args)=>(await c.methods[name](...args).simulate(opts)).result;
const hash=async(t,state)=>(await poseidon2Hash(serializeFields(t,state))).toBigInt();
const maximum=type=>{
 if(type.kind==='struct'&&type.path.endsWith('::AztecAddress'))return AztecAddress.fromBigIntUnsafe(Fr.MODULUS-1n);
 if(type.kind==='field')return Fr.MODULUS-1n;
 if(type.kind==='integer')return (1n<<BigInt(type.width))-1n;
 if(type.kind==='boolean')return true;
 if(type.kind==='array')return Array.from({length:type.length},()=>maximum(type.type));
 return Object.fromEntries(type.fields.map(f=>[f.name,maximum(f.type)]));
};
async function send(calls,from=admin){const sent=await new BatchCall(wallet,calls).send({...opts,from});const r=await node.getTxReceipt(sent.receipt.txHash,{includeTxEffect:true});receipts.push({txHash:r.txHash.toString(),blockNumber:r.blockNumber});return r;}
async function batches(calls,from=admin){for(let i=0;i<calls.length;i+=4)await send(calls.slice(i,i+4),from);}
async function rejection(c,name,args,reason,from=admin){let error;try{await c.methods[name](...args).simulate({...opts,from});}catch(e){error=String(e.message??e);}assert(error?.includes(reason),`${name}: expected ${reason}, got ${error}`);}
async function rejectBoth(role,name,args,reason,from=admin){for(const c of stores[role])await rejection(c,name,args,reason,from);check(`${role}.${name} preserves rejection: ${reason}`);}
function eventWire(receipt,c){return receipt.txEffect.publicLogs.filter(log=>log.contractAddress.equals(c.address)).map(log=>{const f=log.fields.map(v=>BigInt(v.toString()));assert.equal(f[2],BigInt(receipt.blockNumber));return [f[0],f[1],...f.slice(3)];});}
async function pair(role,method,args){const [before,after]=stores[role],receipt=await send([before.methods[method](...args),after.methods[method](...args)]);compare(eventWire(receipt,before),eventWire(receipt,after),`${role}.${method} exact event selector, field order, states and sequence`);return receipt;}
async function verifyState(role,id,state){const expected=await hash(types[role],state);for(const c of stores[role]){
 assert.equal(BigInt((await read(c,'get_state_root',id)).toString()),expected);
 assert.equal(BigInt((await read(c,'get_state_root_unconstrained',id)).toString()),expected);
 assert.equal(await read(c,'verify',id,state),true);assert.equal(await read(c,'verify_unconstrained',id,state),true);
 }check(`${role} exact full-record hash retained at ${id}`);
 if(physicalLayout.localRoots)await physicalRoot(role,id,expected,`${role} physical facade root equals serialized state at ${id}`);
}
try{
 const backendFile=path.join(directory,'game_state_backend-GameStateBackend.json'),backendBytes=fs.readFileSync(backendFile);
 const backendArtifact=loadContractArtifact(JSON.parse(backendBytes)),backendInstance=await node.getContract(backendAddress);
 assert(backendInstance,'Canonical backend must already be deployed');
 const backendClass=(await getContractClassFromArtifact(backendArtifact)).id;
 assert(backendInstance.currentContractClassId.equals(backendClass),'Canonical backend live class must match the exact tested artifact');
 // This suite checks exact nested revert messages as well as rejection. PXE
 // needs the backend artifact to decode its assertion payload. The separate
 // read-only suite deliberately omits it when testing reader independence.
 await wallet.registerContract(backendInstance,backendArtifact);
 hashes.backend={path:backendFile,sha256:crypto.createHash('sha256').update(backendBytes).digest('hex'),address:backendAddress.toString(),currentClassId:backendInstance.currentContractClassId.toString(),artifactClassId:backendClass.toString(),classMatchesArtifact:true};
 for(const [role,name]of Object.entries(files)){
  stores[role]=[];artifacts[role]=[];hashes[role]=[];const constructors=[];
  for(const folder of ['/tmp/df-fee-tools/artifacts/baseline',directory]){
   const filename=path.join(folder,`${role}-${name}.json`),bytes=fs.readFileSync(filename),artifact=loadContractArtifact(JSON.parse(bytes));
   artifacts[role].push(artifact);hashes[role].push({path:filename,sha256:crypto.createHash('sha256').update(bytes).digest('hex')});
   const deployed=await Contract.deploy(wallet,artifact,[admin]).send(opts);const contract=deployed.contract;stores[role].push(contract);
   const instance=await node.getContract(contract.address),artifactClass=(await getContractClassFromArtifact(artifact)).id;
   assert(instance&&instance.currentContractClassId.equals(artifactClass),`${role} new deployment must match the exact tested artifact`);
   Object.assign(hashes[role].at(-1),{address:contract.address.toString(),currentClassId:instance.currentContractClassId.toString(),artifactClassId:artifactClass.toString(),classMatchesArtifact:true});
   const receipt=await node.getTxReceipt(deployed.receipt.txHash,{includeTxEffect:true});constructors.push(eventWire(receipt,contract));
  }
  compare(constructors[0],constructors[1],`${role} original constructor event schema and state`);
  types[role]=[...artifacts[role][0].functions,...(artifacts[role][0].nonDispatchPublicFunctions??[])].find(f=>f.name==='set').parameters[1].type;
  const [before,after]=stores[role],key=role==='player'?AztecAddress.ZERO:0n;
  compare(await read(before,'get_state_root_unconstrained',key),await read(after,'get_state_root_unconstrained',key),`${role} original constructor root before binding`);
  compare(await read(before,'get_admin_unconstrained'),await read(after,'get_admin_unconstrained'),`${role} original constructor admin before binding`);
  if(physicalLayout.localRoots){
   const constructorState=zeroValue(types[role],{addressFromBigInt:v=>AztecAddress.fromBigIntUnsafe(v)});
   if(role==='world'){constructorState.radius=53000n;constructorState.misc_nonce=1n;}
   await physicalRoot(role,key,role==='world'?await hash(types[role],constructorState):0n,`${role} physical constructor root before binding`);
  }
  await rejection(after,'set_state_backend',[backendAddress],'Only admin',stranger);
  await rejection(after,'set_state_backend',[AztecAddress.ZERO],'Invalid state backend');
  const pendingZero=zeroValue(types[role],{addressFromBigInt:v=>AztecAddress.fromBigIntUnsafe(v)});
  await rejection(after,'set',[key,pendingZero],'State backend not bound');
  check(`${role} pending deployment cannot write or bind a zero backend`);
 }
 await batches(Object.values(stores).map(([,c])=>c.methods.set_state_backend(backendAddress)));
 await physicalPermissions('initial namespace binding',admin,[]);
 for(const [role,[before,after]]of Object.entries(stores)){
  await rejection(after,'set_state_backend',[backendAddress],'State backend already bound');check(`${role} rejects rebinding`);
  const zero=zeroValue(types[role],{addressFromBigInt:v=>AztecAddress.fromBigIntUnsafe(v)}),zeroKey=role==='player'?AztecAddress.fromBigIntUnsafe(45001n):role==='arrival'?0n:45001n;
  if(role==='world')zero.radius=53000n; // Exact original World::zero() sentinel.
  await rejection(after,`emit_${role}_update`,[zeroKey,zero],'Only state backend',stranger);check(`${role} rejects spoofed original-event callbacks`);
  await rejectBoth(role,'set',[zeroKey,zero],'Not authorized',stranger);
  await pair(role,'set',[zeroKey,zero]);await verifyState(role,zeroKey,zero);assert.notEqual(await hash(types[role],zero),0n);
  for(const c of [before,after])assert.equal(await read(c,'compute_state_hash_unconstrained',zero),0n);
  check(`${role} explicit H(zero) remains distinct from compute_state_hash(zero)`);
  if(role==='world'){
   const numericZero=zeroValue(types[role],{addressFromBigInt:v=>AztecAddress.fromBigIntUnsafe(v)});
   await pair(role,'set',[45003n,numericZero]);await verifyState(role,45003n,numericZero);
   for(const c of [before,after])assert.equal(await read(c,'compute_state_hash_unconstrained',numericZero),await hash(types[role],numericZero));
   check('World numeric-zero record remains distinct from its radius-53000 default sentinel');
  }
  const max=maximum(types[role]);const id=role==='player'?AztecAddress.fromBigIntUnsafe(45002n):role==='arrival'?max.id:45002n;
  // Public SLOAD must observe the pending backend write in this same simulated
  // transaction. An anchor-only wallet hint would incorrectly return old state.
  const pending=await new BatchCall(wallet,[before.methods.set(id,max),before.methods.get_state_root(id),
    after.methods.set(id,max),after.methods.get_state_root(id)]).simulate(opts);
  const expectedPending=await hash(types[role],max);
  assert.equal(BigInt(pending.result[1].result.toString()),expectedPending);
  assert.equal(BigInt(pending.result[3].result.toString()),expectedPending);
  check(`${role} original public view observes a preceding same-transaction write`);
  await pair(role,'set',[id,max]);await verifyState(role,id,max);
  if(role==='arrival'){
   for(const requested of [0n,max.id,987654321n])compare(await read(before,'get_arrival_unconstrained',requested),await read(after,'get_arrival_unconstrained',requested),`arrival complete stored/unset record ${requested}`);
   const small={...max,pop_arriving:123n,silver_moved:456n,distance:789n,
    departure_time:1234567890n,arrival_time:1234567891n,arrival_type:255n};
   const compactZero={...zero,id};
   const verifyArrival=async(state,label)=>{
    for(const [index,c]of [before,after].entries())for(const method of ['get_arrival','get_arrival_unconstrained'])
     compare(state,await read(c,method,id),`arrival ${label}: ${index===0?'original':'candidate'} ${method} returns all eleven expected fields`);
   };
   await verifyArrival(max,'full-width record');
   // Identity fields keep their full Field range even when numeric values fit
   // the compact representation. Both readers must survive clearing the two
   // previous full-width tail words and restoring them on a later overwrite.
   for(const [label,state]of [['full to compact',small],['compact to full',max],['full to explicit zero at nonzero ID',compactZero]]){
    await pair(role,'set',[id,state]);await verifyState(role,id,state);await verifyArrival(state,label);
   }
   // Latest public state includes preceding writes in this transaction. This
   // also checks that zero-word clearing reads the pending value, not an anchor.
   for(const [index,c]of [before,after].entries()){
    const transitions=await new BatchCall(wallet,[c.methods.set(id,max),c.methods.get_arrival(id),
     c.methods.set(id,small),c.methods.get_arrival(id)]).simulate(opts);
    compare(max,transitions.result[1].result,`arrival ${index===0?'original':'candidate'} same-transaction full-width getter`);
    compare(small,transitions.result[3].result,`arrival ${index===0?'original':'candidate'} same-transaction compact getter after full overwrite`);
   }
   await rejectBoth(role,'set',[123n,zero],'id mismatch');
  }
 }
 // Independent component writes cannot replace neighboring roots: one namespace
 // is changed while all other namespaces retain their already-observed roots.
 const fixed=45002n,unchanged={};
 for(const [role,[,c]]of Object.entries(stores))if(role!=='player')unchanged[role]=await read(c,'get_state_root_unconstrained',fixed);
 const zp=zeroValue(types.planet,{addressFromBigInt:v=>AztecAddress.fromBigIntUnsafe(v)});
 await pair('planet','set',[fixed,zp]);
 if(physicalLayout.localRoots)await physicalRoot('planet',fixed,await hash(types.planet,zp),'planet physical independent overwrite root');
 for(const [role,[,c]]of Object.entries(stores))if(role!=='player'&&role!=='planet')compare(unchanged[role],await read(c,'get_state_root_unconstrained',fixed),`${role} root survives independent planet-only setter`);
 if(physicalLayout.localRoots){const block=await node.getBlockNumber();for(const [role,[,c]]of Object.entries(stores))if(role!=='player'&&role!=='planet'){
  const expected=expectedPhysicalRoots.get(`${role}:${fixed}`)?.expectedRoot??0n;
  await physicalRoot(role,fixed,expected,`${role} physical root survives independent planet-only setter`,block);
 }}
 // Authorization lists are canonical backend state, including zero address
 // grants, swap-removal, duplicate rejection, and admin fallback after transfer.
 await batches(Object.values(stores).flatMap(pair=>pair.map(c=>c.methods.add_authorized_contracts_batch([stranger,AztecAddress.ZERO,third],3n))));
 await physicalPermissions('batch grants including zero address',admin,[stranger,AztecAddress.ZERO,third]);
 for(const [role,pair]of Object.entries(stores)){
  for(const c of pair){assert.equal(await read(c,'get_authorized_count_unconstrained'),3n);for(let i=0;i<3;i++)compare([stranger,AztecAddress.ZERO,third][i].toString(),(await read(c,'get_authorized_contract_unconstrained',BigInt(i))).toString(),`${role} exact inserted grant index ${i}`);}
  await rejectBoth(role,'add_authorized_contract',[stranger],'Already authorized');
  await rejectBoth(role,'add_authorized_contracts_batch',[[admin,admin,admin],4n],'count exceeds batch size');
  await rejectBoth(role,'add_authorized_contracts_batch',[[admin,admin,third],2n],'Already authorized');
 }
 await batches(Object.values(stores).flatMap(pair=>pair.map(c=>c.methods.remove_authorized_contract(AztecAddress.ZERO))));
 await physicalPermissions('zero-address grant removal',admin,[stranger,third]);
 for(const [role,pair]of Object.entries(stores)){
  for(const c of pair){assert.equal(await read(c,'get_authorized_count_unconstrained'),2n);assert((await read(c,'get_authorized_contract_unconstrained',1n)).equals(third));assert((await read(c,'get_authorized_contract_unconstrained',2n)).equals(AztecAddress.ZERO));assert.equal(await read(c,'is_authorized_unconstrained',AztecAddress.ZERO),false);}
  check(`${role} swap-removal clears trailing slot and zero-address authorization`);
  await rejectBoth(role,'remove_authorized_contract',[AztecAddress.ZERO],'Not authorized');
 }
 await batches(Object.values(stores).flatMap(pair=>pair.map(c=>c.methods.remove_authorized_contract(third))));
 await physicalPermissions('third-account grant removal',admin,[stranger]);
 for(const [role,method,width]of [['artifact','set_spaceships_max5',5],['artifact_location','set_spaceship_locations_max5',5],['artifact_location','set_arrival_locations_max20',20]]){
  const state=maximum(types[role]),zero=zeroValue(types[role],{addressFromBigInt:v=>AztecAddress.fromBigIntUnsafe(v)});
  const ids=Array(width).fill(0n),states=Array.from({length:width},()=>zeroValue(types[role],{addressFromBigInt:v=>AztecAddress.fromBigIntUnsafe(v)}));
  ids[0]=51001n;ids[1]=0n;ids[2]=51001n;ids[3]=51002n;states[0]=state;states[1]=state;states[2]=zero;states[3]=state;
  await pair(role,method,[ids,states,4n]);await verifyState(role,51001n,zero);await verifyState(role,51002n,state);
  await pair(role,method,[ids,states,0n]);
  await rejectBoth(role,method,[ids,states,BigInt(width+1)],'count exceeds batch size');
  // This non-granted actor differs from the authorized account used above.
  await rejectBoth(role,method,[ids,states,0n],'Not authorized',third);
 }
 const arrivalPair=stores.arrival;
 for(const c of arrivalPair)assert.equal(await read(c,'get_event_id_counter_unconstrained'),1n);
 for(const expected of [2n,3n]){for(const c of arrivalPair)assert.equal(await read(c,'allocate_event_id'),expected);await pair('arrival','allocate_event_id',[]);for(const c of arrivalPair)assert.equal(await read(c,'get_event_id_counter_unconstrained'),expected);check(`arrival atomic allocation returns ${expected}`);}
 await batches(Object.values(stores).flatMap(pair=>pair.map(c=>c.methods.transfer_admin(stranger))));
 await physicalPermissions('admin transfer to granted stranger',stranger,[stranger]);
 for(const [role,pair]of Object.entries(stores)){for(const c of pair)assert((await read(c,'get_admin_unconstrained')).equals(stranger));await rejectBoth(role,'transfer_admin',[admin],'Only admin');check(`${role} current admin transfer applies to old API`);}
 await batches(Object.values(stores).flatMap(pair=>pair.map(c=>c.methods.transfer_admin(admin))),stranger);
 await physicalPermissions('admin transfer back',admin,[stranger]);
 await batches(Object.values(stores).flatMap(pair=>pair.map(c=>c.methods.transfer_admin(AztecAddress.ZERO))));
 await physicalPermissions('zero-admin transfer',AztecAddress.ZERO,[stranger]);
 for(const [role,pair]of Object.entries(stores)){for(const c of pair){assert((await read(c,'get_admin_unconstrained')).equals(AztecAddress.ZERO));assert.equal(await read(c,'is_authorized_unconstrained',AztecAddress.ZERO),true);}check(`${role} original zero-admin transfer remains permitted`);}
 const isolated={state_backend:backendAddress.toString(),...Object.fromEntries(Object.entries(stores).map(([role,[,c]])=>[role,c.address.toString()]))};
 const report={passed:true,configuration,proverEnabled:false,physicalLayout,physicalObservations:physical.observations,
 scope:'Isolated fresh legacy stores and canonical-backend namespaces; original APIs, actual public receipts and exact emitted fields; V5 independently reads physical facade roots against exact typed-state hashes and Backend grant/admin words against explicit transitions. No shared game state mutated. Gameplay proofs are outside this storage suite.',artifacts:hashes,contracts:Object.fromEntries(Object.entries(stores).map(([role,pair])=>[role,pair.map(c=>c.address.toString())])),backend:backendAddress.toString(),receipts,checks};
 fs.mkdirSync(path.dirname(output),{recursive:true});fs.writeFileSync(output,json(report)+'\n');fs.writeFileSync(output.replace(/\.json$/,'-addresses.json'),json(isolated)+'\n');console.log('COMPLETE',checks.length,'storage API checks');
}finally{await wallet.stop();}
