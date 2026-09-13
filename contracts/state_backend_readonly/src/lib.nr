// roots and permissions belong to immutable facades; Arrival payloads are shared.
// Utility reads use their anchor;
// public_read uses the VM's constrained cross-contract SLOAD at execution time.
// No nested utility call, target artifact registration, or authorization hook is
// required. Backend and facade layouts are checked against compiler metadata.
use aztec::context::UtilityContext;
use aztec::oracle::storage::storage_read;
use aztec::protocol::{address::AztecAddress, storage::map::derive_storage_slot_in_map};
use types::storage::arrival::Arrival;
use libs::arrival_codec::keyed::unpack_arrival;
pub mod public_read;

pub global KINDS: Field = 1;
pub global FACADE_ROOTS: Field = 3;
pub global FACADE_ADMIN: Field = 1;
pub global FACADE_AUTHORIZED: Field = 4;
pub global FACADE_INDEXES: Field = 5;
pub global FACADE_LISTS: Field = 6;
pub global FACADE_COUNT: Field = 7;
pub global ARRIVALS: Field = 2;
pub global COUNTERS: Field = 3;

pub unconstrained fn get_state_root(context: UtilityContext, _backend: AztecAddress, namespace: AztecAddress, key: Field) -> Field {
    let slot = derive_storage_slot_in_map(FACADE_ROOTS, key);
    storage_read(context.block_header(), namespace, slot)
}
pub unconstrained fn get_admin(context: UtilityContext, backend: AztecAddress, namespace: AztecAddress) -> AztecAddress {
storage_read(context.block_header(), namespace, FACADE_ADMIN)
    }
pub unconstrained fn get_authorized_count(context: UtilityContext, backend: AztecAddress, namespace: AztecAddress) -> u32 {
storage_read(context.block_header(), namespace, FACADE_COUNT)
    }
pub unconstrained fn get_authorized_contract(context: UtilityContext, backend: AztecAddress, namespace: AztecAddress, index: u32) -> AztecAddress {
let slot=derive_storage_slot_in_map(FACADE_LISTS,index);
        storage_read(context.block_header(),namespace,slot)
    }
pub unconstrained fn is_authorized(context: UtilityContext, backend: AztecAddress, namespace: AztecAddress, addr: AztecAddress) -> bool {
let slot=derive_storage_slot_in_map(FACADE_AUTHORIZED,addr);
        let granted:bool=storage_read(context.block_header(),namespace,slot);
        if granted { true } else { addr==get_admin(context,backend,namespace) }
    }
pub unconstrained fn get_arrival(context: UtilityContext, backend: AztecAddress, namespace: AztecAddress, id: Field) -> Arrival {
    let slot = derive_storage_slot_in_map(derive_storage_slot_in_map(ARRIVALS, namespace), id);
    let packed: [Field; 7] = storage_read(context.block_header(), backend, slot);
    unpack_arrival(id, packed)
}
pub unconstrained fn get_event_id_counter(context: UtilityContext, backend: AztecAddress, namespace: AztecAddress) -> Field {
    storage_read(context.block_header(), backend, derive_storage_slot_in_map(COUNTERS, namespace))
}
