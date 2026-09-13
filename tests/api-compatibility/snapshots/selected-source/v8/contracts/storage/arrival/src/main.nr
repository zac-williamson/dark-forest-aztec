// Storage contract for arrivals (voyage id, player, from/to planet, pop, silver, etc.).
// Original typed API and event emitter; roots and permissions are authoritative local state.
use ::aztec::macros::aztec;

#[aztec]
pub contract ArrivalStorage {
    use ::aztec::{
        macros::{
            events::event,
            functions::{external, initializer, internal, view},
            storage::storage,
        },
        protocol::{address::AztecAddress, hash::poseidon2_hash, traits::{Serialize, ToField}},
    };

    use ::aztec::state_vars::{Map, PublicMutable};
    use ::game_state_backend::GameStateBackend;
    use ::state_backend_readonly;
    use ::libs::arrival_codec::keyed::{pack_arrival, unpack_arrival};
    use ::aztec::event::event_interface::EventInterface;
    use ::types::storage::arrival::Arrival;

    #[storage]
    struct Storage<Context> {
        admin: PublicMutable<AztecAddress, Context>,
        state_backend: PublicMutable<AztecAddress, Context>,
        local_roots: Map<Field, PublicMutable<Field, Context>, Context>,
        authorized_map: Map<AztecAddress, PublicMutable<bool, Context>, Context>,
        authorized_index: Map<AztecAddress, PublicMutable<u32, Context>, Context>,
        authorized_list: Map<u32, PublicMutable<AztecAddress, Context>, Context>,
        authorized_count: PublicMutable<u32, Context>,
    }

    #[event]
    struct ArrivalUpdate {
        id: Field,
        block_number: u32,
        state: Arrival,
    }

    #[external("public")]
    #[initializer]
    fn constructor(admin: AztecAddress) {

        self.storage.admin.write(admin);
        self.storage.state_backend.write(AztecAddress::zero());
        self.storage.authorized_count.write(0);
        // Next id to hand out starts at 1 (see allocate_event_id).
        // Backend binding initializes the unchanged counter at 1.
    }

    // ================== INTERNAL AUTH ==================

    #[internal("public")]
    fn assert_admin() {

        assert(self.msg_sender() == self.storage.admin.read(), "Only admin");
    }

    #[internal("public")]
    fn assert_authorized() {

        let caller = self.msg_sender();
        let is_admin = caller == self.storage.admin.read();
        let is_authorized = self.storage.authorized_map.at(caller).read();
        assert((is_admin as u8) | (is_authorized as u8) != 0, "Not authorized");
    }

    // ================== ADD / UPDATE ==================

    #[external("public")]
    fn set(id: Field, state: Arrival) {
        let backend_address = self.storage.state_backend.read();
        assert(!backend_address.is_zero(), "State backend not bound");
        let backend = GameStateBackend::at(backend_address);
        self.call(backend.legacy_set_arrival(self.msg_sender(), id, state.id, pack_arrival(state)));
        self.storage.local_roots.at(id).write(poseidon2_hash(state.serialize()));
        self.emit(ArrivalUpdate { id: id, block_number: self.context.block_number(), state: state });
    }

    /// Atomically increment the event ID counter and return the new value.
    /// Used by move_public to allocate unique IDs for arrivals/events
    /// without touching the World state hash.
    #[external("public")]
    fn allocate_event_id() -> Field {
        let backend_address = self.storage.state_backend.read();
        assert(!backend_address.is_zero(), "State backend not bound");
        let backend = GameStateBackend::at(backend_address);
        self.call(backend.allocate_event_id(self.msg_sender()))
    }

    // ================== ADMIN ==================

    #[external("public")]
    fn transfer_admin(new_admin: AztecAddress) {

        self.internal.assert_admin();
        self.storage.admin.write(new_admin);
    }

    #[external("public")]
    fn add_authorized_contract(contract_address: AztecAddress) {

        self.internal.assert_admin();
        assert(!self.storage.authorized_map.at(contract_address).read(), "Already authorized");

        let count = self.storage.authorized_count.read();
        self.storage.authorized_map.at(contract_address).write(true);
        self.storage.authorized_index.at(contract_address).write(count);
        self.storage.authorized_list.at(count).write(contract_address);
        self.storage.authorized_count.write(count + 1);
    }

    #[external("public")]
    fn remove_authorized_contract(contract_address: AztecAddress) {

        self.internal.assert_admin();
        assert(self.storage.authorized_map.at(contract_address).read(), "Not authorized");

        let index = self.storage.authorized_index.at(contract_address).read();
        let last_index = self.storage.authorized_count.read() - 1;
        self.storage.authorized_map.at(contract_address).write(false);
        self.storage.authorized_index.at(contract_address).write(0);

        if index != last_index {
            let last_contract = self.storage.authorized_list.at(last_index).read();
            self.storage.authorized_list.at(index).write(last_contract);
            self.storage.authorized_index.at(last_contract).write(index);
        }

        self.storage.authorized_list.at(last_index).write(AztecAddress::zero());
        self.storage.authorized_count.write(last_index);
    }

    /// Batch authorize up to 3 contracts in a single transaction.
    #[external("public")]
    fn add_authorized_contracts_batch(addresses: [AztecAddress; 3], count: u8) {

        self.internal.assert_admin();
        assert(count <= 3, "count exceeds batch size");
        let mut current_count = self.storage.authorized_count.read();
        for i in 0..3 {
            if (i as u8) < count {
                let addr = addresses[i];
                assert(!self.storage.authorized_map.at(addr).read(), "Already authorized");
                self.storage.authorized_map.at(addr).write(true);
                self.storage.authorized_index.at(addr).write(current_count);
                self.storage.authorized_list.at(current_count).write(addr);
                current_count += 1;
            }
        }
        self.storage.authorized_count.write(current_count);
    }

    // ================== PUBLIC VIEWS ==================

    #[external("public")]
    #[view]
    fn verify(id: Field, state: Arrival) -> bool {

        let stored_hash = self.storage.local_roots.at(id).read();
        if stored_hash == 0 {
            state == Arrival::zero()
        } else {
            let computed_hash = poseidon2_hash(state.serialize());
            computed_hash == stored_hash
        }
    }

    #[external("public")]
    #[view]
    fn compute_state_hash(state: Arrival) -> Field {

        if state == Arrival::zero() {
            0
        } else {
            poseidon2_hash(state.serialize())
        }
    }

    #[external("public")]
    #[view]
    fn get_arrival(id: Field) -> Arrival {
        let backend_address = self.storage.state_backend.read();
        let namespace = self.context.this_address();

        (if backend_address.is_zero() { Arrival::zero() } else { state_backend_readonly::public_read::get_arrival(backend_address, namespace, id) })
    }

    #[external("public")]
    #[view]
    fn is_initialized(id: Field) -> bool {

        let stored_hash = self.storage.local_roots.at(id).read();
        stored_hash != 0
    }

    #[external("public")]
    #[view]
    fn get_state_root(id: Field) -> Field {

        self.storage.local_roots.at(id).read()
    }

    #[external("public")]
    #[view]
    fn verify_hash(id: Field, hash: Field) -> bool {

        let stored_hash = self.storage.local_roots.at(id).read();
        stored_hash == hash
    }

    #[external("public")]
    #[view]
    fn verify_hashes_batch(ids: [Field; 20], hashes: [Field; 20], count: u32) -> bool {

        assert(count <= 20, "count exceeds batch size");
        let mut result = true;
        for i in 0..20 {
            if result & ((i as u32) < count) & (ids[i] != 0) {
                let stored_hash = self.storage.local_roots.at(ids[i]).read();
                if stored_hash != hashes[i] {
                    result = false;
                }
            }
        }
        result
    }

    // ================== UTILITY (UNCONSTRAINED) ==================

    #[external("utility")]
    unconstrained fn verify_unconstrained(id: Field, state: Arrival) -> bool {

        let stored_hash = self.storage.local_roots.at(id).read();
        if stored_hash == 0 {
            state == Arrival::zero()
        } else {
            let computed_hash = poseidon2_hash(state.serialize());
            computed_hash == stored_hash
        }
    }

    #[external("utility")]
    unconstrained fn compute_state_hash_unconstrained(state: Arrival) -> Field {

        if state == Arrival::zero() {
            0
        } else {
            poseidon2_hash(state.serialize())
        }
    }

    #[external("utility")]
    unconstrained fn get_state_root_unconstrained(id: Field) -> Field {

        self.storage.local_roots.at(id).read()
    }

    #[external("utility")]
    unconstrained fn get_default_state_unconstrained() -> Arrival {

        Arrival::zero()
    }

    #[external("utility")]
    unconstrained fn get_admin_unconstrained() -> AztecAddress {

        self.storage.admin.read()
    }

    #[external("utility")]
    unconstrained fn get_authorized_count_unconstrained() -> u32 {

        self.storage.authorized_count.read()
    }

    #[external("utility")]
    unconstrained fn get_authorized_contract_unconstrained(index: u32) -> AztecAddress {

        self.storage.authorized_list.at(index).read()
    }

    #[external("utility")]
    unconstrained fn is_authorized_unconstrained(addr: AztecAddress) -> bool {

        let is_admin: bool = addr == self.storage.admin.read();
        let is_authorized: bool = self.storage.authorized_map.at(addr).read();
        is_admin | is_authorized
    }

    #[external("utility")]
    unconstrained fn is_initialized_unconstrained(id: Field) -> bool {

        let stored_hash = self.storage.local_roots.at(id).read();
        stored_hash != 0
    }

    #[external("utility")]
    unconstrained fn get_arrival_unconstrained(id: Field) -> Arrival {
        let backend_address = self.storage.state_backend.read();
        let namespace = self.context.this_address();

        (if backend_address.is_zero() { Arrival::zero() } else { state_backend_readonly::get_arrival(self.context, backend_address, namespace, id) })
    }

    #[external("utility")]
    unconstrained fn get_event_id_counter_unconstrained() -> Field {
        let backend_address = self.storage.state_backend.read();
        let namespace = self.context.this_address();

        (if backend_address.is_zero() { 1 } else { state_backend_readonly::get_event_id_counter(self.context, backend_address, namespace) })
    }

    // ================== PUBLIC VIEWS (AUTH) ==================

    #[external("public")]
    #[view]
    fn get_authorized_count() -> u32 {

        self.storage.authorized_count.read()
    }

    #[external("public")]
    #[view]
    fn get_authorized_contract(index: u32) -> AztecAddress {

        self.storage.authorized_list.at(index).read()
    }

    #[external("public")]
    #[view]
    fn is_authorized(addr: AztecAddress) -> bool {

        let is_admin: bool = addr == self.storage.admin.read();
        let is_authorized: bool = self.storage.authorized_map.at(addr).read();
        is_admin | is_authorized
    }

    // Deployment wiring for a fresh game. Write before the external call; a failed
    // bind reverts both contracts atomically, and reentrant rebinding is rejected.
    #[external("public")]
    fn set_state_backend(backend_address: AztecAddress) {
        assert(self.storage.state_backend.read().is_zero(), "State backend already bound");
        assert(self.msg_sender() == self.storage.admin.read(), "Only admin");
        assert(!backend_address.is_zero(), "Invalid state backend");
        self.storage.state_backend.write(backend_address);
        self.call(GameStateBackend::at(backend_address).bind_namespace(7, self.storage.admin.read()));
    }

    #[external("public")]
    #[view]
    fn get_state_backend() -> AztecAddress { self.storage.state_backend.read() }

    #[external("utility")]
    unconstrained fn get_state_backend_unconstrained() -> AztecAddress { self.storage.state_backend.read() }

    #[external("public")]
    fn emit_arrival_update(id: Field, state: Arrival) {
        let backend_address = self.storage.state_backend.read();
        assert(!backend_address.is_zero() & (self.msg_sender() == backend_address), "Only state backend");
        self.storage.local_roots.at(id).write(poseidon2_hash(state.serialize()));
        self.emit(ArrivalUpdate { id: id, block_number: self.context.block_number(), state: state });
    }

    #[external("public")]
    fn emit_arrival_fields(id: Field, root: Field, field_0: Field, field_1: Field, field_2: Field, field_3: Field, field_4: Field, field_5: Field, field_6: Field, field_7: Field, field_8: Field, field_9: Field, field_10: Field) {
        let backend_address = self.storage.state_backend.read();
        assert(!backend_address.is_zero() & (self.msg_sender() == backend_address), "Only state backend");
        self.storage.local_roots.at(id).write(root);
        let tag = comptime { aztec::protocol::hash::compute_log_tag(
            ArrivalUpdate::get_event_type_id().to_field(), aztec::protocol::constants::DOM_SEP__EVENT_LOG_TAG,
        ) };
        let log = [tag, id, self.context.block_number() as Field, field_0, field_1, field_2, field_3, field_4, field_5, field_6, field_7, field_8, field_9, field_10];
        // Safety: The VM constrains log emission; the tag/schema/address are identical
        // to self.emit(ArrivalUpdate), and the backend supplies canonical state.
        aztec::oracle::avm::emit_public_log(log.as_vector());
    }
}
