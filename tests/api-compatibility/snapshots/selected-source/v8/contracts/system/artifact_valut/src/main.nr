use ::aztec::macros::aztec;

#[aztec]
contract ArtifactValut {
    use aztec::protocol::traits::FromField;

    use aztec::protocol::traits::Deserialize;

    use aztec::protocol::traits::ToField;

    use ::game_state_backend::GameStateBackend;
    use ::vault_settlement_worker::VaultSettlementWorker;

    use ::aztec::{
        macros::{functions::{external, initializer, internal, only_self, view}, storage::storage},
        protocol::{address::AztecAddress, hash::poseidon2_hash, traits::Serialize},
    };
    use ::aztec::state_vars::PublicMutable;

    use ::types::args::DFTCreateArtifactArgs;
    use ::types::config::{artifacts::ArtifactsConfig, spaceships::SpaceshipsConfig};
    use ::types::storage::{
        arrival::Arrival,
        artifact::{Artifact, ArtifactLocation, ArtifactType},
        planet::{Planet, PlanetArtifacts, PlanetEvents, PlanetType},
        player::Player,
        world::World,
    };
    use ::types::system_storage_addresses::ArtifactFacetSystemStorageAddresses;

    use ::config::Config;

    use ::libs::artifact_utils::{
        artifact_from_create_args, create_and_place_spaceship, is_spaceship,
    };

    use ::libs::batch_utils::{
        assert_artifact_and_location_timestamp_freshness, assert_planet_timestamp_freshness,
        assert_public_timestamp, compute_artifact_and_location_hashes, compute_planet_hashes,
        compute_player_hash, compute_world_hash,
    };
    use ::libs::game_utils::{_put_artifact_on_planet, _take_artifact_off_planet};
    use ::libs::planet::{apply_spaceship_arrive, refresh_planet_v1};

    use ::arrival_storage::ArrivalStorage;
    use ::artifact_location_storage::ArtifactLocationStorage;
    use ::artifact_storage::ArtifactStorage;
    use ::planet_artifacts_storage::PlanetArtifactsStorage;
    use ::planet_events_storage::PlanetEventsStorage;
    use ::planet_storage::PlanetStorage;
    use ::player_storage::PlayerStorage;
    use ::world_storage::WorldStorage;

    #[storage]
    struct Storage<Context> {
        admin: PublicMutable<AztecAddress, Context>,
        config_storage_address: PublicMutable<AztecAddress, Context>,
        arrivals_storage_address: PublicMutable<AztecAddress, Context>,
        artifact_storage_address: PublicMutable<AztecAddress, Context>,
        artifact_location_storage_address: PublicMutable<AztecAddress, Context>,
        planet_storage_address: PublicMutable<AztecAddress, Context>,
        planet_artifacts_storage_address: PublicMutable<AztecAddress, Context>,
        planet_events_storage_address: PublicMutable<AztecAddress, Context>,
        player_storage_address: PublicMutable<AztecAddress, Context>,
        world_storage_address: PublicMutable<AztecAddress, Context>,
        state_backend: PublicMutable<AztecAddress, Context>,
        state_worker: PublicMutable<AztecAddress, Context>,
    }

    #[internal("public")]
    fn assert_admin() {
        assert(self.msg_sender() == self.storage.admin.read(), "Only admin");
    }

    #[external("public")]
    #[initializer]
    fn constructor(admin: AztecAddress) {
        self.storage.admin.write(admin);
    }

    #[external("public")]
    fn transfer_admin(new_admin: AztecAddress) {
        self.internal.assert_admin();
        self.storage.admin.write(new_admin);
    }

    #[external("public")]
    fn set_all_storage_addresses(
        config_storage_address: AztecAddress,
        arrivals_storage_address: AztecAddress,
        artifact_storage_address: AztecAddress,
        artifact_location_storage_address: AztecAddress,
        planet_storage_address: AztecAddress,
        planet_artifacts_storage_address: AztecAddress,
        planet_events_storage_address: AztecAddress,
        player_storage_address: AztecAddress,
        world_storage_address: AztecAddress,
    ) {
        self.internal.assert_admin();
        self.storage.config_storage_address.write(config_storage_address);
        self.storage.arrivals_storage_address.write(arrivals_storage_address);
        self.storage.artifact_storage_address.write(artifact_storage_address);
        self.storage.artifact_location_storage_address.write(artifact_location_storage_address);
        self.storage.planet_storage_address.write(planet_storage_address);
        self.storage.planet_artifacts_storage_address.write(planet_artifacts_storage_address);
        self.storage.planet_events_storage_address.write(planet_events_storage_address);
        self.storage.world_storage_address.write(world_storage_address);
        self.storage.player_storage_address.write(player_storage_address);
    }

    #[external("public")]
    fn set_config_storage_address(config_storage_address: AztecAddress) {
        self.internal.assert_admin();
        self.storage.config_storage_address.write(config_storage_address);
    }

    #[external("public")]
    fn set_arrivals_storage_address(arrivals_storage_address: AztecAddress) {
        self.internal.assert_admin();
        self.storage.arrivals_storage_address.write(arrivals_storage_address);
    }

    #[external("public")]
    fn set_artifact_storage_address(artifact_storage_address: AztecAddress) {
        self.internal.assert_admin();
        self.storage.artifact_storage_address.write(artifact_storage_address);
    }

    #[external("public")]
    fn set_artifact_location_storage_address(artifact_location_storage_address: AztecAddress) {
        self.internal.assert_admin();
        self.storage.artifact_location_storage_address.write(artifact_location_storage_address);
    }

    #[external("public")]
    fn set_planet_storage_address(planet_storage_address: AztecAddress) {
        self.internal.assert_admin();
        self.storage.planet_storage_address.write(planet_storage_address);
    }

    #[external("public")]
    fn set_planet_artifacts_storage_address(planet_artifacts_storage_address: AztecAddress) {
        self.internal.assert_admin();
        self.storage.planet_artifacts_storage_address.write(planet_artifacts_storage_address);
    }

    #[external("public")]
    fn set_planet_events_storage_address(planet_events_storage_address: AztecAddress) {
        self.internal.assert_admin();
        self.storage.planet_events_storage_address.write(planet_events_storage_address);
    }

    #[external("public")]
    fn set_player_storage_address(player_storage_address: AztecAddress) {
        self.internal.assert_admin();
        self.storage.player_storage_address.write(player_storage_address);
    }

    #[external("public")]
    fn set_world_storage_address(world_storage_address: AztecAddress) {
        self.internal.assert_admin();
        self.storage.world_storage_address.write(world_storage_address);
    }

    // ================== UTILITY (UNCONSTRAINED) ==================

    #[external("utility")]
    unconstrained fn get_all_storage_addresses_unconstrained() -> ArtifactFacetSystemStorageAddresses {
        ArtifactFacetSystemStorageAddresses {
            config_storage_address: self.storage.config_storage_address.read(),
            arrivals_storage_address: self.storage.arrivals_storage_address.read(),
            artifact_storage_address: self.storage.artifact_storage_address.read(),
            artifact_location_storage_address: self.storage.artifact_location_storage_address.read(),
            planet_storage_address: self.storage.planet_storage_address.read(),
            planet_artifacts_storage_address: self.storage.planet_artifacts_storage_address.read(),
            planet_events_storage_address: self.storage.planet_events_storage_address.read(),
            player_storage_address: self.storage.player_storage_address.read(),
            world_storage_address: self.storage.world_storage_address.read(),
        }
    }

    /// Noir port of Solidity `DFArtifactFacet.createArtifact`
    #[external("public")]
    fn create_artifact(args: DFTCreateArtifactArgs) {
        self.internal.assert_admin();

        let artifact_storage = ArtifactStorage::at(self.storage.artifact_storage_address.read());
        let artifact_location_storage =
            ArtifactLocationStorage::at(self.storage.artifact_location_storage_address.read());

        let timestamp = self.context.timestamp();

        let artifact = Artifact {
            planet_discovered_on: args.planet_id,
            rarity: args.rarity,
            planet_biome: args.biome,
            minted_at_timestamp: timestamp,
            discoverer: args.discoverer,
            artifact_type: args.artifact_type,
            activations: 0,
            last_activated: 0,
            last_deactivated: 0,
            wormhole_to: 0 as Field,
            owner: AztecAddress::zero(),
            controller: args.controller,
            last_updated: timestamp,
        };

        // By default the artifact is on the planet (not in transit).
        let artifact_location =
            ArtifactLocation { planet_id: args.planet_id, voyage_id: 0, last_updated: timestamp };

        self.call(artifact_storage.set(args.id, artifact));
        self.call(artifact_location_storage.set(args.id, artifact_location));
    }

    /// Noir port of Solidity `DFArtifactFacet.updateArtifact`
    #[external("public")]
    fn update_artifact(id: Field, artifact: Artifact, location: ArtifactLocation) {
        self.internal.assert_admin();

        let artifact_storage = ArtifactStorage::at(self.storage.artifact_storage_address.read());
        let artifact_location_storage =
            ArtifactLocationStorage::at(self.storage.artifact_location_storage_address.read());

        assert(
            self.view(artifact_storage.verify_hash(id, poseidon2_hash(artifact.serialize()))),
            "artifact hash mismatch",
        );
        assert(
            self.view(artifact_location_storage.verify_hash(id, poseidon2_hash(location.serialize()))),
            "artifact location hash mismatch",
        );

        self.call(artifact_storage.set(id, artifact));
        self.call(artifact_location_storage.set(id, location));
    }

    /// Noir port of Solidity `DFArtifactFacet.depositArtifact`.
    #[external("private")]
    fn deposit_artifact(
        location_id: Field,
        artifact_id: Field,
        timestamp: u64,
        planet: Planet,
        planet_artifacts_state: PlanetArtifacts,
        planet_events_state: PlanetEvents,
        arrivals: [Arrival; 20],
        artifacts: [Artifact; 20],
        artifact_locations: [ArtifactLocation; 20],
        artifact: Artifact,
        artifact_location: ArtifactLocation,
        world: World,
    ) {
        let sender = self.msg_sender();

        assert(!world.paused, "Game is paused");

        assert_planet_timestamp_freshness(
            timestamp,
            planet,
            planet_artifacts_state,
            planet_events_state,
            arrivals,
            artifacts,
            artifact_locations,
        );

        assert_artifact_and_location_timestamp_freshness(timestamp, artifact, artifact_location);

        let planet_hashes_result = compute_planet_hashes(
            location_id,
            planet,
            planet_artifacts_state,
            planet_events_state,
            arrivals,
            artifacts,
            artifact_locations,
        );

        let artifact_hashes_result =
            compute_artifact_and_location_hashes(artifact_id, artifact, artifact_location);
        let world_hash_result: Field = compute_world_hash(world);

        let planet_hash = planet_hashes_result.1;
        let planet_artifacts_state_hash = planet_hashes_result.2;
        let planet_events_state_hash = planet_hashes_result.3;
        let arrival_ids: [Field; 20] = planet_hashes_result.4;
        let arrival_hashes: [Field; 20] = planet_hashes_result.5;
        let artifact_ids: [Field; 20] = planet_hashes_result.6;
        let artifact_hashes: [Field; 20] = planet_hashes_result.7;
        let artifact_location_hashes: [Field; 20] = planet_hashes_result.8;
        let origin_arrivals_count = planet_hashes_result.9;

        let artifact_hash = artifact_hashes_result.1;
        let artifact_location_hash = artifact_hashes_result.2;

        let world_hash: Field = world_hash_result;

        let refresh_planet_result = refresh_planet_v1(
            timestamp,
            location_id,
            planet,
            planet_events_state,
            arrivals,
            artifacts,
            artifact_locations,
            planet_artifacts_state,
        );

        let mut new_planet = refresh_planet_result.0;
        let mut new_planet_events_state = refresh_planet_result.1;
        let mut new_planet_artifacts_state = refresh_planet_result.2;
        let mut new_artifact_locations = refresh_planet_result.3;

        assert(!new_planet.destroyed, "planet is destroyed");

        assert(
            new_planet.planet_type == PlanetType::TradingPost,
            "can only deposit on trading posts",
        );

        assert(artifact.owner == sender, "you can only deposit artifacts you own");
        assert(new_planet.owner == sender, "you can only deposit on a planet you own");

        assert(artifact != Artifact::zero(), "artifact does not exist");

        assert(
            new_planet.planet_level > artifact.rarity,
            "spacetime rip not high enough level to deposit this artifact",
        );
        assert(!is_spaceship(artifact.artifact_type), "cannot deposit spaceships");

        assert(new_planet_artifacts_state.count < 5, "too many artifacts on this planet");

        let put_artifact_on_planet_result = _put_artifact_on_planet(
            artifact_id,
            artifact_location,
            location_id,
            new_planet_artifacts_state,
        );

        let mut new_artifact_location = put_artifact_on_planet_result.1;
        new_planet_artifacts_state = put_artifact_on_planet_result.3;

        let mut new_artifact = artifact;
        new_artifact.owner = AztecAddress::zero();

        new_planet.last_updated = timestamp;
        new_planet_artifacts_state.last_updated = timestamp;
        new_planet_events_state.last_updated = timestamp;

        for i in 0..20 {
            if i < origin_arrivals_count & (arrivals[i].carried_artifact_id != 0) {
                new_artifact_locations[i].last_updated = timestamp;
            }
        }

        new_artifact.last_updated = timestamp;
        new_artifact_location.last_updated = timestamp;

        {
            let mut prepared_payload: [Field;267] = [0;267];
            let prepared_part_0 = (location_id).serialize();
            for prepared_i in 0..1 { prepared_payload[0 + prepared_i] = prepared_part_0[prepared_i]; }
            let prepared_part_1 = (artifact_id).serialize();
            for prepared_i in 0..1 { prepared_payload[1 + prepared_i] = prepared_part_1[prepared_i]; }
            let prepared_part_2 = (timestamp).serialize();
            for prepared_i in 0..1 { prepared_payload[2 + prepared_i] = prepared_part_2[prepared_i]; }
            let prepared_part_3 = (planet_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[3 + prepared_i] = prepared_part_3[prepared_i]; }
            let prepared_part_4 = (planet_artifacts_state_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[4 + prepared_i] = prepared_part_4[prepared_i]; }
            let prepared_part_5 = (planet_events_state_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[5 + prepared_i] = prepared_part_5[prepared_i]; }
            let prepared_part_6 = (origin_arrivals_count).serialize();
            for prepared_i in 0..1 { prepared_payload[6 + prepared_i] = prepared_part_6[prepared_i]; }
            let prepared_part_7 = (arrival_ids).serialize();
            for prepared_i in 0..20 { prepared_payload[7 + prepared_i] = prepared_part_7[prepared_i]; }
            let prepared_part_8 = (arrival_hashes).serialize();
            for prepared_i in 0..20 { prepared_payload[27 + prepared_i] = prepared_part_8[prepared_i]; }
            let prepared_part_9 = (artifact_ids).serialize();
            for prepared_i in 0..20 { prepared_payload[47 + prepared_i] = prepared_part_9[prepared_i]; }
            let prepared_part_10 = (artifact_hashes).serialize();
            for prepared_i in 0..20 { prepared_payload[67 + prepared_i] = prepared_part_10[prepared_i]; }
            let prepared_part_11 = (artifact_location_hashes).serialize();
            for prepared_i in 0..20 { prepared_payload[87 + prepared_i] = prepared_part_11[prepared_i]; }
            let prepared_part_12 = (artifact_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[107 + prepared_i] = prepared_part_12[prepared_i]; }
            let prepared_part_13 = (artifact_location_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[108 + prepared_i] = prepared_part_13[prepared_i]; }
            let prepared_part_14 = (world_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[109 + prepared_i] = prepared_part_14[prepared_i]; }
            let prepared_part_15 = (new_planet).serialize();
            for prepared_i in 0..32 { prepared_payload[110 + prepared_i] = prepared_part_15[prepared_i]; }
            let prepared_part_16 = (new_planet_artifacts_state).serialize();
            for prepared_i in 0..22 { prepared_payload[142 + prepared_i] = prepared_part_16[prepared_i]; }
            let prepared_part_17 = (new_planet_events_state).serialize();
            for prepared_i in 0..22 { prepared_payload[164 + prepared_i] = prepared_part_17[prepared_i]; }
            let prepared_part_18 = (new_artifact_locations).serialize();
            for prepared_i in 0..60 { prepared_payload[186 + prepared_i] = prepared_part_18[prepared_i]; }
            let prepared_part_19 = (new_artifact).serialize();
            for prepared_i in 0..13 { prepared_payload[246 + prepared_i] = prepared_part_19[prepared_i]; }
            let prepared_part_20 = (new_artifact_location).serialize();
            for prepared_i in 0..3 { prepared_payload[259 + prepared_i] = prepared_part_20[prepared_i]; }
            let prepared_part_21 = (poseidon2_hash((new_planet).serialize())).serialize();
            for prepared_i in 0..1 { prepared_payload[262 + prepared_i] = prepared_part_21[prepared_i]; }
            let prepared_part_22 = (poseidon2_hash((new_planet_artifacts_state).serialize())).serialize();
            for prepared_i in 0..1 { prepared_payload[263 + prepared_i] = prepared_part_22[prepared_i]; }
            let prepared_part_23 = (poseidon2_hash((new_planet_events_state).serialize())).serialize();
            for prepared_i in 0..1 { prepared_payload[264 + prepared_i] = prepared_part_23[prepared_i]; }
            let prepared_part_24 = (poseidon2_hash((new_artifact).serialize())).serialize();
            for prepared_i in 0..1 { prepared_payload[265 + prepared_i] = prepared_part_24[prepared_i]; }
            let prepared_part_25 = (poseidon2_hash((new_artifact_location).serialize())).serialize();
            for prepared_i in 0..1 { prepared_payload[266 + prepared_i] = prepared_part_25[prepared_i]; }
            self.enqueue_self.deposit_artifact_public_prepared(::libs::field_buffer::FieldBuffer { words: prepared_payload });
        }
    }

    #[external("public")]
    #[only_self]
    fn deposit_artifact_public(
        location_id: Field,
        artifact_id: Field,
        timestamp: u64,
        planet_hash: Field,
        planet_artifacts_state_hash: Field,
        planet_events_state_hash: Field,
        origin_arrivals_count: u32,
        arrival_ids: [Field; 20],
        arrival_hashes: [Field; 20],
        artifact_ids: [Field; 20],
        artifact_hashes: [Field; 20],
        artifact_location_hashes: [Field; 20],
        artifact_hash: Field,
        artifact_location_hash: Field,
        world_hash: Field,
        new_planet: Planet,
        new_planet_artifacts_state: PlanetArtifacts,
        new_planet_events_state: PlanetEvents,
        new_artifact_locations: [ArtifactLocation; 20],
        new_artifact: Artifact,
        new_artifact_location: ArtifactLocation,
    ) {
        let actual_timestamp = self.context.timestamp();

        assert_public_timestamp(timestamp, actual_timestamp);

        let arrival_storage = ArrivalStorage::at(self.storage.arrivals_storage_address.read());
        let artifact_storage = ArtifactStorage::at(self.storage.artifact_storage_address.read());
        let artifact_location_storage =
            ArtifactLocationStorage::at(self.storage.artifact_location_storage_address.read());
        let planet_storage = PlanetStorage::at(self.storage.planet_storage_address.read());
        let planet_artifacts_storage =
            PlanetArtifactsStorage::at(self.storage.planet_artifacts_storage_address.read());
        let planet_events_storage =
            PlanetEventsStorage::at(self.storage.planet_events_storage_address.read());
        let world_storage = WorldStorage::at(self.storage.world_storage_address.read());

        assert(
            self.view(planet_storage.verify_hash(location_id, planet_hash)),
            "planet hash mismatch",
        );
        assert(
            self.view(planet_artifacts_storage.verify_hash(location_id, planet_artifacts_state_hash)),
            "planet_artifacts hash mismatch",
        );
        assert(
            self.view(planet_events_storage.verify_hash(location_id, planet_events_state_hash)),
            "planet_events hash mismatch",
        );

        assert(
            self.view(arrival_storage.verify_hashes_batch(
                arrival_ids,
                arrival_hashes,
                origin_arrivals_count as u32,
            )),
            "arrivals hash mismatch",
        );
        assert(
            self.view(artifact_storage.verify_hashes_batch(
                artifact_ids,
                artifact_hashes,
                origin_arrivals_count as u32,
            )),
            "artifacts hash mismatch",
        );
        assert(
            self.view(artifact_location_storage.verify_hashes_batch(
                artifact_ids,
                artifact_location_hashes,
                origin_arrivals_count as u32,
            )),
            "artifact locations hash mismatch",
        );

        assert(
            self.view(artifact_storage.verify_hash(artifact_id, artifact_hash)),
            "artifact hash mismatch",
        );
        assert(
            self.view(artifact_location_storage.verify_hash(artifact_id, artifact_location_hash)),
            "artifact location hash mismatch",
        );

        assert(self.view(world_storage.verify_hash(0, world_hash)), "world hash mismatch");

        self.call(planet_storage.set(location_id, new_planet));
        self.call(planet_artifacts_storage.set(location_id, new_planet_artifacts_state));
        self.call(planet_events_storage.set(location_id, new_planet_events_state));
        self.call(artifact_location_storage.set_arrival_locations_max20(
            artifact_ids,
            new_artifact_locations,
            origin_arrivals_count as u32,
        ));

        self.call(artifact_storage.set(artifact_id, new_artifact));
        self.call(artifact_location_storage.set(artifact_id, new_artifact_location));
    }

    /// Noir port of Solidity `DFArtifactFacet.withdrawArtifact`.
    #[external("private")]
    fn withdraw_artifact(
        location_id: Field,
        artifact_id: Field,
        timestamp: u64,
        planet: Planet,
        planet_artifacts_state: PlanetArtifacts,
        planet_events_state: PlanetEvents,
        arrivals: [Arrival; 20],
        artifacts: [Artifact; 20],
        artifact_locations: [ArtifactLocation; 20],
        artifact: Artifact,
        artifact_location: ArtifactLocation,
        world: World,
    ) {
        let sender = self.msg_sender();

        assert_planet_timestamp_freshness(
            timestamp,
            planet,
            planet_artifacts_state,
            planet_events_state,
            arrivals,
            artifacts,
            artifact_locations,
        );

        assert_artifact_and_location_timestamp_freshness(timestamp, artifact, artifact_location);

        let planet_hashes_result = compute_planet_hashes(
            location_id,
            planet,
            planet_artifacts_state,
            planet_events_state,
            arrivals,
            artifacts,
            artifact_locations,
        );

        let artifact_hashes_result =
            compute_artifact_and_location_hashes(artifact_id, artifact, artifact_location);
        let world_hash_result = compute_world_hash(world);

        let planet_hash = planet_hashes_result.1;
        let planet_artifacts_state_hash = planet_hashes_result.2;
        let planet_events_state_hash = planet_hashes_result.3;
        let arrival_ids: [Field; 20] = planet_hashes_result.4;
        let arrival_hashes: [Field; 20] = planet_hashes_result.5;
        let artifact_ids: [Field; 20] = planet_hashes_result.6;
        let artifact_hashes: [Field; 20] = planet_hashes_result.7;
        let artifact_location_hashes: [Field; 20] = planet_hashes_result.8;
        let origin_arrivals_count = planet_hashes_result.9;

        let artifact_hash = artifact_hashes_result.1;
        let artifact_location_hash = artifact_hashes_result.2;

        let world_hash = world_hash_result;

        let refresh_planet_result = refresh_planet_v1(
            timestamp,
            location_id,
            planet,
            planet_events_state,
            arrivals,
            artifacts,
            artifact_locations,
            planet_artifacts_state,
        );

        let mut new_planet = refresh_planet_result.0;
        let mut new_planet_events_state = refresh_planet_result.1;
        let mut new_planet_artifacts_state = refresh_planet_result.2;
        let mut new_artifact_locations = refresh_planet_result.3;

        assert(!new_planet.destroyed, "planet is destroyed");

        assert(
            new_planet.planet_type == PlanetType::TradingPost,
            "can only withdraw from trading posts",
        );

        assert(new_planet.owner == sender, "you can only deposit on a planet you own");

        assert(artifact != Artifact::zero(), "artifact does not exist");

        assert(
            new_planet.planet_level > artifact.rarity,
            "spacetime rip not high enough level to withdraw this artifact",
        );
        assert(!is_spaceship(artifact.artifact_type), "cannot deposit spaceships");

        let take_artifact_off_planet_result = _take_artifact_off_planet(
            artifact_id,
            artifact_location,
            artifact,
            location_id,
            new_planet_artifacts_state,
        );

        let mut new_artifact_location = take_artifact_off_planet_result.1;
        new_planet_artifacts_state = take_artifact_off_planet_result.3;

        let mut new_artifact = artifact;
        new_artifact.owner = sender;

        new_planet.last_updated = timestamp;
        new_planet_artifacts_state.last_updated = timestamp;
        new_planet_events_state.last_updated = timestamp;

        for i in 0..20 {
            if i < origin_arrivals_count & (arrivals[i].carried_artifact_id != 0) {
                new_artifact_locations[i].last_updated = timestamp;
            }
        }

        new_artifact.last_updated = timestamp;
        new_artifact_location.last_updated = timestamp;

        {
            let mut prepared_payload: [Field;267] = [0;267];
            let prepared_part_0 = (location_id).serialize();
            for prepared_i in 0..1 { prepared_payload[0 + prepared_i] = prepared_part_0[prepared_i]; }
            let prepared_part_1 = (artifact_id).serialize();
            for prepared_i in 0..1 { prepared_payload[1 + prepared_i] = prepared_part_1[prepared_i]; }
            let prepared_part_2 = (timestamp).serialize();
            for prepared_i in 0..1 { prepared_payload[2 + prepared_i] = prepared_part_2[prepared_i]; }
            let prepared_part_3 = (planet_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[3 + prepared_i] = prepared_part_3[prepared_i]; }
            let prepared_part_4 = (planet_artifacts_state_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[4 + prepared_i] = prepared_part_4[prepared_i]; }
            let prepared_part_5 = (planet_events_state_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[5 + prepared_i] = prepared_part_5[prepared_i]; }
            let prepared_part_6 = (origin_arrivals_count).serialize();
            for prepared_i in 0..1 { prepared_payload[6 + prepared_i] = prepared_part_6[prepared_i]; }
            let prepared_part_7 = (arrival_ids).serialize();
            for prepared_i in 0..20 { prepared_payload[7 + prepared_i] = prepared_part_7[prepared_i]; }
            let prepared_part_8 = (arrival_hashes).serialize();
            for prepared_i in 0..20 { prepared_payload[27 + prepared_i] = prepared_part_8[prepared_i]; }
            let prepared_part_9 = (artifact_ids).serialize();
            for prepared_i in 0..20 { prepared_payload[47 + prepared_i] = prepared_part_9[prepared_i]; }
            let prepared_part_10 = (artifact_hashes).serialize();
            for prepared_i in 0..20 { prepared_payload[67 + prepared_i] = prepared_part_10[prepared_i]; }
            let prepared_part_11 = (artifact_location_hashes).serialize();
            for prepared_i in 0..20 { prepared_payload[87 + prepared_i] = prepared_part_11[prepared_i]; }
            let prepared_part_12 = (artifact_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[107 + prepared_i] = prepared_part_12[prepared_i]; }
            let prepared_part_13 = (artifact_location_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[108 + prepared_i] = prepared_part_13[prepared_i]; }
            let prepared_part_14 = (world_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[109 + prepared_i] = prepared_part_14[prepared_i]; }
            let prepared_part_15 = (new_planet).serialize();
            for prepared_i in 0..32 { prepared_payload[110 + prepared_i] = prepared_part_15[prepared_i]; }
            let prepared_part_16 = (new_planet_artifacts_state).serialize();
            for prepared_i in 0..22 { prepared_payload[142 + prepared_i] = prepared_part_16[prepared_i]; }
            let prepared_part_17 = (new_planet_events_state).serialize();
            for prepared_i in 0..22 { prepared_payload[164 + prepared_i] = prepared_part_17[prepared_i]; }
            let prepared_part_18 = (new_artifact_locations).serialize();
            for prepared_i in 0..60 { prepared_payload[186 + prepared_i] = prepared_part_18[prepared_i]; }
            let prepared_part_19 = (new_artifact).serialize();
            for prepared_i in 0..13 { prepared_payload[246 + prepared_i] = prepared_part_19[prepared_i]; }
            let prepared_part_20 = (new_artifact_location).serialize();
            for prepared_i in 0..3 { prepared_payload[259 + prepared_i] = prepared_part_20[prepared_i]; }
            let prepared_part_21 = (poseidon2_hash((new_planet).serialize())).serialize();
            for prepared_i in 0..1 { prepared_payload[262 + prepared_i] = prepared_part_21[prepared_i]; }
            let prepared_part_22 = (poseidon2_hash((new_planet_artifacts_state).serialize())).serialize();
            for prepared_i in 0..1 { prepared_payload[263 + prepared_i] = prepared_part_22[prepared_i]; }
            let prepared_part_23 = (poseidon2_hash((new_planet_events_state).serialize())).serialize();
            for prepared_i in 0..1 { prepared_payload[264 + prepared_i] = prepared_part_23[prepared_i]; }
            let prepared_part_24 = (poseidon2_hash((new_artifact).serialize())).serialize();
            for prepared_i in 0..1 { prepared_payload[265 + prepared_i] = prepared_part_24[prepared_i]; }
            let prepared_part_25 = (poseidon2_hash((new_artifact_location).serialize())).serialize();
            for prepared_i in 0..1 { prepared_payload[266 + prepared_i] = prepared_part_25[prepared_i]; }
            self.enqueue_self.withdraw_artifact_public_prepared(::libs::field_buffer::FieldBuffer { words: prepared_payload });
        }
    }

    #[external("public")]
    #[only_self]
    fn withdraw_artifact_public(
        location_id: Field,
        artifact_id: Field,
        timestamp: u64,
        planet_hash: Field,
        planet_artifacts_state_hash: Field,
        planet_events_state_hash: Field,
        origin_arrivals_count: u32,
        arrival_ids: [Field; 20],
        arrival_hashes: [Field; 20],
        artifact_ids: [Field; 20],
        artifact_hashes: [Field; 20],
        artifact_location_hashes: [Field; 20],
        artifact_hash: Field,
        artifact_location_hash: Field,
        world_hash: Field,
        new_planet: Planet,
        new_planet_artifacts_state: PlanetArtifacts,
        new_planet_events_state: PlanetEvents,
        new_artifact_locations: [ArtifactLocation; 20],
        new_artifact: Artifact,
        new_artifact_location: ArtifactLocation,
    ) {
        let actual_timestamp = self.context.timestamp();
        assert_public_timestamp(timestamp, actual_timestamp);

        let arrival_storage = ArrivalStorage::at(self.storage.arrivals_storage_address.read());
        let artifact_storage = ArtifactStorage::at(self.storage.artifact_storage_address.read());
        let artifact_location_storage =
            ArtifactLocationStorage::at(self.storage.artifact_location_storage_address.read());
        let planet_storage = PlanetStorage::at(self.storage.planet_storage_address.read());
        let planet_artifacts_storage =
            PlanetArtifactsStorage::at(self.storage.planet_artifacts_storage_address.read());
        let planet_events_storage =
            PlanetEventsStorage::at(self.storage.planet_events_storage_address.read());
        let world_storage = WorldStorage::at(self.storage.world_storage_address.read());

        assert(
            self.view(planet_storage.verify_hash(location_id, planet_hash)),
            "planet hash mismatch",
        );
        assert(
            self.view(planet_artifacts_storage.verify_hash(location_id, planet_artifacts_state_hash)),
            "planet_artifacts hash mismatch",
        );
        assert(
            self.view(planet_events_storage.verify_hash(location_id, planet_events_state_hash)),
            "planet_events hash mismatch",
        );

        assert(
            self.view(arrival_storage.verify_hashes_batch(
                arrival_ids,
                arrival_hashes,
                origin_arrivals_count as u32,
            )),
            "arrivals hash mismatch",
        );
        assert(
            self.view(artifact_storage.verify_hashes_batch(
                artifact_ids,
                artifact_hashes,
                origin_arrivals_count as u32,
            )),
            "artifacts hash mismatch",
        );
        assert(
            self.view(artifact_location_storage.verify_hashes_batch(
                artifact_ids,
                artifact_location_hashes,
                origin_arrivals_count as u32,
            )),
            "artifact locations hash mismatch",
        );

        assert(
            self.view(artifact_storage.verify_hash(artifact_id, artifact_hash)),
            "artifact hash mismatch",
        );
        assert(
            self.view(artifact_location_storage.verify_hash(artifact_id, artifact_location_hash)),
            "artifact location hash mismatch",
        );

        assert(self.view(world_storage.verify_hash(0, world_hash)), "world hash mismatch");

        self.call(planet_storage.set(location_id, new_planet));
        self.call(planet_artifacts_storage.set(location_id, new_planet_artifacts_state));
        self.call(planet_events_storage.set(location_id, new_planet_events_state));
        self.call(artifact_location_storage.set_arrival_locations_max20(
            artifact_ids,
            new_artifact_locations,
            origin_arrivals_count as u32,
        ));

        self.call(artifact_storage.set(artifact_id, new_artifact));
        self.call(artifact_location_storage.set(artifact_id, new_artifact_location));
    }

    /// Noir port of Solidity `DFArtifactFacet.giveSpaceShips`
    #[external("private")]
    fn give_spaceships(
        location_id: Field,
        timestamp: u64,
        planet: Planet,
        planet_artifacts_state: PlanetArtifacts,
        planet_events_state: PlanetEvents,
        arrivals: [Arrival; 20],
        artifacts: [Artifact; 20],
        artifact_locations: [ArtifactLocation; 20],
        player: Player,
        spaceships_config: SpaceshipsConfig,
    ) {
        let sender = self.msg_sender();

        assert(!player.claimed_ships, "player already claimed ships");
        assert(planet.owner == sender, "you can only spawn ships on your home planet");
        assert(planet.is_home_planet, "you can only spawn ships on your home planet");

        assert(planet_events_state.count == 0, "planet events must be empty");
        assert(planet_artifacts_state.count == 0, "planet artifacts must be empty");

        assert_planet_timestamp_freshness(
            timestamp,
            planet,
            planet_artifacts_state,
            planet_events_state,
            arrivals,
            artifacts,
            artifact_locations,
        );

        let planet_hashes_result = compute_planet_hashes(
            location_id,
            planet,
            planet_artifacts_state,
            planet_events_state,
            arrivals,
            artifacts,
            artifact_locations,
        );

        let planet_hash = planet_hashes_result.1;
        let planet_artifacts_state_hash = planet_hashes_result.2;
        let planet_events_state_hash = planet_hashes_result.3;
        let arrival_ids: [Field; 20] = planet_hashes_result.4;
        let arrival_hashes: [Field; 20] = planet_hashes_result.5;
        let artifact_ids: [Field; 20] = planet_hashes_result.6;
        let artifact_hashes: [Field; 20] = planet_hashes_result.7;
        let artifact_location_hashes: [Field; 20] = planet_hashes_result.8;
        let origin_arrivals_count = planet_hashes_result.9;

        let player_hash = compute_player_hash(player);

        let refresh_planet_result = refresh_planet_v1(
            timestamp,
            location_id,
            planet,
            planet_events_state,
            arrivals,
            artifacts,
            artifact_locations,
            planet_artifacts_state,
        );

        let mut new_planet = refresh_planet_result.0;
        let mut new_planet_events_state = refresh_planet_result.1;
        let mut new_planet_artifacts_state = refresh_planet_result.2;
        let mut new_artifact_locations = refresh_planet_result.3;

        let mut nonce: u32 = 1;

        let mut spaceships_ids: [Field; 5] = [0; 5];
        let mut spaceships: [Artifact; 5] = [Artifact::zero(); 5];
        let mut spaceships_locations: [ArtifactLocation; 5] = [ArtifactLocation::zero(); 5];

        let ship_enabled: [bool; 5] = [
            spaceships_config.mothership,
            spaceships_config.crescent,
            spaceships_config.whale,
            spaceships_config.gear,
            spaceships_config.titan,
        ];
        let ship_types: [u8; 5] = [
            ArtifactType::ShipMothership,
            ArtifactType::ShipCrescent,
            ArtifactType::ShipWhale,
            ArtifactType::ShipGear,
            ArtifactType::ShipTitan,
        ];

        let mut nonce: u32 = 1;
        for i in 0..5 {
            if ship_enabled[i] {
                let result = create_and_place_spaceship(location_id, sender, ship_types[i], nonce);
                let ship_id = result.0;
                let ship_args = result.1;

                let ship = artifact_from_create_args(ship_args, sender, timestamp);
                let mut ship_location = ArtifactLocation {
                    planet_id: location_id,
                    voyage_id: 0,
                    last_updated: timestamp,
                };

                let put_result = _put_artifact_on_planet(
                    ship_id,
                    ship_location,
                    location_id,
                    new_planet_artifacts_state,
                );

                ship_location = put_result.1;
                new_planet_artifacts_state = put_result.3;

                spaceships_ids[i] = ship_id;
                spaceships[i] = ship;
                spaceships_locations[i] = ship_location;

                nonce += 1;
            }
        }

        let mut new_player = player;
        new_player.claimed_ships = true;

        new_planet.last_updated = timestamp;
        new_planet_events_state.last_updated = timestamp;
        new_planet_artifacts_state.last_updated = timestamp;
        for i in 0..20 {
            if i < origin_arrivals_count & (arrivals[i].carried_artifact_id != 0) {
                new_artifact_locations[i].last_updated = timestamp;
            }
        }
        new_player.last_updated = timestamp;
        for i in 0..5 {
            if ship_enabled[i] {
                spaceships[i].last_updated = timestamp;
                spaceships_locations[i].last_updated = timestamp;
            }
        }

        {
            let mut prepared_payload: [Field;341] = [0;341];
            let prepared_part_0 = (sender).serialize();
            for prepared_i in 0..1 { prepared_payload[0 + prepared_i] = prepared_part_0[prepared_i]; }
            let prepared_part_1 = (location_id).serialize();
            for prepared_i in 0..1 { prepared_payload[1 + prepared_i] = prepared_part_1[prepared_i]; }
            let prepared_part_2 = (timestamp).serialize();
            for prepared_i in 0..1 { prepared_payload[2 + prepared_i] = prepared_part_2[prepared_i]; }
            let prepared_part_3 = (planet_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[3 + prepared_i] = prepared_part_3[prepared_i]; }
            let prepared_part_4 = (planet_artifacts_state_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[4 + prepared_i] = prepared_part_4[prepared_i]; }
            let prepared_part_5 = (planet_events_state_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[5 + prepared_i] = prepared_part_5[prepared_i]; }
            let prepared_part_6 = (arrival_ids).serialize();
            for prepared_i in 0..20 { prepared_payload[6 + prepared_i] = prepared_part_6[prepared_i]; }
            let prepared_part_7 = (arrival_hashes).serialize();
            for prepared_i in 0..20 { prepared_payload[26 + prepared_i] = prepared_part_7[prepared_i]; }
            let prepared_part_8 = (artifact_ids).serialize();
            for prepared_i in 0..20 { prepared_payload[46 + prepared_i] = prepared_part_8[prepared_i]; }
            let prepared_part_9 = (artifact_hashes).serialize();
            for prepared_i in 0..20 { prepared_payload[66 + prepared_i] = prepared_part_9[prepared_i]; }
            let prepared_part_10 = (artifact_location_hashes).serialize();
            for prepared_i in 0..20 { prepared_payload[86 + prepared_i] = prepared_part_10[prepared_i]; }
            let prepared_part_11 = (origin_arrivals_count).serialize();
            for prepared_i in 0..1 { prepared_payload[106 + prepared_i] = prepared_part_11[prepared_i]; }
            let prepared_part_12 = (player_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[107 + prepared_i] = prepared_part_12[prepared_i]; }
            let prepared_part_13 = (new_planet).serialize();
            for prepared_i in 0..32 { prepared_payload[108 + prepared_i] = prepared_part_13[prepared_i]; }
            let prepared_part_14 = (new_planet_events_state).serialize();
            for prepared_i in 0..22 { prepared_payload[140 + prepared_i] = prepared_part_14[prepared_i]; }
            let prepared_part_15 = (new_planet_artifacts_state).serialize();
            for prepared_i in 0..22 { prepared_payload[162 + prepared_i] = prepared_part_15[prepared_i]; }
            let prepared_part_16 = (new_artifact_locations).serialize();
            for prepared_i in 0..60 { prepared_payload[184 + prepared_i] = prepared_part_16[prepared_i]; }
            let prepared_part_17 = (new_player).serialize();
            for prepared_i in 0..8 { prepared_payload[244 + prepared_i] = prepared_part_17[prepared_i]; }
            let prepared_part_18 = (spaceships_ids).serialize();
            for prepared_i in 0..5 { prepared_payload[252 + prepared_i] = prepared_part_18[prepared_i]; }
            let prepared_part_19 = (spaceships).serialize();
            for prepared_i in 0..65 { prepared_payload[257 + prepared_i] = prepared_part_19[prepared_i]; }
            let prepared_part_20 = (spaceships_locations).serialize();
            for prepared_i in 0..15 { prepared_payload[322 + prepared_i] = prepared_part_20[prepared_i]; }
            let prepared_part_21 = (poseidon2_hash((new_planet).serialize())).serialize();
            for prepared_i in 0..1 { prepared_payload[337 + prepared_i] = prepared_part_21[prepared_i]; }
            let prepared_part_22 = (poseidon2_hash((new_planet_events_state).serialize())).serialize();
            for prepared_i in 0..1 { prepared_payload[338 + prepared_i] = prepared_part_22[prepared_i]; }
            let prepared_part_23 = (poseidon2_hash((new_planet_artifacts_state).serialize())).serialize();
            for prepared_i in 0..1 { prepared_payload[339 + prepared_i] = prepared_part_23[prepared_i]; }
            let prepared_part_24 = (poseidon2_hash((new_player).serialize())).serialize();
            for prepared_i in 0..1 { prepared_payload[340 + prepared_i] = prepared_part_24[prepared_i]; }
            self.enqueue_self.give_spaceships_public_prepared(::libs::field_buffer::FieldBuffer { words: prepared_payload });
        }
    }

    #[external("public")]
    #[only_self]
    fn give_spaceships_public(
        sender: AztecAddress,
        location_id: Field,
        timestamp: u64,
        planet_hash: Field,
        planet_artifacts_state_hash: Field,
        planet_events_state_hash: Field,
        arrival_ids: [Field; 20],
        arrival_hashes: [Field; 20],
        artifact_ids: [Field; 20],
        artifact_hashes: [Field; 20],
        artifact_location_hashes: [Field; 20],
        origin_arrivals_count: u32,
        player_hash: Field,
        new_planet: Planet,
        new_planet_events_state: PlanetEvents,
        new_planet_artifacts_state: PlanetArtifacts,
        new_artifact_locations: [ArtifactLocation; 20],
        new_player: Player,
        spaceships_ids: [Field; 5],
        spaceships: [Artifact; 5],
        spaceships_locations: [ArtifactLocation; 5],
    ) {
        let actual_timestamp = self.context.timestamp();
        assert_public_timestamp(timestamp, actual_timestamp);

        let arrival_storage = ArrivalStorage::at(self.storage.arrivals_storage_address.read());
        let artifact_storage = ArtifactStorage::at(self.storage.artifact_storage_address.read());
        let artifact_location_storage =
            ArtifactLocationStorage::at(self.storage.artifact_location_storage_address.read());
        let planet_storage = PlanetStorage::at(self.storage.planet_storage_address.read());
        let planet_artifacts_storage =
            PlanetArtifactsStorage::at(self.storage.planet_artifacts_storage_address.read());
        let planet_events_storage =
            PlanetEventsStorage::at(self.storage.planet_events_storage_address.read());
        let player_storage = PlayerStorage::at(self.storage.player_storage_address.read());

        assert(
            self.view(planet_storage.verify_hash(location_id, planet_hash)),
            "planet hash mismatch",
        );
        assert(
            self.view(planet_artifacts_storage.verify_hash(location_id, planet_artifacts_state_hash)),
            "planet_artifacts hash mismatch",
        );
        assert(
            self.view(planet_events_storage.verify_hash(location_id, planet_events_state_hash)),
            "planet_events hash mismatch",
        );

        assert(
            self.view(arrival_storage.verify_hashes_batch(
                arrival_ids,
                arrival_hashes,
                origin_arrivals_count as u32,
            )),
            "arrivals hash mismatch",
        );

        assert(
            self.view(artifact_storage.verify_hashes_batch(
                artifact_ids,
                artifact_hashes,
                origin_arrivals_count as u32,
            )),
            "artifacts hash mismatch",
        );

        assert(
            self.view(artifact_location_storage.verify_hashes_batch(
                artifact_ids,
                artifact_location_hashes,
                origin_arrivals_count as u32,
            )),
            "artifact locations hash mismatch",
        );

        assert(self.view(player_storage.verify_hash(sender, player_hash)), "player hash mismatch");

        self.call(planet_storage.set(location_id, new_planet));
        self.call(planet_events_storage.set(location_id, new_planet_events_state));
        self.call(planet_artifacts_storage.set(location_id, new_planet_artifacts_state));
        self.call(artifact_location_storage.set_arrival_locations_max20(
            artifact_ids,
            new_artifact_locations,
            origin_arrivals_count as u32,
        ));
        self.call(player_storage.set(sender, new_player));

        self.call(artifact_storage.set_spaceships_max5(spaceships_ids, spaceships, 5));

        self.call(artifact_location_storage.set_spaceship_locations_max5(
            spaceships_ids,
            spaceships_locations,
            5,
        ));
    }

    /// Noir port of Solidity `DFArtifactFacet.adminGiveArtifact`
    #[external("public")]
    fn admin_give_artifact(args: DFTCreateArtifactArgs, planet_artifacts_state: PlanetArtifacts) {
        self.internal.assert_admin();

        let artifact_storage = ArtifactStorage::at(self.storage.artifact_storage_address.read());
        let artifact_location_storage =
            ArtifactLocationStorage::at(self.storage.artifact_location_storage_address.read());

        let planet_artifacts_storage =
            PlanetArtifactsStorage::at(self.storage.planet_artifacts_storage_address.read());

        let planet_artifacts_state_hash = if planet_artifacts_state == PlanetArtifacts::zero() {
            0
        } else {
            poseidon2_hash(planet_artifacts_state.serialize())
        };

        assert(
            self.view(planet_artifacts_storage.verify_hash(
                args.planet_id,
                planet_artifacts_state_hash,
            )),
            "planet_artifacts hash mismatch",
        );

        let timestamp = self.context.timestamp();

        let mut artifact = Artifact {
            planet_discovered_on: args.planet_id,
            rarity: args.rarity,
            planet_biome: args.biome,
            minted_at_timestamp: timestamp,
            discoverer: args.discoverer,
            artifact_type: args.artifact_type,
            activations: 0,
            last_activated: 0,
            last_deactivated: 0,
            wormhole_to: 0 as Field,
            owner: AztecAddress::zero(),
            controller: args.controller,
            last_updated: timestamp,
        };

        // By default the artifact is on the planet (not in transit).
        let mut artifact_location =
            ArtifactLocation { planet_id: args.planet_id, voyage_id: 0, last_updated: timestamp };

        let artifact_id = args.id;
        let location_id = args.planet_id;

        let put_artifact_on_planet_result = _put_artifact_on_planet(
            artifact_id,
            artifact_location,
            location_id,
            planet_artifacts_state,
        );

        let mut new_artifact_location = put_artifact_on_planet_result.1;
        let mut new_planet_artifacts_state = put_artifact_on_planet_result.3;

        self.call(artifact_storage.set(artifact_id, artifact));
        self.call(artifact_location_storage.set(artifact_id, new_artifact_location));
        self.call(planet_artifacts_storage.set(location_id, new_planet_artifacts_state));
    }

    /// Noir port of Solidity `DFAdminFacet.adminGiveSpaceShip`
    #[external("public")]
    fn admin_give_spaceship(
        args: DFTCreateArtifactArgs,
        planet: Planet,
        planet_artifacts_state: PlanetArtifacts,
    ) {
        self.internal.assert_admin();

        assert(is_spaceship(args.artifact_type), "artifact type must be a spaceship");

        let planet_storage = PlanetStorage::at(self.storage.planet_storage_address.read());
        let artifact_storage = ArtifactStorage::at(self.storage.artifact_storage_address.read());
        let artifact_location_storage =
            ArtifactLocationStorage::at(self.storage.artifact_location_storage_address.read());
        let planet_artifacts_storage =
            PlanetArtifactsStorage::at(self.storage.planet_artifacts_storage_address.read());

        let location_id = args.planet_id;

        // Verify planet state hash
        let planet_state_hash = poseidon2_hash(planet.serialize());
        assert(
            self.view(planet_storage.verify_hash(location_id, planet_state_hash)),
            "planet hash mismatch",
        );
        assert(planet.is_initialized, "planet is not initialized");

        // Verify planet_artifacts state hash
        let planet_artifacts_state_hash = if planet_artifacts_state == PlanetArtifacts::zero() {
            0
        } else {
            poseidon2_hash(planet_artifacts_state.serialize())
        };
        assert(
            self.view(planet_artifacts_storage.verify_hash(location_id, planet_artifacts_state_hash)),
            "planet_artifacts hash mismatch",
        );

        let timestamp = self.context.timestamp();

        let artifact = Artifact {
            planet_discovered_on: location_id,
            rarity: args.rarity,
            planet_biome: args.biome,
            minted_at_timestamp: timestamp,
            discoverer: args.discoverer,
            artifact_type: args.artifact_type,
            activations: 0,
            last_activated: 0,
            last_deactivated: 0,
            wormhole_to: 0 as Field,
            owner: AztecAddress::zero(),
            controller: args.controller,
            last_updated: timestamp,
        };

        let artifact_location =
            ArtifactLocation { planet_id: location_id, voyage_id: 0, last_updated: timestamp };

        let artifact_id = args.id;

        let put_result = _put_artifact_on_planet(
            artifact_id,
            artifact_location,
            location_id,
            planet_artifacts_state,
        );
        let new_artifact_location = put_result.1;
        let new_planet_artifacts_state = put_result.3;

        let new_planet = apply_spaceship_arrive(artifact, planet);

        self.call(artifact_storage.set(artifact_id, artifact));
        self.call(artifact_location_storage.set(artifact_id, new_artifact_location));
        self.call(planet_artifacts_storage.set(location_id, new_planet_artifacts_state));
        self.call(planet_storage.set(location_id, new_planet));
    }


    // Additional hashes are bound by the existing private gameplay proof.
    #[external("public")]
    #[only_self]
    fn deposit_artifact_public_prepared(prepared_payload: ::libs::field_buffer::FieldBuffer<267>) {
        let prepared_payload = prepared_payload.words;
        let state_backend_address = self.storage.state_backend.read();
        let state_worker_address = self.storage.state_worker.read();
        let mut settled_by_backend = false;
        if (state_backend_address != AztecAddress::zero()) & (state_worker_address != AztecAddress::zero()) {
            let plan_addresses = [
                AztecAddress::zero(),
                self.storage.world_storage_address.read(),
                AztecAddress::zero(),
                self.storage.planet_storage_address.read(),
                AztecAddress::zero(),
                self.storage.planet_events_storage_address.read(),
                self.storage.planet_artifacts_storage_address.read(),
                self.storage.arrivals_storage_address.read(),
                self.storage.artifact_storage_address.read(),
                self.storage.artifact_location_storage_address.read(),
            ];
            let system_admin = AztecAddress::zero();
            let worker_selector = comptime { aztec::protocol::abis::function_selector::FunctionSelector::from_signature("try_deposit_artifact_public_prepared(([Field;279]))") };
            let mut worker_calldata:[Field;280]=[0;280];
            worker_calldata[0]=worker_selector.to_field();
            worker_calldata[1]=state_backend_address.to_field();
            for worker_i in 0..10 { worker_calldata[2+worker_i]=plan_addresses[worker_i].to_field(); }
            worker_calldata[12]=system_admin.to_field();
            for worker_i in 0..267 { worker_calldata[13+worker_i]=prepared_payload[worker_i]; }
            let result = ::libs::public_call::call(state_worker_address,worker_calldata);
            settled_by_backend = _checked_worker_result(result);
        }
        if !settled_by_backend {
            let mut original_calldata:[Field;263]=[0;263];
            let original_selector = comptime { aztec::protocol::abis::function_selector::FunctionSelector::from_signature("deposit_artifact_public(Field,Field,u64,Field,Field,Field,u32,[Field;20],[Field;20],[Field;20],[Field;20],[Field;20],Field,Field,Field,(u8,u64,(Field),u8,u8,u8,bool,bool,bool,(Field),(Field),u32,u128,u128,u128,u128,u128,u128,u128,u128,u128,u8,u8,u8,u64,u128,u128,u128,u128,u128,bool,u32),([Field;20],u32,u64),([(Field);20],u32,u64),[(Field,Field,u64);20],(Field,u8,u8,u64,(Field),u8,u128,u64,u64,Field,(Field),(Field),u64),(Field,Field,u64))") };
            original_calldata[0]=original_selector.to_field();
            for fallback_i in 0..262 { original_calldata[1+fallback_i]=prepared_payload[fallback_i]; }
            let result = ::libs::public_call::call(self.context.this_address(),original_calldata);
            assert(result.len() == 0, "Unexpected original continuation result");

        }
}

    // Additional hashes are bound by the existing private gameplay proof.
    #[external("public")]
    #[only_self]
    fn withdraw_artifact_public_prepared(prepared_payload: ::libs::field_buffer::FieldBuffer<267>) {
        let prepared_payload = prepared_payload.words;
        let state_backend_address = self.storage.state_backend.read();
        let state_worker_address = self.storage.state_worker.read();
        let mut settled_by_backend = false;
        if (state_backend_address != AztecAddress::zero()) & (state_worker_address != AztecAddress::zero()) {
            let plan_addresses = [
                AztecAddress::zero(),
                self.storage.world_storage_address.read(),
                AztecAddress::zero(),
                self.storage.planet_storage_address.read(),
                AztecAddress::zero(),
                self.storage.planet_events_storage_address.read(),
                self.storage.planet_artifacts_storage_address.read(),
                self.storage.arrivals_storage_address.read(),
                self.storage.artifact_storage_address.read(),
                self.storage.artifact_location_storage_address.read(),
            ];
            let system_admin = AztecAddress::zero();
            let worker_selector = comptime { aztec::protocol::abis::function_selector::FunctionSelector::from_signature("try_withdraw_artifact_public_prepared(([Field;279]))") };
            let mut worker_calldata:[Field;280]=[0;280];
            worker_calldata[0]=worker_selector.to_field();
            worker_calldata[1]=state_backend_address.to_field();
            for worker_i in 0..10 { worker_calldata[2+worker_i]=plan_addresses[worker_i].to_field(); }
            worker_calldata[12]=system_admin.to_field();
            for worker_i in 0..267 { worker_calldata[13+worker_i]=prepared_payload[worker_i]; }
            let result = ::libs::public_call::call(state_worker_address,worker_calldata);
            settled_by_backend = _checked_worker_result(result);
        }
        if !settled_by_backend {
            let mut original_calldata:[Field;263]=[0;263];
            let original_selector = comptime { aztec::protocol::abis::function_selector::FunctionSelector::from_signature("withdraw_artifact_public(Field,Field,u64,Field,Field,Field,u32,[Field;20],[Field;20],[Field;20],[Field;20],[Field;20],Field,Field,Field,(u8,u64,(Field),u8,u8,u8,bool,bool,bool,(Field),(Field),u32,u128,u128,u128,u128,u128,u128,u128,u128,u128,u8,u8,u8,u64,u128,u128,u128,u128,u128,bool,u32),([Field;20],u32,u64),([(Field);20],u32,u64),[(Field,Field,u64);20],(Field,u8,u8,u64,(Field),u8,u128,u64,u64,Field,(Field),(Field),u64),(Field,Field,u64))") };
            original_calldata[0]=original_selector.to_field();
            for fallback_i in 0..262 { original_calldata[1+fallback_i]=prepared_payload[fallback_i]; }
            let result = ::libs::public_call::call(self.context.this_address(),original_calldata);
            assert(result.len() == 0, "Unexpected original continuation result");

        }
}

    // Additional hashes are bound by the existing private gameplay proof.
    #[external("public")]
    #[only_self]
    fn give_spaceships_public_prepared(prepared_payload: ::libs::field_buffer::FieldBuffer<341>) {
        let prepared_payload=prepared_payload.words;
        let state_backend_address=self.storage.state_backend.read();
        let mut settled_by_backend=false;
        if state_backend_address != AztecAddress::zero() {
            // The original zero-count Arrival view still calls arbitrary stores.
            // Skip it only for the immutable canonical namespace; otherwise the
            // original System continuation observes the exact configured caller.
            let arrival=self.storage.arrivals_storage_address.read();
            if ::state_backend_readonly::public_read::get_namespace_kind(state_backend_address,arrival)==7 {
            let player=self.storage.player_storage_address.read();
            let planet=self.storage.planet_storage_address.read();
            let planet_events=self.storage.planet_events_storage_address.read();
            let planet_artifacts=self.storage.planet_artifacts_storage_address.read();
            let artifact=self.storage.artifact_storage_address.read();
            let artifact_location=self.storage.artifact_location_storage_address.read();
            let selector=comptime { aztec::protocol::abis::function_selector::FunctionSelector::from_signature("try_settle_give_spaceships(([Field;186]))") };
            let calldata=[selector.to_field(), player.to_field(), planet.to_field(), planet_events.to_field(), planet_artifacts.to_field(), artifact.to_field(), artifact_location.to_field(), prepared_payload[0], prepared_payload[1], prepared_payload[2], prepared_payload[3], prepared_payload[4], prepared_payload[5], prepared_payload[107], prepared_payload[108], prepared_payload[109], prepared_payload[110], prepared_payload[111], prepared_payload[112], prepared_payload[113], prepared_payload[114], prepared_payload[115], prepared_payload[116], prepared_payload[117], prepared_payload[118], prepared_payload[119], prepared_payload[120], prepared_payload[121], prepared_payload[122], prepared_payload[123], prepared_payload[124], prepared_payload[125], prepared_payload[126], prepared_payload[127], prepared_payload[128], prepared_payload[129], prepared_payload[130], prepared_payload[131], prepared_payload[132], prepared_payload[133], prepared_payload[134], prepared_payload[135], prepared_payload[136], prepared_payload[137], prepared_payload[138], prepared_payload[139], prepared_payload[140], prepared_payload[141], prepared_payload[142], prepared_payload[143], prepared_payload[144], prepared_payload[145], prepared_payload[146], prepared_payload[147], prepared_payload[148], prepared_payload[149], prepared_payload[150], prepared_payload[151], prepared_payload[152], prepared_payload[153], prepared_payload[154], prepared_payload[155], prepared_payload[156], prepared_payload[157], prepared_payload[158], prepared_payload[159], prepared_payload[160], prepared_payload[161], prepared_payload[162], prepared_payload[163], prepared_payload[164], prepared_payload[165], prepared_payload[166], prepared_payload[167], prepared_payload[168], prepared_payload[169], prepared_payload[170], prepared_payload[171], prepared_payload[172], prepared_payload[173], prepared_payload[174], prepared_payload[175], prepared_payload[176], prepared_payload[177], prepared_payload[178], prepared_payload[179], prepared_payload[180], prepared_payload[181], prepared_payload[182], prepared_payload[183], prepared_payload[244], prepared_payload[245], prepared_payload[246], prepared_payload[247], prepared_payload[248], prepared_payload[249], prepared_payload[250], prepared_payload[251], prepared_payload[252], prepared_payload[253], prepared_payload[254], prepared_payload[255], prepared_payload[256], prepared_payload[257], prepared_payload[258], prepared_payload[259], prepared_payload[260], prepared_payload[261], prepared_payload[262], prepared_payload[263], prepared_payload[264], prepared_payload[265], prepared_payload[266], prepared_payload[267], prepared_payload[268], prepared_payload[269], prepared_payload[270], prepared_payload[271], prepared_payload[272], prepared_payload[273], prepared_payload[274], prepared_payload[275], prepared_payload[276], prepared_payload[277], prepared_payload[278], prepared_payload[279], prepared_payload[280], prepared_payload[281], prepared_payload[282], prepared_payload[283], prepared_payload[284], prepared_payload[285], prepared_payload[286], prepared_payload[287], prepared_payload[288], prepared_payload[289], prepared_payload[290], prepared_payload[291], prepared_payload[292], prepared_payload[293], prepared_payload[294], prepared_payload[295], prepared_payload[296], prepared_payload[297], prepared_payload[298], prepared_payload[299], prepared_payload[300], prepared_payload[301], prepared_payload[302], prepared_payload[303], prepared_payload[304], prepared_payload[305], prepared_payload[306], prepared_payload[307], prepared_payload[308], prepared_payload[309], prepared_payload[310], prepared_payload[311], prepared_payload[312], prepared_payload[313], prepared_payload[314], prepared_payload[315], prepared_payload[316], prepared_payload[317], prepared_payload[318], prepared_payload[319], prepared_payload[320], prepared_payload[321], prepared_payload[322], prepared_payload[323], prepared_payload[324], prepared_payload[325], prepared_payload[326], prepared_payload[327], prepared_payload[328], prepared_payload[329], prepared_payload[330], prepared_payload[331], prepared_payload[332], prepared_payload[333], prepared_payload[334], prepared_payload[335], prepared_payload[336], prepared_payload[337], prepared_payload[338], prepared_payload[339], prepared_payload[340]];
            let result=::libs::public_call::call(state_backend_address,calldata);
            settled_by_backend=_checked_worker_result(result);
            }
        }
        if !settled_by_backend {
            let mut original_calldata:[Field;338]=[0;338];
            let original_selector = comptime { aztec::protocol::abis::function_selector::FunctionSelector::from_signature("give_spaceships_public((Field),Field,u64,Field,Field,Field,[Field;20],[Field;20],[Field;20],[Field;20],[Field;20],u32,Field,(u8,u64,(Field),u8,u8,u8,bool,bool,bool,(Field),(Field),u32,u128,u128,u128,u128,u128,u128,u128,u128,u128,u8,u8,u8,u64,u128,u128,u128,u128,u128,bool,u32),([(Field);20],u32,u64),([Field;20],u32,u64),[(Field,Field,u64);20],(u64,Field,u64,u128,u128,u128,bool,u64),[Field;5],[(Field,u8,u8,u64,(Field),u8,u128,u64,u64,Field,(Field),(Field),u64);5],[(Field,Field,u64);5])") };
            original_calldata[0]=original_selector.to_field();
            for fallback_i in 0..337 { original_calldata[1+fallback_i]=prepared_payload[fallback_i]; }
            let result = ::libs::public_call::call(self.context.this_address(),original_calldata);
            assert(result.len() == 0, "Unexpected original continuation result");

        }
}

    #[external("public")]
    fn set_state_backend(state_backend: AztecAddress) {
        self.internal.assert_admin();
        self.storage.state_backend.write(state_backend);
    }

    #[external("public")]
    #[view]
    fn get_backend_admin() -> AztecAddress {
        self.storage.admin.read()
    }

    #[external("public")]
    #[view]
    fn get_state_backend() -> AztecAddress {
        self.storage.state_backend.read()
    }
    #[external("public")]
    fn set_state_worker(state_worker:AztecAddress) {
        self.internal.assert_admin();
        self.storage.state_worker.write(state_worker);
    }
    #[external("public")] #[view]
    fn get_state_worker() -> AztecAddress {
        self.storage.state_worker.read()
    }

    #[inline_never]
    #[contract_library_method]
    unconstrained fn _checked_worker_result(result:[Field]) -> bool {
        // A malformed response cannot bypass the original continuation.
        if result.len()==1 { result[0]==1 } else { false }
    }
}
