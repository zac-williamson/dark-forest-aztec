import assert from 'node:assert/strict';
import {observeLocalRoot,observeNamespacePermission} from './local-root-observer.mjs';

// Select the artifact's OWN storage declaration, not dependency declarations
// (Config is often the first entry in outputs.globals.storage).
export function declaredSlots(raw){
 const declarations=raw.outputs.globals.storage.filter(item=>item.fields.find(field=>field.name==='contract_name')?.value.value===raw.name);
 assert.equal(declarations.length,1,`${raw.name} needs exactly one own compiled storage declaration`);
 const fields=declarations[0].fields.find(field=>field.name==='fields').value.fields;
 return Object.fromEntries(fields.map(field=>[field.name,BigInt(`0x${field.value.fields.find(item=>item.name==='slot').value.value}`)]));
}

export function assertPhysicalStorageLayout({variant,backendRaw,facades}){
 const backend=declaredSlots(backendRaw),detected=Object.hasOwn(backend,'roots')?'v4':'v5';
 const labelled=String(variant).match(/(?:^|-)v([45])(?:$|-)/)?.[1];
 if(labelled)assert.equal(detected,`v${labelled}`,'Physical storage layout must match the selected variant');
 assert.equal(backend.admins,2n);assert.equal(backend.authorized,3n);
 assert.equal(backend.arrivals,detected==='v5'?7n:8n);assert.equal(backend.counters,detected==='v5'?8n:9n);
 if(detected==='v4')assert.equal(backend.roots,7n);
 for(const raw of Object.values(facades)){
  const slots=declaredSlots(raw);assert.equal(slots.bootstrap_admin,1n);assert.equal(slots.state_backend,2n);
  if(detected==='v5')assert.equal(slots.local_roots,3n,`${raw.name} must own its complete root at map slot3`);
  else assert(!Object.hasOwn(slots,'local_roots'),'V4 replay must not assume V5 local roots');
 }
 assert.equal(Object.keys(facades).length,9,'Independently check all nine compiled facade layouts');
 return {version:detected,localRoots:detected==='v5',facadeRootMapSlot:detected==='v5'?3:null,backendAdminMapSlot:2,backendGrantMapSlot:3};
}

// Expected hashes and grants come from typed fixture states and explicit test
// transitions. Never accept a public/utility getter as the expected value here.
export function physicalStorageChecks({node,backend,layout,record=()=>{}}){
 const observations=[];
 async function root({namespace,key,expectedRoot,block,label}){
  if(!layout.localRoots)return;
  const result=await observeLocalRoot({node,namespace,key,expectedRoot,block});
  observations.push({kind:'facade-root',label,expectedRoot:expectedRoot.toString(),...result});
  record(label,{physicalRoot:result,expectedSerializedHash:expectedRoot.toString()});return result;
 }
 async function permission({namespace,actor,expectedAdmin,expectedGranted,block,label}){
  if(!layout.localRoots)return;
  const expected=expectedGranted||actor.equals(expectedAdmin);
  const result=await observeNamespacePermission({node,backend,namespace,actor,expected,block});
  assert.equal(BigInt(result.admin),expectedAdmin.toBigInt(),'Physical admin must match the explicit transfer target');
  assert.equal(BigInt(result.granted),expectedGranted?1n:0n,'Physical grant word must match the explicit add/remove operation');
  observations.push({kind:'backend-permission',label,expectedAdmin:expectedAdmin.toString(),expectedGranted,...result});
  record(label,{physicalPermission:result,expectedAdmin:expectedAdmin.toString(),expectedGranted});return result;
 }
 return {root,permission,observations};
}
