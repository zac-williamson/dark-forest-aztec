use ::aztec::macros::aztec;

#[aztec]
contract ArtifactAction {
    use aztec::protocol::traits::FromField;

    use aztec::protocol::traits::Deserialize;

    use aztec::protocol::traits::ToField;

    use ::game_state_backend::GameStateBackend;

    use ::aztec::{
        macros::{functions::{external, initializer, internal, only_self, view}, storage::storage},
        oracle::block_header::get_block_header_at,
        protocol::{address::AztecAddress, hash::poseidon2_hash, traits::{Hash, Serialize}},
    };
    use ::aztec::state_vars::PublicMutable;

    use ::types::args::DFPFindArtifactArgs;
    use ::types::storage::{
        arrival::Arrival,
        artifact::{Artifact, ArtifactLocation, ArtifactType},
        planet::{Planet, PlanetArtifacts, PlanetEvents, PlanetType},
        player::Player,
        world::World,
    };
    use ::types::system_storage_addresses::ArtifactFacetSystemStorageAddresses;

    use ::types::config::{
        artifacts::ArtifactsConfig,
        capture_zones::CaptureZonesConfig,
        default_stats::PlanetDefaultStats,
        game::{GameConfigCore, PlanetLevelThresholds, PlanetTypeWeightsTier},
        snark::SnarkConfig,
        space_junk::SpaceJunkConfig,
        spaceships::SpaceshipsConfig,
        upgrade::Upgrade,
        world::WorldConfig,
    };

    use ::libs::artifact_utils::{
        artifact_from_create_args, contains_gear, create_and_place_spaceship, is_spaceship,
    };

    use ::libs::batch_utils::{
        assert_artifact_and_location_timestamp_freshness,
        assert_owned_artifacts_timestamp_freshness, assert_planet_timestamp_freshness,
        assert_public_timestamp, compute_artifact_and_location_hashes,
        compute_owned_artifact_hashes, compute_planet_hashes, compute_world_hash,
    };
    use ::libs::game_utils::{
        _buff_planet, _debuff_planet, _default_planet, _get_biome, _get_upgrade_for_artifact,
        _put_artifact_on_planet, _random_artifact_type_and_level_bonus, _take_artifact_off_planet,
        artifact_rarity_from_planet_level, is_artifact_on_planet,
    };
    use ::libs::planet::{refresh_planet_v1, refresh_planet_v2};

    use ::circuits::biomebase::biome_proof;

    use ::arrival_storage::ArrivalStorage;
    use ::artifact_location_storage::ArtifactLocationStorage;
    use ::artifact_storage::ArtifactStorage;
    use ::config::Config;
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

    /// Noir port of Solidity `DFArtifactFacet.activateArtifact`
    #[external("private")]
    fn activate_artifact(
        location_id: Field,
        artifact_id: Field,
        wormhole_to: Field,
        timestamp: u64,
        // State inputs (to be validated via hash in public)
        planet: Planet,
        planet_events_state: PlanetEvents,
        arrivals: [Arrival; 20],
        arrival_artifacts: [Artifact; 20],
        arrival_artifact_locations: [ArtifactLocation; 20],
        planet_artifacts_state: PlanetArtifacts,
        artifact: Artifact,
        artifact_location: ArtifactLocation,
        world: World,
        world_config: WorldConfig,
        planet_default_stats: PlanetDefaultStats,
    ) {
        let sender = self.msg_sender();
        assert(!world.paused, "Game is paused");

        assert_planet_timestamp_freshness(
            timestamp,
            planet,
            planet_artifacts_state,
            planet_events_state,
            arrivals,
            arrival_artifacts,
            arrival_artifact_locations,
        );

        assert_artifact_and_location_timestamp_freshness(timestamp, artifact, artifact_location);

        let planet_hashes_result = compute_planet_hashes(
            location_id,
            planet,
            planet_artifacts_state,
            planet_events_state,
            arrivals,
            arrival_artifacts,
            arrival_artifact_locations,
        );

        let artifact_hashes_result =
            compute_artifact_and_location_hashes(artifact_id, artifact, artifact_location);

        let world_hash_result = compute_world_hash(world);

        let planet_hash = planet_hashes_result.1;
        let planet_events_state_hash = planet_hashes_result.3;
        let arrival_ids: [Field; 20] = planet_hashes_result.4;
        let arrival_hashes: [Field; 20] = planet_hashes_result.5;
        let arrival_artifact_ids: [Field; 20] = planet_hashes_result.6;
        let arrival_artifact_hashes: [Field; 20] = planet_hashes_result.7;
        let arrival_artifact_location_hashes: [Field; 20] = planet_hashes_result.8;
        let origin_arrivals_count = planet_hashes_result.9;
        let planet_artifacts_state_hash = planet_hashes_result.2;
        let artifact_hash = artifact_hashes_result.1;
        let artifact_location_hash = artifact_hashes_result.2;
        let world_hash = world_hash_result;
        let world_config_hash = poseidon2_hash(world_config.serialize());
        let planet_default_stats_hash = poseidon2_hash(planet_default_stats.serialize());

        let refresh_planet_result = refresh_planet_v2(
            timestamp,
            location_id,
            planet,
            planet_events_state,
            arrivals,
            arrival_artifacts,
            arrival_artifact_locations,
            planet_artifacts_state,
        );

        let mut new_planet = refresh_planet_result.0;
        let mut new_planet_events_state = refresh_planet_result.1;
        let mut new_planet_artifacts_state = refresh_planet_result.2;
        let mut change_artifact_location_count = refresh_planet_result.3;
        let mut change_artifact_location_ids = refresh_planet_result.4;
        let mut change_artifact_locations = refresh_planet_result.5;

        let mut new_artifact = artifact;
        let mut new_artifact_location = artifact_location;

        // If this artifact arrived via a voyage that completed during refresh,
        // use the refreshed location instead of the stale input.
        for i in 0..20 {
            if i < change_artifact_location_count {
                if change_artifact_location_ids[i] == artifact_id {
                    new_artifact_location = change_artifact_locations[i];
                }
            }
        }

        assert(!new_planet.destroyed, "planet is destroyed");
        assert(
            is_artifact_on_planet(location_id, new_planet_artifacts_state, artifact_id),
            "can't active an artifact on a planet it's not on",
        );
        assert(artifact != Artifact::zero(), "artifact not found");

        let is_spaceship = is_spaceship(new_artifact.artifact_type);

        if is_spaceship {
            // activateSpaceshipArtifact
            let is_crescent = new_artifact.artifact_type == ArtifactType::ShipCrescent;

            if is_crescent {
                assert(
                    new_artifact.activations == 0,
                    "crescent cannot be activated more than once",
                );
                assert(new_planet.planet_type != 1, "cannot turn a silver mine into a silver mine");
                assert(
                    new_planet.owner == AztecAddress::zero(),
                    "can only activate crescent on unowned planets",
                );
                assert(new_planet.planet_level >= 1, "planet level must be more than one");

                new_artifact.last_activated = timestamp;
                new_artifact.last_deactivated = timestamp;

                if new_planet.silver == 0 {
                    new_planet.silver = 1;

                    let default_planet = _default_planet(
                        location_id,
                        new_planet.planet_level,
                        PlanetType::SilverMine,
                        new_planet.space_type,
                        world_config.time_factor_hundredths,
                        planet_default_stats,
                    );

                    new_planet.silver_growth = default_planet.silver_growth;
                }
                new_planet.planet_type = PlanetType::SilverMine;
            }
        } else {
            // activateNonSpaceshipArtifact
            assert(
                new_planet.owner == sender,
                "you must own the planet you are activating an artifact on",
            );

            let artifact_cooldown_hours: [u64; 10] = [24, 0, 0, 0, 0, 4, 4, 24, 24, 24];
            let cooldown_hours = artifact_cooldown_hours[new_artifact.artifact_type as u32];
            assert(
                new_artifact.last_deactivated + cooldown_hours * 60 * 60 < timestamp,
                "this artifact is on a cooldown",
            );

            let mut shoud_deactivate_and_burn = false;

            new_artifact.last_activated = timestamp;

            if new_artifact.artifact_type == ArtifactType::Wormhole {
                assert(wormhole_to != 0, "you must provide a wormholeTo to activate a wormhole");
                assert(
                    new_planet.owner == sender,
                    "you can only create a wormhole to a planet you own",
                );
                assert(!new_planet.destroyed, "planet destroyed");
                new_artifact.wormhole_to = wormhole_to;
            } else if new_artifact.artifact_type == ArtifactType::BloomFilter {
                assert(
                    2 * (new_artifact.rarity as u32) >= (new_planet.planet_level as u32),
                    "artifact is not powerful enough to apply effect to this planet level",
                );
                new_planet.population = new_planet.population_cap;
                new_planet.silver = new_planet.silver_cap;
                shoud_deactivate_and_burn = true;
            } else if new_artifact.artifact_type == ArtifactType::BlackDomain {
                assert(
                    2 * (new_artifact.rarity as u32) >= (new_planet.planet_level as u32),
                    "artifact is not powerful enough to apply effect to this planet level",
                );
                new_planet.destroyed = true;
                shoud_deactivate_and_burn = true;
            }

            if shoud_deactivate_and_burn {
                new_artifact.last_deactivated = timestamp;

                let take_artifact_off_planet_result = _take_artifact_off_planet(
                    artifact_id,
                    artifact_location,
                    artifact,
                    location_id,
                    new_planet_artifacts_state,
                );

                new_artifact_location = take_artifact_off_planet_result.1;
                new_planet_artifacts_state = take_artifact_off_planet_result.3;
            }

            let upgrade = _get_upgrade_for_artifact(new_artifact);
            let buff_planet_result = _buff_planet(location_id, new_planet, upgrade);
            new_planet = buff_planet_result.1;
        }

        new_artifact.activations += 1;

        let mut change_artifact_location_count = refresh_planet_result.3;
        let mut change_artifact_location_ids = refresh_planet_result.4;
        let mut change_artifact_locations = refresh_planet_result.5;

        new_planet.last_updated = timestamp;
        new_planet_events_state.last_updated = timestamp;
        new_planet_artifacts_state.last_updated = timestamp;

        for i in 0..20 {
            if i < change_artifact_location_count {
                change_artifact_locations[i].last_updated = timestamp;
            }
        }

        new_artifact.last_updated = timestamp;
        new_artifact_location.last_updated = timestamp;

        {
            let mut prepared_payload: [Field;291] = [0;291];
            let prepared_part_0 = (location_id).serialize();
            for prepared_i in 0..1 { prepared_payload[0 + prepared_i] = prepared_part_0[prepared_i]; }
            let prepared_part_1 = (artifact_id).serialize();
            for prepared_i in 0..1 { prepared_payload[1 + prepared_i] = prepared_part_1[prepared_i]; }
            let prepared_part_2 = (wormhole_to).serialize();
            for prepared_i in 0..1 { prepared_payload[2 + prepared_i] = prepared_part_2[prepared_i]; }
            let prepared_part_3 = (timestamp).serialize();
            for prepared_i in 0..1 { prepared_payload[3 + prepared_i] = prepared_part_3[prepared_i]; }
            let prepared_part_4 = (planet_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[4 + prepared_i] = prepared_part_4[prepared_i]; }
            let prepared_part_5 = (planet_events_state_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[5 + prepared_i] = prepared_part_5[prepared_i]; }
            let prepared_part_6 = (arrival_ids).serialize();
            for prepared_i in 0..20 { prepared_payload[6 + prepared_i] = prepared_part_6[prepared_i]; }
            let prepared_part_7 = (arrival_hashes).serialize();
            for prepared_i in 0..20 { prepared_payload[26 + prepared_i] = prepared_part_7[prepared_i]; }
            let prepared_part_8 = (arrival_artifact_ids).serialize();
            for prepared_i in 0..20 { prepared_payload[46 + prepared_i] = prepared_part_8[prepared_i]; }
            let prepared_part_9 = (arrival_artifact_hashes).serialize();
            for prepared_i in 0..20 { prepared_payload[66 + prepared_i] = prepared_part_9[prepared_i]; }
            let prepared_part_10 = (arrival_artifact_location_hashes).serialize();
            for prepared_i in 0..20 { prepared_payload[86 + prepared_i] = prepared_part_10[prepared_i]; }
            let prepared_part_11 = (origin_arrivals_count).serialize();
            for prepared_i in 0..1 { prepared_payload[106 + prepared_i] = prepared_part_11[prepared_i]; }
            let prepared_part_12 = (planet_artifacts_state_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[107 + prepared_i] = prepared_part_12[prepared_i]; }
            let prepared_part_13 = (artifact_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[108 + prepared_i] = prepared_part_13[prepared_i]; }
            let prepared_part_14 = (artifact_location_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[109 + prepared_i] = prepared_part_14[prepared_i]; }
            let prepared_part_15 = (world_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[110 + prepared_i] = prepared_part_15[prepared_i]; }
            let prepared_part_16 = (world_config_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[111 + prepared_i] = prepared_part_16[prepared_i]; }
            let prepared_part_17 = (planet_default_stats_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[112 + prepared_i] = prepared_part_17[prepared_i]; }
            let prepared_part_18 = (new_planet).serialize();
            for prepared_i in 0..32 { prepared_payload[113 + prepared_i] = prepared_part_18[prepared_i]; }
            let prepared_part_19 = (new_planet_events_state).serialize();
            for prepared_i in 0..22 { prepared_payload[145 + prepared_i] = prepared_part_19[prepared_i]; }
            let prepared_part_20 = (new_planet_artifacts_state).serialize();
            for prepared_i in 0..22 { prepared_payload[167 + prepared_i] = prepared_part_20[prepared_i]; }
            let prepared_part_21 = (change_artifact_location_count).serialize();
            for prepared_i in 0..1 { prepared_payload[189 + prepared_i] = prepared_part_21[prepared_i]; }
            let prepared_part_22 = (change_artifact_location_ids).serialize();
            for prepared_i in 0..20 { prepared_payload[190 + prepared_i] = prepared_part_22[prepared_i]; }
            let prepared_part_23 = (change_artifact_locations).serialize();
            for prepared_i in 0..60 { prepared_payload[210 + prepared_i] = prepared_part_23[prepared_i]; }
            let prepared_part_24 = (new_artifact).serialize();
            for prepared_i in 0..13 { prepared_payload[270 + prepared_i] = prepared_part_24[prepared_i]; }
            let prepared_part_25 = (new_artifact_location).serialize();
            for prepared_i in 0..3 { prepared_payload[283 + prepared_i] = prepared_part_25[prepared_i]; }
            let prepared_part_26 = (poseidon2_hash((new_planet).serialize())).serialize();
            for prepared_i in 0..1 { prepared_payload[286 + prepared_i] = prepared_part_26[prepared_i]; }
            let prepared_part_27 = (poseidon2_hash((new_planet_events_state).serialize())).serialize();
            for prepared_i in 0..1 { prepared_payload[287 + prepared_i] = prepared_part_27[prepared_i]; }
            let prepared_part_28 = (poseidon2_hash((new_planet_artifacts_state).serialize())).serialize();
            for prepared_i in 0..1 { prepared_payload[288 + prepared_i] = prepared_part_28[prepared_i]; }
            let prepared_part_29 = (poseidon2_hash((new_artifact).serialize())).serialize();
            for prepared_i in 0..1 { prepared_payload[289 + prepared_i] = prepared_part_29[prepared_i]; }
            let prepared_part_30 = (poseidon2_hash((new_artifact_location).serialize())).serialize();
            for prepared_i in 0..1 { prepared_payload[290 + prepared_i] = prepared_part_30[prepared_i]; }
            self.enqueue_self.activate_artifact_public_prepared(::libs::field_buffer::FieldBuffer { words: prepared_payload });
        }
    }

    #[external("public")]
    #[only_self]
    fn activate_artifact_public(
        location_id: Field,
        artifact_id: Field,
        wormhole_to: Field,
        timestamp: u64,
        planet_hash: Field,
        planet_events_state_hash: Field,
        arrival_ids: [Field; 20],
        arrival_hashes: [Field; 20],
        arrival_artifact_ids: [Field; 20],
        arrival_artifact_hashes: [Field; 20],
        arrival_artifact_location_hashes: [Field; 20],
        origin_arrivals_count: u32,
        planet_artifacts_state_hash: Field,
        artifact_hash: Field,
        artifact_location_hash: Field,
        world_hash: Field,
        world_config_hash: Field,
        planet_default_stats_hash: Field,
        new_planet: Planet,
        new_planet_events_state: PlanetEvents,
        new_planet_artifacts_state: PlanetArtifacts,
        change_artifact_location_count: u32,
        change_artifact_location_ids: [Field; 20],
        change_artifact_locations: [ArtifactLocation; 20],
        new_artifact: Artifact,
        new_artifact_location: ArtifactLocation,
    ) {
        self.internal._legacy_activate_artifact_public(location_id, artifact_id, wormhole_to, timestamp, planet_hash, planet_events_state_hash, arrival_ids, arrival_hashes, arrival_artifact_ids, arrival_artifact_hashes, arrival_artifact_location_hashes, origin_arrivals_count, planet_artifacts_state_hash, artifact_hash, artifact_location_hash, world_hash, world_config_hash, planet_default_stats_hash, new_planet, new_planet_events_state, new_planet_artifacts_state, change_artifact_location_count, change_artifact_location_ids, change_artifact_locations, new_artifact, new_artifact_location);
    }

    /// Noir port of Solidity `DFArtifactFacet.deactivateArtifact`.
    #[external("private")]
    fn deactivate_artifact(
        location_id: Field,
        artifact_id: Field,
        timestamp: u64,
        planet: Planet,
        planet_events_state: PlanetEvents,
        arrivals: [Arrival; 20],
        arrival_artifacts: [Artifact; 20],
        arrival_artifact_locations: [ArtifactLocation; 20],
        planet_artifacts_state: PlanetArtifacts,
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
            arrival_artifacts,
            arrival_artifact_locations,
        );

        assert_artifact_and_location_timestamp_freshness(timestamp, artifact, artifact_location);

        let planet_hashes_result = compute_planet_hashes(
            location_id,
            planet,
            planet_artifacts_state,
            planet_events_state,
            arrivals,
            arrival_artifacts,
            arrival_artifact_locations,
        );

        let artifact_hashes_result =
            compute_artifact_and_location_hashes(artifact_id, artifact, artifact_location);

        let world_hash_result = compute_world_hash(world);

        let planet_hash = planet_hashes_result.1;
        let planet_events_state_hash = planet_hashes_result.3;
        let arrival_ids: [Field; 20] = planet_hashes_result.4;
        let arrival_hashes: [Field; 20] = planet_hashes_result.5;
        let arrival_artifact_ids: [Field; 20] = planet_hashes_result.6;
        let arrival_artifact_hashes: [Field; 20] = planet_hashes_result.7;
        let arrival_artifact_location_hashes: [Field; 20] = planet_hashes_result.8;
        let origin_arrivals_count = planet_hashes_result.9;
        let planet_artifacts_state_hash = planet_hashes_result.2;
        let artifact_hash = artifact_hashes_result.1;
        let artifact_location_hash = artifact_hashes_result.2;
        let world_hash = world_hash_result;

        let refresh_planet_result = refresh_planet_v2(
            timestamp,
            location_id,
            planet,
            planet_events_state,
            arrivals,
            arrival_artifacts,
            arrival_artifact_locations,
            planet_artifacts_state,
        );

        let mut new_planet = refresh_planet_result.0;
        let mut new_planet_events_state = refresh_planet_result.1;
        let mut new_planet_artifacts_state = refresh_planet_result.2;
        let mut change_artifact_location_count = refresh_planet_result.3;
        let mut change_artifact_location_ids = refresh_planet_result.4;
        let mut change_artifact_locations = refresh_planet_result.5;

        let mut new_artifact = artifact;
        let mut new_artifact_location = artifact_location;

        // If this artifact arrived via a voyage that completed during refresh,
        // use the refreshed location instead of the stale input.
        for i in 0..20 {
            if i < change_artifact_location_count {
                if change_artifact_location_ids[i] == artifact_id {
                    new_artifact_location = change_artifact_locations[i];
                }
            }
        }

        assert(
            new_planet.owner == sender,
            "you must own the planet you are deactivating an artifact on",
        );
        assert(!new_planet.destroyed, "planet is destroyed");
        assert(
            is_artifact_on_planet(location_id, new_planet_artifacts_state, artifact_id),
            "can't deactivate an artifact on a planet it's not on",
        );
        assert(new_artifact != Artifact::zero(), "this artifact is not on this planet");
        assert(
            new_artifact.last_activated > new_artifact.last_deactivated,
            "artifact not activated",
        );

        new_artifact.last_deactivated = timestamp;
        new_artifact.wormhole_to = 0;

        let should_burn = (new_artifact.artifact_type == ArtifactType::PlanetaryShield)
            | (new_artifact.artifact_type == ArtifactType::PhotoidCannon);

        if should_burn {
            let take_artifact_off_planet_result = _take_artifact_off_planet(
                artifact_id,
                new_artifact_location,
                new_artifact,
                location_id,
                new_planet_artifacts_state,
            );

            new_artifact_location = take_artifact_off_planet_result.1;
            new_planet_artifacts_state = take_artifact_off_planet_result.3;
        }

        let upgrade = _get_upgrade_for_artifact(new_artifact);
        let debuff_planet_result = _debuff_planet(location_id, new_planet, upgrade);
        new_planet = debuff_planet_result.1;

        new_planet.last_updated = timestamp;
        new_planet_events_state.last_updated = timestamp;
        new_planet_artifacts_state.last_updated = timestamp;

        for i in 0..20 {
            if i < change_artifact_location_count {
                change_artifact_locations[i].last_updated = timestamp;
            }
        }

        new_artifact.last_updated = timestamp;
        new_artifact_location.last_updated = timestamp;

        {
            let mut prepared_payload: [Field;288] = [0;288];
            let prepared_part_0 = (location_id).serialize();
            for prepared_i in 0..1 { prepared_payload[0 + prepared_i] = prepared_part_0[prepared_i]; }
            let prepared_part_1 = (artifact_id).serialize();
            for prepared_i in 0..1 { prepared_payload[1 + prepared_i] = prepared_part_1[prepared_i]; }
            let prepared_part_2 = (timestamp).serialize();
            for prepared_i in 0..1 { prepared_payload[2 + prepared_i] = prepared_part_2[prepared_i]; }
            let prepared_part_3 = (planet_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[3 + prepared_i] = prepared_part_3[prepared_i]; }
            let prepared_part_4 = (planet_events_state_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[4 + prepared_i] = prepared_part_4[prepared_i]; }
            let prepared_part_5 = (arrival_ids).serialize();
            for prepared_i in 0..20 { prepared_payload[5 + prepared_i] = prepared_part_5[prepared_i]; }
            let prepared_part_6 = (arrival_hashes).serialize();
            for prepared_i in 0..20 { prepared_payload[25 + prepared_i] = prepared_part_6[prepared_i]; }
            let prepared_part_7 = (arrival_artifact_ids).serialize();
            for prepared_i in 0..20 { prepared_payload[45 + prepared_i] = prepared_part_7[prepared_i]; }
            let prepared_part_8 = (arrival_artifact_hashes).serialize();
            for prepared_i in 0..20 { prepared_payload[65 + prepared_i] = prepared_part_8[prepared_i]; }
            let prepared_part_9 = (arrival_artifact_location_hashes).serialize();
            for prepared_i in 0..20 { prepared_payload[85 + prepared_i] = prepared_part_9[prepared_i]; }
            let prepared_part_10 = (origin_arrivals_count).serialize();
            for prepared_i in 0..1 { prepared_payload[105 + prepared_i] = prepared_part_10[prepared_i]; }
            let prepared_part_11 = (planet_artifacts_state_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[106 + prepared_i] = prepared_part_11[prepared_i]; }
            let prepared_part_12 = (artifact_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[107 + prepared_i] = prepared_part_12[prepared_i]; }
            let prepared_part_13 = (artifact_location_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[108 + prepared_i] = prepared_part_13[prepared_i]; }
            let prepared_part_14 = (world_hash).serialize();
            for prepared_i in 0..1 { prepared_payload[109 + prepared_i] = prepared_part_14[prepared_i]; }
            let prepared_part_15 = (new_planet).serialize();
            for prepared_i in 0..32 { prepared_payload[110 + prepared_i] = prepared_part_15[prepared_i]; }
            let prepared_part_16 = (new_planet_events_state).serialize();
            for prepared_i in 0..22 { prepared_payload[142 + prepared_i] = prepared_part_16[prepared_i]; }
            let prepared_part_17 = (new_planet_artifacts_state).serialize();
            for prepared_i in 0..22 { prepared_payload[164 + prepared_i] = prepared_part_17[prepared_i]; }
            let prepared_part_18 = (change_artifact_location_count).serialize();
            for prepared_i in 0..1 { prepared_payload[186 + prepared_i] = prepared_part_18[prepared_i]; }
            let prepared_part_19 = (change_artifact_location_ids).serialize();
            for prepared_i in 0..20 { prepared_payload[187 + prepared_i] = prepared_part_19[prepared_i]; }
            let prepared_part_20 = (change_artifact_locations).serialize();
            for prepared_i in 0..60 { prepared_payload[207 + prepared_i] = prepared_part_20[prepared_i]; }
            let prepared_part_21 = (new_artifact).serialize();
            for prepared_i in 0..13 { prepared_payload[267 + prepared_i] = prepared_part_21[prepared_i]; }
            let prepared_part_22 = (new_artifact_location).serialize();
            for prepared_i in 0..3 { prepared_payload[280 + prepared_i] = prepared_part_22[prepared_i]; }
            let prepared_part_23 = (poseidon2_hash((new_planet).serialize())).serialize();
            for prepared_i in 0..1 { prepared_payload[283 + prepared_i] = prepared_part_23[prepared_i]; }
            let prepared_part_24 = (poseidon2_hash((new_planet_events_state).serialize())).serialize();
            for prepared_i in 0..1 { prepared_payload[284 + prepared_i] = prepared_part_24[prepared_i]; }
            let prepared_part_25 = (poseidon2_hash((new_planet_artifacts_state).serialize())).serialize();
            for prepared_i in 0..1 { prepared_payload[285 + prepared_i] = prepared_part_25[prepared_i]; }
            let prepared_part_26 = (poseidon2_hash((new_artifact).serialize())).serialize();
            for prepared_i in 0..1 { prepared_payload[286 + prepared_i] = prepared_part_26[prepared_i]; }
            let prepared_part_27 = (poseidon2_hash((new_artifact_location).serialize())).serialize();
            for prepared_i in 0..1 { prepared_payload[287 + prepared_i] = prepared_part_27[prepared_i]; }
            self.enqueue_self.deactivate_artifact_public_prepared(::libs::field_buffer::FieldBuffer { words: prepared_payload });
        }
    }

    #[external("public")]
    #[only_self]
    fn deactivate_artifact_public(
        location_id: Field,
        artifact_id: Field,
        timestamp: u64,
        planet_hash: Field,
        planet_events_state_hash: Field,
        arrival_ids: [Field; 20],
        arrival_hashes: [Field; 20],
        arrival_artifact_ids: [Field; 20],
        arrival_artifact_hashes: [Field; 20],
        arrival_artifact_location_hashes: [Field; 20],
        origin_arrivals_count: u32,
        planet_artifacts_state_hash: Field,
        artifact_hash: Field,
        artifact_location_hash: Field,
        world_hash: Field,
        new_planet: Planet,
        new_planet_events_state: PlanetEvents,
        new_planet_artifacts_state: PlanetArtifacts,
        change_artifact_location_count: u32,
        change_artifact_location_ids: [Field; 20],
        change_artifact_locations: [ArtifactLocation; 20],
        new_artifact: Artifact,
        new_artifact_location: ArtifactLocation,
    ) {
        self.internal._legacy_deactivate_artifact_public(location_id, artifact_id, timestamp, planet_hash, planet_events_state_hash, arrival_ids, arrival_hashes, arrival_artifact_ids, arrival_artifact_hashes, arrival_artifact_location_hashes, origin_arrivals_count, planet_artifacts_state_hash, artifact_hash, artifact_location_hash, world_hash, new_planet, new_planet_events_state, new_planet_artifacts_state, change_artifact_location_count, change_artifact_location_ids, change_artifact_locations, new_artifact, new_artifact_location);
    }


    // Additional hashes are bound by the existing private gameplay proof.
    #[external("public")]
    #[only_self]
    fn activate_artifact_public_prepared(prepared_payload: ::libs::field_buffer::FieldBuffer<291>) {
        let prepared_payload = prepared_payload.words;
        let location_id: Field = prepared_payload[0];
        let artifact_id: Field = prepared_payload[1];
        let wormhole_to: Field = prepared_payload[2];
        let timestamp: u64 = (prepared_payload[3] as u64);
        let planet_hash: Field = prepared_payload[4];
        let planet_events_state_hash: Field = prepared_payload[5];
        let arrival_ids: [Field; 20] = [prepared_payload[6], prepared_payload[7], prepared_payload[8], prepared_payload[9], prepared_payload[10], prepared_payload[11], prepared_payload[12], prepared_payload[13], prepared_payload[14], prepared_payload[15], prepared_payload[16], prepared_payload[17], prepared_payload[18], prepared_payload[19], prepared_payload[20], prepared_payload[21], prepared_payload[22], prepared_payload[23], prepared_payload[24], prepared_payload[25]];
        let arrival_hashes: [Field; 20] = [prepared_payload[26], prepared_payload[27], prepared_payload[28], prepared_payload[29], prepared_payload[30], prepared_payload[31], prepared_payload[32], prepared_payload[33], prepared_payload[34], prepared_payload[35], prepared_payload[36], prepared_payload[37], prepared_payload[38], prepared_payload[39], prepared_payload[40], prepared_payload[41], prepared_payload[42], prepared_payload[43], prepared_payload[44], prepared_payload[45]];
        let arrival_artifact_ids: [Field; 20] = [prepared_payload[46], prepared_payload[47], prepared_payload[48], prepared_payload[49], prepared_payload[50], prepared_payload[51], prepared_payload[52], prepared_payload[53], prepared_payload[54], prepared_payload[55], prepared_payload[56], prepared_payload[57], prepared_payload[58], prepared_payload[59], prepared_payload[60], prepared_payload[61], prepared_payload[62], prepared_payload[63], prepared_payload[64], prepared_payload[65]];
        let arrival_artifact_hashes: [Field; 20] = [prepared_payload[66], prepared_payload[67], prepared_payload[68], prepared_payload[69], prepared_payload[70], prepared_payload[71], prepared_payload[72], prepared_payload[73], prepared_payload[74], prepared_payload[75], prepared_payload[76], prepared_payload[77], prepared_payload[78], prepared_payload[79], prepared_payload[80], prepared_payload[81], prepared_payload[82], prepared_payload[83], prepared_payload[84], prepared_payload[85]];
        let arrival_artifact_location_hashes: [Field; 20] = [prepared_payload[86], prepared_payload[87], prepared_payload[88], prepared_payload[89], prepared_payload[90], prepared_payload[91], prepared_payload[92], prepared_payload[93], prepared_payload[94], prepared_payload[95], prepared_payload[96], prepared_payload[97], prepared_payload[98], prepared_payload[99], prepared_payload[100], prepared_payload[101], prepared_payload[102], prepared_payload[103], prepared_payload[104], prepared_payload[105]];
        let origin_arrivals_count: u32 = (prepared_payload[106] as u32);
        let planet_artifacts_state_hash: Field = prepared_payload[107];
        let artifact_hash: Field = prepared_payload[108];
        let artifact_location_hash: Field = prepared_payload[109];
        let world_hash: Field = prepared_payload[110];
        let world_config_hash: Field = prepared_payload[111];
        let planet_default_stats_hash: Field = prepared_payload[112];
        let new_planet: Planet = ::types::storage::planet::Planet { perlin: (prepared_payload[113] as u8), created_at: (prepared_payload[114] as u64), owner: AztecAddress::from_field(prepared_payload[115]), planet_level: (prepared_payload[116] as u8), planet_type: (prepared_payload[117] as u8), space_type: (prepared_payload[118] as u8), is_home_planet: (prepared_payload[119] == 1), is_initialized: (prepared_payload[120] == 1), destroyed: (prepared_payload[121] == 1), invader: AztecAddress::from_field(prepared_payload[122]), capturer: AztecAddress::from_field(prepared_payload[123]), invade_start_block: (prepared_payload[124] as u32), population_cap: (prepared_payload[125] as u128), population_growth: (prepared_payload[126] as u128), range: (prepared_payload[127] as u128), speed: (prepared_payload[128] as u128), defense: (prepared_payload[129] as u128), silver_cap: (prepared_payload[130] as u128), silver_growth: (prepared_payload[131] as u128), population: (prepared_payload[132] as u128), silver: (prepared_payload[133] as u128), upgrade_state_0: (prepared_payload[134] as u8), upgrade_state_1: (prepared_payload[135] as u8), upgrade_state_2: (prepared_payload[136] as u8), last_updated: (prepared_payload[137] as u64), pausers: (prepared_payload[138] as u128), energy_gro_doublers: (prepared_payload[139] as u128), silver_gro_doublers: (prepared_payload[140] as u128), hat_level: (prepared_payload[141] as u128), space_junk: (prepared_payload[142] as u128), has_tried_finding_artifact: (prepared_payload[143] == 1), prospected_block_number: (prepared_payload[144] as u32) };
        let new_planet_events_state: PlanetEvents = ::types::storage::planet::PlanetEvents { events: [::types::storage::planet::PlanetEventMetadata { id: prepared_payload[145] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[146] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[147] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[148] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[149] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[150] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[151] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[152] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[153] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[154] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[155] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[156] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[157] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[158] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[159] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[160] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[161] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[162] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[163] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[164] }], count: (prepared_payload[165] as u32), last_updated: (prepared_payload[166] as u64) };
        let new_planet_artifacts_state: PlanetArtifacts = ::types::storage::planet::PlanetArtifacts { ids: [prepared_payload[167], prepared_payload[168], prepared_payload[169], prepared_payload[170], prepared_payload[171], prepared_payload[172], prepared_payload[173], prepared_payload[174], prepared_payload[175], prepared_payload[176], prepared_payload[177], prepared_payload[178], prepared_payload[179], prepared_payload[180], prepared_payload[181], prepared_payload[182], prepared_payload[183], prepared_payload[184], prepared_payload[185], prepared_payload[186]], count: (prepared_payload[187] as u32), last_updated: (prepared_payload[188] as u64) };
        let change_artifact_location_count: u32 = (prepared_payload[189] as u32);
        let change_artifact_location_ids: [Field; 20] = [prepared_payload[190], prepared_payload[191], prepared_payload[192], prepared_payload[193], prepared_payload[194], prepared_payload[195], prepared_payload[196], prepared_payload[197], prepared_payload[198], prepared_payload[199], prepared_payload[200], prepared_payload[201], prepared_payload[202], prepared_payload[203], prepared_payload[204], prepared_payload[205], prepared_payload[206], prepared_payload[207], prepared_payload[208], prepared_payload[209]];
        let change_artifact_locations: [ArtifactLocation; 20] = [::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[210], voyage_id: prepared_payload[211], last_updated: (prepared_payload[212] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[213], voyage_id: prepared_payload[214], last_updated: (prepared_payload[215] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[216], voyage_id: prepared_payload[217], last_updated: (prepared_payload[218] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[219], voyage_id: prepared_payload[220], last_updated: (prepared_payload[221] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[222], voyage_id: prepared_payload[223], last_updated: (prepared_payload[224] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[225], voyage_id: prepared_payload[226], last_updated: (prepared_payload[227] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[228], voyage_id: prepared_payload[229], last_updated: (prepared_payload[230] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[231], voyage_id: prepared_payload[232], last_updated: (prepared_payload[233] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[234], voyage_id: prepared_payload[235], last_updated: (prepared_payload[236] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[237], voyage_id: prepared_payload[238], last_updated: (prepared_payload[239] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[240], voyage_id: prepared_payload[241], last_updated: (prepared_payload[242] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[243], voyage_id: prepared_payload[244], last_updated: (prepared_payload[245] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[246], voyage_id: prepared_payload[247], last_updated: (prepared_payload[248] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[249], voyage_id: prepared_payload[250], last_updated: (prepared_payload[251] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[252], voyage_id: prepared_payload[253], last_updated: (prepared_payload[254] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[255], voyage_id: prepared_payload[256], last_updated: (prepared_payload[257] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[258], voyage_id: prepared_payload[259], last_updated: (prepared_payload[260] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[261], voyage_id: prepared_payload[262], last_updated: (prepared_payload[263] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[264], voyage_id: prepared_payload[265], last_updated: (prepared_payload[266] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[267], voyage_id: prepared_payload[268], last_updated: (prepared_payload[269] as u64) }];
        let new_artifact: Artifact = ::types::storage::artifact::Artifact { planet_discovered_on: prepared_payload[270], rarity: (prepared_payload[271] as u8), planet_biome: (prepared_payload[272] as u8), minted_at_timestamp: (prepared_payload[273] as u64), discoverer: AztecAddress::from_field(prepared_payload[274]), artifact_type: (prepared_payload[275] as u8), activations: (prepared_payload[276] as u128), last_activated: (prepared_payload[277] as u64), last_deactivated: (prepared_payload[278] as u64), wormhole_to: prepared_payload[279], owner: AztecAddress::from_field(prepared_payload[280]), controller: AztecAddress::from_field(prepared_payload[281]), last_updated: (prepared_payload[282] as u64) };
        let new_artifact_location: ArtifactLocation = ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[283], voyage_id: prepared_payload[284], last_updated: (prepared_payload[285] as u64) };
        let prepared_new_planet_root: Field = prepared_payload[286];
        let prepared_new_planet_events_state_root: Field = prepared_payload[287];
        let prepared_new_planet_artifacts_state_root: Field = prepared_payload[288];
        let prepared_new_artifact_root: Field = prepared_payload[289];
        let prepared_new_artifact_location_root: Field = prepared_payload[290];
        let state_backend_address = self.storage.state_backend.read();
        let mut settled_by_backend = false;
        if state_backend_address != AztecAddress::zero() {
            let plan_addresses = [
                self.storage.config_storage_address.read(),
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

            let supported = ::state_backend_readonly::public_read::can_settle(state_backend_address, plan_addresses, 1002);
            if supported {
                let mut write_plan = ::libs::state_plan::WritePlan::new();

        let actual_timestamp = self.context.timestamp();
        assert_public_timestamp(timestamp, actual_timestamp);








        let config = Config::at(plan_addresses[0]);

        // Verify planet state hashes
        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[3], location_id, planet_hash),
            "planet hash mismatch",
        );
        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[5], location_id, planet_events_state_hash),
            "planet_events hash mismatch",
        );
        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[6], location_id, planet_artifacts_state_hash),
            "planet_artifacts hash mismatch",
        );

        // Batch verify arrival hashes
        if origin_arrivals_count != 0 {
            assert(
                ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[7], arrival_ids, arrival_hashes, origin_arrivals_count),
                "arrivals hash mismatch",
            );
            if ::libs::batch_utils::has_nonzero_ids(arrival_artifact_ids, origin_arrivals_count) {
                assert(
                    ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[8], arrival_artifact_ids, arrival_artifact_hashes, origin_arrivals_count),
                    "arrival artifacts hash mismatch",
                );

                assert(
                    ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[9], arrival_artifact_ids, arrival_artifact_location_hashes, origin_arrivals_count),
                    "arrival artifact locations hash mismatch",
                );
            }
        }

        // Verify the artifact being activated
        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[8], artifact_id, artifact_hash),
            "artifact hash mismatch",
        );
        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[9], artifact_id, artifact_location_hash),
            "artifact_location hash mismatch",
        );

        // Verify world hash
        assert(::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[1], 0, world_hash), "world hash mismatch");

        // Verify config hashes (world_config used for time_factor, planet_default_stats for Crescent activation)
        assert(
            self.view(config.verify_world_config_hash(world_config_hash)),
            "world config hash mismatch",
        );
        assert(
            self.view(config.verify_planet_default_stats_hash(
                new_planet.planet_level,
                planet_default_stats_hash,
            )),
            "planet default stats hash mismatch",
        );

        // Write refreshed planet state
        write_plan.set(3, location_id, prepared_new_planet_root, true, new_planet.serialize());
        write_plan.set(5, location_id, prepared_new_planet_events_state_root, true, new_planet_events_state.serialize());
        write_plan.set(6, location_id, prepared_new_planet_artifacts_state_root, true, new_planet_artifacts_state.serialize());

        // Batch write changed artifact locations from refresh
        {
            let batch_start=write_plan.start_batch(9, change_artifact_location_count, 20);
            let bounded_count = if (change_artifact_location_count) <= 20 { change_artifact_location_count } else { 20 };
            for plan_i in 0..bounded_count { if change_artifact_location_ids[plan_i] != 0 {
                write_plan.append_batch_item(batch_start, change_artifact_location_ids[plan_i], change_artifact_locations[plan_i].serialize());
            } }
        };

        // Write the activated artifact and its location
        write_plan.set(8, artifact_id, prepared_new_artifact_root, true, new_artifact.serialize());
        write_plan.set(9, artifact_id, prepared_new_artifact_location_root, true, new_artifact_location.serialize());

                _commit_plan_for_system(self.context, state_backend_address, plan_addresses, 1002, write_plan);
                settled_by_backend = true;
            }
        }
        if !settled_by_backend {
            self.internal._legacy_activate_artifact_public(location_id, artifact_id, wormhole_to, timestamp, planet_hash, planet_events_state_hash, arrival_ids, arrival_hashes, arrival_artifact_ids, arrival_artifact_hashes, arrival_artifact_location_hashes, origin_arrivals_count, planet_artifacts_state_hash, artifact_hash, artifact_location_hash, world_hash, world_config_hash, planet_default_stats_hash, new_planet, new_planet_events_state, new_planet_artifacts_state, change_artifact_location_count, change_artifact_location_ids, change_artifact_locations, new_artifact, new_artifact_location);
        }
}

    // Additional hashes are bound by the existing private gameplay proof.
    #[external("public")]
    #[only_self]
    fn deactivate_artifact_public_prepared(prepared_payload: ::libs::field_buffer::FieldBuffer<288>) {
        let prepared_payload = prepared_payload.words;
        let location_id: Field = prepared_payload[0];
        let artifact_id: Field = prepared_payload[1];
        let timestamp: u64 = (prepared_payload[2] as u64);
        let planet_hash: Field = prepared_payload[3];
        let planet_events_state_hash: Field = prepared_payload[4];
        let arrival_ids: [Field; 20] = [prepared_payload[5], prepared_payload[6], prepared_payload[7], prepared_payload[8], prepared_payload[9], prepared_payload[10], prepared_payload[11], prepared_payload[12], prepared_payload[13], prepared_payload[14], prepared_payload[15], prepared_payload[16], prepared_payload[17], prepared_payload[18], prepared_payload[19], prepared_payload[20], prepared_payload[21], prepared_payload[22], prepared_payload[23], prepared_payload[24]];
        let arrival_hashes: [Field; 20] = [prepared_payload[25], prepared_payload[26], prepared_payload[27], prepared_payload[28], prepared_payload[29], prepared_payload[30], prepared_payload[31], prepared_payload[32], prepared_payload[33], prepared_payload[34], prepared_payload[35], prepared_payload[36], prepared_payload[37], prepared_payload[38], prepared_payload[39], prepared_payload[40], prepared_payload[41], prepared_payload[42], prepared_payload[43], prepared_payload[44]];
        let arrival_artifact_ids: [Field; 20] = [prepared_payload[45], prepared_payload[46], prepared_payload[47], prepared_payload[48], prepared_payload[49], prepared_payload[50], prepared_payload[51], prepared_payload[52], prepared_payload[53], prepared_payload[54], prepared_payload[55], prepared_payload[56], prepared_payload[57], prepared_payload[58], prepared_payload[59], prepared_payload[60], prepared_payload[61], prepared_payload[62], prepared_payload[63], prepared_payload[64]];
        let arrival_artifact_hashes: [Field; 20] = [prepared_payload[65], prepared_payload[66], prepared_payload[67], prepared_payload[68], prepared_payload[69], prepared_payload[70], prepared_payload[71], prepared_payload[72], prepared_payload[73], prepared_payload[74], prepared_payload[75], prepared_payload[76], prepared_payload[77], prepared_payload[78], prepared_payload[79], prepared_payload[80], prepared_payload[81], prepared_payload[82], prepared_payload[83], prepared_payload[84]];
        let arrival_artifact_location_hashes: [Field; 20] = [prepared_payload[85], prepared_payload[86], prepared_payload[87], prepared_payload[88], prepared_payload[89], prepared_payload[90], prepared_payload[91], prepared_payload[92], prepared_payload[93], prepared_payload[94], prepared_payload[95], prepared_payload[96], prepared_payload[97], prepared_payload[98], prepared_payload[99], prepared_payload[100], prepared_payload[101], prepared_payload[102], prepared_payload[103], prepared_payload[104]];
        let origin_arrivals_count: u32 = (prepared_payload[105] as u32);
        let planet_artifacts_state_hash: Field = prepared_payload[106];
        let artifact_hash: Field = prepared_payload[107];
        let artifact_location_hash: Field = prepared_payload[108];
        let world_hash: Field = prepared_payload[109];
        let new_planet: Planet = ::types::storage::planet::Planet { perlin: (prepared_payload[110] as u8), created_at: (prepared_payload[111] as u64), owner: AztecAddress::from_field(prepared_payload[112]), planet_level: (prepared_payload[113] as u8), planet_type: (prepared_payload[114] as u8), space_type: (prepared_payload[115] as u8), is_home_planet: (prepared_payload[116] == 1), is_initialized: (prepared_payload[117] == 1), destroyed: (prepared_payload[118] == 1), invader: AztecAddress::from_field(prepared_payload[119]), capturer: AztecAddress::from_field(prepared_payload[120]), invade_start_block: (prepared_payload[121] as u32), population_cap: (prepared_payload[122] as u128), population_growth: (prepared_payload[123] as u128), range: (prepared_payload[124] as u128), speed: (prepared_payload[125] as u128), defense: (prepared_payload[126] as u128), silver_cap: (prepared_payload[127] as u128), silver_growth: (prepared_payload[128] as u128), population: (prepared_payload[129] as u128), silver: (prepared_payload[130] as u128), upgrade_state_0: (prepared_payload[131] as u8), upgrade_state_1: (prepared_payload[132] as u8), upgrade_state_2: (prepared_payload[133] as u8), last_updated: (prepared_payload[134] as u64), pausers: (prepared_payload[135] as u128), energy_gro_doublers: (prepared_payload[136] as u128), silver_gro_doublers: (prepared_payload[137] as u128), hat_level: (prepared_payload[138] as u128), space_junk: (prepared_payload[139] as u128), has_tried_finding_artifact: (prepared_payload[140] == 1), prospected_block_number: (prepared_payload[141] as u32) };
        let new_planet_events_state: PlanetEvents = ::types::storage::planet::PlanetEvents { events: [::types::storage::planet::PlanetEventMetadata { id: prepared_payload[142] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[143] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[144] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[145] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[146] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[147] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[148] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[149] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[150] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[151] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[152] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[153] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[154] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[155] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[156] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[157] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[158] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[159] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[160] }, ::types::storage::planet::PlanetEventMetadata { id: prepared_payload[161] }], count: (prepared_payload[162] as u32), last_updated: (prepared_payload[163] as u64) };
        let new_planet_artifacts_state: PlanetArtifacts = ::types::storage::planet::PlanetArtifacts { ids: [prepared_payload[164], prepared_payload[165], prepared_payload[166], prepared_payload[167], prepared_payload[168], prepared_payload[169], prepared_payload[170], prepared_payload[171], prepared_payload[172], prepared_payload[173], prepared_payload[174], prepared_payload[175], prepared_payload[176], prepared_payload[177], prepared_payload[178], prepared_payload[179], prepared_payload[180], prepared_payload[181], prepared_payload[182], prepared_payload[183]], count: (prepared_payload[184] as u32), last_updated: (prepared_payload[185] as u64) };
        let change_artifact_location_count: u32 = (prepared_payload[186] as u32);
        let change_artifact_location_ids: [Field; 20] = [prepared_payload[187], prepared_payload[188], prepared_payload[189], prepared_payload[190], prepared_payload[191], prepared_payload[192], prepared_payload[193], prepared_payload[194], prepared_payload[195], prepared_payload[196], prepared_payload[197], prepared_payload[198], prepared_payload[199], prepared_payload[200], prepared_payload[201], prepared_payload[202], prepared_payload[203], prepared_payload[204], prepared_payload[205], prepared_payload[206]];
        let change_artifact_locations: [ArtifactLocation; 20] = [::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[207], voyage_id: prepared_payload[208], last_updated: (prepared_payload[209] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[210], voyage_id: prepared_payload[211], last_updated: (prepared_payload[212] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[213], voyage_id: prepared_payload[214], last_updated: (prepared_payload[215] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[216], voyage_id: prepared_payload[217], last_updated: (prepared_payload[218] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[219], voyage_id: prepared_payload[220], last_updated: (prepared_payload[221] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[222], voyage_id: prepared_payload[223], last_updated: (prepared_payload[224] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[225], voyage_id: prepared_payload[226], last_updated: (prepared_payload[227] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[228], voyage_id: prepared_payload[229], last_updated: (prepared_payload[230] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[231], voyage_id: prepared_payload[232], last_updated: (prepared_payload[233] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[234], voyage_id: prepared_payload[235], last_updated: (prepared_payload[236] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[237], voyage_id: prepared_payload[238], last_updated: (prepared_payload[239] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[240], voyage_id: prepared_payload[241], last_updated: (prepared_payload[242] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[243], voyage_id: prepared_payload[244], last_updated: (prepared_payload[245] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[246], voyage_id: prepared_payload[247], last_updated: (prepared_payload[248] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[249], voyage_id: prepared_payload[250], last_updated: (prepared_payload[251] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[252], voyage_id: prepared_payload[253], last_updated: (prepared_payload[254] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[255], voyage_id: prepared_payload[256], last_updated: (prepared_payload[257] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[258], voyage_id: prepared_payload[259], last_updated: (prepared_payload[260] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[261], voyage_id: prepared_payload[262], last_updated: (prepared_payload[263] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[264], voyage_id: prepared_payload[265], last_updated: (prepared_payload[266] as u64) }];
        let new_artifact: Artifact = ::types::storage::artifact::Artifact { planet_discovered_on: prepared_payload[267], rarity: (prepared_payload[268] as u8), planet_biome: (prepared_payload[269] as u8), minted_at_timestamp: (prepared_payload[270] as u64), discoverer: AztecAddress::from_field(prepared_payload[271]), artifact_type: (prepared_payload[272] as u8), activations: (prepared_payload[273] as u128), last_activated: (prepared_payload[274] as u64), last_deactivated: (prepared_payload[275] as u64), wormhole_to: prepared_payload[276], owner: AztecAddress::from_field(prepared_payload[277]), controller: AztecAddress::from_field(prepared_payload[278]), last_updated: (prepared_payload[279] as u64) };
        let new_artifact_location: ArtifactLocation = ::types::storage::artifact::ArtifactLocation { planet_id: prepared_payload[280], voyage_id: prepared_payload[281], last_updated: (prepared_payload[282] as u64) };
        let prepared_new_planet_root: Field = prepared_payload[283];
        let prepared_new_planet_events_state_root: Field = prepared_payload[284];
        let prepared_new_planet_artifacts_state_root: Field = prepared_payload[285];
        let prepared_new_artifact_root: Field = prepared_payload[286];
        let prepared_new_artifact_location_root: Field = prepared_payload[287];
        let state_backend_address = self.storage.state_backend.read();
        let mut settled_by_backend = false;
        if state_backend_address != AztecAddress::zero() {
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

            let supported = ::state_backend_readonly::public_read::can_settle(state_backend_address, plan_addresses, 1002);
            if supported {
                let mut write_plan = ::libs::state_plan::WritePlan::new();

        let actual_timestamp = self.context.timestamp();
        assert_public_timestamp(timestamp, actual_timestamp);









        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[3], location_id, planet_hash),
            "planet hash mismatch",
        );
        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[5], location_id, planet_events_state_hash),
            "planet_events hash mismatch",
        );
        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[6], location_id, planet_artifacts_state_hash),
            "planet_artifacts hash mismatch",
        );

        if origin_arrivals_count != 0 {
            assert(
                ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[7], arrival_ids, arrival_hashes, origin_arrivals_count),
                "arrivals hash mismatch",
            );
            if ::libs::batch_utils::has_nonzero_ids(arrival_artifact_ids, origin_arrivals_count) {
                assert(
                    ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[8], arrival_artifact_ids, arrival_artifact_hashes, origin_arrivals_count),
                    "arrival artifacts hash mismatch",
                );

                assert(
                    ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[9], arrival_artifact_ids, arrival_artifact_location_hashes, origin_arrivals_count),
                    "arrival artifact locations hash mismatch",
                );
            }
        }

        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[8], artifact_id, artifact_hash),
            "artifact hash mismatch",
        );
        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[9], artifact_id, artifact_location_hash),
            "artifact_location hash mismatch",
        );

        assert(::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[1], 0, world_hash), "world hash mismatch");

        write_plan.set(3, location_id, prepared_new_planet_root, true, new_planet.serialize());
        write_plan.set(5, location_id, prepared_new_planet_events_state_root, true, new_planet_events_state.serialize());
        write_plan.set(6, location_id, prepared_new_planet_artifacts_state_root, true, new_planet_artifacts_state.serialize());

        {
            let batch_start=write_plan.start_batch(9, change_artifact_location_count, 20);
            let bounded_count = if (change_artifact_location_count) <= 20 { change_artifact_location_count } else { 20 };
            for plan_i in 0..bounded_count { if change_artifact_location_ids[plan_i] != 0 {
                write_plan.append_batch_item(batch_start, change_artifact_location_ids[plan_i], change_artifact_locations[plan_i].serialize());
            } }
        };

        write_plan.set(8, artifact_id, prepared_new_artifact_root, true, new_artifact.serialize());
        write_plan.set(9, artifact_id, prepared_new_artifact_location_root, true, new_artifact_location.serialize());

                _commit_plan_for_system(self.context, state_backend_address, plan_addresses, 1002, write_plan);
                settled_by_backend = true;
            }
        }
        if !settled_by_backend {
            self.internal._legacy_deactivate_artifact_public(location_id, artifact_id, timestamp, planet_hash, planet_events_state_hash, arrival_ids, arrival_hashes, arrival_artifact_ids, arrival_artifact_hashes, arrival_artifact_location_hashes, origin_arrivals_count, planet_artifacts_state_hash, artifact_hash, artifact_location_hash, world_hash, new_planet, new_planet_events_state, new_planet_artifacts_state, change_artifact_location_count, change_artifact_location_ids, change_artifact_locations, new_artifact, new_artifact_location);
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


    #[internal("public")]

    fn _legacy_activate_artifact_public(
        location_id: Field,
        artifact_id: Field,
        wormhole_to: Field,
        timestamp: u64,
        planet_hash: Field,
        planet_events_state_hash: Field,
        arrival_ids: [Field; 20],
        arrival_hashes: [Field; 20],
        arrival_artifact_ids: [Field; 20],
        arrival_artifact_hashes: [Field; 20],
        arrival_artifact_location_hashes: [Field; 20],
        origin_arrivals_count: u32,
        planet_artifacts_state_hash: Field,
        artifact_hash: Field,
        artifact_location_hash: Field,
        world_hash: Field,
        world_config_hash: Field,
        planet_default_stats_hash: Field,
        new_planet: Planet,
        new_planet_events_state: PlanetEvents,
        new_planet_artifacts_state: PlanetArtifacts,
        change_artifact_location_count: u32,
        change_artifact_location_ids: [Field; 20],
        change_artifact_locations: [ArtifactLocation; 20],
        new_artifact: Artifact,
        new_artifact_location: ArtifactLocation,
    ) {
        let actual_timestamp = self.context.timestamp();
        assert_public_timestamp(timestamp, actual_timestamp);

        let planet_storage = PlanetStorage::at(self.storage.planet_storage_address.read());
        let planet_artifacts_storage =
            PlanetArtifactsStorage::at(self.storage.planet_artifacts_storage_address.read());
        let planet_events_storage =
            PlanetEventsStorage::at(self.storage.planet_events_storage_address.read());
        let artifact_location_storage =
            ArtifactLocationStorage::at(self.storage.artifact_location_storage_address.read());
        let arrival_storage = ArrivalStorage::at(self.storage.arrivals_storage_address.read());
        let artifact_storage = ArtifactStorage::at(self.storage.artifact_storage_address.read());
        let world_storage = WorldStorage::at(self.storage.world_storage_address.read());
        let config = Config::at(self.storage.config_storage_address.read());

        // Verify planet state hashes
        assert(
            self.view(planet_storage.verify_hash(location_id, planet_hash)),
            "planet hash mismatch",
        );
        assert(
            self.view(planet_events_storage.verify_hash(location_id, planet_events_state_hash)),
            "planet_events hash mismatch",
        );
        assert(
            self.view(planet_artifacts_storage.verify_hash(location_id, planet_artifacts_state_hash)),
            "planet_artifacts hash mismatch",
        );

        // Batch verify arrival hashes
        assert(
            self.view(arrival_storage.verify_hashes_batch(
                arrival_ids,
                arrival_hashes,
                origin_arrivals_count,
            )),
            "arrivals hash mismatch",
        );
        assert(
            self.view(artifact_storage.verify_hashes_batch(
                arrival_artifact_ids,
                arrival_artifact_hashes,
                origin_arrivals_count,
            )),
            "arrival artifacts hash mismatch",
        );
        assert(
            self.view(artifact_location_storage.verify_hashes_batch(
                arrival_artifact_ids,
                arrival_artifact_location_hashes,
                origin_arrivals_count,
            )),
            "arrival artifact locations hash mismatch",
        );

        // Verify the artifact being activated
        assert(
            self.view(artifact_storage.verify_hash(artifact_id, artifact_hash)),
            "artifact hash mismatch",
        );
        assert(
            self.view(artifact_location_storage.verify_hash(artifact_id, artifact_location_hash)),
            "artifact_location hash mismatch",
        );

        // Verify world hash
        assert(self.view(world_storage.verify_hash(0, world_hash)), "world hash mismatch");

        // Verify config hashes (world_config used for time_factor, planet_default_stats for Crescent activation)
        assert(
            self.view(config.verify_world_config_hash(world_config_hash)),
            "world config hash mismatch",
        );
        assert(
            self.view(config.verify_planet_default_stats_hash(
                new_planet.planet_level,
                planet_default_stats_hash,
            )),
            "planet default stats hash mismatch",
        );

        // Write refreshed planet state
        self.call(planet_storage.set(location_id, new_planet));
        self.call(planet_events_storage.set(location_id, new_planet_events_state));
        self.call(planet_artifacts_storage.set(location_id, new_planet_artifacts_state));

        // Batch write changed artifact locations from refresh
        self.call(artifact_location_storage.set_arrival_locations_max20(
            change_artifact_location_ids,
            change_artifact_locations,
            change_artifact_location_count,
        ));

        // Write the activated artifact and its location
        self.call(artifact_storage.set(artifact_id, new_artifact));
        self.call(artifact_location_storage.set(artifact_id, new_artifact_location));
    }



    #[internal("public")]

    fn _legacy_deactivate_artifact_public(
        location_id: Field,
        artifact_id: Field,
        timestamp: u64,
        planet_hash: Field,
        planet_events_state_hash: Field,
        arrival_ids: [Field; 20],
        arrival_hashes: [Field; 20],
        arrival_artifact_ids: [Field; 20],
        arrival_artifact_hashes: [Field; 20],
        arrival_artifact_location_hashes: [Field; 20],
        origin_arrivals_count: u32,
        planet_artifacts_state_hash: Field,
        artifact_hash: Field,
        artifact_location_hash: Field,
        world_hash: Field,
        new_planet: Planet,
        new_planet_events_state: PlanetEvents,
        new_planet_artifacts_state: PlanetArtifacts,
        change_artifact_location_count: u32,
        change_artifact_location_ids: [Field; 20],
        change_artifact_locations: [ArtifactLocation; 20],
        new_artifact: Artifact,
        new_artifact_location: ArtifactLocation,
    ) {
        let actual_timestamp = self.context.timestamp();
        assert_public_timestamp(timestamp, actual_timestamp);

        let planet_storage = PlanetStorage::at(self.storage.planet_storage_address.read());
        let planet_artifacts_storage =
            PlanetArtifactsStorage::at(self.storage.planet_artifacts_storage_address.read());
        let planet_events_storage =
            PlanetEventsStorage::at(self.storage.planet_events_storage_address.read());
        let artifact_location_storage =
            ArtifactLocationStorage::at(self.storage.artifact_location_storage_address.read());
        let arrival_storage = ArrivalStorage::at(self.storage.arrivals_storage_address.read());
        let artifact_storage = ArtifactStorage::at(self.storage.artifact_storage_address.read());
        let world_storage = WorldStorage::at(self.storage.world_storage_address.read());

        assert(
            self.view(planet_storage.verify_hash(location_id, planet_hash)),
            "planet hash mismatch",
        );
        assert(
            self.view(planet_events_storage.verify_hash(location_id, planet_events_state_hash)),
            "planet_events hash mismatch",
        );
        assert(
            self.view(planet_artifacts_storage.verify_hash(location_id, planet_artifacts_state_hash)),
            "planet_artifacts hash mismatch",
        );

        assert(
            self.view(arrival_storage.verify_hashes_batch(
                arrival_ids,
                arrival_hashes,
                origin_arrivals_count,
            )),
            "arrivals hash mismatch",
        );
        assert(
            self.view(artifact_storage.verify_hashes_batch(
                arrival_artifact_ids,
                arrival_artifact_hashes,
                origin_arrivals_count,
            )),
            "arrival artifacts hash mismatch",
        );
        assert(
            self.view(artifact_location_storage.verify_hashes_batch(
                arrival_artifact_ids,
                arrival_artifact_location_hashes,
                origin_arrivals_count,
            )),
            "arrival artifact locations hash mismatch",
        );

        assert(
            self.view(artifact_storage.verify_hash(artifact_id, artifact_hash)),
            "artifact hash mismatch",
        );
        assert(
            self.view(artifact_location_storage.verify_hash(artifact_id, artifact_location_hash)),
            "artifact_location hash mismatch",
        );

        assert(self.view(world_storage.verify_hash(0, world_hash)), "world hash mismatch");

        self.call(planet_storage.set(location_id, new_planet));
        self.call(planet_events_storage.set(location_id, new_planet_events_state));
        self.call(planet_artifacts_storage.set(location_id, new_planet_artifacts_state));

        self.call(artifact_location_storage.set_arrival_locations_max20(
            change_artifact_location_ids,
            change_artifact_locations,
            change_artifact_location_count,
        ));

        self.call(artifact_storage.set(artifact_id, new_artifact));
        self.call(artifact_location_storage.set(artifact_id, new_artifact_location));
    }
    #[inline_never]
    #[contract_library_method]
    unconstrained fn _commit_plan_for_system(
        context: aztec::context::PublicContext,
        backend_address: AztecAddress,
        addresses: [AztecAddress;10],
        required_mask: u16,
        plan: ::libs::state_plan::WritePlan,
    ) {
        let mut self = __aztec_nr_internals__create_public_self_from_context(context);
        if plan.length <= 128 {
            let selector = comptime { aztec::protocol::abis::function_selector::FunctionSelector::from_signature("commit_plan_small(([Field;141]))") };
            let calldata=[selector.to_field(), self.msg_sender().to_field(), addresses[0].to_field(), addresses[1].to_field(), addresses[2].to_field(), addresses[3].to_field(), addresses[4].to_field(), addresses[5].to_field(), addresses[6].to_field(), addresses[7].to_field(), addresses[8].to_field(), addresses[9].to_field(), required_mask as Field, plan.words[0], plan.words[1], plan.words[2], plan.words[3], plan.words[4], plan.words[5], plan.words[6], plan.words[7], plan.words[8], plan.words[9], plan.words[10], plan.words[11], plan.words[12], plan.words[13], plan.words[14], plan.words[15], plan.words[16], plan.words[17], plan.words[18], plan.words[19], plan.words[20], plan.words[21], plan.words[22], plan.words[23], plan.words[24], plan.words[25], plan.words[26], plan.words[27], plan.words[28], plan.words[29], plan.words[30], plan.words[31], plan.words[32], plan.words[33], plan.words[34], plan.words[35], plan.words[36], plan.words[37], plan.words[38], plan.words[39], plan.words[40], plan.words[41], plan.words[42], plan.words[43], plan.words[44], plan.words[45], plan.words[46], plan.words[47], plan.words[48], plan.words[49], plan.words[50], plan.words[51], plan.words[52], plan.words[53], plan.words[54], plan.words[55], plan.words[56], plan.words[57], plan.words[58], plan.words[59], plan.words[60], plan.words[61], plan.words[62], plan.words[63], plan.words[64], plan.words[65], plan.words[66], plan.words[67], plan.words[68], plan.words[69], plan.words[70], plan.words[71], plan.words[72], plan.words[73], plan.words[74], plan.words[75], plan.words[76], plan.words[77], plan.words[78], plan.words[79], plan.words[80], plan.words[81], plan.words[82], plan.words[83], plan.words[84], plan.words[85], plan.words[86], plan.words[87], plan.words[88], plan.words[89], plan.words[90], plan.words[91], plan.words[92], plan.words[93], plan.words[94], plan.words[95], plan.words[96], plan.words[97], plan.words[98], plan.words[99], plan.words[100], plan.words[101], plan.words[102], plan.words[103], plan.words[104], plan.words[105], plan.words[106], plan.words[107], plan.words[108], plan.words[109], plan.words[110], plan.words[111], plan.words[112], plan.words[113], plan.words[114], plan.words[115], plan.words[116], plan.words[117], plan.words[118], plan.words[119], plan.words[120], plan.words[121], plan.words[122], plan.words[123], plan.words[124], plan.words[125], plan.words[126], plan.words[127], plan.length as Field];

            let result=::libs::public_call::call(backend_address,calldata);
            assert(result.len()==0, "Unexpected settlement result");
        } else {
            let selector = comptime { aztec::protocol::abis::function_selector::FunctionSelector::from_signature("commit_plan(([Field;397]))") };
            let calldata=[selector.to_field(), self.msg_sender().to_field(), addresses[0].to_field(), addresses[1].to_field(), addresses[2].to_field(), addresses[3].to_field(), addresses[4].to_field(), addresses[5].to_field(), addresses[6].to_field(), addresses[7].to_field(), addresses[8].to_field(), addresses[9].to_field(), required_mask as Field, plan.words[0], plan.words[1], plan.words[2], plan.words[3], plan.words[4], plan.words[5], plan.words[6], plan.words[7], plan.words[8], plan.words[9], plan.words[10], plan.words[11], plan.words[12], plan.words[13], plan.words[14], plan.words[15], plan.words[16], plan.words[17], plan.words[18], plan.words[19], plan.words[20], plan.words[21], plan.words[22], plan.words[23], plan.words[24], plan.words[25], plan.words[26], plan.words[27], plan.words[28], plan.words[29], plan.words[30], plan.words[31], plan.words[32], plan.words[33], plan.words[34], plan.words[35], plan.words[36], plan.words[37], plan.words[38], plan.words[39], plan.words[40], plan.words[41], plan.words[42], plan.words[43], plan.words[44], plan.words[45], plan.words[46], plan.words[47], plan.words[48], plan.words[49], plan.words[50], plan.words[51], plan.words[52], plan.words[53], plan.words[54], plan.words[55], plan.words[56], plan.words[57], plan.words[58], plan.words[59], plan.words[60], plan.words[61], plan.words[62], plan.words[63], plan.words[64], plan.words[65], plan.words[66], plan.words[67], plan.words[68], plan.words[69], plan.words[70], plan.words[71], plan.words[72], plan.words[73], plan.words[74], plan.words[75], plan.words[76], plan.words[77], plan.words[78], plan.words[79], plan.words[80], plan.words[81], plan.words[82], plan.words[83], plan.words[84], plan.words[85], plan.words[86], plan.words[87], plan.words[88], plan.words[89], plan.words[90], plan.words[91], plan.words[92], plan.words[93], plan.words[94], plan.words[95], plan.words[96], plan.words[97], plan.words[98], plan.words[99], plan.words[100], plan.words[101], plan.words[102], plan.words[103], plan.words[104], plan.words[105], plan.words[106], plan.words[107], plan.words[108], plan.words[109], plan.words[110], plan.words[111], plan.words[112], plan.words[113], plan.words[114], plan.words[115], plan.words[116], plan.words[117], plan.words[118], plan.words[119], plan.words[120], plan.words[121], plan.words[122], plan.words[123], plan.words[124], plan.words[125], plan.words[126], plan.words[127], plan.words[128], plan.words[129], plan.words[130], plan.words[131], plan.words[132], plan.words[133], plan.words[134], plan.words[135], plan.words[136], plan.words[137], plan.words[138], plan.words[139], plan.words[140], plan.words[141], plan.words[142], plan.words[143], plan.words[144], plan.words[145], plan.words[146], plan.words[147], plan.words[148], plan.words[149], plan.words[150], plan.words[151], plan.words[152], plan.words[153], plan.words[154], plan.words[155], plan.words[156], plan.words[157], plan.words[158], plan.words[159], plan.words[160], plan.words[161], plan.words[162], plan.words[163], plan.words[164], plan.words[165], plan.words[166], plan.words[167], plan.words[168], plan.words[169], plan.words[170], plan.words[171], plan.words[172], plan.words[173], plan.words[174], plan.words[175], plan.words[176], plan.words[177], plan.words[178], plan.words[179], plan.words[180], plan.words[181], plan.words[182], plan.words[183], plan.words[184], plan.words[185], plan.words[186], plan.words[187], plan.words[188], plan.words[189], plan.words[190], plan.words[191], plan.words[192], plan.words[193], plan.words[194], plan.words[195], plan.words[196], plan.words[197], plan.words[198], plan.words[199], plan.words[200], plan.words[201], plan.words[202], plan.words[203], plan.words[204], plan.words[205], plan.words[206], plan.words[207], plan.words[208], plan.words[209], plan.words[210], plan.words[211], plan.words[212], plan.words[213], plan.words[214], plan.words[215], plan.words[216], plan.words[217], plan.words[218], plan.words[219], plan.words[220], plan.words[221], plan.words[222], plan.words[223], plan.words[224], plan.words[225], plan.words[226], plan.words[227], plan.words[228], plan.words[229], plan.words[230], plan.words[231], plan.words[232], plan.words[233], plan.words[234], plan.words[235], plan.words[236], plan.words[237], plan.words[238], plan.words[239], plan.words[240], plan.words[241], plan.words[242], plan.words[243], plan.words[244], plan.words[245], plan.words[246], plan.words[247], plan.words[248], plan.words[249], plan.words[250], plan.words[251], plan.words[252], plan.words[253], plan.words[254], plan.words[255], plan.words[256], plan.words[257], plan.words[258], plan.words[259], plan.words[260], plan.words[261], plan.words[262], plan.words[263], plan.words[264], plan.words[265], plan.words[266], plan.words[267], plan.words[268], plan.words[269], plan.words[270], plan.words[271], plan.words[272], plan.words[273], plan.words[274], plan.words[275], plan.words[276], plan.words[277], plan.words[278], plan.words[279], plan.words[280], plan.words[281], plan.words[282], plan.words[283], plan.words[284], plan.words[285], plan.words[286], plan.words[287], plan.words[288], plan.words[289], plan.words[290], plan.words[291], plan.words[292], plan.words[293], plan.words[294], plan.words[295], plan.words[296], plan.words[297], plan.words[298], plan.words[299], plan.words[300], plan.words[301], plan.words[302], plan.words[303], plan.words[304], plan.words[305], plan.words[306], plan.words[307], plan.words[308], plan.words[309], plan.words[310], plan.words[311], plan.words[312], plan.words[313], plan.words[314], plan.words[315], plan.words[316], plan.words[317], plan.words[318], plan.words[319], plan.words[320], plan.words[321], plan.words[322], plan.words[323], plan.words[324], plan.words[325], plan.words[326], plan.words[327], plan.words[328], plan.words[329], plan.words[330], plan.words[331], plan.words[332], plan.words[333], plan.words[334], plan.words[335], plan.words[336], plan.words[337], plan.words[338], plan.words[339], plan.words[340], plan.words[341], plan.words[342], plan.words[343], plan.words[344], plan.words[345], plan.words[346], plan.words[347], plan.words[348], plan.words[349], plan.words[350], plan.words[351], plan.words[352], plan.words[353], plan.words[354], plan.words[355], plan.words[356], plan.words[357], plan.words[358], plan.words[359], plan.words[360], plan.words[361], plan.words[362], plan.words[363], plan.words[364], plan.words[365], plan.words[366], plan.words[367], plan.words[368], plan.words[369], plan.words[370], plan.words[371], plan.words[372], plan.words[373], plan.words[374], plan.words[375], plan.words[376], plan.words[377], plan.words[378], plan.words[379], plan.words[380], plan.words[381], plan.words[382], plan.words[383], plan.length as Field];

            let result=::libs::public_call::call(backend_address,calldata);
            assert(result.len()==0, "Unexpected settlement result");
        }
    }

}
