import assert from 'node:assert/strict';
import {Fr} from '@aztec/foundation/curves/bn254';
import {deriveStorageSlotInMap} from '@aztec/stdlib/hash';

const field=value=>typeof value?.toField==='function'?value.toField():new Fr(BigInt(value.toString()));

// Independent physical storage observation complements public/utility getters.
// The caller controls scheduling and supplies the exact expected serialized hash;
// this helper creates no wallet and never simulates or sends a transaction.
export async function observeLocalRoot({node,namespace,key,expectedRoot,block='latest'}){
 const slot=await deriveStorageSlotInMap(new Fr(3),field(key));
 const value=await node.getPublicStorageAt(block,namespace,slot);
 assert.equal(value.toBigInt(),field(expectedRoot).toBigInt(),'Authoritative facade slot3 root differs from the expected full state hash');
 return {namespace:namespace.toString(),key:field(key).toString(),slot:slot.toString(),root:value.toString(),block};
}

export async function observeNamespacePermission({node,backend,namespace,actor,expected,block='latest'}){
 const authorizedMap=await deriveStorageSlotInMap(new Fr(3),namespace);
 const authorizedSlot=await deriveStorageSlotInMap(authorizedMap,actor);
 const adminSlot=await deriveStorageSlotInMap(new Fr(2),namespace);
 const granted=await node.getPublicStorageAt(block,backend,authorizedSlot);
 const admin=await node.getPublicStorageAt(block,backend,adminSlot);
 const authorized=granted.toBigInt()!==0n||admin.equals(actor.toField());
 assert.equal(authorized,expected,'Current shared namespace permissions differ from the expected grant/admin state');
 return {backend:backend.toString(),namespace:namespace.toString(),actor:actor.toString(),granted:granted.toString(),admin:admin.toString(),authorized,block};
}
