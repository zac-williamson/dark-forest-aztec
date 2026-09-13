// Storage contract for global world state (paused, counts, radius, next_change_block, etc.).
// Original typed API and event emitter; roots and permissions are authoritative local state.
use ::aztec::macros::aztec;

#[aztec]
pub contract WorldStorage {
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
    use ::aztec::event::event_interface::EventInterface;
    use ::types::storage::world::World;

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
    struct WorldUpdate {
        id: Field,
        block_number: u32,
        state: World,
    }

    #[external("public")]
    #[initializer]
    fn constructor(admin: AztecAddress) {

        self.storage.admin.write(admin);
        self.storage.state_backend.write(AztecAddress::zero());
        self.storage.authorized_count.write(0);
        let mut world = World::zero();
        world.misc_nonce = 1; // Activate: distinguish from World::zero()
        let root = poseidon2_hash(world.serialize());
        self.storage.local_roots.at(0).write(root);
        self.emit(WorldUpdate { id: 0, block_number: self.context.block_number(), state: world });
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
    fn set(id: Field, state: World) {

        self.internal.assert_authorized();
        let block_number = self.context.block_number();
        let root = poseidon2_hash(state.serialize());
        self.storage.local_roots.at(id).write(root);
        self.emit(WorldUpdate { id: id, block_number: block_number, state: state });
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
    fn verify(id: Field, state: World) -> bool {

        let stored_hash = self.storage.local_roots.at(id).read();
        if stored_hash == 0 {
            state == World::zero()
        } else {
            let computed_hash = poseidon2_hash(state.serialize());
            computed_hash == stored_hash
        }
    }

    #[external("public")]
    #[view]
    fn compute_state_hash(state: World) -> Field {

        if (state == World::zero()) {
            0
        } else {
            poseidon2_hash(state.serialize())
        }
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

    // ================== UTILITY (UNCONSTRAINED) ==================

    #[external("utility")]
    unconstrained fn verify_unconstrained(id: Field, state: World) -> bool {

        let stored_hash = self.storage.local_roots.at(id).read();
        if stored_hash == 0 {
            state == World::zero()
        } else {
            let computed_hash = poseidon2_hash(state.serialize());
            computed_hash == stored_hash
        }
    }

    #[external("utility")]
    unconstrained fn compute_state_hash_unconstrained(state: World) -> Field {

        if (state == World::zero()) {
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
    unconstrained fn get_default_state_unconstrained() -> World {

        World::zero()
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
        self.call(GameStateBackend::at(backend_address).bind_namespace(1, self.storage.admin.read()));
    }

    #[external("public")]
    #[view]
    fn get_state_backend() -> AztecAddress { self.storage.state_backend.read() }

    #[external("utility")]
    unconstrained fn get_state_backend_unconstrained() -> AztecAddress { self.storage.state_backend.read() }

    #[external("public")]
    fn emit_world_update(id: Field, state: World) {
        let backend_address = self.storage.state_backend.read();
        assert(!backend_address.is_zero() & (self.msg_sender() == backend_address), "Only state backend");
        self.storage.local_roots.at(id).write(poseidon2_hash(state.serialize()));
        self.emit(WorldUpdate { id: id, block_number: self.context.block_number(), state: state });
    }

    #[external("public")]
    fn emit_world_fields(id: Field, root: Field, field_0: Field, field_1: Field, field_2: Field, field_3: Field) {
        let backend_address = self.storage.state_backend.read();
        assert(!backend_address.is_zero() & (self.msg_sender() == backend_address), "Only state backend");
        self.storage.local_roots.at(id).write(root);
        let tag = comptime { aztec::protocol::hash::compute_log_tag(
            WorldUpdate::get_event_type_id().to_field(), aztec::protocol::constants::DOM_SEP__EVENT_LOG_TAG,
        ) };
        let log = [tag, id, self.context.block_number() as Field, field_0, field_1, field_2, field_3];
        // Safety: The VM constrains log emission; the tag/schema/address are identical
        // to self.emit(WorldUpdate), and the backend supplies canonical state.
        aztec::oracle::avm::emit_public_log(log.as_vector());
    }
}
