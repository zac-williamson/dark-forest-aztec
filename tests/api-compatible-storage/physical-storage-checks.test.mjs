import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {Fr} from '@aztec/foundation/curves/bn254';
import {AztecAddress} from '@aztec/aztec.js/addresses';
import {deriveStorageSlotInMap} from '@aztec/stdlib/hash';
import {assertPhysicalStorageLayout,declaredSlots,physicalStorageChecks} from './physical-storage-checks.mjs';

const declaration=(name,slots)=>({fields:[{name:'contract_name',value:{value:name}},{name:'fields',value:{fields:Object.entries(slots).map(([name,slot])=>({name,value:{fields:[{name:'slot',value:{value:BigInt(slot).toString(16)}}]}}))}}]});
const raw=(name,slots)=>({name,outputs:{globals:{storage:[declaration('Config',{wrong_first_entry:99}),declaration(name,slots)]}}});
const inputs=version=>({variant:`candidate-${version}`,backendRaw:raw('GameStateBackend',{kinds:1,admins:2,authorized:3,indexes:4,lists:5,counts:6,...(version==='v4'?{roots:7,arrivals:8,counters:9}:{arrivals:7,counters:8})}),
 facades:Object.fromEntries(Array.from({length:9},(_,i)=>[i,raw(`Facade${i}`,{bootstrap_admin:1,state_backend:2,...(version==='v5'?{local_roots:3}:{})})]))});

test('compiled layout chooses own contract and distinguishes V4/V5 before runtime',()=>{
 assert.deepEqual(declaredSlots(raw('Own',{local_roots:3})),{local_roots:3n});
 assert.equal(assertPhysicalStorageLayout(inputs('v4')).localRoots,false);
 assert.equal(assertPhysicalStorageLayout(inputs('v5')).localRoots,true);
 const mixed=inputs('v5');mixed.facades[3]=raw('Facade3',{bootstrap_admin:1,state_backend:2,local_roots:4});
 assert.throws(()=>assertPhysicalStorageLayout(mixed),/slot3/);
 const mislabel=inputs('v4');mislabel.variant='candidate-v5';assert.throws(()=>assertPhysicalStorageLayout(mislabel),/selected variant/);
 const missing=inputs('v5');delete missing.facades[8];assert.throws(()=>assertPhysicalStorageLayout(missing),/nine/);
});

test('V4 replay makes no V5 physical reads',async()=>{
 const checks=physicalStorageChecks({node:{getPublicStorageAt(){throw Error('Unexpected read');}},backend:null,layout:assertPhysicalStorageLayout(inputs('v4'))});
 await checks.root({});await checks.permission({});assert.deepEqual(checks.observations,[]);
});

test('actual frozen V4 native storage declarations remain replayable',()=>{
 const directory='/tmp/df-api-compatible-v4-native';
 const names={world:'WorldStorage',player:'PlayerStorage',planet:'PlanetStorage',planet_revealed_coords:'PlanetRevealedCoordsStorage',planet_events:'PlanetEventsStorage',planet_artifacts:'PlanetArtifactsStorage',arrival:'ArrivalStorage',artifact:'ArtifactStorage',artifact_location:'ArtifactLocationStorage'};
 const read=file=>JSON.parse(fs.readFileSync(`${directory}/${file}`));
 const layout=assertPhysicalStorageLayout({variant:'candidate-v4',backendRaw:read('game_state_backend-GameStateBackend.json'),facades:Object.fromEntries(Object.entries(names).map(([role,name])=>[role,read(`${role}-${name}.json`)]))});
 assert.equal(layout.version,'v4');assert.equal(layout.localRoots,false);
});

test('physical roots retain full Field values and reject stale or truncated storage independent of getters',async()=>{
 const namespace=AztecAddress.fromBigIntUnsafe(123n),key=456n,expectedRoot=(1n<<220n)+789n,block=77;
 const expectedSlot=await deriveStorageSlotInMap(new Fr(3),new Fr(key));let stored=expectedRoot;
 const node={async getPublicStorageAt(actualBlock,address,slot){assert.equal(actualBlock,block);assert(address.equals(namespace));assert(slot.equals(expectedSlot));return new Fr(stored);}};
 const checks=physicalStorageChecks({node,backend:null,layout:{localRoots:true}});
 await checks.root({namespace,key,expectedRoot,block,label:'typed-state hash'});
 assert.equal(checks.observations[0].expectedRoot,expectedRoot.toString());
 for(const bad of [789n,0n,expectedRoot+1n]){stored=bad;await assert.rejects(checks.root({namespace,key,expectedRoot,block}),/expected full state hash/);}
 assert.equal(checks.observations.length,1,'Failed physical checks are never recorded as successful');
});

test('physical permissions distinguish exact grant words and admin transfers even when effective authorization agrees',async()=>{
 const backend=AztecAddress.fromBigIntUnsafe(101n),namespace=AztecAddress.fromBigIntUnsafe(102n),actor=AztecAddress.fromBigIntUnsafe(103n),other=AztecAddress.fromBigIntUnsafe(104n);
 const grantSlot=await deriveStorageSlotInMap(await deriveStorageSlotInMap(new Fr(3),namespace),actor);
 const adminSlot=await deriveStorageSlotInMap(new Fr(2),namespace);let grant=0n,admin=actor;
 const node={async getPublicStorageAt(block,address,slot){assert.equal(block,88);assert(address.equals(backend));if(slot.equals(grantSlot))return new Fr(grant);assert(slot.equals(adminSlot));return admin.toField();}};
 const checks=physicalStorageChecks({node,backend,layout:{localRoots:true}});
 const inspect=(expectedAdmin,expectedGranted)=>checks.permission({namespace,actor,expectedAdmin,expectedGranted,block:88,label:'explicit transition'});
 await inspect(actor,false); // Authorized through admin, raw grant remains zero.
 grant=1n;await inspect(actor,true);
 await assert.rejects(inspect(actor,false),/Physical grant word/); // Effective auth still true.
 admin=other;await inspect(other,true);
 await assert.rejects(inspect(actor,true),/Physical admin/); // Grant masks stale admin in getters.
 grant=2n;await assert.rejects(inspect(other,true),/Physical grant word/);
 grant=0n;await inspect(other,false);
 assert.equal(checks.observations.length,4);
});
