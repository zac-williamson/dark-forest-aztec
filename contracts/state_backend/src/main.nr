// Shared game settlement and compact Arrival payloads.
// Each immutable facade owns its authoritative root map and original event emitter.
mod trusted_classes;
use aztec::macros::aztec;
#[aztec]
pub contract GameStateBackend {
    use aztec::macros::{functions::{external,initializer,internal,view},storage::storage};
    use aztec::state_vars::{Map,PublicMutable,StateVariable};
    use aztec::protocol::traits::Deserialize;
    use aztec::oracle::get_contract_instance::get_contract_instance_current_class_id_avm;
    use state_facade_interface::StateFacadeInterface;
    use config::Config;
    use libs::arrival_codec::keyed::pack_arrival;
    use libs::batch_utils::assert_public_timestamp;
    use types::storage::artifact::ArtifactType;
    use aztec::protocol::{address::AztecAddress, hash::poseidon2_hash, traits::{Serialize,ToField,FromField}};
    use types::storage::{world::World, player::Player, planet::{Planet,PlanetArtifacts,PlanetEvents,PlanetEventMetadata,PlanetRevealedCoords}, arrival::Arrival, artifact::{Artifact,ArtifactLocation}};

    #[storage]
    struct Storage<Context> {
        kinds: Map<AztecAddress,PublicMutable<u8,Context>,Context>,
        arrivals: Map<AztecAddress,Map<Field,PublicMutable<[Field;7],Context>,Context>,Context>,
        counters: Map<AztecAddress,PublicMutable<Field,Context>,Context>,
    }
    #[external("public")] #[initializer]
    fn constructor() {}

    // The namespace is the authenticated caller, never a caller-supplied address.
    #[external("public")]
    fn bind_namespace(kind: u8, initial_admin: AztecAddress) {
        let ns = self.msg_sender();
        assert(kind >= 1 & kind <= 9, "Unknown namespace kind");
        assert(self.storage.kinds.at(ns).read() == 0, "Namespace already bound");
        let caller_class = get_contract_instance_current_class_id_avm(ns);
        assert(caller_class.is_some(), "Unrecognized facade");
        let expected_class = super::trusted_classes::FACADE_CLASSES[(kind - 1) as u32];
        assert(expected_class != 0, "Facade classes not configured");
        assert(caller_class.unwrap().to_field() == expected_class, "Unrecognized facade");
        self.storage.kinds.at(ns).write(kind);
        // Retain the additive binding ABI; the facade owns its current admin.
        let _ = initial_admin;
        if kind == 7 { self.storage.counters.at(ns).write(1); }
    }
    #[internal("public")]
    fn _expect_kind(ns: AztecAddress, kind: u8) {
        assert(self.storage.kinds.at(ns).read() == kind, "Wrong namespace kind");
    }
    #[internal("public")]
    fn _assert_authorized(ns: AztecAddress, actor: AztecAddress) {
        let slot=aztec::protocol::storage::map::derive_storage_slot_in_map(4,actor);
        let explicitly_granted=aztec::oracle::avm::storage_read(slot,ns.to_field());
        if explicitly_granted == 0 {
            let admin=AztecAddress::from_field(aztec::oracle::avm::storage_read(1,ns.to_field()));
            assert(actor==admin,"Not authorized");
        }
    }
    #[internal("public")]
    fn _is_prepared_writer(actor: AztecAddress) -> bool {
        let current = get_contract_instance_current_class_id_avm(actor);
        if current.is_some() { super::trusted_classes::contains(current.unwrap().to_field()) }
        else { false }
    }
    #[internal("public")]
    fn _can_settle(addresses: [AztecAddress;10], required_mask: u16) -> bool {
        let mut valid = true;
        for i in 1..10 {
            if (required_mask & (1u16 << i)) != 0 {
                if self.storage.kinds.at(addresses[i as u32]).read() != (i as u8) { valid = false; }
            }
        }
        valid
    }
    #[internal("public")]
    fn _verify_hash(ns: AztecAddress, key: Field, hash: Field) -> bool {
        aztec::oracle::avm::storage_read(aztec::protocol::storage::map::derive_storage_slot_in_map(3,key),ns.to_field()) == hash
    }
    #[internal("public")]
    fn _is_initialized(ns: AztecAddress, key: Field) -> bool {
        aztec::oracle::avm::storage_read(aztec::protocol::storage::map::derive_storage_slot_in_map(3,key),ns.to_field()) != 0
    }
    #[internal("public")]
    fn _verify_hashes_batch(ns: AztecAddress, ids:[Field;20], hashes:[Field;20], count:u32) -> bool {
        assert(count <= 20, "count exceeds batch size");
        let mut result = true;
        for i in 0..count {
            if result & (ids[i] != 0) {
                if aztec::oracle::avm::storage_read(aztec::protocol::storage::map::derive_storage_slot_in_map(3,ids[i]),ns.to_field()) != hashes[i] { result = false; }
            }
        }
        result
    }
    #[internal("public")]
    fn _verify_hashes_three(ns:AztecAddress, ids:[Field;3], hashes:[Field;3])->[bool;3] {
        let first = aztec::oracle::avm::storage_read(aztec::protocol::storage::map::derive_storage_slot_in_map(3,ids[0]),ns.to_field());
        let second = if ids[1] == ids[0] { first }
            else { aztec::oracle::avm::storage_read(aztec::protocol::storage::map::derive_storage_slot_in_map(3,ids[1]),ns.to_field()) };
        let third = if ids[2] == ids[0] { first }
            else if ids[2] == ids[1] { second }
            else { aztec::oracle::avm::storage_read(aztec::protocol::storage::map::derive_storage_slot_in_map(3,ids[2]),ns.to_field()) };
        [first == hashes[0], second == hashes[1], third == hashes[2]]
    }
    #[internal("public")]
    fn _store_arrival_payload(ns:AztecAddress, id:Field, packed:[Field;7]) {
        let slot=self.storage.arrivals.at(ns).at(id).get_storage_slot();
        for i in 0..7 {
            // Unwritten words already read as zero. On an overwrite, explicitly
            // clear any old nonzero word, so compact/full transitions are exact.
            if packed[i] != 0 {
                self.context.raw_storage_write(slot+i as Field,[packed[i]]);
            } else {
                let old:[Field;1]=self.context.raw_storage_read(slot+i as Field);
                if old[0] != 0 { self.context.raw_storage_write(slot+i as Field,[0]); }
            }
        }
    }
    #[internal("public")]
    fn _allocate_event_id(ns:AztecAddress, actor:AztecAddress)->Field {
        self.internal._assert_authorized(ns,actor);
        let next=self.storage.counters.at(ns).read()+1;
        self.storage.counters.at(ns).write(next); next
    }
    #[external("public")]
    fn allocate_event_id(actor:AztecAddress)->Field {
        let ns=self.msg_sender(); self.internal._expect_kind(ns,7);
        self.internal._allocate_event_id(ns,actor)
    }
    #[internal("public")]
    fn _write_world(ns:AztecAddress, actor:AztecAddress, id:Field, state:World, new_root:Field, prepared:bool) -> Field {
        self.internal._assert_authorized(ns,actor);

        // Every game settlement authenticates its immutable System caller once
        // before reaching this helper. Original arbitrary writers use the
        // class-authenticated typed facade setters, which hash their own state.
        let root = if prepared { new_root } else { poseidon2_hash(state.serialize()) };

        root
    }
    #[internal("public")]
    fn _set_world(ns:AztecAddress, actor:AztecAddress, id:Field, state:World, new_root:Field, prepared:bool) {
        let root = self.internal._write_world(ns,actor,id,state,new_root,prepared);
        let fields=state.serialize();
        self.call(StateFacadeInterface::at(ns).emit_world_fields(id,root,fields[0], fields[1], fields[2], fields[3]));
    }
    #[internal("public")]
    fn _set_world_fields(ns:AztecAddress, actor:AztecAddress, id:Field, fields:[Field;4], new_root:Field, prepared:bool) {
        self.internal._assert_authorized(ns,actor);
        // Only immutable, class-authenticated typed producers can reach this
        // internal primitive. Original arbitrary writers use typed facade APIs.
        let root = if prepared { new_root } else { poseidon2_hash(fields) };
        self.call(StateFacadeInterface::at(ns).emit_world_fields(id,root,fields[0], fields[1], fields[2], fields[3]));
    }
    #[internal("public")]
    fn _write_player(ns:AztecAddress, actor:AztecAddress, id:Field, state:Player, new_root:Field, prepared:bool) -> Field {
        self.internal._assert_authorized(ns,actor);

        // Every game settlement authenticates its immutable System caller once
        // before reaching this helper. Original arbitrary writers use the
        // class-authenticated typed facade setters, which hash their own state.
        let root = if prepared { new_root } else { poseidon2_hash(state.serialize()) };

        root
    }
    #[internal("public")]
    fn _set_player(ns:AztecAddress, actor:AztecAddress, id:Field, state:Player, new_root:Field, prepared:bool) {
        let root = self.internal._write_player(ns,actor,id,state,new_root,prepared);
        let fields=state.serialize();
        self.call(StateFacadeInterface::at(ns).emit_player_fields(id,root,fields[0], fields[1], fields[2], fields[3], fields[4], fields[5], fields[6], fields[7]));
    }
    #[internal("public")]
    fn _set_player_fields(ns:AztecAddress, actor:AztecAddress, id:Field, fields:[Field;8], new_root:Field, prepared:bool) {
        self.internal._assert_authorized(ns,actor);
        // Only immutable, class-authenticated typed producers can reach this
        // internal primitive. Original arbitrary writers use typed facade APIs.
        let root = if prepared { new_root } else { poseidon2_hash(fields) };
        self.call(StateFacadeInterface::at(ns).emit_player_fields(id,root,fields[0], fields[1], fields[2], fields[3], fields[4], fields[5], fields[6], fields[7]));
    }
    #[internal("public")]
    fn _write_planet(ns:AztecAddress, actor:AztecAddress, id:Field, state:Planet, new_root:Field, prepared:bool) -> Field {
        self.internal._assert_authorized(ns,actor);

        // Every game settlement authenticates its immutable System caller once
        // before reaching this helper. Original arbitrary writers use the
        // class-authenticated typed facade setters, which hash their own state.
        let root = if prepared { new_root } else { poseidon2_hash(state.serialize()) };

        root
    }
    #[internal("public")]
    fn _set_planet(ns:AztecAddress, actor:AztecAddress, id:Field, state:Planet, new_root:Field, prepared:bool) {
        let root = self.internal._write_planet(ns,actor,id,state,new_root,prepared);
        let fields=state.serialize();
        self.call(StateFacadeInterface::at(ns).emit_planet_fields(id,root,fields[0], fields[1], fields[2], fields[3], fields[4], fields[5], fields[6], fields[7], fields[8], fields[9], fields[10], fields[11], fields[12], fields[13], fields[14], fields[15], fields[16], fields[17], fields[18], fields[19], fields[20], fields[21], fields[22], fields[23], fields[24], fields[25], fields[26], fields[27], fields[28], fields[29], fields[30], fields[31]));
    }
    #[internal("public")]
    fn _set_planet_fields(ns:AztecAddress, actor:AztecAddress, id:Field, fields:[Field;32], new_root:Field, prepared:bool) {
        self.internal._assert_authorized(ns,actor);
        // Only immutable, class-authenticated typed producers can reach this
        // internal primitive. Original arbitrary writers use typed facade APIs.
        let root = if prepared { new_root } else { poseidon2_hash(fields) };
        self.call(StateFacadeInterface::at(ns).emit_planet_fields(id,root,fields[0], fields[1], fields[2], fields[3], fields[4], fields[5], fields[6], fields[7], fields[8], fields[9], fields[10], fields[11], fields[12], fields[13], fields[14], fields[15], fields[16], fields[17], fields[18], fields[19], fields[20], fields[21], fields[22], fields[23], fields[24], fields[25], fields[26], fields[27], fields[28], fields[29], fields[30], fields[31]));
    }
    #[internal("public")]
    fn _write_planet_revealed_coords(ns:AztecAddress, actor:AztecAddress, id:Field, state:PlanetRevealedCoords, new_root:Field, prepared:bool) -> Field {
        self.internal._assert_authorized(ns,actor);

        // Every game settlement authenticates its immutable System caller once
        // before reaching this helper. Original arbitrary writers use the
        // class-authenticated typed facade setters, which hash their own state.
        let root = if prepared { new_root } else { poseidon2_hash(state.serialize()) };

        root
    }
    #[internal("public")]
    fn _set_planet_revealed_coords(ns:AztecAddress, actor:AztecAddress, id:Field, state:PlanetRevealedCoords, new_root:Field, prepared:bool) {
        let root = self.internal._write_planet_revealed_coords(ns,actor,id,state,new_root,prepared);
        let fields=state.serialize();
        self.call(StateFacadeInterface::at(ns).emit_planet_revealed_coords_fields(id,root,fields[0], fields[1], fields[2], fields[3]));
    }
    #[internal("public")]
    fn _set_planet_revealed_coords_fields(ns:AztecAddress, actor:AztecAddress, id:Field, fields:[Field;4], new_root:Field, prepared:bool) {
        self.internal._assert_authorized(ns,actor);
        // Only immutable, class-authenticated typed producers can reach this
        // internal primitive. Original arbitrary writers use typed facade APIs.
        let root = if prepared { new_root } else { poseidon2_hash(fields) };
        self.call(StateFacadeInterface::at(ns).emit_planet_revealed_coords_fields(id,root,fields[0], fields[1], fields[2], fields[3]));
    }
    #[internal("public")]
    fn _write_planet_events(ns:AztecAddress, actor:AztecAddress, id:Field, state:PlanetEvents, new_root:Field, prepared:bool) -> Field {
        self.internal._assert_authorized(ns,actor);

        // Every game settlement authenticates its immutable System caller once
        // before reaching this helper. Original arbitrary writers use the
        // class-authenticated typed facade setters, which hash their own state.
        let root = if prepared { new_root } else { poseidon2_hash(state.serialize()) };

        root
    }
    #[internal("public")]
    fn _set_planet_events(ns:AztecAddress, actor:AztecAddress, id:Field, state:PlanetEvents, new_root:Field, prepared:bool) {
        let root = self.internal._write_planet_events(ns,actor,id,state,new_root,prepared);
        let fields=state.serialize();
        self.call(StateFacadeInterface::at(ns).emit_planet_events_fields(id,root,fields[0], fields[1], fields[2], fields[3], fields[4], fields[5], fields[6], fields[7], fields[8], fields[9], fields[10], fields[11], fields[12], fields[13], fields[14], fields[15], fields[16], fields[17], fields[18], fields[19], fields[20], fields[21]));
    }
    #[internal("public")]
    fn _set_planet_events_fields(ns:AztecAddress, actor:AztecAddress, id:Field, fields:[Field;22], new_root:Field, prepared:bool) {
        self.internal._assert_authorized(ns,actor);
        // Only immutable, class-authenticated typed producers can reach this
        // internal primitive. Original arbitrary writers use typed facade APIs.
        let root = if prepared { new_root } else { poseidon2_hash(fields) };
        self.call(StateFacadeInterface::at(ns).emit_planet_events_fields(id,root,fields[0], fields[1], fields[2], fields[3], fields[4], fields[5], fields[6], fields[7], fields[8], fields[9], fields[10], fields[11], fields[12], fields[13], fields[14], fields[15], fields[16], fields[17], fields[18], fields[19], fields[20], fields[21]));
    }
    #[internal("public")]
    fn _write_planet_artifacts(ns:AztecAddress, actor:AztecAddress, id:Field, state:PlanetArtifacts, new_root:Field, prepared:bool) -> Field {
        self.internal._assert_authorized(ns,actor);

        // Every game settlement authenticates its immutable System caller once
        // before reaching this helper. Original arbitrary writers use the
        // class-authenticated typed facade setters, which hash their own state.
        let root = if prepared { new_root } else { poseidon2_hash(state.serialize()) };

        root
    }
    #[internal("public")]
    fn _set_planet_artifacts(ns:AztecAddress, actor:AztecAddress, id:Field, state:PlanetArtifacts, new_root:Field, prepared:bool) {
        let root = self.internal._write_planet_artifacts(ns,actor,id,state,new_root,prepared);
        let fields=state.serialize();
        self.call(StateFacadeInterface::at(ns).emit_planet_artifacts_fields(id,root,fields[0], fields[1], fields[2], fields[3], fields[4], fields[5], fields[6], fields[7], fields[8], fields[9], fields[10], fields[11], fields[12], fields[13], fields[14], fields[15], fields[16], fields[17], fields[18], fields[19], fields[20], fields[21]));
    }
    #[internal("public")]
    fn _set_planet_artifacts_fields(ns:AztecAddress, actor:AztecAddress, id:Field, fields:[Field;22], new_root:Field, prepared:bool) {
        self.internal._assert_authorized(ns,actor);
        // Only immutable, class-authenticated typed producers can reach this
        // internal primitive. Original arbitrary writers use typed facade APIs.
        let root = if prepared { new_root } else { poseidon2_hash(fields) };
        self.call(StateFacadeInterface::at(ns).emit_planet_artifacts_fields(id,root,fields[0], fields[1], fields[2], fields[3], fields[4], fields[5], fields[6], fields[7], fields[8], fields[9], fields[10], fields[11], fields[12], fields[13], fields[14], fields[15], fields[16], fields[17], fields[18], fields[19], fields[20], fields[21]));
    }
    #[internal("public")]
    fn _write_arrival(ns:AztecAddress, actor:AztecAddress, id:Field, state:Arrival, new_root:Field, prepared:bool) -> Field {
        self.internal._assert_authorized(ns,actor);
        assert(id == state.id, "id mismatch");
        // Every game settlement authenticates its immutable System caller once
        // before reaching this helper. Original arbitrary writers use the
        // class-authenticated typed facade setters, which hash their own state.
        let root = if prepared { new_root } else { poseidon2_hash(state.serialize()) };
        self.internal._store_arrival_payload(ns,id,pack_arrival(state));
        root
    }
    #[internal("public")]
    fn _set_arrival(ns:AztecAddress, actor:AztecAddress, id:Field, state:Arrival, new_root:Field, prepared:bool) {
        let root = self.internal._write_arrival(ns,actor,id,state,new_root,prepared);
        let fields=state.serialize();
        self.call(StateFacadeInterface::at(ns).emit_arrival_fields(id,root,fields[0], fields[1], fields[2], fields[3], fields[4], fields[5], fields[6], fields[7], fields[8], fields[9], fields[10]));
    }
    #[internal("public")]
    fn _write_artifact(ns:AztecAddress, actor:AztecAddress, id:Field, state:Artifact, new_root:Field, prepared:bool) -> Field {
        self.internal._assert_authorized(ns,actor);

        // Every game settlement authenticates its immutable System caller once
        // before reaching this helper. Original arbitrary writers use the
        // class-authenticated typed facade setters, which hash their own state.
        let root = if prepared { new_root } else { poseidon2_hash(state.serialize()) };

        root
    }
    #[internal("public")]
    fn _set_artifact(ns:AztecAddress, actor:AztecAddress, id:Field, state:Artifact, new_root:Field, prepared:bool) {
        let root = self.internal._write_artifact(ns,actor,id,state,new_root,prepared);
        let fields=state.serialize();
        self.call(StateFacadeInterface::at(ns).emit_artifact_fields(id,root,fields[0], fields[1], fields[2], fields[3], fields[4], fields[5], fields[6], fields[7], fields[8], fields[9], fields[10], fields[11], fields[12]));
    }
    #[internal("public")]
    fn _set_artifact_fields(ns:AztecAddress, actor:AztecAddress, id:Field, fields:[Field;13], new_root:Field, prepared:bool) {
        self.internal._assert_authorized(ns,actor);
        // Only immutable, class-authenticated typed producers can reach this
        // internal primitive. Original arbitrary writers use typed facade APIs.
        let root = if prepared { new_root } else { poseidon2_hash(fields) };
        self.call(StateFacadeInterface::at(ns).emit_artifact_fields(id,root,fields[0], fields[1], fields[2], fields[3], fields[4], fields[5], fields[6], fields[7], fields[8], fields[9], fields[10], fields[11], fields[12]));
    }
    #[internal("public")]
    fn _write_artifact_location(ns:AztecAddress, actor:AztecAddress, id:Field, state:ArtifactLocation, new_root:Field, prepared:bool) -> Field {
        self.internal._assert_authorized(ns,actor);

        // Every game settlement authenticates its immutable System caller once
        // before reaching this helper. Original arbitrary writers use the
        // class-authenticated typed facade setters, which hash their own state.
        let root = if prepared { new_root } else { poseidon2_hash(state.serialize()) };

        root
    }
    #[internal("public")]
    fn _set_artifact_location(ns:AztecAddress, actor:AztecAddress, id:Field, state:ArtifactLocation, new_root:Field, prepared:bool) {
        let root = self.internal._write_artifact_location(ns,actor,id,state,new_root,prepared);
        let fields=state.serialize();
        self.call(StateFacadeInterface::at(ns).emit_artifact_location_fields(id,root,fields[0], fields[1], fields[2]));
    }
    #[internal("public")]
    fn _set_artifact_location_fields(ns:AztecAddress, actor:AztecAddress, id:Field, fields:[Field;3], new_root:Field, prepared:bool) {
        self.internal._assert_authorized(ns,actor);
        // Only immutable, class-authenticated typed producers can reach this
        // internal primitive. Original arbitrary writers use typed facade APIs.
        let root = if prepared { new_root } else { poseidon2_hash(fields) };
        self.call(StateFacadeInterface::at(ns).emit_artifact_location_fields(id,root,fields[0], fields[1], fields[2]));
    }
    // The immutable Arrival facade authenticates its actual caller here.
    // No external callback occurs between payload storage and its local root write.
    #[external("public")]
    fn legacy_set_arrival(actor:AztecAddress,id:Field,state_id:Field,packed:[Field;7]) {
        let ns=self.msg_sender();self.internal._expect_kind(ns,7);
        self.internal._assert_authorized(ns,actor);
        assert(id == state_id, "id mismatch");
        self.internal._store_arrival_payload(ns,id,packed);
    }
    #[internal("public")]
    fn _emit_artifact_location_batch_max5(ns:AztecAddress,ids:[Field;5],fields:[[Field;3];5],count:u32) {
        if count == 1 {
            self.call(StateFacadeInterface::at(ns).emit_artifact_location_fields(ids[0],poseidon2_hash(fields[0]),fields[0][0], fields[0][1], fields[0][2]));
        } else if count > 1 {
            self.call(StateFacadeInterface::at(ns).emit_artifact_location_batch_max5(ids,fields,count));
        }
    }
    #[internal("public")]
    fn _emit_artifact_batch_max5(ns:AztecAddress,ids:[Field;5],fields:[[Field;13];5],count:u32) {
        if count == 1 {
            self.call(StateFacadeInterface::at(ns).emit_artifact_fields(ids[0],poseidon2_hash(fields[0]),fields[0][0], fields[0][1], fields[0][2], fields[0][3], fields[0][4], fields[0][5], fields[0][6], fields[0][7], fields[0][8], fields[0][9], fields[0][10], fields[0][11], fields[0][12]));
        } else if count > 1 {
            self.call(StateFacadeInterface::at(ns).emit_artifact_batch_max5(ids,fields,count));
        }
    }
    #[internal("public")]
    fn _emit_artifact_location_batch_max20(ns:AztecAddress,ids:[Field;20],fields:[[Field;3];20],count:u32) {
        if count <= 5 {
            let small_ids=[ids[0],ids[1],ids[2],ids[3],ids[4]];
            let small_fields=[fields[0],fields[1],fields[2],fields[3],fields[4]];
            self.internal._emit_artifact_location_batch_max5(ns,small_ids,small_fields,count);
        } else {
            self.call(StateFacadeInterface::at(ns).emit_artifact_location_batch_max20(ids,fields,count));
        }
    }
    #[internal("public")]
    fn _set_arrival_locations_max20(ns:AztecAddress,actor:AztecAddress,ids:[Field;20],states:[ArtifactLocation;20],count:u32) {
        self.internal._assert_authorized(ns,actor);
        assert(count<=20,"count exceeds batch size");
        let mut active_ids=[0;20];
        let mut fields=[[0;3];20];
        let mut active=0;
        for i in 0..count {
            if ids[i]!=0 {
                active_ids[active]=ids[i];
                fields[active]=states[i].serialize();
                active+=1;
            }
        }
        self.internal._emit_artifact_location_batch_max20(ns,active_ids,fields,active);
    }
    #[internal("public")]
    fn _set_spaceship_locations_max5(ns:AztecAddress,actor:AztecAddress,ids:[Field;5],states:[ArtifactLocation;5],count:u32) {
        self.internal._assert_authorized(ns,actor);
        assert(count<=5,"count exceeds batch size");
        let mut active_ids=[0;5];
        let mut fields=[[0;3];5];
        let mut active=0;
        for i in 0..count {
            if ids[i]!=0 {
                active_ids[active]=ids[i];
                fields[active]=states[i].serialize();
                active+=1;
            }
        }
        self.internal._emit_artifact_location_batch_max5(ns,active_ids,fields,active);
    }
    #[internal("public")]
    fn _set_spaceships_max5(ns:AztecAddress,actor:AztecAddress,ids:[Field;5],states:[Artifact;5],count:u32) {
        self.internal._assert_authorized(ns,actor);
        assert(count<=5,"count exceeds batch size");
        let mut active_ids=[0;5];
        let mut fields=[[0;13];5];
        let mut active=0;
        for i in 0..count {
            if ids[i]!=0 {
                active_ids[active]=ids[i];
                fields[active]=states[i].serialize();
                active+=1;
            }
        }
        self.internal._emit_artifact_batch_max5(ns,active_ids,fields,active);
    }

// Generated generic plan execution. Original System continuations retain all game checks.
    #[inline_never]
    #[contract_library_method]
    unconstrained fn _resolve_plan_actor(context: aztec::context::PublicContext, claimed_actor: AztecAddress) -> AztecAddress {
        let self = __aztec_nr_internals__create_public_self_from_context(context);
        let caller = self.msg_sender();
        let current = get_contract_instance_current_class_id_avm(caller);
        assert(current.is_some(), "Only audited settlement worker");
        let caller_id = current.unwrap().to_field();
        if super::trusted_classes::contains(caller_id) { caller } else {
            let system_class = get_contract_instance_current_class_id_avm(claimed_actor);
            assert(system_class.is_some(), "Only audited settlement worker");
            let system_id = system_class.unwrap().to_field();
            assert((caller_id != 0) & (system_id != 0), "Only audited settlement worker");
            assert(
                ((caller_id == super::trusted_classes::WORKER_CLASSES[0]) & (system_id == super::trusted_classes::SYSTEM_CLASSES[1]))
                | ((caller_id == super::trusted_classes::WORKER_CLASSES[1]) & (system_id == super::trusted_classes::SYSTEM_CLASSES[6])),
                "Only audited settlement worker",
            );
            claimed_actor
        }
    }
    #[inline_never]
    #[contract_library_method]
    unconstrained fn _commit_state_plan(context: aztec::context::PublicContext, addresses:[AztecAddress;10], required_mask:u16, words:[Field], length:u32, actor:AztecAddress) {
        let self = __aztec_nr_internals__create_public_self_from_context(context);
        assert(self.internal._can_settle(addresses,required_mask), "Settlement namespaces changed");
        let end = 12 + length;
        assert(end <= words.len(), "Write plan length exceeded");
        let mut cursor = 12;
        while cursor < end {
            assert(cursor + 3 <= end, "Truncated write header");
            let descriptor = words[cursor] as u32;
            assert(descriptor as Field == words[cursor], "Invalid write descriptor");
            assert(descriptor < 128, "Invalid write descriptor");
            let namespace = descriptor & 15;
            let prepared = descriptor & 16 != 0;
            let auth_only = descriptor & 32 != 0;
            let batch = descriptor & 64 != 0;
            assert(!(batch & (auth_only | prepared)), "Invalid batch descriptor");
            assert(namespace >= 1 & namespace <= 9, "Invalid write namespace");
            assert((required_mask & (1u16 << (namespace as u16))) != 0, "Unvalidated write namespace");
            let ns = addresses[namespace];
            let key = words[cursor+1];
            let root = words[cursor+2];
            cursor += 3;
            if auth_only | batch {
                self.internal._assert_authorized(ns,actor);
                let count = key as u32;
                let maximum = root as u32;
                assert(count as Field == key, "Invalid batch count");
                assert(maximum as Field == root, "Invalid batch maximum");
                assert(((namespace == 9) & ((maximum == 5) | (maximum == 20))) | ((namespace == 8) & (maximum == 5)), "Invalid batch kind");
                assert(count <= maximum, "count exceeds batch size");
                if batch {
                    assert(cursor < end, "Truncated batch header");
                    let active=words[cursor] as u32;
                    assert(active as Field == words[cursor], "Invalid active count");
                    assert(active <= count, "Active count exceeds batch count");
                    cursor+=1;
                    if namespace == 9 {
                        assert(cursor + active*4 <= end, "Truncated location batch");
                        let mut ids=[0;20];
                        let mut fields=[[0;3];20];
                        for i in 0..active {
                            ids[i]=words[cursor];
                            fields[i]=[words[cursor+1],words[cursor+2],words[cursor+3]];
                            assert(ids[i]!=0,"Invalid compact batch ID");
                            cursor+=4;
                        }
                        self.internal._emit_artifact_location_batch_max20(ns,ids,fields,active);
                    } else {
                        assert(cursor + active*14 <= end, "Truncated artifact batch");
                        let mut ids=[0;5];
                        let mut fields=[[0;13];5];
                        for i in 0..active {
                            ids[i]=words[cursor];
                            for j in 0..13 { fields[i][j]=words[cursor+1+j]; }
                            assert(ids[i]!=0,"Invalid compact batch ID");
                            cursor+=14;
                        }
                        self.internal._emit_artifact_batch_max5(ns,ids,fields,active);
                    }
                }
            } else {
                if namespace == 2 {
                    assert(cursor + 8 <= end, "Truncated player payload");
                    let fields: [Field;8] = [words[cursor+0], words[cursor+1], words[cursor+2], words[cursor+3], words[cursor+4], words[cursor+5], words[cursor+6], words[cursor+7]];
                    // The audited System serialized canonical typed state before the guarded commit.
                    self.internal._set_player_fields(ns,actor,key,fields,root,prepared);
                    cursor += 8;
                }
                else if namespace == 3 {
                    assert(cursor + 32 <= end, "Truncated planet payload");
                    let fields: [Field;32] = [words[cursor+0], words[cursor+1], words[cursor+2], words[cursor+3], words[cursor+4], words[cursor+5], words[cursor+6], words[cursor+7], words[cursor+8], words[cursor+9], words[cursor+10], words[cursor+11], words[cursor+12], words[cursor+13], words[cursor+14], words[cursor+15], words[cursor+16], words[cursor+17], words[cursor+18], words[cursor+19], words[cursor+20], words[cursor+21], words[cursor+22], words[cursor+23], words[cursor+24], words[cursor+25], words[cursor+26], words[cursor+27], words[cursor+28], words[cursor+29], words[cursor+30], words[cursor+31]];
                    // The audited System serialized canonical typed state before the guarded commit.
                    self.internal._set_planet_fields(ns,actor,key,fields,root,prepared);
                    cursor += 32;
                }
                else if namespace == 4 {
                    assert(cursor + 4 <= end, "Truncated planet_revealed_coords payload");
                    let fields: [Field;4] = [words[cursor+0], words[cursor+1], words[cursor+2], words[cursor+3]];
                    // The audited System serialized canonical typed state before the guarded commit.
                    self.internal._set_planet_revealed_coords_fields(ns,actor,key,fields,root,prepared);
                    cursor += 4;
                }
                else if namespace == 5 {
                    assert(cursor + 22 <= end, "Truncated planet_events payload");
                    let fields: [Field;22] = [words[cursor+0], words[cursor+1], words[cursor+2], words[cursor+3], words[cursor+4], words[cursor+5], words[cursor+6], words[cursor+7], words[cursor+8], words[cursor+9], words[cursor+10], words[cursor+11], words[cursor+12], words[cursor+13], words[cursor+14], words[cursor+15], words[cursor+16], words[cursor+17], words[cursor+18], words[cursor+19], words[cursor+20], words[cursor+21]];
                    // The audited System serialized canonical typed state before the guarded commit.
                    self.internal._set_planet_events_fields(ns,actor,key,fields,root,prepared);
                    cursor += 22;
                }
                else if namespace == 6 {
                    assert(cursor + 22 <= end, "Truncated planet_artifacts payload");
                    let fields: [Field;22] = [words[cursor+0], words[cursor+1], words[cursor+2], words[cursor+3], words[cursor+4], words[cursor+5], words[cursor+6], words[cursor+7], words[cursor+8], words[cursor+9], words[cursor+10], words[cursor+11], words[cursor+12], words[cursor+13], words[cursor+14], words[cursor+15], words[cursor+16], words[cursor+17], words[cursor+18], words[cursor+19], words[cursor+20], words[cursor+21]];
                    // The audited System serialized canonical typed state before the guarded commit.
                    self.internal._set_planet_artifacts_fields(ns,actor,key,fields,root,prepared);
                    cursor += 22;
                }
                else if namespace == 8 {
                    assert(cursor + 13 <= end, "Truncated artifact payload");
                    let fields: [Field;13] = [words[cursor+0], words[cursor+1], words[cursor+2], words[cursor+3], words[cursor+4], words[cursor+5], words[cursor+6], words[cursor+7], words[cursor+8], words[cursor+9], words[cursor+10], words[cursor+11], words[cursor+12]];
                    // The audited System serialized canonical typed state before the guarded commit.
                    self.internal._set_artifact_fields(ns,actor,key,fields,root,prepared);
                    cursor += 13;
                }
                else if namespace == 9 {
                    assert(cursor + 3 <= end, "Truncated artifact_location payload");
                    let fields: [Field;3] = [words[cursor+0], words[cursor+1], words[cursor+2]];
                    // The audited System serialized canonical typed state before the guarded commit.
                    self.internal._set_artifact_location_fields(ns,actor,key,fields,root,prepared);
                    cursor += 3;
                }
                else { assert(false, "Unsupported write namespace"); }
            }
        }
    }
    #[external("public")]
    fn commit_plan_small(payload: ::libs::field_buffer::FieldBuffer<141>) {
        let actor = _resolve_plan_actor(self.context, AztecAddress::from_field(payload.words[0]));
        let addresses=[AztecAddress::from_field(payload.words[1]), AztecAddress::from_field(payload.words[2]), AztecAddress::from_field(payload.words[3]), AztecAddress::from_field(payload.words[4]), AztecAddress::from_field(payload.words[5]), AztecAddress::from_field(payload.words[6]), AztecAddress::from_field(payload.words[7]), AztecAddress::from_field(payload.words[8]), AztecAddress::from_field(payload.words[9]), AztecAddress::from_field(payload.words[10])];
        let required_mask=payload.words[11] as u16;
        let length=payload.words[140] as u32;
        assert(length <= 128, "Write plan length exceeded");
        _commit_state_plan(self.context,addresses,required_mask,payload.words.as_slice(),length,actor);
    }
    #[external("public")]
    fn commit_plan_medium(payload: ::libs::field_buffer::FieldBuffer<185>) {
        let actor = _resolve_plan_actor(self.context, AztecAddress::from_field(payload.words[0]));
        let addresses=[AztecAddress::from_field(payload.words[1]), AztecAddress::from_field(payload.words[2]), AztecAddress::from_field(payload.words[3]), AztecAddress::from_field(payload.words[4]), AztecAddress::from_field(payload.words[5]), AztecAddress::from_field(payload.words[6]), AztecAddress::from_field(payload.words[7]), AztecAddress::from_field(payload.words[8]), AztecAddress::from_field(payload.words[9]), AztecAddress::from_field(payload.words[10])];
        let required_mask=payload.words[11] as u16;
        let length=payload.words[184] as u32;
        assert(length <= 172, "Write plan length exceeded");
        _commit_state_plan(self.context,addresses,required_mask,payload.words.as_slice(),length,actor);
    }
    #[external("public")]
    fn commit_plan(payload: ::libs::field_buffer::FieldBuffer<397>) {
        let actor = _resolve_plan_actor(self.context, AztecAddress::from_field(payload.words[0]));
        let addresses=[AztecAddress::from_field(payload.words[1]), AztecAddress::from_field(payload.words[2]), AztecAddress::from_field(payload.words[3]), AztecAddress::from_field(payload.words[4]), AztecAddress::from_field(payload.words[5]), AztecAddress::from_field(payload.words[6]), AztecAddress::from_field(payload.words[7]), AztecAddress::from_field(payload.words[8]), AztecAddress::from_field(payload.words[9]), AztecAddress::from_field(payload.words[10])];
        let required_mask=payload.words[11] as u16;
        let length=payload.words[396] as u32;
        assert(length <= 384, "Write plan length exceeded");
        _commit_state_plan(self.context,addresses,required_mask,payload.words.as_slice(),length,actor);
    }

    // The original private System asserts both queue and inventory counts zero.
    // Its complete341-word enqueue is retained for exact custom-store fallback.
    #[external("public")]
    fn try_settle_give_spaceships(payload: ::libs::field_buffer::FieldBuffer<186>) -> bool {
        assert(self.internal._is_prepared_writer(self.msg_sender()), "Only audited system");
        let player=AztecAddress::from_field(payload.words[0]);
        let planet=AztecAddress::from_field(payload.words[1]);
        let planet_events=AztecAddress::from_field(payload.words[2]);
        let planet_artifacts=AztecAddress::from_field(payload.words[3]);
        let artifact=AztecAddress::from_field(payload.words[4]);
        let artifact_location=AztecAddress::from_field(payload.words[5]);
        let supported=(self.storage.kinds.at(player).read()==2)
            & (self.storage.kinds.at(planet).read()==3)
            & (self.storage.kinds.at(planet_events).read()==5)
            & (self.storage.kinds.at(planet_artifacts).read()==6)
            & (self.storage.kinds.at(artifact).read()==8)
            & (self.storage.kinds.at(artifact_location).read()==9);
        if supported {
            let actor=self.msg_sender();
            let sender=payload.words[6];
            let location=payload.words[7];
            assert_public_timestamp(payload.words[8] as u64,self.context.timestamp());
            assert(self.internal._verify_hash(planet,location,payload.words[9]),"planet hash mismatch");
            assert(self.internal._verify_hash(planet_artifacts,location,payload.words[10]),"planet_artifacts hash mismatch");
            assert(self.internal._verify_hash(planet_events,location,payload.words[11]),"planet_events hash mismatch");
            assert(self.internal._verify_hash(player,sender,payload.words[12]),"player hash mismatch");
            self.internal._set_planet_fields(planet,actor,location,[payload.words[13], payload.words[14], payload.words[15], payload.words[16], payload.words[17], payload.words[18], payload.words[19], payload.words[20], payload.words[21], payload.words[22], payload.words[23], payload.words[24], payload.words[25], payload.words[26], payload.words[27], payload.words[28], payload.words[29], payload.words[30], payload.words[31], payload.words[32], payload.words[33], payload.words[34], payload.words[35], payload.words[36], payload.words[37], payload.words[38], payload.words[39], payload.words[40], payload.words[41], payload.words[42], payload.words[43], payload.words[44]],payload.words[182],true);
            self.internal._set_planet_events_fields(planet_events,actor,location,[payload.words[45], payload.words[46], payload.words[47], payload.words[48], payload.words[49], payload.words[50], payload.words[51], payload.words[52], payload.words[53], payload.words[54], payload.words[55], payload.words[56], payload.words[57], payload.words[58], payload.words[59], payload.words[60], payload.words[61], payload.words[62], payload.words[63], payload.words[64], payload.words[65], payload.words[66]],payload.words[183],true);
            self.internal._set_planet_artifacts_fields(planet_artifacts,actor,location,[payload.words[67], payload.words[68], payload.words[69], payload.words[70], payload.words[71], payload.words[72], payload.words[73], payload.words[74], payload.words[75], payload.words[76], payload.words[77], payload.words[78], payload.words[79], payload.words[80], payload.words[81], payload.words[82], payload.words[83], payload.words[84], payload.words[85], payload.words[86], payload.words[87], payload.words[88]],payload.words[184],true);
            // Even an empty batch retains its original authorization check.
            self.internal._assert_authorized(artifact_location,actor);
            self.internal._set_player_fields(player,actor,sender,[payload.words[89], payload.words[90], payload.words[91], payload.words[92], payload.words[93], payload.words[94], payload.words[95], payload.words[96]],payload.words[185],true);
            self.internal._assert_authorized(artifact,actor);
            let mut ids=[0;5];
            let mut ships=[[0;13];5];
            let mut active=0;
            for i in 0..5 {
                let id=payload.words[97+i];
                if id!=0 {
                    ids[active]=id;
                    ships[active]=[payload.words[102+i*13+0], payload.words[102+i*13+1], payload.words[102+i*13+2], payload.words[102+i*13+3], payload.words[102+i*13+4], payload.words[102+i*13+5], payload.words[102+i*13+6], payload.words[102+i*13+7], payload.words[102+i*13+8], payload.words[102+i*13+9], payload.words[102+i*13+10], payload.words[102+i*13+11], payload.words[102+i*13+12]];
                    active+=1;
                }
            }
            self.internal._emit_artifact_batch_max5(artifact,ids,ships,active);
            self.internal._assert_authorized(artifact_location,actor);
            let mut locations=[[0;3];5];
            active=0;
            for i in 0..5 {
                if payload.words[97+i]!=0 {
                    locations[active]=[payload.words[167+i*3+0], payload.words[167+i*3+1], payload.words[167+i*3+2]];
                    active+=1;
                }
            }
            self.internal._emit_artifact_location_batch_max5(artifact_location,ids,locations,active);
        }
        supported
    }
    #[external("public")]
    fn try_settle_initialize_new(payload: ::libs::field_buffer::FieldBuffer<60>) -> bool {
        assert(self.internal._is_prepared_writer(self.msg_sender()), "Only audited system");
        let config_address=AztecAddress::from_field(payload.words[0]);
        let world=AztecAddress::from_field(payload.words[1]);
        let player=AztecAddress::from_field(payload.words[2]);
        let planet=AztecAddress::from_field(payload.words[3]);
        let supported=(self.storage.kinds.at(world).read()==1)
            & (self.storage.kinds.at(player).read()==2)
            & (self.storage.kinds.at(planet).read()==3);
        if supported {
            assert_public_timestamp(payload.words[6] as u64,self.context.timestamp());
            let config=Config::at(config_address);
            let config_hashes=[payload.words[7], payload.words[8], payload.words[9], payload.words[10], payload.words[11], payload.words[12], payload.words[13], payload.words[14], payload.words[15]];
            assert(self.view(config.verify_config_hashes(payload.words[21] as u8,payload.words[16],config_hashes)),"Config hash mismatch");
            assert(!self.internal._is_initialized(player,payload.words[4]),"Player already initialized");
            assert(payload.words[17]!=0,"World state must be initialized");
            assert(self.internal._verify_hash(world,0,payload.words[17]),"World state hash mismatch");
            let actor=self.msg_sender();
            let planet_fields=[payload.words[18], payload.words[19], payload.words[20], payload.words[21], payload.words[22], payload.words[23], payload.words[24], payload.words[25], payload.words[26], payload.words[27], payload.words[28], payload.words[29], payload.words[30], payload.words[31], payload.words[32], payload.words[33], payload.words[34], payload.words[35], payload.words[36], payload.words[37], payload.words[38], payload.words[39], payload.words[40], payload.words[41], payload.words[42], payload.words[43], payload.words[44], payload.words[45], payload.words[46], payload.words[47], payload.words[48], payload.words[49]];
            let player_fields=[payload.words[50], payload.words[51], payload.words[52], payload.words[53], payload.words[54], payload.words[55], payload.words[56], payload.words[57]];
            self.internal._set_planet_fields(planet,actor,payload.words[5],planet_fields,payload.words[58],true);
            self.internal._set_player_fields(player,actor,payload.words[4],player_fields,payload.words[59],true);
        }
        supported
    }
    // The initiating private function selects this path only for count zero.
    #[external("public")]
    fn try_settle_refresh_empty(payload: ::libs::field_buffer::FieldBuffer<88>) -> bool {
        assert(self.internal._is_prepared_writer(self.msg_sender()), "Only audited system");
        let planet=AztecAddress::from_field(payload.words[0]);
        let planet_artifacts=AztecAddress::from_field(payload.words[1]);
        let planet_events=AztecAddress::from_field(payload.words[2]);
        let artifact_location=AztecAddress::from_field(payload.words[3]);
        let supported=(self.storage.kinds.at(planet).read()==3)
            & (self.storage.kinds.at(planet_artifacts).read()==6)
            & (self.storage.kinds.at(planet_events).read()==5)
            & (self.storage.kinds.at(artifact_location).read()==9);
        if supported {
            let actor=self.msg_sender();
            let location=payload.words[4];
            assert_public_timestamp(payload.words[5] as u64,self.context.timestamp());
            assert(self.internal._verify_hash(planet,location,payload.words[6]),"Planet state hash mismatch");
            assert(self.internal._verify_hash(planet_artifacts,location,payload.words[7]),"Planet artifacts state hash mismatch");
            assert(self.internal._verify_hash(planet_events,location,payload.words[8]),"Planet events state hash mismatch");
            let planet_fields=[payload.words[9], payload.words[10], payload.words[11], payload.words[12], payload.words[13], payload.words[14], payload.words[15], payload.words[16], payload.words[17], payload.words[18], payload.words[19], payload.words[20], payload.words[21], payload.words[22], payload.words[23], payload.words[24], payload.words[25], payload.words[26], payload.words[27], payload.words[28], payload.words[29], payload.words[30], payload.words[31], payload.words[32], payload.words[33], payload.words[34], payload.words[35], payload.words[36], payload.words[37], payload.words[38], payload.words[39], payload.words[40]];
            self.internal._set_planet_fields(planet,actor,location,planet_fields,payload.words[85],true);
            let planet_artifacts_fields=[payload.words[41], payload.words[42], payload.words[43], payload.words[44], payload.words[45], payload.words[46], payload.words[47], payload.words[48], payload.words[49], payload.words[50], payload.words[51], payload.words[52], payload.words[53], payload.words[54], payload.words[55], payload.words[56], payload.words[57], payload.words[58], payload.words[59], payload.words[60], payload.words[61], payload.words[62]];
            self.internal._set_planet_artifacts_fields(planet_artifacts,actor,location,planet_artifacts_fields,payload.words[86],true);
            let planet_events_fields=[payload.words[63], payload.words[64], payload.words[65], payload.words[66], payload.words[67], payload.words[68], payload.words[69], payload.words[70], payload.words[71], payload.words[72], payload.words[73], payload.words[74], payload.words[75], payload.words[76], payload.words[77], payload.words[78], payload.words[79], payload.words[80], payload.words[81], payload.words[82], payload.words[83], payload.words[84]];
            self.internal._set_planet_events_fields(planet_events,actor,location,planet_events_fields,payload.words[87],true);
            // The original zero-count batch still checks its writer permission.
            // It occurs after the three typed writes and emits no additional event.
            self.internal._assert_authorized(artifact_location,actor);
        }
        supported
    }


// Generated shared Move settlement; exact canonical statement expansion checked.
    #[inline_never]
    #[contract_library_method]
    unconstrained fn _move_check_source(
        context: aztec::context::PublicContext,
        addresses: [AztecAddress; 10],
        source_loc: Field,
        target_level: u8,
        timestamp: u64,
        config_hashes: [Field; 9],
        artifacts_config_hash: Field,
        planet_default_stats_hash: Field,
        source_planet_hash: Field,
        source_planet_artifacts_state_hash: Field,
        source_planet_events_state_hash: Field,
    ) {
        let mut self = __aztec_nr_internals__create_public_self_from_context(context);
        // Verify timestamp
            let actual_timestamp = self.context.timestamp();
            assert_public_timestamp(timestamp, actual_timestamp);

            let config = Config::at(addresses[0]);








            // The current class, rather than an address or supplied flag, authenticates this cache.
            let mut cached_configuration_matches = false;
            let config_class = get_contract_instance_current_class_id_avm(addresses[0]);
            if config_class.is_some() {
                if (super::trusted_classes::CONFIG_CLASS != 0)
                    & (config_class.unwrap().to_field() == super::trusted_classes::CONFIG_CLASS) {
                    // SLOAD is constrained by the public VM and observes pending
                    // writes. These are the compiler-verified slots of this
                    // exact immutable Config class, not off-chain witness data.
                    let config_common_slot: Field = 304;
                    let config_stats_map_slot: Field = 299;
                    let config_common_root = aztec::oracle::avm::storage_read(
                        config_common_slot, addresses[0].to_field(),
                    );
                    let config_stats_slot = aztec::protocol::storage::map::derive_storage_slot_in_map(
                        config_stats_map_slot, target_level,
                    );
                    let config_default_stats_root = aztec::oracle::avm::storage_read(
                        config_stats_slot, addresses[0].to_field(),
                    );
                    cached_configuration_matches = (config_common_root == poseidon2_hash([
                            config_hashes[0], config_hashes[1], config_hashes[2],
                            config_hashes[3], config_hashes[4], config_hashes[5],
                            config_hashes[6], config_hashes[7], config_hashes[8],
                            artifacts_config_hash,
                        ])) & (config_default_stats_root == planet_default_stats_hash);
                }
            }
            if !cached_configuration_matches {
                // Verify base config hashes in a single cross-contract call
            assert(
                self.view(config.verify_config_hashes(
                    target_level,
                    planet_default_stats_hash,
                    config_hashes,
                )),
                "Config hash mismatch",
            );
            assert(
                self.view(config.verify_artifacts_config_hash(artifacts_config_hash)),
                "Artifacts config hash mismatch",
            );


            }

            // Verify source planet state hashes
            assert(
                self.internal._verify_hash(addresses[3], source_loc, source_planet_hash),
                "Source planet hash mismatch",
            );

            assert(
                self.internal._verify_hash(addresses[6], source_loc, source_planet_artifacts_state_hash),
                "Source planet artifacts hash mismatch",
            );

            assert(
                self.internal._verify_hash(addresses[5], source_loc, source_planet_events_state_hash),
                "Source planet events hash mismatch",
            );
    }

    #[inline_never]
    #[contract_library_method]
    unconstrained fn _move_check_target(
        context: aztec::context::PublicContext,
        addresses: [AztecAddress; 10],
        target_loc: Field,
        target_planet_hash: Field,
        target_planet_artifacts_state_hash: Field,
        target_planet_events_state_hash: Field,
    ) {
        let mut self = __aztec_nr_internals__create_public_self_from_context(context);
        // Verify target planet state hashes
            assert(
                self.internal._verify_hash(addresses[3], target_loc, target_planet_hash),
                "Target planet hash mismatch",
            );

            assert(
                self.internal._verify_hash(addresses[6], target_loc, target_planet_artifacts_state_hash),
                "Target planet artifacts hash mismatch",
            );

            assert(
                self.internal._verify_hash(addresses[5], target_loc, target_planet_events_state_hash),
                "Target planet events hash mismatch",
            );
    }

    #[inline_never]
    #[contract_library_method]
    unconstrained fn _move_check_world_and_allocate(
        context: aztec::context::PublicContext,
        addresses: [AztecAddress; 10],
        moved_artifact_id: Field,
        source_activated_artifact_id: Field,
        target_activated_artifact_id: Field,
        world_hash: Field,
        moved_artifact_hash: Field,
        source_activated_artifact_hash: Field,
        target_activated_artifact_hash: Field,
        actor: AztecAddress,
    ) -> Field {
        let mut self = __aztec_nr_internals__create_public_self_from_context(context);
        // Verify world, moved artifact, and activated artifact hashes
            assert(self.internal._verify_hash(addresses[1], 0, world_hash), "World hash mismatch");

            let artifact_checks = self.internal._verify_hashes_three(addresses[8], [moved_artifact_id, source_activated_artifact_id, target_activated_artifact_id], [moved_artifact_hash, source_activated_artifact_hash, target_activated_artifact_hash]);
            assert(artifact_checks[0], "Moved artifact hash mismatch");
            assert(artifact_checks[1], "Activated artifact hash mismatch");
            assert(artifact_checks[2], "Target activated artifact hash mismatch");

            // Allocate a unique event ID from the atomic counter in ArrivalStorage,
            // then patch the placeholder IDs in arrival, planet events, and artifact location.
            let event_id: Field = self.internal._allocate_event_id(addresses[7], actor);
        event_id
    }

    #[inline_never]
    #[contract_library_method]
    unconstrained fn _move_write_source(
        context: aztec::context::PublicContext,
        addresses: [AztecAddress; 10],
        source_loc: Field,
        new_source_planet: [Field; 32],
        new_source_planet_artifacts_state: [Field; 22],
        new_source_planet_events_state: [Field; 22],
        prepared_new_source_planet_root: Field,
        prepared_new_source_planet_artifacts_state_root: Field,
        prepared_new_source_planet_events_state_root: Field,
        actor: AztecAddress,
    ) {
        let mut self = __aztec_nr_internals__create_public_self_from_context(context);
        // Write new states to storage
            self.internal._set_planet_fields(addresses[3], actor, source_loc, new_source_planet, prepared_new_source_planet_root, true);
            self.internal._set_planet_artifacts_fields(addresses[6], actor, source_loc, new_source_planet_artifacts_state, prepared_new_source_planet_artifacts_state_root, true);
            self.internal._set_planet_events_fields(addresses[5], actor, source_loc, new_source_planet_events_state, prepared_new_source_planet_events_state_root, true);
    }

    #[inline_never]
    #[contract_library_method]
    unconstrained fn _move_write_target(
        context: aztec::context::PublicContext,
        addresses: [AztecAddress; 10],
        target_loc: Field,
        new_target_planet: [Field; 32],
        new_target_planet_artifacts_state: [Field; 22],
        prepared_new_target_planet_root: Field,
        prepared_new_target_planet_artifacts_state_root: Field,
        actor: AztecAddress,
        new_target_planet_events_state: [Field; 22],
    ) {
        let mut self = __aztec_nr_internals__create_public_self_from_context(context);
        self.internal._set_planet_fields(addresses[3], actor, target_loc, new_target_planet, prepared_new_target_planet_root, true);
            self.internal._set_planet_artifacts_fields(addresses[6], actor, target_loc, new_target_planet_artifacts_state, prepared_new_target_planet_artifacts_state_root, true);
            self.internal._set_planet_events_fields(addresses[5], actor, target_loc, new_target_planet_events_state, 0, false);
    }

    #[inline_never]
    #[contract_library_method]
    unconstrained fn _move_write_tail(
        context: aztec::context::PublicContext,
        addresses: [AztecAddress; 10],
        moved_artifact_id: Field,
        source_activated_artifact_id: Field,
        new_source_activated_artifact: [Field; 13],
        new_source_activated_artifact_location: [Field; 3],
        prepared_new_source_activated_artifact_root: Field,
        prepared_new_source_activated_artifact_location_root: Field,
        actor: AztecAddress,
        new_arrival: Arrival,
        new_moved_artifact_location: [Field; 3],
    ) {
        let mut self = __aztec_nr_internals__create_public_self_from_context(context);
        self.internal._set_arrival(addresses[7], actor, new_arrival.id, new_arrival, 0, false);

            if moved_artifact_id != 0 {
                self.internal._set_artifact_location_fields(addresses[9], actor, moved_artifact_id, new_moved_artifact_location, 0, false);
            }

            // Write back deactivated/burned source activated artifact
            if source_activated_artifact_id != 0 {
                self.internal._set_artifact_fields(addresses[8], actor, source_activated_artifact_id, new_source_activated_artifact, prepared_new_source_activated_artifact_root, true);

                // PhotoidCannon and PlanetaryShield are burned on deactivation
                let is_burn_type = (
                    (new_source_activated_artifact[5] as u8) == ArtifactType::PhotoidCannon
                )
                    | ((new_source_activated_artifact[5] as u8) == ArtifactType::PlanetaryShield);

                let was_deactivated = (new_source_activated_artifact[8] as u64)
                    >= (new_source_activated_artifact[7] as u64);
                if is_burn_type & was_deactivated {
                    self.internal._set_artifact_location_fields(addresses[9], actor, source_activated_artifact_id, new_source_activated_artifact_location, prepared_new_source_activated_artifact_location_root, true);
                }
            }
    }

    #[external("public")]
    fn try_settle_move_move(
        prepared_payload: libs::field_buffer::FieldBuffer<549>,
    ) -> bool {
        assert(self.internal._is_prepared_writer(self.msg_sender()), "Only audited system");
        let addresses: [AztecAddress; 10] = [AztecAddress::from_field(prepared_payload.words[0]), AztecAddress::from_field(prepared_payload.words[1]), AztecAddress::from_field(prepared_payload.words[2]), AztecAddress::from_field(prepared_payload.words[3]), AztecAddress::from_field(prepared_payload.words[4]), AztecAddress::from_field(prepared_payload.words[5]), AztecAddress::from_field(prepared_payload.words[6]), AztecAddress::from_field(prepared_payload.words[7]), AztecAddress::from_field(prepared_payload.words[8]), AztecAddress::from_field(prepared_payload.words[9])];
        let source_loc: Field = prepared_payload.words[10];
        let target_loc: Field = prepared_payload.words[11];
        let target_level: u8 = (prepared_payload.words[12] as u8);
        let moved_artifact_id: Field = prepared_payload.words[13];
        let source_activated_artifact_id: Field = prepared_payload.words[14];
        let target_activated_artifact_id: Field = prepared_payload.words[15];
        let timestamp: u64 = (prepared_payload.words[16] as u64);
        let config_hashes: [Field; 9] = [prepared_payload.words[17], prepared_payload.words[18], prepared_payload.words[19], prepared_payload.words[20], prepared_payload.words[21], prepared_payload.words[22], prepared_payload.words[23], prepared_payload.words[24], prepared_payload.words[25]];
        let artifacts_config_hash: Field = prepared_payload.words[26];
        let planet_default_stats_hash: Field = prepared_payload.words[27];
        let source_planet_hash: Field = prepared_payload.words[28];
        let source_planet_artifacts_state_hash: Field = prepared_payload.words[29];
        let source_planet_events_state_hash: Field = prepared_payload.words[30];
        let source_arrival_ids: [Field; 20] = [prepared_payload.words[31], prepared_payload.words[32], prepared_payload.words[33], prepared_payload.words[34], prepared_payload.words[35], prepared_payload.words[36], prepared_payload.words[37], prepared_payload.words[38], prepared_payload.words[39], prepared_payload.words[40], prepared_payload.words[41], prepared_payload.words[42], prepared_payload.words[43], prepared_payload.words[44], prepared_payload.words[45], prepared_payload.words[46], prepared_payload.words[47], prepared_payload.words[48], prepared_payload.words[49], prepared_payload.words[50]];
        let source_arrival_hashes: [Field; 20] = [prepared_payload.words[51], prepared_payload.words[52], prepared_payload.words[53], prepared_payload.words[54], prepared_payload.words[55], prepared_payload.words[56], prepared_payload.words[57], prepared_payload.words[58], prepared_payload.words[59], prepared_payload.words[60], prepared_payload.words[61], prepared_payload.words[62], prepared_payload.words[63], prepared_payload.words[64], prepared_payload.words[65], prepared_payload.words[66], prepared_payload.words[67], prepared_payload.words[68], prepared_payload.words[69], prepared_payload.words[70]];
        let source_arrival_artifact_ids: [Field; 20] = [prepared_payload.words[71], prepared_payload.words[72], prepared_payload.words[73], prepared_payload.words[74], prepared_payload.words[75], prepared_payload.words[76], prepared_payload.words[77], prepared_payload.words[78], prepared_payload.words[79], prepared_payload.words[80], prepared_payload.words[81], prepared_payload.words[82], prepared_payload.words[83], prepared_payload.words[84], prepared_payload.words[85], prepared_payload.words[86], prepared_payload.words[87], prepared_payload.words[88], prepared_payload.words[89], prepared_payload.words[90]];
        let source_arrival_artifact_hashes: [Field; 20] = [prepared_payload.words[91], prepared_payload.words[92], prepared_payload.words[93], prepared_payload.words[94], prepared_payload.words[95], prepared_payload.words[96], prepared_payload.words[97], prepared_payload.words[98], prepared_payload.words[99], prepared_payload.words[100], prepared_payload.words[101], prepared_payload.words[102], prepared_payload.words[103], prepared_payload.words[104], prepared_payload.words[105], prepared_payload.words[106], prepared_payload.words[107], prepared_payload.words[108], prepared_payload.words[109], prepared_payload.words[110]];
        let source_arrival_artifact_location_hashes: [Field; 20] = [prepared_payload.words[111], prepared_payload.words[112], prepared_payload.words[113], prepared_payload.words[114], prepared_payload.words[115], prepared_payload.words[116], prepared_payload.words[117], prepared_payload.words[118], prepared_payload.words[119], prepared_payload.words[120], prepared_payload.words[121], prepared_payload.words[122], prepared_payload.words[123], prepared_payload.words[124], prepared_payload.words[125], prepared_payload.words[126], prepared_payload.words[127], prepared_payload.words[128], prepared_payload.words[129], prepared_payload.words[130]];
        let original_source_arrivals_count: u32 = (prepared_payload.words[131] as u32);
        let target_planet_hash: Field = prepared_payload.words[132];
        let target_planet_artifacts_state_hash: Field = prepared_payload.words[133];
        let target_planet_events_state_hash: Field = prepared_payload.words[134];
        let target_arrival_ids: [Field; 20] = [prepared_payload.words[135], prepared_payload.words[136], prepared_payload.words[137], prepared_payload.words[138], prepared_payload.words[139], prepared_payload.words[140], prepared_payload.words[141], prepared_payload.words[142], prepared_payload.words[143], prepared_payload.words[144], prepared_payload.words[145], prepared_payload.words[146], prepared_payload.words[147], prepared_payload.words[148], prepared_payload.words[149], prepared_payload.words[150], prepared_payload.words[151], prepared_payload.words[152], prepared_payload.words[153], prepared_payload.words[154]];
        let target_arrival_hashes: [Field; 20] = [prepared_payload.words[155], prepared_payload.words[156], prepared_payload.words[157], prepared_payload.words[158], prepared_payload.words[159], prepared_payload.words[160], prepared_payload.words[161], prepared_payload.words[162], prepared_payload.words[163], prepared_payload.words[164], prepared_payload.words[165], prepared_payload.words[166], prepared_payload.words[167], prepared_payload.words[168], prepared_payload.words[169], prepared_payload.words[170], prepared_payload.words[171], prepared_payload.words[172], prepared_payload.words[173], prepared_payload.words[174]];
        let target_arrival_artifact_ids: [Field; 20] = [prepared_payload.words[175], prepared_payload.words[176], prepared_payload.words[177], prepared_payload.words[178], prepared_payload.words[179], prepared_payload.words[180], prepared_payload.words[181], prepared_payload.words[182], prepared_payload.words[183], prepared_payload.words[184], prepared_payload.words[185], prepared_payload.words[186], prepared_payload.words[187], prepared_payload.words[188], prepared_payload.words[189], prepared_payload.words[190], prepared_payload.words[191], prepared_payload.words[192], prepared_payload.words[193], prepared_payload.words[194]];
        let target_arrival_artifact_hashes: [Field; 20] = [prepared_payload.words[195], prepared_payload.words[196], prepared_payload.words[197], prepared_payload.words[198], prepared_payload.words[199], prepared_payload.words[200], prepared_payload.words[201], prepared_payload.words[202], prepared_payload.words[203], prepared_payload.words[204], prepared_payload.words[205], prepared_payload.words[206], prepared_payload.words[207], prepared_payload.words[208], prepared_payload.words[209], prepared_payload.words[210], prepared_payload.words[211], prepared_payload.words[212], prepared_payload.words[213], prepared_payload.words[214]];
        let target_arrival_artifact_location_hashes: [Field; 20] = [prepared_payload.words[215], prepared_payload.words[216], prepared_payload.words[217], prepared_payload.words[218], prepared_payload.words[219], prepared_payload.words[220], prepared_payload.words[221], prepared_payload.words[222], prepared_payload.words[223], prepared_payload.words[224], prepared_payload.words[225], prepared_payload.words[226], prepared_payload.words[227], prepared_payload.words[228], prepared_payload.words[229], prepared_payload.words[230], prepared_payload.words[231], prepared_payload.words[232], prepared_payload.words[233], prepared_payload.words[234]];
        let original_target_arrivals_count: u32 = (prepared_payload.words[235] as u32);
        let world_hash: Field = prepared_payload.words[236];
        let moved_artifact_hash: Field = prepared_payload.words[237];
        let source_activated_artifact_hash: Field = prepared_payload.words[238];
        let target_activated_artifact_hash: Field = prepared_payload.words[239];
        let new_source_planet: [Field; 32] = [prepared_payload.words[240], prepared_payload.words[241], prepared_payload.words[242], prepared_payload.words[243], prepared_payload.words[244], prepared_payload.words[245], prepared_payload.words[246], prepared_payload.words[247], prepared_payload.words[248], prepared_payload.words[249], prepared_payload.words[250], prepared_payload.words[251], prepared_payload.words[252], prepared_payload.words[253], prepared_payload.words[254], prepared_payload.words[255], prepared_payload.words[256], prepared_payload.words[257], prepared_payload.words[258], prepared_payload.words[259], prepared_payload.words[260], prepared_payload.words[261], prepared_payload.words[262], prepared_payload.words[263], prepared_payload.words[264], prepared_payload.words[265], prepared_payload.words[266], prepared_payload.words[267], prepared_payload.words[268], prepared_payload.words[269], prepared_payload.words[270], prepared_payload.words[271]];
        let new_source_planet_artifacts_state: [Field; 22] = [prepared_payload.words[272], prepared_payload.words[273], prepared_payload.words[274], prepared_payload.words[275], prepared_payload.words[276], prepared_payload.words[277], prepared_payload.words[278], prepared_payload.words[279], prepared_payload.words[280], prepared_payload.words[281], prepared_payload.words[282], prepared_payload.words[283], prepared_payload.words[284], prepared_payload.words[285], prepared_payload.words[286], prepared_payload.words[287], prepared_payload.words[288], prepared_payload.words[289], prepared_payload.words[290], prepared_payload.words[291], prepared_payload.words[292], prepared_payload.words[293]];
        let new_source_planet_events_state: [Field; 22] = [prepared_payload.words[294], prepared_payload.words[295], prepared_payload.words[296], prepared_payload.words[297], prepared_payload.words[298], prepared_payload.words[299], prepared_payload.words[300], prepared_payload.words[301], prepared_payload.words[302], prepared_payload.words[303], prepared_payload.words[304], prepared_payload.words[305], prepared_payload.words[306], prepared_payload.words[307], prepared_payload.words[308], prepared_payload.words[309], prepared_payload.words[310], prepared_payload.words[311], prepared_payload.words[312], prepared_payload.words[313], prepared_payload.words[314], prepared_payload.words[315]];
        let new_source_arrival_artifact_locations: [ArtifactLocation; 20] = [ArtifactLocation { planet_id: prepared_payload.words[316], voyage_id: prepared_payload.words[317], last_updated: (prepared_payload.words[318] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[319], voyage_id: prepared_payload.words[320], last_updated: (prepared_payload.words[321] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[322], voyage_id: prepared_payload.words[323], last_updated: (prepared_payload.words[324] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[325], voyage_id: prepared_payload.words[326], last_updated: (prepared_payload.words[327] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[328], voyage_id: prepared_payload.words[329], last_updated: (prepared_payload.words[330] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[331], voyage_id: prepared_payload.words[332], last_updated: (prepared_payload.words[333] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[334], voyage_id: prepared_payload.words[335], last_updated: (prepared_payload.words[336] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[337], voyage_id: prepared_payload.words[338], last_updated: (prepared_payload.words[339] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[340], voyage_id: prepared_payload.words[341], last_updated: (prepared_payload.words[342] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[343], voyage_id: prepared_payload.words[344], last_updated: (prepared_payload.words[345] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[346], voyage_id: prepared_payload.words[347], last_updated: (prepared_payload.words[348] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[349], voyage_id: prepared_payload.words[350], last_updated: (prepared_payload.words[351] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[352], voyage_id: prepared_payload.words[353], last_updated: (prepared_payload.words[354] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[355], voyage_id: prepared_payload.words[356], last_updated: (prepared_payload.words[357] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[358], voyage_id: prepared_payload.words[359], last_updated: (prepared_payload.words[360] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[361], voyage_id: prepared_payload.words[362], last_updated: (prepared_payload.words[363] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[364], voyage_id: prepared_payload.words[365], last_updated: (prepared_payload.words[366] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[367], voyage_id: prepared_payload.words[368], last_updated: (prepared_payload.words[369] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[370], voyage_id: prepared_payload.words[371], last_updated: (prepared_payload.words[372] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[373], voyage_id: prepared_payload.words[374], last_updated: (prepared_payload.words[375] as u64) }];
        let new_target_planet: [Field; 32] = [prepared_payload.words[376], prepared_payload.words[377], prepared_payload.words[378], prepared_payload.words[379], prepared_payload.words[380], prepared_payload.words[381], prepared_payload.words[382], prepared_payload.words[383], prepared_payload.words[384], prepared_payload.words[385], prepared_payload.words[386], prepared_payload.words[387], prepared_payload.words[388], prepared_payload.words[389], prepared_payload.words[390], prepared_payload.words[391], prepared_payload.words[392], prepared_payload.words[393], prepared_payload.words[394], prepared_payload.words[395], prepared_payload.words[396], prepared_payload.words[397], prepared_payload.words[398], prepared_payload.words[399], prepared_payload.words[400], prepared_payload.words[401], prepared_payload.words[402], prepared_payload.words[403], prepared_payload.words[404], prepared_payload.words[405], prepared_payload.words[406], prepared_payload.words[407]];
        let new_target_planet_artifacts_state: [Field; 22] = [prepared_payload.words[408], prepared_payload.words[409], prepared_payload.words[410], prepared_payload.words[411], prepared_payload.words[412], prepared_payload.words[413], prepared_payload.words[414], prepared_payload.words[415], prepared_payload.words[416], prepared_payload.words[417], prepared_payload.words[418], prepared_payload.words[419], prepared_payload.words[420], prepared_payload.words[421], prepared_payload.words[422], prepared_payload.words[423], prepared_payload.words[424], prepared_payload.words[425], prepared_payload.words[426], prepared_payload.words[427], prepared_payload.words[428], prepared_payload.words[429]];
        let new_target_planet_events_state_input: [Field; 22] = [prepared_payload.words[430], prepared_payload.words[431], prepared_payload.words[432], prepared_payload.words[433], prepared_payload.words[434], prepared_payload.words[435], prepared_payload.words[436], prepared_payload.words[437], prepared_payload.words[438], prepared_payload.words[439], prepared_payload.words[440], prepared_payload.words[441], prepared_payload.words[442], prepared_payload.words[443], prepared_payload.words[444], prepared_payload.words[445], prepared_payload.words[446], prepared_payload.words[447], prepared_payload.words[448], prepared_payload.words[449], prepared_payload.words[450], prepared_payload.words[451]];
        let new_target_arrival_artifact_locations: [ArtifactLocation; 20] = [ArtifactLocation { planet_id: prepared_payload.words[452], voyage_id: prepared_payload.words[453], last_updated: (prepared_payload.words[454] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[455], voyage_id: prepared_payload.words[456], last_updated: (prepared_payload.words[457] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[458], voyage_id: prepared_payload.words[459], last_updated: (prepared_payload.words[460] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[461], voyage_id: prepared_payload.words[462], last_updated: (prepared_payload.words[463] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[464], voyage_id: prepared_payload.words[465], last_updated: (prepared_payload.words[466] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[467], voyage_id: prepared_payload.words[468], last_updated: (prepared_payload.words[469] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[470], voyage_id: prepared_payload.words[471], last_updated: (prepared_payload.words[472] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[473], voyage_id: prepared_payload.words[474], last_updated: (prepared_payload.words[475] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[476], voyage_id: prepared_payload.words[477], last_updated: (prepared_payload.words[478] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[479], voyage_id: prepared_payload.words[480], last_updated: (prepared_payload.words[481] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[482], voyage_id: prepared_payload.words[483], last_updated: (prepared_payload.words[484] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[485], voyage_id: prepared_payload.words[486], last_updated: (prepared_payload.words[487] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[488], voyage_id: prepared_payload.words[489], last_updated: (prepared_payload.words[490] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[491], voyage_id: prepared_payload.words[492], last_updated: (prepared_payload.words[493] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[494], voyage_id: prepared_payload.words[495], last_updated: (prepared_payload.words[496] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[497], voyage_id: prepared_payload.words[498], last_updated: (prepared_payload.words[499] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[500], voyage_id: prepared_payload.words[501], last_updated: (prepared_payload.words[502] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[503], voyage_id: prepared_payload.words[504], last_updated: (prepared_payload.words[505] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[506], voyage_id: prepared_payload.words[507], last_updated: (prepared_payload.words[508] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[509], voyage_id: prepared_payload.words[510], last_updated: (prepared_payload.words[511] as u64) }];
        let new_arrival_input: Arrival = Arrival { id: prepared_payload.words[512], player: AztecAddress::from_field(prepared_payload.words[513]), from_planet: prepared_payload.words[514], to_planet: prepared_payload.words[515], pop_arriving: (prepared_payload.words[516] as u128), silver_moved: (prepared_payload.words[517] as u128), departure_time: (prepared_payload.words[518] as u64), arrival_time: (prepared_payload.words[519] as u64), arrival_type: (prepared_payload.words[520] as u8), carried_artifact_id: prepared_payload.words[521], distance: (prepared_payload.words[522] as u128) };
        let new_moved_artifact_location_input: [Field; 3] = [prepared_payload.words[523], prepared_payload.words[524], prepared_payload.words[525]];
        let new_source_activated_artifact: [Field; 13] = [prepared_payload.words[526], prepared_payload.words[527], prepared_payload.words[528], prepared_payload.words[529], prepared_payload.words[530], prepared_payload.words[531], prepared_payload.words[532], prepared_payload.words[533], prepared_payload.words[534], prepared_payload.words[535], prepared_payload.words[536], prepared_payload.words[537], prepared_payload.words[538]];
        let new_source_activated_artifact_location: [Field; 3] = [prepared_payload.words[539], prepared_payload.words[540], prepared_payload.words[541]];
        let prepared_new_source_planet_root: Field = prepared_payload.words[542];
        let prepared_new_source_planet_artifacts_state_root: Field = prepared_payload.words[543];
        let prepared_new_source_planet_events_state_root: Field = prepared_payload.words[544];
        let prepared_new_target_planet_root: Field = prepared_payload.words[545];
        let prepared_new_target_planet_artifacts_state_root: Field = prepared_payload.words[546];
        let prepared_new_source_activated_artifact_root: Field = prepared_payload.words[547];
        let prepared_new_source_activated_artifact_location_root: Field = prepared_payload.words[548];

        if self.internal._can_settle(addresses, 1002) {
            let actor = self.msg_sender();

            let mut new_target_planet_events_state = new_target_planet_events_state_input;
            let mut new_arrival = new_arrival_input;
            let mut new_moved_artifact_location = new_moved_artifact_location_input;

            _move_check_source(self.context, addresses, source_loc, target_level, timestamp, config_hashes, artifacts_config_hash, planet_default_stats_hash, source_planet_hash, source_planet_artifacts_state_hash, source_planet_events_state_hash);

            if original_source_arrivals_count != 0 {
                assert(
                    self.internal._verify_hashes_batch(addresses[7], source_arrival_ids, source_arrival_hashes, original_source_arrivals_count),
                    "Source arrival hash mismatch",
                );
                if ::libs::batch_utils::has_nonzero_ids(
                    source_arrival_artifact_ids,
                    original_source_arrivals_count,
                ) {
                    assert(
                        self.internal._verify_hashes_batch(addresses[8], source_arrival_artifact_ids, source_arrival_artifact_hashes, original_source_arrivals_count),
                        "Source artifact hash mismatch",
                    );

                    assert(
                        self.internal._verify_hashes_batch(addresses[9], source_arrival_artifact_ids, source_arrival_artifact_location_hashes, original_source_arrivals_count),
                        "Source artifact location hash mismatch",
                    );
                }
            }

            _move_check_target(self.context, addresses, target_loc, target_planet_hash, target_planet_artifacts_state_hash, target_planet_events_state_hash);

            // Batch verify target arrivals, artifacts, artifact_locations (3 calls instead of 60)
            if original_target_arrivals_count != 0 {
                assert(
                    self.internal._verify_hashes_batch(addresses[7], target_arrival_ids, target_arrival_hashes, original_target_arrivals_count),
                    "Target arrival hash mismatch",
                );

                if ::libs::batch_utils::has_nonzero_ids(
                    target_arrival_artifact_ids,
                    original_target_arrivals_count,
                ) {
                    assert(
                        self.internal._verify_hashes_batch(addresses[8], target_arrival_artifact_ids, target_arrival_artifact_hashes, original_target_arrivals_count),
                        "Target artifact hash mismatch",
                    );

                    assert(
                        self.internal._verify_hashes_batch(addresses[9], target_arrival_artifact_ids, target_arrival_artifact_location_hashes, original_target_arrivals_count),
                        "Target artifact location hash mismatch",
                    );
                }
            }

            let event_id: Field = _move_check_world_and_allocate(self.context, addresses, moved_artifact_id, source_activated_artifact_id, target_activated_artifact_id, world_hash, moved_artifact_hash, source_activated_artifact_hash, target_activated_artifact_hash, actor);
            new_arrival.id = event_id;

            // Patch the last event in target planet events (the one just added in private)
            assert((new_target_planet_events_state[20] as u32) > 0, "Expected at least one planet event");
            assert((new_target_planet_events_state[20] as u32) <= 20, "Index out of bounds");
            new_target_planet_events_state[(new_target_planet_events_state[20] as u32) - 1] =
                event_id;

            if moved_artifact_id != 0 {
                new_moved_artifact_location[1] = event_id;
            }

            _move_write_source(self.context, addresses, source_loc, new_source_planet, new_source_planet_artifacts_state, new_source_planet_events_state, prepared_new_source_planet_root, prepared_new_source_planet_artifacts_state_root, prepared_new_source_planet_events_state_root, actor);

            // Batch write source arrival artifact locations (1 call instead of up to 20)
            self.internal._set_arrival_locations_max20(addresses[9], actor, source_arrival_artifact_ids, new_source_arrival_artifact_locations, original_source_arrivals_count);

            _move_write_target(self.context, addresses, target_loc, new_target_planet, new_target_planet_artifacts_state, prepared_new_target_planet_root, prepared_new_target_planet_artifacts_state_root, actor, new_target_planet_events_state);

            // Batch write target arrival artifact locations (1 call instead of up to 20)
            self.internal._set_arrival_locations_max20(addresses[9], actor, target_arrival_artifact_ids, new_target_arrival_artifact_locations, original_target_arrivals_count);

            _move_write_tail(self.context, addresses, moved_artifact_id, source_activated_artifact_id, new_source_activated_artifact, new_source_activated_artifact_location, prepared_new_source_activated_artifact_root, prepared_new_source_activated_artifact_location_root, actor, new_arrival, new_moved_artifact_location);

            true
        } else {
            false
        }
    }

    #[external("public")]
    fn try_settle_move_move_empty(
        prepared_payload: libs::field_buffer::FieldBuffer<227>,
    ) -> bool {
        assert(self.internal._is_prepared_writer(self.msg_sender()), "Only audited system");
        let addresses: [AztecAddress; 10] = [AztecAddress::from_field(prepared_payload.words[0]), AztecAddress::from_field(prepared_payload.words[1]), AztecAddress::from_field(prepared_payload.words[2]), AztecAddress::from_field(prepared_payload.words[3]), AztecAddress::from_field(prepared_payload.words[4]), AztecAddress::from_field(prepared_payload.words[5]), AztecAddress::from_field(prepared_payload.words[6]), AztecAddress::from_field(prepared_payload.words[7]), AztecAddress::from_field(prepared_payload.words[8]), AztecAddress::from_field(prepared_payload.words[9])];
        let source_loc: Field = prepared_payload.words[10];
        let target_loc: Field = prepared_payload.words[11];
        let target_level: u8 = (prepared_payload.words[12] as u8);
        let moved_artifact_id: Field = prepared_payload.words[13];
        let source_activated_artifact_id: Field = prepared_payload.words[14];
        let target_activated_artifact_id: Field = prepared_payload.words[15];
        let timestamp: u64 = (prepared_payload.words[16] as u64);
        let config_hashes: [Field; 9] = [prepared_payload.words[17], prepared_payload.words[18], prepared_payload.words[19], prepared_payload.words[20], prepared_payload.words[21], prepared_payload.words[22], prepared_payload.words[23], prepared_payload.words[24], prepared_payload.words[25]];
        let artifacts_config_hash: Field = prepared_payload.words[26];
        let planet_default_stats_hash: Field = prepared_payload.words[27];
        let source_planet_hash: Field = prepared_payload.words[28];
        let source_planet_artifacts_state_hash: Field = prepared_payload.words[29];
        let source_planet_events_state_hash: Field = prepared_payload.words[30];
        let target_planet_hash: Field = prepared_payload.words[31];
        let target_planet_artifacts_state_hash: Field = prepared_payload.words[32];
        let target_planet_events_state_hash: Field = prepared_payload.words[33];
        let world_hash: Field = prepared_payload.words[34];
        let moved_artifact_hash: Field = prepared_payload.words[35];
        let source_activated_artifact_hash: Field = prepared_payload.words[36];
        let target_activated_artifact_hash: Field = prepared_payload.words[37];
        let new_source_planet: [Field; 32] = [prepared_payload.words[38], prepared_payload.words[39], prepared_payload.words[40], prepared_payload.words[41], prepared_payload.words[42], prepared_payload.words[43], prepared_payload.words[44], prepared_payload.words[45], prepared_payload.words[46], prepared_payload.words[47], prepared_payload.words[48], prepared_payload.words[49], prepared_payload.words[50], prepared_payload.words[51], prepared_payload.words[52], prepared_payload.words[53], prepared_payload.words[54], prepared_payload.words[55], prepared_payload.words[56], prepared_payload.words[57], prepared_payload.words[58], prepared_payload.words[59], prepared_payload.words[60], prepared_payload.words[61], prepared_payload.words[62], prepared_payload.words[63], prepared_payload.words[64], prepared_payload.words[65], prepared_payload.words[66], prepared_payload.words[67], prepared_payload.words[68], prepared_payload.words[69]];
        let new_source_planet_artifacts_state: [Field; 22] = [prepared_payload.words[70], prepared_payload.words[71], prepared_payload.words[72], prepared_payload.words[73], prepared_payload.words[74], prepared_payload.words[75], prepared_payload.words[76], prepared_payload.words[77], prepared_payload.words[78], prepared_payload.words[79], prepared_payload.words[80], prepared_payload.words[81], prepared_payload.words[82], prepared_payload.words[83], prepared_payload.words[84], prepared_payload.words[85], prepared_payload.words[86], prepared_payload.words[87], prepared_payload.words[88], prepared_payload.words[89], prepared_payload.words[90], prepared_payload.words[91]];
        let new_source_planet_events_state: [Field; 22] = [prepared_payload.words[92], prepared_payload.words[93], prepared_payload.words[94], prepared_payload.words[95], prepared_payload.words[96], prepared_payload.words[97], prepared_payload.words[98], prepared_payload.words[99], prepared_payload.words[100], prepared_payload.words[101], prepared_payload.words[102], prepared_payload.words[103], prepared_payload.words[104], prepared_payload.words[105], prepared_payload.words[106], prepared_payload.words[107], prepared_payload.words[108], prepared_payload.words[109], prepared_payload.words[110], prepared_payload.words[111], prepared_payload.words[112], prepared_payload.words[113]];
        let new_target_planet: [Field; 32] = [prepared_payload.words[114], prepared_payload.words[115], prepared_payload.words[116], prepared_payload.words[117], prepared_payload.words[118], prepared_payload.words[119], prepared_payload.words[120], prepared_payload.words[121], prepared_payload.words[122], prepared_payload.words[123], prepared_payload.words[124], prepared_payload.words[125], prepared_payload.words[126], prepared_payload.words[127], prepared_payload.words[128], prepared_payload.words[129], prepared_payload.words[130], prepared_payload.words[131], prepared_payload.words[132], prepared_payload.words[133], prepared_payload.words[134], prepared_payload.words[135], prepared_payload.words[136], prepared_payload.words[137], prepared_payload.words[138], prepared_payload.words[139], prepared_payload.words[140], prepared_payload.words[141], prepared_payload.words[142], prepared_payload.words[143], prepared_payload.words[144], prepared_payload.words[145]];
        let new_target_planet_artifacts_state: [Field; 22] = [prepared_payload.words[146], prepared_payload.words[147], prepared_payload.words[148], prepared_payload.words[149], prepared_payload.words[150], prepared_payload.words[151], prepared_payload.words[152], prepared_payload.words[153], prepared_payload.words[154], prepared_payload.words[155], prepared_payload.words[156], prepared_payload.words[157], prepared_payload.words[158], prepared_payload.words[159], prepared_payload.words[160], prepared_payload.words[161], prepared_payload.words[162], prepared_payload.words[163], prepared_payload.words[164], prepared_payload.words[165], prepared_payload.words[166], prepared_payload.words[167]];
        let new_target_planet_events_state_input: [Field; 22] = [prepared_payload.words[168], prepared_payload.words[169], prepared_payload.words[170], prepared_payload.words[171], prepared_payload.words[172], prepared_payload.words[173], prepared_payload.words[174], prepared_payload.words[175], prepared_payload.words[176], prepared_payload.words[177], prepared_payload.words[178], prepared_payload.words[179], prepared_payload.words[180], prepared_payload.words[181], prepared_payload.words[182], prepared_payload.words[183], prepared_payload.words[184], prepared_payload.words[185], prepared_payload.words[186], prepared_payload.words[187], prepared_payload.words[188], prepared_payload.words[189]];
        let new_arrival_input: Arrival = Arrival { id: prepared_payload.words[190], player: AztecAddress::from_field(prepared_payload.words[191]), from_planet: prepared_payload.words[192], to_planet: prepared_payload.words[193], pop_arriving: (prepared_payload.words[194] as u128), silver_moved: (prepared_payload.words[195] as u128), departure_time: (prepared_payload.words[196] as u64), arrival_time: (prepared_payload.words[197] as u64), arrival_type: (prepared_payload.words[198] as u8), carried_artifact_id: prepared_payload.words[199], distance: (prepared_payload.words[200] as u128) };
        let new_moved_artifact_location_input: [Field; 3] = [prepared_payload.words[201], prepared_payload.words[202], prepared_payload.words[203]];
        let new_source_activated_artifact: [Field; 13] = [prepared_payload.words[204], prepared_payload.words[205], prepared_payload.words[206], prepared_payload.words[207], prepared_payload.words[208], prepared_payload.words[209], prepared_payload.words[210], prepared_payload.words[211], prepared_payload.words[212], prepared_payload.words[213], prepared_payload.words[214], prepared_payload.words[215], prepared_payload.words[216]];
        let new_source_activated_artifact_location: [Field; 3] = [prepared_payload.words[217], prepared_payload.words[218], prepared_payload.words[219]];
        let prepared_new_source_planet_root: Field = prepared_payload.words[220];
        let prepared_new_source_planet_artifacts_state_root: Field = prepared_payload.words[221];
        let prepared_new_source_planet_events_state_root: Field = prepared_payload.words[222];
        let prepared_new_target_planet_root: Field = prepared_payload.words[223];
        let prepared_new_target_planet_artifacts_state_root: Field = prepared_payload.words[224];
        let prepared_new_source_activated_artifact_root: Field = prepared_payload.words[225];
        let prepared_new_source_activated_artifact_location_root: Field = prepared_payload.words[226];

        if self.internal._can_settle(addresses, 1002) {
            let actor = self.msg_sender();

            let mut new_target_planet_events_state = new_target_planet_events_state_input;
            let mut new_arrival = new_arrival_input;
            let mut new_moved_artifact_location = new_moved_artifact_location_input;

            _move_check_source(self.context, addresses, source_loc, target_level, timestamp, config_hashes, artifacts_config_hash, planet_default_stats_hash, source_planet_hash, source_planet_artifacts_state_hash, source_planet_events_state_hash);



            _move_check_target(self.context, addresses, target_loc, target_planet_hash, target_planet_artifacts_state_hash, target_planet_events_state_hash);

            // Batch verify target arrivals, artifacts, artifact_locations (3 calls instead of 60)


            let event_id: Field = _move_check_world_and_allocate(self.context, addresses, moved_artifact_id, source_activated_artifact_id, target_activated_artifact_id, world_hash, moved_artifact_hash, source_activated_artifact_hash, target_activated_artifact_hash, actor);
            new_arrival.id = event_id;

            // Patch the last event in target planet events (the one just added in private)
            assert((new_target_planet_events_state[20] as u32) > 0, "Expected at least one planet event");
            assert((new_target_planet_events_state[20] as u32) <= 20, "Index out of bounds");
            new_target_planet_events_state[(new_target_planet_events_state[20] as u32) - 1] =
                event_id;

            if moved_artifact_id != 0 {
                new_moved_artifact_location[1] = event_id;
            }

            _move_write_source(self.context, addresses, source_loc, new_source_planet, new_source_planet_artifacts_state, new_source_planet_events_state, prepared_new_source_planet_root, prepared_new_source_planet_artifacts_state_root, prepared_new_source_planet_events_state_root, actor);

            // Batch write source arrival artifact locations (1 call instead of up to 20)
            self.internal._assert_authorized(addresses[9], actor);

            _move_write_target(self.context, addresses, target_loc, new_target_planet, new_target_planet_artifacts_state, prepared_new_target_planet_root, prepared_new_target_planet_artifacts_state_root, actor, new_target_planet_events_state);

            // Batch write target arrival artifact locations (1 call instead of up to 20)
            self.internal._assert_authorized(addresses[9], actor);

            _move_write_tail(self.context, addresses, moved_artifact_id, source_activated_artifact_id, new_source_activated_artifact, new_source_activated_artifact_location, prepared_new_source_activated_artifact_root, prepared_new_source_activated_artifact_location_root, actor, new_arrival, new_moved_artifact_location);

            true
        } else {
            false
        }
    }

}
