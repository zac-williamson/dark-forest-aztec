// Public VM reads, not unconstrained wallet hints. The SLOAD opcode constrains
// both the target contract and its current storage value. Slot constants are
// checked against the compiled backend and all nine facades.
use aztec::oracle::avm::storage_read;
use aztec::protocol::{address::AztecAddress, storage::map::derive_storage_slot_in_map, traits::{FromField,ToField}};
use types::storage::arrival::Arrival;
use libs::arrival_codec::keyed::unpack_arrival;

pub unconstrained fn get_namespace_kind(backend:AztecAddress, namespace:AztecAddress)->u8 {
    storage_read(derive_storage_slot_in_map(super::KINDS,namespace),backend.to_field()) as u8
}
pub unconstrained fn get_state_root(_backend:AztecAddress, namespace:AztecAddress, key:Field)->Field {
    let slot=derive_storage_slot_in_map(super::FACADE_ROOTS,key);
    storage_read(slot,namespace.to_field())
}
pub unconstrained fn get_admin(backend:AztecAddress, namespace:AztecAddress)->AztecAddress {
AztecAddress::from_field(storage_read(super::FACADE_ADMIN,namespace.to_field()))
    }
pub unconstrained fn get_authorized_count(backend:AztecAddress, namespace:AztecAddress)->u32 {
storage_read(super::FACADE_COUNT,namespace.to_field()) as u32
    }
pub unconstrained fn get_authorized_contract(backend:AztecAddress, namespace:AztecAddress, index:u32)->AztecAddress {
let slot=derive_storage_slot_in_map(super::FACADE_LISTS,index);
        AztecAddress::from_field(storage_read(slot,namespace.to_field()))
    }
pub unconstrained fn is_authorized(backend:AztecAddress, namespace:AztecAddress, actor:AztecAddress)->bool {
let slot=derive_storage_slot_in_map(super::FACADE_AUTHORIZED,actor);
        if storage_read(slot,namespace.to_field())!=0 { true } else { actor==get_admin(backend,namespace) }
    }
pub unconstrained fn get_arrival(backend:AztecAddress, namespace:AztecAddress, id:Field)->Arrival {
    let slot=derive_storage_slot_in_map(derive_storage_slot_in_map(super::ARRIVALS,namespace),id);
    let mut packed=[0;7];
    for i in 0..7 { packed[i]=storage_read(slot+i as Field,backend.to_field()); }
    unpack_arrival(id,packed)
}
pub unconstrained fn get_event_id_counter(backend:AztecAddress, namespace:AztecAddress)->Field {
    storage_read(derive_storage_slot_in_map(super::COUNTERS,namespace),backend.to_field())
}
pub unconstrained fn can_settle(backend:AztecAddress, addresses:[AztecAddress;10], required_mask:u16)->bool {
    if backend.is_zero() { false } else {
        let mut valid=true;
        for i in 1..10 {
            if (required_mask & (1u16<<i))!=0 {
                if get_namespace_kind(backend,addresses[i as u32])!=(i as u8) { valid=false; }
            }
        }
        valid
    }
}
pub unconstrained fn verify_hash(backend:AztecAddress, namespace:AztecAddress, key:Field, expected:Field)->bool {
    get_state_root(backend,namespace,key)==expected
}
pub unconstrained fn is_initialized(backend:AztecAddress, namespace:AztecAddress, key:Field)->bool {
    get_state_root(backend,namespace,key)!=0
}
pub unconstrained fn verify_hashes_batch_20(backend:AztecAddress, namespace:AztecAddress, ids:[Field;20], hashes:[Field;20], count:u32)->bool {
    assert(count<=20,"count exceeds batch size");
    let mut result=true;
    for i in 0..count {
        if result & (ids[i]!=0) {
            if !verify_hash(backend,namespace,ids[i],hashes[i]) { result=false; }
        }
    }
    result
}
