use ::aztec::macros::aztec;

#[aztec]
contract Move {
    use ::game_state_backend::GameStateBackend;
    use ::libs::field_buffer::FieldBuffer;

    use ::aztec::{
        macros::{
            events::event,
            functions::{external, initializer, internal, only_self, view},
            storage::storage,
        },
        protocol::{address::AztecAddress, hash::poseidon2_hash, traits::{Serialize, FromField, ToField}},
    };
    use ::aztec::state_vars::{Map, PublicMutable};

    use ::types::args::{
        AdminCreatePlanetArgs, DFPCreateArrivalArgs, DFPInitPlanetArgs, DFPMoveArgs,
    };

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

    use ::types::storage::{
        arrival::{Arrival, ArrivalType},
        artifact::{Artifact, ArtifactLocation, ArtifactRarity, ArtifactType},
        planet::{
            Planet, PlanetArtifacts, PlanetEventMetadata, PlanetEvents, PlanetEventType,
            PlanetRevealedCoords, PlanetType, SpaceType, UpgradeBranch,
        },
        player::Player,
        world::World,
    };
    use ::types::system_storage_addresses::MoveSystemStorageAddresses;

    use ::libs::game_utils::{
        _buff_planet, _debuff_planet, _get_upgrade_for_artifact, _take_artifact_off_planet,
        is_activated, is_artifact_on_planet, revert_if_bad_snark_perlin_flags,
    };

    use ::libs::batch_utils::{
        assert_artifact_timestamp_freshness, assert_planet_timestamp_freshness,
        assert_public_timestamp, compute_artifact_and_location_hashes, compute_artifact_hash,
        compute_config_hashes, compute_planet_hashes, compute_world_hash,
    };
    use ::libs::planet::{
        apply_spaceship_depart, check_player_init, initialize_planet_with_defaults,
        refresh_planet_v1, refresh_planet_v2,
    };

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
        // Global
        config_storage_address: PublicMutable<AztecAddress, Context>,
        world_storage_address: PublicMutable<AztecAddress, Context>,
        // Actor
        player_storage_address: PublicMutable<AztecAddress, Context>,
        // Planet and its sub-entities
        planet_storage_address: PublicMutable<AztecAddress, Context>,
        planet_events_storage_address: PublicMutable<AztecAddress, Context>,
        planet_artifacts_storage_address: PublicMutable<AztecAddress, Context>,
        // Voyages between planets
        arrivals_storage_address: PublicMutable<AztecAddress, Context>,
        // Artifacts and their locations
        artifact_storage_address: PublicMutable<AztecAddress, Context>,
        artifact_location_storage_address: PublicMutable<AztecAddress, Context>,
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
    fn set_config_storage_address(config_storage_address: AztecAddress) {
        self.internal.assert_admin();
        self.storage.config_storage_address.write(config_storage_address);
    }

    #[external("public")]
    fn set_world_storage_address(world_storage_address: AztecAddress) {
        self.internal.assert_admin();
        self.storage.world_storage_address.write(world_storage_address);
    }

    #[external("public")]
    fn set_player_storage_address(player_storage_address: AztecAddress) {
        self.internal.assert_admin();
        self.storage.player_storage_address.write(player_storage_address);
    }

    #[external("public")]
    fn set_planet_storage_address(planet_storage_address: AztecAddress) {
        self.internal.assert_admin();
        self.storage.planet_storage_address.write(planet_storage_address);
    }

    #[external("public")]
    fn set_planet_events_storage_address(planet_events_storage_address: AztecAddress) {
        self.internal.assert_admin();
        self.storage.planet_events_storage_address.write(planet_events_storage_address);
    }

    #[external("public")]
    fn set_planet_artifacts_storage_address(planet_artifacts_storage_address: AztecAddress) {
        self.internal.assert_admin();
        self.storage.planet_artifacts_storage_address.write(planet_artifacts_storage_address);
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

    /// Batch set all storage addresses in a single transaction.
    #[external("public")]
    fn set_all_storage_addresses(
        config_addr: AztecAddress,
        world_addr: AztecAddress,
        player_addr: AztecAddress,
        planet_addr: AztecAddress,
        planet_events_addr: AztecAddress,
        planet_artifacts_addr: AztecAddress,
        arrivals_addr: AztecAddress,
        artifact_addr: AztecAddress,
        artifact_location_addr: AztecAddress,
    ) {
        self.internal.assert_admin();
        self.storage.config_storage_address.write(config_addr);
        self.storage.world_storage_address.write(world_addr);
        self.storage.player_storage_address.write(player_addr);
        self.storage.planet_storage_address.write(planet_addr);
        self.storage.planet_events_storage_address.write(planet_events_addr);
        self.storage.planet_artifacts_storage_address.write(planet_artifacts_addr);
        self.storage.arrivals_storage_address.write(arrivals_addr);
        self.storage.artifact_storage_address.write(artifact_addr);
        self.storage.artifact_location_storage_address.write(artifact_location_addr);
    }

    // ================== UTILITY (UNCONSTRAINED) ==================

    #[external("utility")]
    unconstrained fn get_all_storage_addresses_unconstrained() -> MoveSystemStorageAddresses {
        MoveSystemStorageAddresses {
            config_storage_address: self.storage.config_storage_address.read(),
            world_storage_address: self.storage.world_storage_address.read(),
            player_storage_address: self.storage.player_storage_address.read(),
            planet_storage_address: self.storage.planet_storage_address.read(),
            planet_events_storage_address: self.storage.planet_events_storage_address.read(),
            planet_artifacts_storage_address: self.storage.planet_artifacts_storage_address.read(),
            arrivals_storage_address: self.storage.arrivals_storage_address.read(),
            artifact_storage_address: self.storage.artifact_storage_address.read(),
            artifact_location_storage_address: self.storage.artifact_location_storage_address.read(),
        }
    }

    #[external("private")]
    fn move(
        // --- Location & target properties ---
        source_loc: Field,
        target_loc: Field,
        target_perlin: u8,
        target_level: u8,
        max_dist: u128,
        // --- Private coordinates (ZK proof inputs) ---
        x1: Field,
        y1: Field,
        x2: Field,
        y2: Field,
        // --- Move action parameters ---
        pop_moved: u128,
        silver_moved: u128,
        moved_artifact_id: Field,
        source_activated_artifact_id: Field,
        target_activated_artifact_id: Field,
        is_abandoning: bool,
        timestamp: u64,
        // --- Config inputs (validated via hash in public) ---
        snark_config: SnarkConfig,
        planet_default_stats: PlanetDefaultStats,
        world_config: WorldConfig,
        game_config_core: GameConfigCore,
        planet_level_thresholds: PlanetLevelThresholds,
        space_junk_config: SpaceJunkConfig,
        planet_type_weights_tier_0: PlanetTypeWeightsTier,
        planet_type_weights_tier_1: PlanetTypeWeightsTier,
        planet_type_weights_tier_2: PlanetTypeWeightsTier,
        planet_type_weights_tier_3: PlanetTypeWeightsTier,
        artifacts_config: ArtifactsConfig,
        // --- Source planet state (validated via hash in public) ---
        source_planet: Planet,
        source_planet_artifacts_state: PlanetArtifacts,
        source_planet_events_state: PlanetEvents,
        source_arrivals: [Arrival; 20],
        source_arrival_artifacts: [Artifact; 20],
        source_arrival_artifact_locations: [ArtifactLocation; 20],
        // --- Target planet state (validated via hash in public) ---
        target_planet: Planet,
        target_planet_artifacts_state: PlanetArtifacts,
        target_planet_events_state: PlanetEvents,
        target_arrivals: [Arrival; 20],
        target_arrival_artifacts: [Artifact; 20],
        target_arrival_artifact_locations: [ArtifactLocation; 20],
        // --- World & artifact state (validated via hash in public) ---
        world: World,
        moved_artifact: Artifact,
        source_activated_artifact: Artifact,
        target_activated_artifact: Artifact,
    ) {
        if !snark_config.disable_zk_checks {
            // Verify move proof: coords (x1,y1)->(x2,y2) produce source_loc, target_loc, target_perlin
            let r = world.radius as Field;
            let dist_max = max_dist as Field;
            let planet_hash_key = snark_config.planethash_key as Field;
            let space_type_key = snark_config.spacetype_key as Field;
            let scale = snark_config.perlin_length_scale;
            let (expected_source, expected_target, expected_perlin) = circuits::move::move_proof(
                r,
                dist_max,
                planet_hash_key,
                space_type_key,
                scale,
                snark_config.perlin_mirror_x,
                snark_config.perlin_mirror_y,
                x1,
                y1,
                x2,
                y2,
            );
            assert(expected_source == source_loc, "Move proof: source location hash mismatch");
            assert(expected_target == target_loc, "Move proof: target location hash mismatch");
            assert(expected_perlin == target_perlin, "Move proof: target perlin mismatch");
        }

        let sender = self.msg_sender();
        assert(!world.paused, "Game is paused");

        // Verify timestamp freshness for source planet
        assert_planet_timestamp_freshness(
            timestamp,
            source_planet,
            source_planet_artifacts_state,
            source_planet_events_state,
            source_arrivals,
            source_arrival_artifacts,
            source_arrival_artifact_locations,
        );

        // Verify timestamp freshness for target planet
        assert_planet_timestamp_freshness(
            timestamp,
            target_planet,
            target_planet_artifacts_state,
            target_planet_events_state,
            target_arrivals,
            target_arrival_artifacts,
            target_arrival_artifact_locations,
        );

        if moved_artifact_id != 0 {
            assert_artifact_timestamp_freshness(timestamp, moved_artifact);
        }

        if source_activated_artifact_id != 0 {
            assert_artifact_timestamp_freshness(timestamp, source_activated_artifact);
        }

        if target_activated_artifact_id != 0 {
            assert_artifact_timestamp_freshness(timestamp, target_activated_artifact);
        }

        // Compute config hashes for public verification
        let (planet_default_stats_hash, config_hashes) = compute_config_hashes(
            snark_config,
            planet_default_stats,
            world_config,
            game_config_core,
            planet_level_thresholds,
            space_junk_config,
            planet_type_weights_tier_0,
            planet_type_weights_tier_1,
            planet_type_weights_tier_2,
            planet_type_weights_tier_3,
        );
        let artifacts_config_hash = poseidon2_hash(artifacts_config.serialize());

        // Compute state hashes for public verification
        let (_, source_planet_hash, source_planet_artifacts_state_hash, source_planet_events_state_hash, source_arrival_ids, source_arrival_hashes, source_arrival_artifact_ids, source_arrival_artifact_hashes, source_arrival_artifact_location_hashes, original_source_arrivals_count) = compute_planet_hashes(
            source_loc,
            source_planet,
            source_planet_artifacts_state,
            source_planet_events_state,
            source_arrivals,
            source_arrival_artifacts,
            source_arrival_artifact_locations,
        );

        let (_, target_planet_hash, target_planet_artifacts_state_hash, target_planet_events_state_hash, target_arrival_ids, target_arrival_hashes, target_arrival_artifact_ids, target_arrival_artifact_hashes, target_arrival_artifact_location_hashes, original_target_arrivals_count) = compute_planet_hashes(
            target_loc,
            target_planet,
            target_planet_artifacts_state,
            target_planet_events_state,
            target_arrivals,
            target_arrival_artifacts,
            target_arrival_artifact_locations,
        );

        let world_hash = compute_world_hash(world);

        let moved_artifact_hash = compute_artifact_hash(moved_artifact_id, moved_artifact);
        let source_activated_artifact_hash =
            compute_artifact_hash(source_activated_artifact_id, source_activated_artifact);
        let target_activated_artifact_hash =
            compute_artifact_hash(target_activated_artifact_id, target_activated_artifact);

        let source_planet_is_initialized = source_planet != Planet::zero();
        assert(source_planet_is_initialized, "Source planet is not initialized");

        let new_source_planet_state = refresh_planet_v1(
            timestamp,
            source_loc,
            source_planet,
            source_planet_events_state,
            source_arrivals,
            source_arrival_artifacts,
            source_arrival_artifact_locations,
            source_planet_artifacts_state,
        );

        let mut new_source_planet = new_source_planet_state.0;
        let mut new_source_planet_events_state = new_source_planet_state.1;
        let mut new_source_planet_artifacts_state = new_source_planet_state.2;
        let mut new_source_arrival_artifact_locations = new_source_planet_state.3;

        let mut new_source_activated_artifact = source_activated_artifact;
        let mut new_source_activated_artifact_location = ArtifactLocation::zero();

        let target_planet_is_initialized = target_planet != Planet::zero();

        let mut new_target_planet = target_planet;
        let mut new_target_planet_events_state = target_planet_events_state;
        let mut new_target_planet_artifacts_state = target_planet_artifacts_state;
        let mut new_target_arrival_artifact_locations = target_arrival_artifact_locations;

        if target_planet_is_initialized {
            let new_target_states = refresh_planet_v1(
                timestamp,
                target_loc,
                target_planet,
                target_planet_events_state,
                target_arrivals,
                target_arrival_artifacts,
                target_arrival_artifact_locations,
                target_planet_artifacts_state,
            );

            new_target_planet = new_target_states.0;
            new_target_planet_events_state = new_target_states.1;
            new_target_planet_artifacts_state = new_target_states.2;
            new_target_arrival_artifact_locations = new_target_states.3;

            // checkPlanetDOS - Rate limiting check for planet arrivals
            let mut arrivals_from_owner: u8 = 0;
            let mut arrivals_from_others: u8 = 0;

            // After refresh_planet, event indices may have been rearranged via
            // swap-and-pop. Look up each remaining event's arrival by matching
            // event id against the arrivals array instead of using index directly.
            for i in 0..20 {
                if i < new_target_planet_events_state.count {
                    let event_id: Field = new_target_planet_events_state.events[i].id;
                    let mut arrival_player_address = AztecAddress::zero();

                    let mut found = false;
                    for j in 0..20 {
                        if (target_arrivals[j].id == event_id) & (found == false) {
                            arrival_player_address = target_arrivals[j].player;
                            found = true;
                        }
                    }
                    assert(found, "Arrival not found for event");

                    if arrival_player_address == new_target_planet.owner {
                        arrivals_from_owner += 1;
                    } else {
                        arrivals_from_others += 1;
                    }
                }
            }

            // Apply rate limits based on sender
            if sender == new_target_planet.owner {
                assert(arrivals_from_owner < 10, "Planet is rate-limited");
            } else {
                assert(arrivals_from_others < 10, "Planet is rate-limited");
            }

            // Apply total arrivals limit
            assert((arrivals_from_owner + arrivals_from_others) < 20, "Planet is rate-limited");
        } else {
            new_target_planet = initialize_planet_with_defaults(
                target_loc,
                target_perlin,
                false,
                timestamp,
                sender,
                target_level,
                planet_default_stats,
                world_config,
                planet_level_thresholds,
                game_config_core,
                space_junk_config,
                planet_type_weights_tier_0,
                planet_type_weights_tier_1,
                planet_type_weights_tier_2,
                planet_type_weights_tier_3,
            );
        }

        // Verify moved artifact is on the (refreshed) source planet
        if moved_artifact_id != 0 {
            assert(
                is_artifact_on_planet(
                    source_loc,
                    new_source_planet_artifacts_state,
                    moved_artifact_id,
                ),
                "Moved artifact is not on source planet",
            );
        }

        // Verify activated artifact is on the (refreshed) source planet
        if source_activated_artifact_id != 0 {
            assert(
                is_artifact_on_planet(
                    source_loc,
                    new_source_planet_artifacts_state,
                    source_activated_artifact_id,
                ),
                "Activated artifact is not on source planet",
            );
        }

        // Verify target activated artifact is on the (refreshed) target planet
        if target_activated_artifact_id != 0 {
            assert(
                is_artifact_on_planet(
                    target_loc,
                    new_target_planet_artifacts_state,
                    target_activated_artifact_id,
                ),
                "Target activated artifact is not on target planet",
            );
        }

        // Target planet artifact count limit - fixes Solidity bug where only
        // on-planet artifacts were checked, ignoring in-transit ones carried by
        // pending arrivals. Uses pre-refresh state so we can iterate arrivals
        // directly without the 20x20 event-to-arrival lookup.
        if moved_artifact_id != 0 {
            let mut carried_artifacts: u32 = 0;
            for i in 0..20 {
                if target_arrivals[i].carried_artifact_id != 0 {
                    carried_artifacts += 1;
                }
            }
            assert(
                target_planet_artifacts_state.count + carried_artifacts + 1 < 6,
                "Too many artifacts on target planet",
            );
        }

        let mut args: DFPMoveArgs = DFPMoveArgs {
            old_loc: source_loc,
            new_loc: target_loc,
            max_dist,
            pop_moved,
            silver_moved,
            moved_artifact_id,
            is_abandoning,
            sender,
        };

        // Check if this is a spaceship move
        let is_spaceship_move = if moved_artifact_id != 0 {
            let artifact_type = moved_artifact.artifact_type;

            (artifact_type == ArtifactType::ShipMothership)
                | (artifact_type == ArtifactType::ShipCrescent)
                | (artifact_type == ArtifactType::ShipWhale)
                | (artifact_type == ArtifactType::ShipGear)
                | (artifact_type == ArtifactType::ShipTitan)
        } else {
            false
        };

        if is_spaceship_move {
            args.sender = AztecAddress::zero();
        }

        // Check move validity
        if is_spaceship_move {
            assert(pop_moved == 0, "ship moves must move 0 energy");
            assert(silver_moved == 0, "ship moves must move 0 silver");
            assert(moved_artifact.controller == sender, "you can only move your own ships");
        } else {
            assert(
                !new_target_planet.destroyed & !new_source_planet.destroyed,
                "planet is destroyed",
            );
            assert(
                new_source_planet.owner == sender,
                "Only owner account can perform that operation on planet.",
            );

            // note: this is fine because energy and silver now grow linearly
            assert(
                new_source_planet.population >= pop_moved,
                "Tried to move more population that what exists",
            );

            assert(
                new_source_planet.silver >= silver_moved,
                "Tried to move more silver than what exists",
            );
        }

        let mut effectiveDistTimesHundred: u128 = args.max_dist * 100;
        let mut arrival_type = ArrivalType::Normal;
        let mut temporary_upgrade = Upgrade::zero();

        // _checkWormhole: if an active Wormhole artifact on either planet
        // points to the other, shorten effective distance based on rarity.
        let source_has_wormhole = if source_activated_artifact_id != 0 {
            is_activated(source_activated_artifact)
                & (source_activated_artifact.artifact_type == ArtifactType::Wormhole)
                & (source_activated_artifact.wormhole_to == target_loc)
        } else {
            false
        };

        let target_has_wormhole = if target_activated_artifact_id != 0 {
            is_activated(target_activated_artifact)
                & (target_activated_artifact.artifact_type == ArtifactType::Wormhole)
                & (target_activated_artifact.wormhole_to == source_loc)
        } else {
            false
        };

        if source_has_wormhole | target_has_wormhole {
            let wormhole_rarity = if source_has_wormhole {
                source_activated_artifact.rarity
            } else {
                target_activated_artifact.rarity
            };
            let speed_boosts: [u128; 6] = [1, 2, 4, 8, 16, 32];
            effectiveDistTimesHundred /= speed_boosts[wormhole_rarity as u32];
            arrival_type = ArrivalType::Wormhole;
        }

        // _checkPhotoid: if the source planet has an active PhotoidCannon whose
        // activation delay has elapsed, apply a temporary speed/range boost and
        // deactivate it. Only applies to non-spaceship moves.
        if !is_spaceship_move & (source_activated_artifact_id != 0) {
            let is_photoid = is_activated(source_activated_artifact)
                & (source_activated_artifact.artifact_type == ArtifactType::PhotoidCannon)
                & (
                    timestamp - source_activated_artifact.last_activated
                        >= artifacts_config.photoid_activation_delay
                );

            if is_photoid {
                let r = source_activated_artifact.rarity as u32;
                let range_boosts: [u128; 6] = [100, 200, 200, 200, 200, 200];
                let speed_boosts: [u128; 6] = [100, 500, 1000, 1500, 2000, 2500];
                temporary_upgrade = Upgrade {
                    pop_cap_multiplier: 100,
                    pop_gro_multiplier: 100,
                    range_multiplier: range_boosts[r],
                    speed_multiplier: speed_boosts[r],
                    def_multiplier: 100,
                };
                arrival_type = ArrivalType::Photoid;

                // Deactivate the photoid artifact
                new_source_activated_artifact.last_deactivated = timestamp;
                new_source_activated_artifact.last_updated = timestamp;

                // Burn: remove from source planet artifacts (swap-and-pop)
                let art_count = new_source_planet_artifacts_state.count;
                let mut burn_index: u32 = 0;
                let mut burn_found = false;
                for i in 0..20 {
                    if (i < art_count) & !burn_found {
                        if new_source_planet_artifacts_state.ids[i] == source_activated_artifact_id {
                            burn_index = i;
                            burn_found = true;
                        }
                    }
                }
                assert(burn_found, "Photoid artifact not found on source planet");
                let burn_last = art_count - 1;
                new_source_planet_artifacts_state.ids[burn_index] =
                    new_source_planet_artifacts_state.ids[burn_last];
                new_source_planet_artifacts_state.ids[burn_last] = 0;
                new_source_planet_artifacts_state.count -= 1;

                // Clear artifact location (no longer on any planet)
                new_source_activated_artifact_location = ArtifactLocation {
                    planet_id: 0 as Field,
                    voyage_id: 0 as Field,
                    last_updated: timestamp,
                };

                // Reverse the permanent artifact buff (defense reduction) that was
                // applied when the PhotoidCannon was activated on this planet.
                let permanent_upgrade = _get_upgrade_for_artifact(new_source_activated_artifact);
                let debuff_result =
                    _debuff_planet(args.old_loc, new_source_planet, permanent_upgrade);
                new_source_planet = debuff_result.1;
            }
        }

        // Remove spaceship effects from origin planet when a ship departs
        if is_spaceship_move {
            new_source_planet =
                apply_spaceship_depart(moved_artifact, new_source_planet, timestamp);
        }

        let pop_moved = args.pop_moved;
        let silver_moved = args.silver_moved;
        let remaining_origin_planet_population = new_source_planet.population - pop_moved;

        // todo: how to handle SPACE_JUNK_ENABLE = true

        let buff_planet_result = _buff_planet(args.old_loc, new_source_planet, temporary_upgrade);
        new_source_planet = buff_planet_result.1;

        let mut travel_time: u64 = (effectiveDistTimesHundred / new_source_planet.speed) as u64;

        if travel_time == 0 {
            travel_time = 1;
        }

        // All checks pass. Execute move
        // Push the new event into the planetEvents array for target location
        assert(new_target_planet_events_state.count < 20, "Too many events on target planet");

        new_target_planet_events_state.events[new_target_planet_events_state.count] = PlanetEventMetadata {
            id: 0, // placeholder; allocated atomically in move_public
            // event_type: PlanetEventType::Arrival,
            // time_trigger: timestamp + travel_time,
            // time_created: timestamp,
        };
        new_target_planet_events_state.count += 1;

        // _createArrival - Enter the arrival data for event id

        // Piecewise linear decay: max reachable distance D_max depends on energy percentage.
        // Constraint points: (0%,0L) (25%,0.5L) (50%,0.75L) (100%,L) where L = range * 432/100.
        // Within D_max, arriving pop decays linearly: popMoved * (D_max - dist) / D_max.
        let pop_arriving = if is_spaceship_move {
            0
        } else {
            let percent = pop_moved * 100 / new_source_planet.population_cap;

            let d_max_percent = if percent <= 25 {
                percent * 2
            } else if percent <= 50 {
                25 + percent
            } else {
                (100 + percent) / 2
            };

            let d_factor = new_source_planet.range * 432 * d_max_percent;
            let dist_scaled = effectiveDistTimesHundred * 100;

            if (dist_scaled >= d_factor) | (d_factor == 0) {
                0
            } else {
                pop_moved * (d_factor - dist_scaled) / d_factor
            }
        };

        // Spaceship moves must be 0 energy moves
        assert(pop_arriving > 0 | is_spaceship_move, "Not enough forces to make move");
        assert(!is_spaceship_move | (pop_moved == 0), "spaceship moves must be 0 energy moves");

        // Create the new arrival (id is a placeholder; allocated in move_public)
        let new_arrival = Arrival {
            id: 0,
            player: sender,
            from_planet: source_loc,
            to_planet: target_loc,
            pop_arriving,
            silver_moved,
            departure_time: timestamp,
            arrival_time: timestamp + travel_time,
            arrival_type,
            carried_artifact_id: moved_artifact_id,
            distance: args.max_dist,
        };

        let mut new_moved_artifact_location = ArtifactLocation::zero();

        // Handle artifact movement
        if moved_artifact_id != 0 {
            // Take artifact off the source planet
            let take_artifact_result = _take_artifact_off_planet(
                moved_artifact_id,
                new_moved_artifact_location,
                moved_artifact,
                source_loc,
                new_source_planet_artifacts_state,
            );

            // Unpack the results
            new_moved_artifact_location = take_artifact_result.1;
            new_source_planet_artifacts_state = take_artifact_result.3;

            // voyage_id is patched in move_public after event ID allocation
            new_moved_artifact_location.last_updated = timestamp;
        }

        let debuff_planet_result =
            _debuff_planet(args.old_loc, new_source_planet, temporary_upgrade);
        new_source_planet = debuff_planet_result.1;

        new_source_planet.silver -= silver_moved;
        new_source_planet.population = remaining_origin_planet_population;

        // Set last_updated on all new state tables before passing to public
        new_source_planet.last_updated = timestamp;
        new_source_planet_events_state.last_updated = timestamp;
        new_source_planet_artifacts_state.last_updated = timestamp;
        for i in 0..20 {
            if i < original_source_arrivals_count & (source_arrivals[i].carried_artifact_id != 0) {
                new_source_arrival_artifact_locations[i].last_updated = timestamp;
            }
        }

        new_target_planet.last_updated = timestamp;
        new_target_planet_events_state.last_updated = timestamp;
        new_target_planet_artifacts_state.last_updated = timestamp;
        for i in 0..20 {
            if i < original_target_arrivals_count & (target_arrivals[i].carried_artifact_id != 0) {
                new_target_arrival_artifact_locations[i].last_updated = timestamp;
            }
        }

        new_source_activated_artifact.last_updated = timestamp;
        new_source_activated_artifact_location.last_updated = timestamp;

        // Pass hashes and computed results to public for verification and storage
        if (original_source_arrivals_count == 0) & (original_target_arrivals_count == 0) {
            let mut prepared_payload: [Field; 337] = [0; 337];
            let prepared_argument_0: [Field; 1] = (source_loc).serialize();
            for prepared_index_0 in 0..1 { prepared_payload[0 + prepared_index_0] = prepared_argument_0[prepared_index_0]; }
            let prepared_argument_1: [Field; 1] = (target_loc).serialize();
            for prepared_index_1 in 0..1 { prepared_payload[1 + prepared_index_1] = prepared_argument_1[prepared_index_1]; }
            let prepared_argument_2: [Field; 1] = (target_level).serialize();
            for prepared_index_2 in 0..1 { prepared_payload[2 + prepared_index_2] = prepared_argument_2[prepared_index_2]; }
            let prepared_argument_3: [Field; 1] = (moved_artifact_id).serialize();
            for prepared_index_3 in 0..1 { prepared_payload[3 + prepared_index_3] = prepared_argument_3[prepared_index_3]; }
            let prepared_argument_4: [Field; 1] = (source_activated_artifact_id).serialize();
            for prepared_index_4 in 0..1 { prepared_payload[4 + prepared_index_4] = prepared_argument_4[prepared_index_4]; }
            let prepared_argument_5: [Field; 1] = (target_activated_artifact_id).serialize();
            for prepared_index_5 in 0..1 { prepared_payload[5 + prepared_index_5] = prepared_argument_5[prepared_index_5]; }
            let prepared_argument_6: [Field; 1] = (timestamp).serialize();
            for prepared_index_6 in 0..1 { prepared_payload[6 + prepared_index_6] = prepared_argument_6[prepared_index_6]; }
            let prepared_argument_7: [Field; 9] = (config_hashes).serialize();
            for prepared_index_7 in 0..9 { prepared_payload[7 + prepared_index_7] = prepared_argument_7[prepared_index_7]; }
            let prepared_argument_8: [Field; 1] = (artifacts_config_hash).serialize();
            for prepared_index_8 in 0..1 { prepared_payload[16 + prepared_index_8] = prepared_argument_8[prepared_index_8]; }
            let prepared_argument_9: [Field; 1] = (planet_default_stats_hash).serialize();
            for prepared_index_9 in 0..1 { prepared_payload[17 + prepared_index_9] = prepared_argument_9[prepared_index_9]; }
            let prepared_argument_10: [Field; 1] = (source_planet_hash).serialize();
            for prepared_index_10 in 0..1 { prepared_payload[18 + prepared_index_10] = prepared_argument_10[prepared_index_10]; }
            let prepared_argument_11: [Field; 1] = (source_planet_artifacts_state_hash).serialize();
            for prepared_index_11 in 0..1 { prepared_payload[19 + prepared_index_11] = prepared_argument_11[prepared_index_11]; }
            let prepared_argument_12: [Field; 1] = (source_planet_events_state_hash).serialize();
            for prepared_index_12 in 0..1 { prepared_payload[20 + prepared_index_12] = prepared_argument_12[prepared_index_12]; }
            let prepared_argument_13: [Field; 1] = (target_planet_hash).serialize();
            for prepared_index_13 in 0..1 { prepared_payload[21 + prepared_index_13] = prepared_argument_13[prepared_index_13]; }
            let prepared_argument_14: [Field; 1] = (target_planet_artifacts_state_hash).serialize();
            for prepared_index_14 in 0..1 { prepared_payload[22 + prepared_index_14] = prepared_argument_14[prepared_index_14]; }
            let prepared_argument_15: [Field; 1] = (target_planet_events_state_hash).serialize();
            for prepared_index_15 in 0..1 { prepared_payload[23 + prepared_index_15] = prepared_argument_15[prepared_index_15]; }
            let prepared_argument_16: [Field; 1] = (world_hash).serialize();
            for prepared_index_16 in 0..1 { prepared_payload[24 + prepared_index_16] = prepared_argument_16[prepared_index_16]; }
            let prepared_argument_17: [Field; 1] = (moved_artifact_hash).serialize();
            for prepared_index_17 in 0..1 { prepared_payload[25 + prepared_index_17] = prepared_argument_17[prepared_index_17]; }
            let prepared_argument_18: [Field; 1] = (source_activated_artifact_hash).serialize();
            for prepared_index_18 in 0..1 { prepared_payload[26 + prepared_index_18] = prepared_argument_18[prepared_index_18]; }
            let prepared_argument_19: [Field; 1] = (target_activated_artifact_hash).serialize();
            for prepared_index_19 in 0..1 { prepared_payload[27 + prepared_index_19] = prepared_argument_19[prepared_index_19]; }
            let prepared_argument_20: [Field; 32] = (new_source_planet).serialize();
            for prepared_index_20 in 0..32 { prepared_payload[28 + prepared_index_20] = prepared_argument_20[prepared_index_20]; }
            let prepared_argument_21: [Field; 22] = (new_source_planet_artifacts_state).serialize();
            for prepared_index_21 in 0..22 { prepared_payload[60 + prepared_index_21] = prepared_argument_21[prepared_index_21]; }
            let prepared_argument_22: [Field; 22] = (new_source_planet_events_state).serialize();
            for prepared_index_22 in 0..22 { prepared_payload[82 + prepared_index_22] = prepared_argument_22[prepared_index_22]; }
            let prepared_argument_23: [Field; 32] = (new_target_planet).serialize();
            for prepared_index_23 in 0..32 { prepared_payload[104 + prepared_index_23] = prepared_argument_23[prepared_index_23]; }
            let prepared_argument_24: [Field; 22] = (new_target_planet_artifacts_state).serialize();
            for prepared_index_24 in 0..22 { prepared_payload[136 + prepared_index_24] = prepared_argument_24[prepared_index_24]; }
            let prepared_argument_25: [Field; 22] = (new_target_planet_events_state).serialize();
            for prepared_index_25 in 0..22 { prepared_payload[158 + prepared_index_25] = prepared_argument_25[prepared_index_25]; }
            let prepared_argument_26: [Field; 11] = (new_arrival).serialize();
            for prepared_index_26 in 0..11 { prepared_payload[180 + prepared_index_26] = prepared_argument_26[prepared_index_26]; }
            let prepared_argument_27: [Field; 3] = (new_moved_artifact_location).serialize();
            for prepared_index_27 in 0..3 { prepared_payload[191 + prepared_index_27] = prepared_argument_27[prepared_index_27]; }
            let prepared_argument_28: [Field; 13] = (new_source_activated_artifact).serialize();
            for prepared_index_28 in 0..13 { prepared_payload[194 + prepared_index_28] = prepared_argument_28[prepared_index_28]; }
            let prepared_argument_29: [Field; 3] = (new_source_activated_artifact_location).serialize();
            for prepared_index_29 in 0..3 { prepared_payload[207 + prepared_index_29] = prepared_argument_29[prepared_index_29]; }
            let prepared_argument_30: [Field; 1] = (poseidon2_hash((new_source_planet).serialize())).serialize();
            for prepared_index_30 in 0..1 { prepared_payload[210 + prepared_index_30] = prepared_argument_30[prepared_index_30]; }
            let prepared_argument_31: [Field; 1] = (poseidon2_hash((new_source_planet_artifacts_state).serialize())).serialize();
            for prepared_index_31 in 0..1 { prepared_payload[211 + prepared_index_31] = prepared_argument_31[prepared_index_31]; }
            let prepared_argument_32: [Field; 1] = (poseidon2_hash((new_source_planet_events_state).serialize())).serialize();
            for prepared_index_32 in 0..1 { prepared_payload[212 + prepared_index_32] = prepared_argument_32[prepared_index_32]; }
            let prepared_argument_33: [Field; 1] = (poseidon2_hash((new_target_planet).serialize())).serialize();
            for prepared_index_33 in 0..1 { prepared_payload[213 + prepared_index_33] = prepared_argument_33[prepared_index_33]; }
            let prepared_argument_34: [Field; 1] = (poseidon2_hash((new_target_planet_artifacts_state).serialize())).serialize();
            for prepared_index_34 in 0..1 { prepared_payload[214 + prepared_index_34] = prepared_argument_34[prepared_index_34]; }
            let prepared_argument_35: [Field; 1] = (poseidon2_hash((new_source_activated_artifact).serialize())).serialize();
            for prepared_index_35 in 0..1 { prepared_payload[215 + prepared_index_35] = prepared_argument_35[prepared_index_35]; }
            let prepared_argument_36: [Field; 1] = (poseidon2_hash((new_source_activated_artifact_location).serialize())).serialize();
            for prepared_index_36 in 0..1 { prepared_payload[216 + prepared_index_36] = prepared_argument_36[prepared_index_36]; }
            let fallback_source_locations: [Field; 60] = (new_source_arrival_artifact_locations).serialize();
            for fallback_source_index in 0..60 { prepared_payload[217 + fallback_source_index] = fallback_source_locations[fallback_source_index]; }
            let fallback_target_locations: [Field; 60] = (new_target_arrival_artifact_locations).serialize();
            for fallback_target_index in 0..60 { prepared_payload[277 + fallback_target_index] = fallback_target_locations[fallback_target_index]; }
            self.enqueue_self.move_public_empty_prepared(FieldBuffer { words: prepared_payload });
        } else {
            let mut prepared_payload: [Field; 539] = [0; 539];
            let prepared_argument_0: [Field; 1] = (source_loc).serialize();
            for prepared_index_0 in 0..1 { prepared_payload[0 + prepared_index_0] = prepared_argument_0[prepared_index_0]; }
            let prepared_argument_1: [Field; 1] = (target_loc).serialize();
            for prepared_index_1 in 0..1 { prepared_payload[1 + prepared_index_1] = prepared_argument_1[prepared_index_1]; }
            let prepared_argument_2: [Field; 1] = (target_level).serialize();
            for prepared_index_2 in 0..1 { prepared_payload[2 + prepared_index_2] = prepared_argument_2[prepared_index_2]; }
            let prepared_argument_3: [Field; 1] = (moved_artifact_id).serialize();
            for prepared_index_3 in 0..1 { prepared_payload[3 + prepared_index_3] = prepared_argument_3[prepared_index_3]; }
            let prepared_argument_4: [Field; 1] = (source_activated_artifact_id).serialize();
            for prepared_index_4 in 0..1 { prepared_payload[4 + prepared_index_4] = prepared_argument_4[prepared_index_4]; }
            let prepared_argument_5: [Field; 1] = (target_activated_artifact_id).serialize();
            for prepared_index_5 in 0..1 { prepared_payload[5 + prepared_index_5] = prepared_argument_5[prepared_index_5]; }
            let prepared_argument_6: [Field; 1] = (timestamp).serialize();
            for prepared_index_6 in 0..1 { prepared_payload[6 + prepared_index_6] = prepared_argument_6[prepared_index_6]; }
            let prepared_argument_7: [Field; 9] = (config_hashes).serialize();
            for prepared_index_7 in 0..9 { prepared_payload[7 + prepared_index_7] = prepared_argument_7[prepared_index_7]; }
            let prepared_argument_8: [Field; 1] = (artifacts_config_hash).serialize();
            for prepared_index_8 in 0..1 { prepared_payload[16 + prepared_index_8] = prepared_argument_8[prepared_index_8]; }
            let prepared_argument_9: [Field; 1] = (planet_default_stats_hash).serialize();
            for prepared_index_9 in 0..1 { prepared_payload[17 + prepared_index_9] = prepared_argument_9[prepared_index_9]; }
            let prepared_argument_10: [Field; 1] = (source_planet_hash).serialize();
            for prepared_index_10 in 0..1 { prepared_payload[18 + prepared_index_10] = prepared_argument_10[prepared_index_10]; }
            let prepared_argument_11: [Field; 1] = (source_planet_artifacts_state_hash).serialize();
            for prepared_index_11 in 0..1 { prepared_payload[19 + prepared_index_11] = prepared_argument_11[prepared_index_11]; }
            let prepared_argument_12: [Field; 1] = (source_planet_events_state_hash).serialize();
            for prepared_index_12 in 0..1 { prepared_payload[20 + prepared_index_12] = prepared_argument_12[prepared_index_12]; }
            let prepared_argument_13: [Field; 20] = (source_arrival_ids).serialize();
            for prepared_index_13 in 0..20 { prepared_payload[21 + prepared_index_13] = prepared_argument_13[prepared_index_13]; }
            let prepared_argument_14: [Field; 20] = (source_arrival_hashes).serialize();
            for prepared_index_14 in 0..20 { prepared_payload[41 + prepared_index_14] = prepared_argument_14[prepared_index_14]; }
            let prepared_argument_15: [Field; 20] = (source_arrival_artifact_ids).serialize();
            for prepared_index_15 in 0..20 { prepared_payload[61 + prepared_index_15] = prepared_argument_15[prepared_index_15]; }
            let prepared_argument_16: [Field; 20] = (source_arrival_artifact_hashes).serialize();
            for prepared_index_16 in 0..20 { prepared_payload[81 + prepared_index_16] = prepared_argument_16[prepared_index_16]; }
            let prepared_argument_17: [Field; 20] = (source_arrival_artifact_location_hashes).serialize();
            for prepared_index_17 in 0..20 { prepared_payload[101 + prepared_index_17] = prepared_argument_17[prepared_index_17]; }
            let prepared_argument_18: [Field; 1] = (original_source_arrivals_count).serialize();
            for prepared_index_18 in 0..1 { prepared_payload[121 + prepared_index_18] = prepared_argument_18[prepared_index_18]; }
            let prepared_argument_19: [Field; 1] = (target_planet_hash).serialize();
            for prepared_index_19 in 0..1 { prepared_payload[122 + prepared_index_19] = prepared_argument_19[prepared_index_19]; }
            let prepared_argument_20: [Field; 1] = (target_planet_artifacts_state_hash).serialize();
            for prepared_index_20 in 0..1 { prepared_payload[123 + prepared_index_20] = prepared_argument_20[prepared_index_20]; }
            let prepared_argument_21: [Field; 1] = (target_planet_events_state_hash).serialize();
            for prepared_index_21 in 0..1 { prepared_payload[124 + prepared_index_21] = prepared_argument_21[prepared_index_21]; }
            let prepared_argument_22: [Field; 20] = (target_arrival_ids).serialize();
            for prepared_index_22 in 0..20 { prepared_payload[125 + prepared_index_22] = prepared_argument_22[prepared_index_22]; }
            let prepared_argument_23: [Field; 20] = (target_arrival_hashes).serialize();
            for prepared_index_23 in 0..20 { prepared_payload[145 + prepared_index_23] = prepared_argument_23[prepared_index_23]; }
            let prepared_argument_24: [Field; 20] = (target_arrival_artifact_ids).serialize();
            for prepared_index_24 in 0..20 { prepared_payload[165 + prepared_index_24] = prepared_argument_24[prepared_index_24]; }
            let prepared_argument_25: [Field; 20] = (target_arrival_artifact_hashes).serialize();
            for prepared_index_25 in 0..20 { prepared_payload[185 + prepared_index_25] = prepared_argument_25[prepared_index_25]; }
            let prepared_argument_26: [Field; 20] = (target_arrival_artifact_location_hashes).serialize();
            for prepared_index_26 in 0..20 { prepared_payload[205 + prepared_index_26] = prepared_argument_26[prepared_index_26]; }
            let prepared_argument_27: [Field; 1] = (original_target_arrivals_count).serialize();
            for prepared_index_27 in 0..1 { prepared_payload[225 + prepared_index_27] = prepared_argument_27[prepared_index_27]; }
            let prepared_argument_28: [Field; 1] = (world_hash).serialize();
            for prepared_index_28 in 0..1 { prepared_payload[226 + prepared_index_28] = prepared_argument_28[prepared_index_28]; }
            let prepared_argument_29: [Field; 1] = (moved_artifact_hash).serialize();
            for prepared_index_29 in 0..1 { prepared_payload[227 + prepared_index_29] = prepared_argument_29[prepared_index_29]; }
            let prepared_argument_30: [Field; 1] = (source_activated_artifact_hash).serialize();
            for prepared_index_30 in 0..1 { prepared_payload[228 + prepared_index_30] = prepared_argument_30[prepared_index_30]; }
            let prepared_argument_31: [Field; 1] = (target_activated_artifact_hash).serialize();
            for prepared_index_31 in 0..1 { prepared_payload[229 + prepared_index_31] = prepared_argument_31[prepared_index_31]; }
            let prepared_argument_32: [Field; 32] = (new_source_planet).serialize();
            for prepared_index_32 in 0..32 { prepared_payload[230 + prepared_index_32] = prepared_argument_32[prepared_index_32]; }
            let prepared_argument_33: [Field; 22] = (new_source_planet_artifacts_state).serialize();
            for prepared_index_33 in 0..22 { prepared_payload[262 + prepared_index_33] = prepared_argument_33[prepared_index_33]; }
            let prepared_argument_34: [Field; 22] = (new_source_planet_events_state).serialize();
            for prepared_index_34 in 0..22 { prepared_payload[284 + prepared_index_34] = prepared_argument_34[prepared_index_34]; }
            let prepared_argument_35: [Field; 60] = (new_source_arrival_artifact_locations).serialize();
            for prepared_index_35 in 0..60 { prepared_payload[306 + prepared_index_35] = prepared_argument_35[prepared_index_35]; }
            let prepared_argument_36: [Field; 32] = (new_target_planet).serialize();
            for prepared_index_36 in 0..32 { prepared_payload[366 + prepared_index_36] = prepared_argument_36[prepared_index_36]; }
            let prepared_argument_37: [Field; 22] = (new_target_planet_artifacts_state).serialize();
            for prepared_index_37 in 0..22 { prepared_payload[398 + prepared_index_37] = prepared_argument_37[prepared_index_37]; }
            let prepared_argument_38: [Field; 22] = (new_target_planet_events_state).serialize();
            for prepared_index_38 in 0..22 { prepared_payload[420 + prepared_index_38] = prepared_argument_38[prepared_index_38]; }
            let prepared_argument_39: [Field; 60] = (new_target_arrival_artifact_locations).serialize();
            for prepared_index_39 in 0..60 { prepared_payload[442 + prepared_index_39] = prepared_argument_39[prepared_index_39]; }
            let prepared_argument_40: [Field; 11] = (new_arrival).serialize();
            for prepared_index_40 in 0..11 { prepared_payload[502 + prepared_index_40] = prepared_argument_40[prepared_index_40]; }
            let prepared_argument_41: [Field; 3] = (new_moved_artifact_location).serialize();
            for prepared_index_41 in 0..3 { prepared_payload[513 + prepared_index_41] = prepared_argument_41[prepared_index_41]; }
            let prepared_argument_42: [Field; 13] = (new_source_activated_artifact).serialize();
            for prepared_index_42 in 0..13 { prepared_payload[516 + prepared_index_42] = prepared_argument_42[prepared_index_42]; }
            let prepared_argument_43: [Field; 3] = (new_source_activated_artifact_location).serialize();
            for prepared_index_43 in 0..3 { prepared_payload[529 + prepared_index_43] = prepared_argument_43[prepared_index_43]; }
            let prepared_argument_44: [Field; 1] = (poseidon2_hash((new_source_planet).serialize())).serialize();
            for prepared_index_44 in 0..1 { prepared_payload[532 + prepared_index_44] = prepared_argument_44[prepared_index_44]; }
            let prepared_argument_45: [Field; 1] = (poseidon2_hash((new_source_planet_artifacts_state).serialize())).serialize();
            for prepared_index_45 in 0..1 { prepared_payload[533 + prepared_index_45] = prepared_argument_45[prepared_index_45]; }
            let prepared_argument_46: [Field; 1] = (poseidon2_hash((new_source_planet_events_state).serialize())).serialize();
            for prepared_index_46 in 0..1 { prepared_payload[534 + prepared_index_46] = prepared_argument_46[prepared_index_46]; }
            let prepared_argument_47: [Field; 1] = (poseidon2_hash((new_target_planet).serialize())).serialize();
            for prepared_index_47 in 0..1 { prepared_payload[535 + prepared_index_47] = prepared_argument_47[prepared_index_47]; }
            let prepared_argument_48: [Field; 1] = (poseidon2_hash((new_target_planet_artifacts_state).serialize())).serialize();
            for prepared_index_48 in 0..1 { prepared_payload[536 + prepared_index_48] = prepared_argument_48[prepared_index_48]; }
            let prepared_argument_49: [Field; 1] = (poseidon2_hash((new_source_activated_artifact).serialize())).serialize();
            for prepared_index_49 in 0..1 { prepared_payload[537 + prepared_index_49] = prepared_argument_49[prepared_index_49]; }
            let prepared_argument_50: [Field; 1] = (poseidon2_hash((new_source_activated_artifact_location).serialize())).serialize();
            for prepared_index_50 in 0..1 { prepared_payload[538 + prepared_index_50] = prepared_argument_50[prepared_index_50]; }
            self.enqueue_self.move_public_prepared(FieldBuffer { words: prepared_payload });
        }
    }

    #[external("public")]
    #[only_self]
    fn move_public(
        // Basic move parameters
        source_loc: Field,
        target_loc: Field,
        target_level: u8,
        moved_artifact_id: Field,
        source_activated_artifact_id: Field,
        target_activated_artifact_id: Field,
        timestamp: u64,
        // Config hashes: [snark, world, game_core, thresholds, space_junk, tier0, tier1, tier2, tier3]
        config_hashes: [Field; 9],
        artifacts_config_hash: Field,
        planet_default_stats_hash: Field,
        // State hashes from private function for verification
        source_planet_hash: Field,
        source_planet_artifacts_state_hash: Field,
        source_planet_events_state_hash: Field,
        source_arrival_ids: [Field; 20],
        source_arrival_hashes: [Field; 20],
        source_arrival_artifact_ids: [Field; 20],
        source_arrival_artifact_hashes: [Field; 20],
        source_arrival_artifact_location_hashes: [Field; 20],
        original_source_arrivals_count: u32,
        target_planet_hash: Field,
        target_planet_artifacts_state_hash: Field,
        target_planet_events_state_hash: Field,
        target_arrival_ids: [Field; 20],
        target_arrival_hashes: [Field; 20],
        target_arrival_artifact_ids: [Field; 20],
        target_arrival_artifact_hashes: [Field; 20],
        target_arrival_artifact_location_hashes: [Field; 20],
        original_target_arrivals_count: u32,
        world_hash: Field,
        moved_artifact_hash: Field,
        source_activated_artifact_hash: Field,
        target_activated_artifact_hash: Field,
        // New states to write (computed in private function)
        new_source_planet: Planet,
        new_source_planet_artifacts_state: PlanetArtifacts,
        new_source_planet_events_state: PlanetEvents,
        new_source_arrival_artifact_locations: [ArtifactLocation; 20],
        new_target_planet: Planet,
        new_target_planet_artifacts_state: PlanetArtifacts,
        new_target_planet_events_state_input: PlanetEvents,
        new_target_arrival_artifact_locations: [ArtifactLocation; 20],
        new_arrival_input: Arrival,
        new_moved_artifact_location_input: ArtifactLocation,
        new_source_activated_artifact: Artifact,
        new_source_activated_artifact_location: ArtifactLocation,
    ) {
        _move_public_legacy(
            self.context,
            source_loc,
            target_loc,
            target_level,
            moved_artifact_id,
            source_activated_artifact_id,
            target_activated_artifact_id,
            timestamp,
            config_hashes,
            artifacts_config_hash,
            planet_default_stats_hash,
            source_planet_hash,
            source_planet_artifacts_state_hash,
            source_planet_events_state_hash,
            source_arrival_ids,
            source_arrival_hashes,
            source_arrival_artifact_ids,
            source_arrival_artifact_hashes,
            source_arrival_artifact_location_hashes,
            original_source_arrivals_count,
            target_planet_hash,
            target_planet_artifacts_state_hash,
            target_planet_events_state_hash,
            target_arrival_ids,
            target_arrival_hashes,
            target_arrival_artifact_ids,
            target_arrival_artifact_hashes,
            target_arrival_artifact_location_hashes,
            original_target_arrivals_count,
            world_hash,
            moved_artifact_hash,
            source_activated_artifact_hash,
            target_activated_artifact_hash,
            new_source_planet,
            new_source_planet_artifacts_state,
            new_source_planet_events_state,
            new_source_arrival_artifact_locations,
            new_target_planet,
            new_target_planet_artifacts_state,
            new_target_planet_events_state_input,
            new_target_arrival_artifact_locations,
            new_arrival_input,
            new_moved_artifact_location_input,
            new_source_activated_artifact,
            new_source_activated_artifact_location,
        );
    }

    #[external("public")]
    #[only_self]
    fn move_public_prepared(
        prepared_payload: FieldBuffer<539>,
    ) {
        let state_backend_address = self.storage.state_backend.read();
        let mut settled_by_backend = false;
        if state_backend_address != AztecAddress::zero() {
            if ::libs::config_recognition::supports_config(self.storage.config_storage_address.read()) {
                let backend_calldata: [Field; 550] = [
                    comptime {
                    aztec::protocol::abis::function_selector::FunctionSelector::from_signature(
                        "try_settle_move_move(([Field;549]))",
                    ).to_field()
                },
                    (self.storage.config_storage_address.read()).to_field(),
                    (self.storage.world_storage_address.read()).to_field(),
                    (AztecAddress::zero()).to_field(),
                    (self.storage.planet_storage_address.read()).to_field(),
                    (AztecAddress::zero()).to_field(),
                    (self.storage.planet_events_storage_address.read()).to_field(),
                    (self.storage.planet_artifacts_storage_address.read()).to_field(),
                    (self.storage.arrivals_storage_address.read()).to_field(),
                    (self.storage.artifact_storage_address.read()).to_field(),
                    (self.storage.artifact_location_storage_address.read()).to_field(),
                    prepared_payload.words[0],
                    prepared_payload.words[1],
                    prepared_payload.words[2],
                    prepared_payload.words[3],
                    prepared_payload.words[4],
                    prepared_payload.words[5],
                    prepared_payload.words[6],
                    prepared_payload.words[7],
                    prepared_payload.words[8],
                    prepared_payload.words[9],
                    prepared_payload.words[10],
                    prepared_payload.words[11],
                    prepared_payload.words[12],
                    prepared_payload.words[13],
                    prepared_payload.words[14],
                    prepared_payload.words[15],
                    prepared_payload.words[16],
                    prepared_payload.words[17],
                    prepared_payload.words[18],
                    prepared_payload.words[19],
                    prepared_payload.words[20],
                    prepared_payload.words[21],
                    prepared_payload.words[22],
                    prepared_payload.words[23],
                    prepared_payload.words[24],
                    prepared_payload.words[25],
                    prepared_payload.words[26],
                    prepared_payload.words[27],
                    prepared_payload.words[28],
                    prepared_payload.words[29],
                    prepared_payload.words[30],
                    prepared_payload.words[31],
                    prepared_payload.words[32],
                    prepared_payload.words[33],
                    prepared_payload.words[34],
                    prepared_payload.words[35],
                    prepared_payload.words[36],
                    prepared_payload.words[37],
                    prepared_payload.words[38],
                    prepared_payload.words[39],
                    prepared_payload.words[40],
                    prepared_payload.words[41],
                    prepared_payload.words[42],
                    prepared_payload.words[43],
                    prepared_payload.words[44],
                    prepared_payload.words[45],
                    prepared_payload.words[46],
                    prepared_payload.words[47],
                    prepared_payload.words[48],
                    prepared_payload.words[49],
                    prepared_payload.words[50],
                    prepared_payload.words[51],
                    prepared_payload.words[52],
                    prepared_payload.words[53],
                    prepared_payload.words[54],
                    prepared_payload.words[55],
                    prepared_payload.words[56],
                    prepared_payload.words[57],
                    prepared_payload.words[58],
                    prepared_payload.words[59],
                    prepared_payload.words[60],
                    prepared_payload.words[61],
                    prepared_payload.words[62],
                    prepared_payload.words[63],
                    prepared_payload.words[64],
                    prepared_payload.words[65],
                    prepared_payload.words[66],
                    prepared_payload.words[67],
                    prepared_payload.words[68],
                    prepared_payload.words[69],
                    prepared_payload.words[70],
                    prepared_payload.words[71],
                    prepared_payload.words[72],
                    prepared_payload.words[73],
                    prepared_payload.words[74],
                    prepared_payload.words[75],
                    prepared_payload.words[76],
                    prepared_payload.words[77],
                    prepared_payload.words[78],
                    prepared_payload.words[79],
                    prepared_payload.words[80],
                    prepared_payload.words[81],
                    prepared_payload.words[82],
                    prepared_payload.words[83],
                    prepared_payload.words[84],
                    prepared_payload.words[85],
                    prepared_payload.words[86],
                    prepared_payload.words[87],
                    prepared_payload.words[88],
                    prepared_payload.words[89],
                    prepared_payload.words[90],
                    prepared_payload.words[91],
                    prepared_payload.words[92],
                    prepared_payload.words[93],
                    prepared_payload.words[94],
                    prepared_payload.words[95],
                    prepared_payload.words[96],
                    prepared_payload.words[97],
                    prepared_payload.words[98],
                    prepared_payload.words[99],
                    prepared_payload.words[100],
                    prepared_payload.words[101],
                    prepared_payload.words[102],
                    prepared_payload.words[103],
                    prepared_payload.words[104],
                    prepared_payload.words[105],
                    prepared_payload.words[106],
                    prepared_payload.words[107],
                    prepared_payload.words[108],
                    prepared_payload.words[109],
                    prepared_payload.words[110],
                    prepared_payload.words[111],
                    prepared_payload.words[112],
                    prepared_payload.words[113],
                    prepared_payload.words[114],
                    prepared_payload.words[115],
                    prepared_payload.words[116],
                    prepared_payload.words[117],
                    prepared_payload.words[118],
                    prepared_payload.words[119],
                    prepared_payload.words[120],
                    prepared_payload.words[121],
                    prepared_payload.words[122],
                    prepared_payload.words[123],
                    prepared_payload.words[124],
                    prepared_payload.words[125],
                    prepared_payload.words[126],
                    prepared_payload.words[127],
                    prepared_payload.words[128],
                    prepared_payload.words[129],
                    prepared_payload.words[130],
                    prepared_payload.words[131],
                    prepared_payload.words[132],
                    prepared_payload.words[133],
                    prepared_payload.words[134],
                    prepared_payload.words[135],
                    prepared_payload.words[136],
                    prepared_payload.words[137],
                    prepared_payload.words[138],
                    prepared_payload.words[139],
                    prepared_payload.words[140],
                    prepared_payload.words[141],
                    prepared_payload.words[142],
                    prepared_payload.words[143],
                    prepared_payload.words[144],
                    prepared_payload.words[145],
                    prepared_payload.words[146],
                    prepared_payload.words[147],
                    prepared_payload.words[148],
                    prepared_payload.words[149],
                    prepared_payload.words[150],
                    prepared_payload.words[151],
                    prepared_payload.words[152],
                    prepared_payload.words[153],
                    prepared_payload.words[154],
                    prepared_payload.words[155],
                    prepared_payload.words[156],
                    prepared_payload.words[157],
                    prepared_payload.words[158],
                    prepared_payload.words[159],
                    prepared_payload.words[160],
                    prepared_payload.words[161],
                    prepared_payload.words[162],
                    prepared_payload.words[163],
                    prepared_payload.words[164],
                    prepared_payload.words[165],
                    prepared_payload.words[166],
                    prepared_payload.words[167],
                    prepared_payload.words[168],
                    prepared_payload.words[169],
                    prepared_payload.words[170],
                    prepared_payload.words[171],
                    prepared_payload.words[172],
                    prepared_payload.words[173],
                    prepared_payload.words[174],
                    prepared_payload.words[175],
                    prepared_payload.words[176],
                    prepared_payload.words[177],
                    prepared_payload.words[178],
                    prepared_payload.words[179],
                    prepared_payload.words[180],
                    prepared_payload.words[181],
                    prepared_payload.words[182],
                    prepared_payload.words[183],
                    prepared_payload.words[184],
                    prepared_payload.words[185],
                    prepared_payload.words[186],
                    prepared_payload.words[187],
                    prepared_payload.words[188],
                    prepared_payload.words[189],
                    prepared_payload.words[190],
                    prepared_payload.words[191],
                    prepared_payload.words[192],
                    prepared_payload.words[193],
                    prepared_payload.words[194],
                    prepared_payload.words[195],
                    prepared_payload.words[196],
                    prepared_payload.words[197],
                    prepared_payload.words[198],
                    prepared_payload.words[199],
                    prepared_payload.words[200],
                    prepared_payload.words[201],
                    prepared_payload.words[202],
                    prepared_payload.words[203],
                    prepared_payload.words[204],
                    prepared_payload.words[205],
                    prepared_payload.words[206],
                    prepared_payload.words[207],
                    prepared_payload.words[208],
                    prepared_payload.words[209],
                    prepared_payload.words[210],
                    prepared_payload.words[211],
                    prepared_payload.words[212],
                    prepared_payload.words[213],
                    prepared_payload.words[214],
                    prepared_payload.words[215],
                    prepared_payload.words[216],
                    prepared_payload.words[217],
                    prepared_payload.words[218],
                    prepared_payload.words[219],
                    prepared_payload.words[220],
                    prepared_payload.words[221],
                    prepared_payload.words[222],
                    prepared_payload.words[223],
                    prepared_payload.words[224],
                    prepared_payload.words[225],
                    prepared_payload.words[226],
                    prepared_payload.words[227],
                    prepared_payload.words[228],
                    prepared_payload.words[229],
                    prepared_payload.words[230],
                    prepared_payload.words[231],
                    prepared_payload.words[232],
                    prepared_payload.words[233],
                    prepared_payload.words[234],
                    prepared_payload.words[235],
                    prepared_payload.words[236],
                    prepared_payload.words[237],
                    prepared_payload.words[238],
                    prepared_payload.words[239],
                    prepared_payload.words[240],
                    prepared_payload.words[241],
                    prepared_payload.words[242],
                    prepared_payload.words[243],
                    prepared_payload.words[244],
                    prepared_payload.words[245],
                    prepared_payload.words[246],
                    prepared_payload.words[247],
                    prepared_payload.words[248],
                    prepared_payload.words[249],
                    prepared_payload.words[250],
                    prepared_payload.words[251],
                    prepared_payload.words[252],
                    prepared_payload.words[253],
                    prepared_payload.words[254],
                    prepared_payload.words[255],
                    prepared_payload.words[256],
                    prepared_payload.words[257],
                    prepared_payload.words[258],
                    prepared_payload.words[259],
                    prepared_payload.words[260],
                    prepared_payload.words[261],
                    prepared_payload.words[262],
                    prepared_payload.words[263],
                    prepared_payload.words[264],
                    prepared_payload.words[265],
                    prepared_payload.words[266],
                    prepared_payload.words[267],
                    prepared_payload.words[268],
                    prepared_payload.words[269],
                    prepared_payload.words[270],
                    prepared_payload.words[271],
                    prepared_payload.words[272],
                    prepared_payload.words[273],
                    prepared_payload.words[274],
                    prepared_payload.words[275],
                    prepared_payload.words[276],
                    prepared_payload.words[277],
                    prepared_payload.words[278],
                    prepared_payload.words[279],
                    prepared_payload.words[280],
                    prepared_payload.words[281],
                    prepared_payload.words[282],
                    prepared_payload.words[283],
                    prepared_payload.words[284],
                    prepared_payload.words[285],
                    prepared_payload.words[286],
                    prepared_payload.words[287],
                    prepared_payload.words[288],
                    prepared_payload.words[289],
                    prepared_payload.words[290],
                    prepared_payload.words[291],
                    prepared_payload.words[292],
                    prepared_payload.words[293],
                    prepared_payload.words[294],
                    prepared_payload.words[295],
                    prepared_payload.words[296],
                    prepared_payload.words[297],
                    prepared_payload.words[298],
                    prepared_payload.words[299],
                    prepared_payload.words[300],
                    prepared_payload.words[301],
                    prepared_payload.words[302],
                    prepared_payload.words[303],
                    prepared_payload.words[304],
                    prepared_payload.words[305],
                    prepared_payload.words[306],
                    prepared_payload.words[307],
                    prepared_payload.words[308],
                    prepared_payload.words[309],
                    prepared_payload.words[310],
                    prepared_payload.words[311],
                    prepared_payload.words[312],
                    prepared_payload.words[313],
                    prepared_payload.words[314],
                    prepared_payload.words[315],
                    prepared_payload.words[316],
                    prepared_payload.words[317],
                    prepared_payload.words[318],
                    prepared_payload.words[319],
                    prepared_payload.words[320],
                    prepared_payload.words[321],
                    prepared_payload.words[322],
                    prepared_payload.words[323],
                    prepared_payload.words[324],
                    prepared_payload.words[325],
                    prepared_payload.words[326],
                    prepared_payload.words[327],
                    prepared_payload.words[328],
                    prepared_payload.words[329],
                    prepared_payload.words[330],
                    prepared_payload.words[331],
                    prepared_payload.words[332],
                    prepared_payload.words[333],
                    prepared_payload.words[334],
                    prepared_payload.words[335],
                    prepared_payload.words[336],
                    prepared_payload.words[337],
                    prepared_payload.words[338],
                    prepared_payload.words[339],
                    prepared_payload.words[340],
                    prepared_payload.words[341],
                    prepared_payload.words[342],
                    prepared_payload.words[343],
                    prepared_payload.words[344],
                    prepared_payload.words[345],
                    prepared_payload.words[346],
                    prepared_payload.words[347],
                    prepared_payload.words[348],
                    prepared_payload.words[349],
                    prepared_payload.words[350],
                    prepared_payload.words[351],
                    prepared_payload.words[352],
                    prepared_payload.words[353],
                    prepared_payload.words[354],
                    prepared_payload.words[355],
                    prepared_payload.words[356],
                    prepared_payload.words[357],
                    prepared_payload.words[358],
                    prepared_payload.words[359],
                    prepared_payload.words[360],
                    prepared_payload.words[361],
                    prepared_payload.words[362],
                    prepared_payload.words[363],
                    prepared_payload.words[364],
                    prepared_payload.words[365],
                    prepared_payload.words[366],
                    prepared_payload.words[367],
                    prepared_payload.words[368],
                    prepared_payload.words[369],
                    prepared_payload.words[370],
                    prepared_payload.words[371],
                    prepared_payload.words[372],
                    prepared_payload.words[373],
                    prepared_payload.words[374],
                    prepared_payload.words[375],
                    prepared_payload.words[376],
                    prepared_payload.words[377],
                    prepared_payload.words[378],
                    prepared_payload.words[379],
                    prepared_payload.words[380],
                    prepared_payload.words[381],
                    prepared_payload.words[382],
                    prepared_payload.words[383],
                    prepared_payload.words[384],
                    prepared_payload.words[385],
                    prepared_payload.words[386],
                    prepared_payload.words[387],
                    prepared_payload.words[388],
                    prepared_payload.words[389],
                    prepared_payload.words[390],
                    prepared_payload.words[391],
                    prepared_payload.words[392],
                    prepared_payload.words[393],
                    prepared_payload.words[394],
                    prepared_payload.words[395],
                    prepared_payload.words[396],
                    prepared_payload.words[397],
                    prepared_payload.words[398],
                    prepared_payload.words[399],
                    prepared_payload.words[400],
                    prepared_payload.words[401],
                    prepared_payload.words[402],
                    prepared_payload.words[403],
                    prepared_payload.words[404],
                    prepared_payload.words[405],
                    prepared_payload.words[406],
                    prepared_payload.words[407],
                    prepared_payload.words[408],
                    prepared_payload.words[409],
                    prepared_payload.words[410],
                    prepared_payload.words[411],
                    prepared_payload.words[412],
                    prepared_payload.words[413],
                    prepared_payload.words[414],
                    prepared_payload.words[415],
                    prepared_payload.words[416],
                    prepared_payload.words[417],
                    prepared_payload.words[418],
                    prepared_payload.words[419],
                    prepared_payload.words[420],
                    prepared_payload.words[421],
                    prepared_payload.words[422],
                    prepared_payload.words[423],
                    prepared_payload.words[424],
                    prepared_payload.words[425],
                    prepared_payload.words[426],
                    prepared_payload.words[427],
                    prepared_payload.words[428],
                    prepared_payload.words[429],
                    prepared_payload.words[430],
                    prepared_payload.words[431],
                    prepared_payload.words[432],
                    prepared_payload.words[433],
                    prepared_payload.words[434],
                    prepared_payload.words[435],
                    prepared_payload.words[436],
                    prepared_payload.words[437],
                    prepared_payload.words[438],
                    prepared_payload.words[439],
                    prepared_payload.words[440],
                    prepared_payload.words[441],
                    prepared_payload.words[442],
                    prepared_payload.words[443],
                    prepared_payload.words[444],
                    prepared_payload.words[445],
                    prepared_payload.words[446],
                    prepared_payload.words[447],
                    prepared_payload.words[448],
                    prepared_payload.words[449],
                    prepared_payload.words[450],
                    prepared_payload.words[451],
                    prepared_payload.words[452],
                    prepared_payload.words[453],
                    prepared_payload.words[454],
                    prepared_payload.words[455],
                    prepared_payload.words[456],
                    prepared_payload.words[457],
                    prepared_payload.words[458],
                    prepared_payload.words[459],
                    prepared_payload.words[460],
                    prepared_payload.words[461],
                    prepared_payload.words[462],
                    prepared_payload.words[463],
                    prepared_payload.words[464],
                    prepared_payload.words[465],
                    prepared_payload.words[466],
                    prepared_payload.words[467],
                    prepared_payload.words[468],
                    prepared_payload.words[469],
                    prepared_payload.words[470],
                    prepared_payload.words[471],
                    prepared_payload.words[472],
                    prepared_payload.words[473],
                    prepared_payload.words[474],
                    prepared_payload.words[475],
                    prepared_payload.words[476],
                    prepared_payload.words[477],
                    prepared_payload.words[478],
                    prepared_payload.words[479],
                    prepared_payload.words[480],
                    prepared_payload.words[481],
                    prepared_payload.words[482],
                    prepared_payload.words[483],
                    prepared_payload.words[484],
                    prepared_payload.words[485],
                    prepared_payload.words[486],
                    prepared_payload.words[487],
                    prepared_payload.words[488],
                    prepared_payload.words[489],
                    prepared_payload.words[490],
                    prepared_payload.words[491],
                    prepared_payload.words[492],
                    prepared_payload.words[493],
                    prepared_payload.words[494],
                    prepared_payload.words[495],
                    prepared_payload.words[496],
                    prepared_payload.words[497],
                    prepared_payload.words[498],
                    prepared_payload.words[499],
                    prepared_payload.words[500],
                    prepared_payload.words[501],
                    prepared_payload.words[502],
                    prepared_payload.words[503],
                    prepared_payload.words[504],
                    prepared_payload.words[505],
                    prepared_payload.words[506],
                    prepared_payload.words[507],
                    prepared_payload.words[508],
                    prepared_payload.words[509],
                    prepared_payload.words[510],
                    prepared_payload.words[511],
                    prepared_payload.words[512],
                    prepared_payload.words[513],
                    prepared_payload.words[514],
                    prepared_payload.words[515],
                    prepared_payload.words[516],
                    prepared_payload.words[517],
                    prepared_payload.words[518],
                    prepared_payload.words[519],
                    prepared_payload.words[520],
                    prepared_payload.words[521],
                    prepared_payload.words[522],
                    prepared_payload.words[523],
                    prepared_payload.words[524],
                    prepared_payload.words[525],
                    prepared_payload.words[526],
                    prepared_payload.words[527],
                    prepared_payload.words[528],
                    prepared_payload.words[529],
                    prepared_payload.words[530],
                    prepared_payload.words[531],
                    prepared_payload.words[532],
                    prepared_payload.words[533],
                    prepared_payload.words[534],
                    prepared_payload.words[535],
                    prepared_payload.words[536],
                    prepared_payload.words[537],
                    prepared_payload.words[538],
                ];
                let backend_returns = libs::public_call::call(state_backend_address, backend_calldata);
                settled_by_backend = aztec::protocol::traits::Deserialize::deserialize(backend_returns.as_array());
            }
        }
        if !settled_by_backend {
        let source_loc: Field = prepared_payload.words[0];
        let target_loc: Field = prepared_payload.words[1];
        let target_level: u8 = (prepared_payload.words[2] as u8);
        let moved_artifact_id: Field = prepared_payload.words[3];
        let source_activated_artifact_id: Field = prepared_payload.words[4];
        let target_activated_artifact_id: Field = prepared_payload.words[5];
        let timestamp: u64 = (prepared_payload.words[6] as u64);
        let config_hashes: [Field; 9] = [prepared_payload.words[7], prepared_payload.words[8], prepared_payload.words[9], prepared_payload.words[10], prepared_payload.words[11], prepared_payload.words[12], prepared_payload.words[13], prepared_payload.words[14], prepared_payload.words[15]];
        let artifacts_config_hash: Field = prepared_payload.words[16];
        let planet_default_stats_hash: Field = prepared_payload.words[17];
        let source_planet_hash: Field = prepared_payload.words[18];
        let source_planet_artifacts_state_hash: Field = prepared_payload.words[19];
        let source_planet_events_state_hash: Field = prepared_payload.words[20];
        let source_arrival_ids: [Field; 20] = [prepared_payload.words[21], prepared_payload.words[22], prepared_payload.words[23], prepared_payload.words[24], prepared_payload.words[25], prepared_payload.words[26], prepared_payload.words[27], prepared_payload.words[28], prepared_payload.words[29], prepared_payload.words[30], prepared_payload.words[31], prepared_payload.words[32], prepared_payload.words[33], prepared_payload.words[34], prepared_payload.words[35], prepared_payload.words[36], prepared_payload.words[37], prepared_payload.words[38], prepared_payload.words[39], prepared_payload.words[40]];
        let source_arrival_hashes: [Field; 20] = [prepared_payload.words[41], prepared_payload.words[42], prepared_payload.words[43], prepared_payload.words[44], prepared_payload.words[45], prepared_payload.words[46], prepared_payload.words[47], prepared_payload.words[48], prepared_payload.words[49], prepared_payload.words[50], prepared_payload.words[51], prepared_payload.words[52], prepared_payload.words[53], prepared_payload.words[54], prepared_payload.words[55], prepared_payload.words[56], prepared_payload.words[57], prepared_payload.words[58], prepared_payload.words[59], prepared_payload.words[60]];
        let source_arrival_artifact_ids: [Field; 20] = [prepared_payload.words[61], prepared_payload.words[62], prepared_payload.words[63], prepared_payload.words[64], prepared_payload.words[65], prepared_payload.words[66], prepared_payload.words[67], prepared_payload.words[68], prepared_payload.words[69], prepared_payload.words[70], prepared_payload.words[71], prepared_payload.words[72], prepared_payload.words[73], prepared_payload.words[74], prepared_payload.words[75], prepared_payload.words[76], prepared_payload.words[77], prepared_payload.words[78], prepared_payload.words[79], prepared_payload.words[80]];
        let source_arrival_artifact_hashes: [Field; 20] = [prepared_payload.words[81], prepared_payload.words[82], prepared_payload.words[83], prepared_payload.words[84], prepared_payload.words[85], prepared_payload.words[86], prepared_payload.words[87], prepared_payload.words[88], prepared_payload.words[89], prepared_payload.words[90], prepared_payload.words[91], prepared_payload.words[92], prepared_payload.words[93], prepared_payload.words[94], prepared_payload.words[95], prepared_payload.words[96], prepared_payload.words[97], prepared_payload.words[98], prepared_payload.words[99], prepared_payload.words[100]];
        let source_arrival_artifact_location_hashes: [Field; 20] = [prepared_payload.words[101], prepared_payload.words[102], prepared_payload.words[103], prepared_payload.words[104], prepared_payload.words[105], prepared_payload.words[106], prepared_payload.words[107], prepared_payload.words[108], prepared_payload.words[109], prepared_payload.words[110], prepared_payload.words[111], prepared_payload.words[112], prepared_payload.words[113], prepared_payload.words[114], prepared_payload.words[115], prepared_payload.words[116], prepared_payload.words[117], prepared_payload.words[118], prepared_payload.words[119], prepared_payload.words[120]];
        let original_source_arrivals_count: u32 = (prepared_payload.words[121] as u32);
        let target_planet_hash: Field = prepared_payload.words[122];
        let target_planet_artifacts_state_hash: Field = prepared_payload.words[123];
        let target_planet_events_state_hash: Field = prepared_payload.words[124];
        let target_arrival_ids: [Field; 20] = [prepared_payload.words[125], prepared_payload.words[126], prepared_payload.words[127], prepared_payload.words[128], prepared_payload.words[129], prepared_payload.words[130], prepared_payload.words[131], prepared_payload.words[132], prepared_payload.words[133], prepared_payload.words[134], prepared_payload.words[135], prepared_payload.words[136], prepared_payload.words[137], prepared_payload.words[138], prepared_payload.words[139], prepared_payload.words[140], prepared_payload.words[141], prepared_payload.words[142], prepared_payload.words[143], prepared_payload.words[144]];
        let target_arrival_hashes: [Field; 20] = [prepared_payload.words[145], prepared_payload.words[146], prepared_payload.words[147], prepared_payload.words[148], prepared_payload.words[149], prepared_payload.words[150], prepared_payload.words[151], prepared_payload.words[152], prepared_payload.words[153], prepared_payload.words[154], prepared_payload.words[155], prepared_payload.words[156], prepared_payload.words[157], prepared_payload.words[158], prepared_payload.words[159], prepared_payload.words[160], prepared_payload.words[161], prepared_payload.words[162], prepared_payload.words[163], prepared_payload.words[164]];
        let target_arrival_artifact_ids: [Field; 20] = [prepared_payload.words[165], prepared_payload.words[166], prepared_payload.words[167], prepared_payload.words[168], prepared_payload.words[169], prepared_payload.words[170], prepared_payload.words[171], prepared_payload.words[172], prepared_payload.words[173], prepared_payload.words[174], prepared_payload.words[175], prepared_payload.words[176], prepared_payload.words[177], prepared_payload.words[178], prepared_payload.words[179], prepared_payload.words[180], prepared_payload.words[181], prepared_payload.words[182], prepared_payload.words[183], prepared_payload.words[184]];
        let target_arrival_artifact_hashes: [Field; 20] = [prepared_payload.words[185], prepared_payload.words[186], prepared_payload.words[187], prepared_payload.words[188], prepared_payload.words[189], prepared_payload.words[190], prepared_payload.words[191], prepared_payload.words[192], prepared_payload.words[193], prepared_payload.words[194], prepared_payload.words[195], prepared_payload.words[196], prepared_payload.words[197], prepared_payload.words[198], prepared_payload.words[199], prepared_payload.words[200], prepared_payload.words[201], prepared_payload.words[202], prepared_payload.words[203], prepared_payload.words[204]];
        let target_arrival_artifact_location_hashes: [Field; 20] = [prepared_payload.words[205], prepared_payload.words[206], prepared_payload.words[207], prepared_payload.words[208], prepared_payload.words[209], prepared_payload.words[210], prepared_payload.words[211], prepared_payload.words[212], prepared_payload.words[213], prepared_payload.words[214], prepared_payload.words[215], prepared_payload.words[216], prepared_payload.words[217], prepared_payload.words[218], prepared_payload.words[219], prepared_payload.words[220], prepared_payload.words[221], prepared_payload.words[222], prepared_payload.words[223], prepared_payload.words[224]];
        let original_target_arrivals_count: u32 = (prepared_payload.words[225] as u32);
        let world_hash: Field = prepared_payload.words[226];
        let moved_artifact_hash: Field = prepared_payload.words[227];
        let source_activated_artifact_hash: Field = prepared_payload.words[228];
        let target_activated_artifact_hash: Field = prepared_payload.words[229];
        let new_source_planet: Planet = Planet { perlin: (prepared_payload.words[230] as u8), created_at: (prepared_payload.words[231] as u64), owner: AztecAddress::from_field(prepared_payload.words[232]), planet_level: (prepared_payload.words[233] as u8), planet_type: (prepared_payload.words[234] as u8), space_type: (prepared_payload.words[235] as u8), is_home_planet: (prepared_payload.words[236] == 1), is_initialized: (prepared_payload.words[237] == 1), destroyed: (prepared_payload.words[238] == 1), invader: AztecAddress::from_field(prepared_payload.words[239]), capturer: AztecAddress::from_field(prepared_payload.words[240]), invade_start_block: (prepared_payload.words[241] as u32), population_cap: (prepared_payload.words[242] as u128), population_growth: (prepared_payload.words[243] as u128), range: (prepared_payload.words[244] as u128), speed: (prepared_payload.words[245] as u128), defense: (prepared_payload.words[246] as u128), silver_cap: (prepared_payload.words[247] as u128), silver_growth: (prepared_payload.words[248] as u128), population: (prepared_payload.words[249] as u128), silver: (prepared_payload.words[250] as u128), upgrade_state_0: (prepared_payload.words[251] as u8), upgrade_state_1: (prepared_payload.words[252] as u8), upgrade_state_2: (prepared_payload.words[253] as u8), last_updated: (prepared_payload.words[254] as u64), pausers: (prepared_payload.words[255] as u128), energy_gro_doublers: (prepared_payload.words[256] as u128), silver_gro_doublers: (prepared_payload.words[257] as u128), hat_level: (prepared_payload.words[258] as u128), space_junk: (prepared_payload.words[259] as u128), has_tried_finding_artifact: (prepared_payload.words[260] == 1), prospected_block_number: (prepared_payload.words[261] as u32) };
        let new_source_planet_artifacts_state: PlanetArtifacts = PlanetArtifacts { ids: [prepared_payload.words[262], prepared_payload.words[263], prepared_payload.words[264], prepared_payload.words[265], prepared_payload.words[266], prepared_payload.words[267], prepared_payload.words[268], prepared_payload.words[269], prepared_payload.words[270], prepared_payload.words[271], prepared_payload.words[272], prepared_payload.words[273], prepared_payload.words[274], prepared_payload.words[275], prepared_payload.words[276], prepared_payload.words[277], prepared_payload.words[278], prepared_payload.words[279], prepared_payload.words[280], prepared_payload.words[281]], count: (prepared_payload.words[282] as u32), last_updated: (prepared_payload.words[283] as u64) };
        let new_source_planet_events_state: PlanetEvents = PlanetEvents { events: [PlanetEventMetadata { id: prepared_payload.words[284] }, PlanetEventMetadata { id: prepared_payload.words[285] }, PlanetEventMetadata { id: prepared_payload.words[286] }, PlanetEventMetadata { id: prepared_payload.words[287] }, PlanetEventMetadata { id: prepared_payload.words[288] }, PlanetEventMetadata { id: prepared_payload.words[289] }, PlanetEventMetadata { id: prepared_payload.words[290] }, PlanetEventMetadata { id: prepared_payload.words[291] }, PlanetEventMetadata { id: prepared_payload.words[292] }, PlanetEventMetadata { id: prepared_payload.words[293] }, PlanetEventMetadata { id: prepared_payload.words[294] }, PlanetEventMetadata { id: prepared_payload.words[295] }, PlanetEventMetadata { id: prepared_payload.words[296] }, PlanetEventMetadata { id: prepared_payload.words[297] }, PlanetEventMetadata { id: prepared_payload.words[298] }, PlanetEventMetadata { id: prepared_payload.words[299] }, PlanetEventMetadata { id: prepared_payload.words[300] }, PlanetEventMetadata { id: prepared_payload.words[301] }, PlanetEventMetadata { id: prepared_payload.words[302] }, PlanetEventMetadata { id: prepared_payload.words[303] }], count: (prepared_payload.words[304] as u32), last_updated: (prepared_payload.words[305] as u64) };
        let new_source_arrival_artifact_locations: [ArtifactLocation; 20] = [ArtifactLocation { planet_id: prepared_payload.words[306], voyage_id: prepared_payload.words[307], last_updated: (prepared_payload.words[308] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[309], voyage_id: prepared_payload.words[310], last_updated: (prepared_payload.words[311] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[312], voyage_id: prepared_payload.words[313], last_updated: (prepared_payload.words[314] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[315], voyage_id: prepared_payload.words[316], last_updated: (prepared_payload.words[317] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[318], voyage_id: prepared_payload.words[319], last_updated: (prepared_payload.words[320] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[321], voyage_id: prepared_payload.words[322], last_updated: (prepared_payload.words[323] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[324], voyage_id: prepared_payload.words[325], last_updated: (prepared_payload.words[326] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[327], voyage_id: prepared_payload.words[328], last_updated: (prepared_payload.words[329] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[330], voyage_id: prepared_payload.words[331], last_updated: (prepared_payload.words[332] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[333], voyage_id: prepared_payload.words[334], last_updated: (prepared_payload.words[335] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[336], voyage_id: prepared_payload.words[337], last_updated: (prepared_payload.words[338] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[339], voyage_id: prepared_payload.words[340], last_updated: (prepared_payload.words[341] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[342], voyage_id: prepared_payload.words[343], last_updated: (prepared_payload.words[344] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[345], voyage_id: prepared_payload.words[346], last_updated: (prepared_payload.words[347] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[348], voyage_id: prepared_payload.words[349], last_updated: (prepared_payload.words[350] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[351], voyage_id: prepared_payload.words[352], last_updated: (prepared_payload.words[353] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[354], voyage_id: prepared_payload.words[355], last_updated: (prepared_payload.words[356] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[357], voyage_id: prepared_payload.words[358], last_updated: (prepared_payload.words[359] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[360], voyage_id: prepared_payload.words[361], last_updated: (prepared_payload.words[362] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[363], voyage_id: prepared_payload.words[364], last_updated: (prepared_payload.words[365] as u64) }];
        let new_target_planet: Planet = Planet { perlin: (prepared_payload.words[366] as u8), created_at: (prepared_payload.words[367] as u64), owner: AztecAddress::from_field(prepared_payload.words[368]), planet_level: (prepared_payload.words[369] as u8), planet_type: (prepared_payload.words[370] as u8), space_type: (prepared_payload.words[371] as u8), is_home_planet: (prepared_payload.words[372] == 1), is_initialized: (prepared_payload.words[373] == 1), destroyed: (prepared_payload.words[374] == 1), invader: AztecAddress::from_field(prepared_payload.words[375]), capturer: AztecAddress::from_field(prepared_payload.words[376]), invade_start_block: (prepared_payload.words[377] as u32), population_cap: (prepared_payload.words[378] as u128), population_growth: (prepared_payload.words[379] as u128), range: (prepared_payload.words[380] as u128), speed: (prepared_payload.words[381] as u128), defense: (prepared_payload.words[382] as u128), silver_cap: (prepared_payload.words[383] as u128), silver_growth: (prepared_payload.words[384] as u128), population: (prepared_payload.words[385] as u128), silver: (prepared_payload.words[386] as u128), upgrade_state_0: (prepared_payload.words[387] as u8), upgrade_state_1: (prepared_payload.words[388] as u8), upgrade_state_2: (prepared_payload.words[389] as u8), last_updated: (prepared_payload.words[390] as u64), pausers: (prepared_payload.words[391] as u128), energy_gro_doublers: (prepared_payload.words[392] as u128), silver_gro_doublers: (prepared_payload.words[393] as u128), hat_level: (prepared_payload.words[394] as u128), space_junk: (prepared_payload.words[395] as u128), has_tried_finding_artifact: (prepared_payload.words[396] == 1), prospected_block_number: (prepared_payload.words[397] as u32) };
        let new_target_planet_artifacts_state: PlanetArtifacts = PlanetArtifacts { ids: [prepared_payload.words[398], prepared_payload.words[399], prepared_payload.words[400], prepared_payload.words[401], prepared_payload.words[402], prepared_payload.words[403], prepared_payload.words[404], prepared_payload.words[405], prepared_payload.words[406], prepared_payload.words[407], prepared_payload.words[408], prepared_payload.words[409], prepared_payload.words[410], prepared_payload.words[411], prepared_payload.words[412], prepared_payload.words[413], prepared_payload.words[414], prepared_payload.words[415], prepared_payload.words[416], prepared_payload.words[417]], count: (prepared_payload.words[418] as u32), last_updated: (prepared_payload.words[419] as u64) };
        let new_target_planet_events_state_input: PlanetEvents = PlanetEvents { events: [PlanetEventMetadata { id: prepared_payload.words[420] }, PlanetEventMetadata { id: prepared_payload.words[421] }, PlanetEventMetadata { id: prepared_payload.words[422] }, PlanetEventMetadata { id: prepared_payload.words[423] }, PlanetEventMetadata { id: prepared_payload.words[424] }, PlanetEventMetadata { id: prepared_payload.words[425] }, PlanetEventMetadata { id: prepared_payload.words[426] }, PlanetEventMetadata { id: prepared_payload.words[427] }, PlanetEventMetadata { id: prepared_payload.words[428] }, PlanetEventMetadata { id: prepared_payload.words[429] }, PlanetEventMetadata { id: prepared_payload.words[430] }, PlanetEventMetadata { id: prepared_payload.words[431] }, PlanetEventMetadata { id: prepared_payload.words[432] }, PlanetEventMetadata { id: prepared_payload.words[433] }, PlanetEventMetadata { id: prepared_payload.words[434] }, PlanetEventMetadata { id: prepared_payload.words[435] }, PlanetEventMetadata { id: prepared_payload.words[436] }, PlanetEventMetadata { id: prepared_payload.words[437] }, PlanetEventMetadata { id: prepared_payload.words[438] }, PlanetEventMetadata { id: prepared_payload.words[439] }], count: (prepared_payload.words[440] as u32), last_updated: (prepared_payload.words[441] as u64) };
        let new_target_arrival_artifact_locations: [ArtifactLocation; 20] = [ArtifactLocation { planet_id: prepared_payload.words[442], voyage_id: prepared_payload.words[443], last_updated: (prepared_payload.words[444] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[445], voyage_id: prepared_payload.words[446], last_updated: (prepared_payload.words[447] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[448], voyage_id: prepared_payload.words[449], last_updated: (prepared_payload.words[450] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[451], voyage_id: prepared_payload.words[452], last_updated: (prepared_payload.words[453] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[454], voyage_id: prepared_payload.words[455], last_updated: (prepared_payload.words[456] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[457], voyage_id: prepared_payload.words[458], last_updated: (prepared_payload.words[459] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[460], voyage_id: prepared_payload.words[461], last_updated: (prepared_payload.words[462] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[463], voyage_id: prepared_payload.words[464], last_updated: (prepared_payload.words[465] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[466], voyage_id: prepared_payload.words[467], last_updated: (prepared_payload.words[468] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[469], voyage_id: prepared_payload.words[470], last_updated: (prepared_payload.words[471] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[472], voyage_id: prepared_payload.words[473], last_updated: (prepared_payload.words[474] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[475], voyage_id: prepared_payload.words[476], last_updated: (prepared_payload.words[477] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[478], voyage_id: prepared_payload.words[479], last_updated: (prepared_payload.words[480] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[481], voyage_id: prepared_payload.words[482], last_updated: (prepared_payload.words[483] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[484], voyage_id: prepared_payload.words[485], last_updated: (prepared_payload.words[486] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[487], voyage_id: prepared_payload.words[488], last_updated: (prepared_payload.words[489] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[490], voyage_id: prepared_payload.words[491], last_updated: (prepared_payload.words[492] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[493], voyage_id: prepared_payload.words[494], last_updated: (prepared_payload.words[495] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[496], voyage_id: prepared_payload.words[497], last_updated: (prepared_payload.words[498] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[499], voyage_id: prepared_payload.words[500], last_updated: (prepared_payload.words[501] as u64) }];
        let new_arrival_input: Arrival = Arrival { id: prepared_payload.words[502], player: AztecAddress::from_field(prepared_payload.words[503]), from_planet: prepared_payload.words[504], to_planet: prepared_payload.words[505], pop_arriving: (prepared_payload.words[506] as u128), silver_moved: (prepared_payload.words[507] as u128), departure_time: (prepared_payload.words[508] as u64), arrival_time: (prepared_payload.words[509] as u64), arrival_type: (prepared_payload.words[510] as u8), carried_artifact_id: prepared_payload.words[511], distance: (prepared_payload.words[512] as u128) };
        let new_moved_artifact_location_input: ArtifactLocation = ArtifactLocation { planet_id: prepared_payload.words[513], voyage_id: prepared_payload.words[514], last_updated: (prepared_payload.words[515] as u64) };
        let new_source_activated_artifact: Artifact = Artifact { planet_discovered_on: prepared_payload.words[516], rarity: (prepared_payload.words[517] as u8), planet_biome: (prepared_payload.words[518] as u8), minted_at_timestamp: (prepared_payload.words[519] as u64), discoverer: AztecAddress::from_field(prepared_payload.words[520]), artifact_type: (prepared_payload.words[521] as u8), activations: (prepared_payload.words[522] as u128), last_activated: (prepared_payload.words[523] as u64), last_deactivated: (prepared_payload.words[524] as u64), wormhole_to: prepared_payload.words[525], owner: AztecAddress::from_field(prepared_payload.words[526]), controller: AztecAddress::from_field(prepared_payload.words[527]), last_updated: (prepared_payload.words[528] as u64) };
        let new_source_activated_artifact_location: ArtifactLocation = ArtifactLocation { planet_id: prepared_payload.words[529], voyage_id: prepared_payload.words[530], last_updated: (prepared_payload.words[531] as u64) };

        _move_public_legacy(
            self.context,
            source_loc,
            target_loc,
            target_level,
            moved_artifact_id,
            source_activated_artifact_id,
            target_activated_artifact_id,
            timestamp,
            config_hashes,
            artifacts_config_hash,
            planet_default_stats_hash,
            source_planet_hash,
            source_planet_artifacts_state_hash,
            source_planet_events_state_hash,
            source_arrival_ids,
            source_arrival_hashes,
            source_arrival_artifact_ids,
            source_arrival_artifact_hashes,
            source_arrival_artifact_location_hashes,
            original_source_arrivals_count,
            target_planet_hash,
            target_planet_artifacts_state_hash,
            target_planet_events_state_hash,
            target_arrival_ids,
            target_arrival_hashes,
            target_arrival_artifact_ids,
            target_arrival_artifact_hashes,
            target_arrival_artifact_location_hashes,
            original_target_arrivals_count,
            world_hash,
            moved_artifact_hash,
            source_activated_artifact_hash,
            target_activated_artifact_hash,
            new_source_planet,
            new_source_planet_artifacts_state,
            new_source_planet_events_state,
            new_source_arrival_artifact_locations,
            new_target_planet,
            new_target_planet_artifacts_state,
            new_target_planet_events_state_input,
            new_target_arrival_artifact_locations,
            new_arrival_input,
            new_moved_artifact_location_input,
            new_source_activated_artifact,
            new_source_activated_artifact_location,
        );

        }
}

    #[external("public")]
    #[only_self]
    fn move_public_empty_prepared(
        prepared_payload: FieldBuffer<337>,
    ) {
        let state_backend_address = self.storage.state_backend.read();
        let mut settled_by_backend = false;
        if state_backend_address != AztecAddress::zero() {
            if ::libs::config_recognition::supports_config(self.storage.config_storage_address.read()) {
                let backend_calldata: [Field; 228] = [
                    comptime {
                    aztec::protocol::abis::function_selector::FunctionSelector::from_signature(
                        "try_settle_move_move_empty(([Field;227]))",
                    ).to_field()
                },
                    (self.storage.config_storage_address.read()).to_field(),
                    (self.storage.world_storage_address.read()).to_field(),
                    (AztecAddress::zero()).to_field(),
                    (self.storage.planet_storage_address.read()).to_field(),
                    (AztecAddress::zero()).to_field(),
                    (self.storage.planet_events_storage_address.read()).to_field(),
                    (self.storage.planet_artifacts_storage_address.read()).to_field(),
                    (self.storage.arrivals_storage_address.read()).to_field(),
                    (self.storage.artifact_storage_address.read()).to_field(),
                    (self.storage.artifact_location_storage_address.read()).to_field(),
                    prepared_payload.words[0],
                    prepared_payload.words[1],
                    prepared_payload.words[2],
                    prepared_payload.words[3],
                    prepared_payload.words[4],
                    prepared_payload.words[5],
                    prepared_payload.words[6],
                    prepared_payload.words[7],
                    prepared_payload.words[8],
                    prepared_payload.words[9],
                    prepared_payload.words[10],
                    prepared_payload.words[11],
                    prepared_payload.words[12],
                    prepared_payload.words[13],
                    prepared_payload.words[14],
                    prepared_payload.words[15],
                    prepared_payload.words[16],
                    prepared_payload.words[17],
                    prepared_payload.words[18],
                    prepared_payload.words[19],
                    prepared_payload.words[20],
                    prepared_payload.words[21],
                    prepared_payload.words[22],
                    prepared_payload.words[23],
                    prepared_payload.words[24],
                    prepared_payload.words[25],
                    prepared_payload.words[26],
                    prepared_payload.words[27],
                    prepared_payload.words[28],
                    prepared_payload.words[29],
                    prepared_payload.words[30],
                    prepared_payload.words[31],
                    prepared_payload.words[32],
                    prepared_payload.words[33],
                    prepared_payload.words[34],
                    prepared_payload.words[35],
                    prepared_payload.words[36],
                    prepared_payload.words[37],
                    prepared_payload.words[38],
                    prepared_payload.words[39],
                    prepared_payload.words[40],
                    prepared_payload.words[41],
                    prepared_payload.words[42],
                    prepared_payload.words[43],
                    prepared_payload.words[44],
                    prepared_payload.words[45],
                    prepared_payload.words[46],
                    prepared_payload.words[47],
                    prepared_payload.words[48],
                    prepared_payload.words[49],
                    prepared_payload.words[50],
                    prepared_payload.words[51],
                    prepared_payload.words[52],
                    prepared_payload.words[53],
                    prepared_payload.words[54],
                    prepared_payload.words[55],
                    prepared_payload.words[56],
                    prepared_payload.words[57],
                    prepared_payload.words[58],
                    prepared_payload.words[59],
                    prepared_payload.words[60],
                    prepared_payload.words[61],
                    prepared_payload.words[62],
                    prepared_payload.words[63],
                    prepared_payload.words[64],
                    prepared_payload.words[65],
                    prepared_payload.words[66],
                    prepared_payload.words[67],
                    prepared_payload.words[68],
                    prepared_payload.words[69],
                    prepared_payload.words[70],
                    prepared_payload.words[71],
                    prepared_payload.words[72],
                    prepared_payload.words[73],
                    prepared_payload.words[74],
                    prepared_payload.words[75],
                    prepared_payload.words[76],
                    prepared_payload.words[77],
                    prepared_payload.words[78],
                    prepared_payload.words[79],
                    prepared_payload.words[80],
                    prepared_payload.words[81],
                    prepared_payload.words[82],
                    prepared_payload.words[83],
                    prepared_payload.words[84],
                    prepared_payload.words[85],
                    prepared_payload.words[86],
                    prepared_payload.words[87],
                    prepared_payload.words[88],
                    prepared_payload.words[89],
                    prepared_payload.words[90],
                    prepared_payload.words[91],
                    prepared_payload.words[92],
                    prepared_payload.words[93],
                    prepared_payload.words[94],
                    prepared_payload.words[95],
                    prepared_payload.words[96],
                    prepared_payload.words[97],
                    prepared_payload.words[98],
                    prepared_payload.words[99],
                    prepared_payload.words[100],
                    prepared_payload.words[101],
                    prepared_payload.words[102],
                    prepared_payload.words[103],
                    prepared_payload.words[104],
                    prepared_payload.words[105],
                    prepared_payload.words[106],
                    prepared_payload.words[107],
                    prepared_payload.words[108],
                    prepared_payload.words[109],
                    prepared_payload.words[110],
                    prepared_payload.words[111],
                    prepared_payload.words[112],
                    prepared_payload.words[113],
                    prepared_payload.words[114],
                    prepared_payload.words[115],
                    prepared_payload.words[116],
                    prepared_payload.words[117],
                    prepared_payload.words[118],
                    prepared_payload.words[119],
                    prepared_payload.words[120],
                    prepared_payload.words[121],
                    prepared_payload.words[122],
                    prepared_payload.words[123],
                    prepared_payload.words[124],
                    prepared_payload.words[125],
                    prepared_payload.words[126],
                    prepared_payload.words[127],
                    prepared_payload.words[128],
                    prepared_payload.words[129],
                    prepared_payload.words[130],
                    prepared_payload.words[131],
                    prepared_payload.words[132],
                    prepared_payload.words[133],
                    prepared_payload.words[134],
                    prepared_payload.words[135],
                    prepared_payload.words[136],
                    prepared_payload.words[137],
                    prepared_payload.words[138],
                    prepared_payload.words[139],
                    prepared_payload.words[140],
                    prepared_payload.words[141],
                    prepared_payload.words[142],
                    prepared_payload.words[143],
                    prepared_payload.words[144],
                    prepared_payload.words[145],
                    prepared_payload.words[146],
                    prepared_payload.words[147],
                    prepared_payload.words[148],
                    prepared_payload.words[149],
                    prepared_payload.words[150],
                    prepared_payload.words[151],
                    prepared_payload.words[152],
                    prepared_payload.words[153],
                    prepared_payload.words[154],
                    prepared_payload.words[155],
                    prepared_payload.words[156],
                    prepared_payload.words[157],
                    prepared_payload.words[158],
                    prepared_payload.words[159],
                    prepared_payload.words[160],
                    prepared_payload.words[161],
                    prepared_payload.words[162],
                    prepared_payload.words[163],
                    prepared_payload.words[164],
                    prepared_payload.words[165],
                    prepared_payload.words[166],
                    prepared_payload.words[167],
                    prepared_payload.words[168],
                    prepared_payload.words[169],
                    prepared_payload.words[170],
                    prepared_payload.words[171],
                    prepared_payload.words[172],
                    prepared_payload.words[173],
                    prepared_payload.words[174],
                    prepared_payload.words[175],
                    prepared_payload.words[176],
                    prepared_payload.words[177],
                    prepared_payload.words[178],
                    prepared_payload.words[179],
                    prepared_payload.words[180],
                    prepared_payload.words[181],
                    prepared_payload.words[182],
                    prepared_payload.words[183],
                    prepared_payload.words[184],
                    prepared_payload.words[185],
                    prepared_payload.words[186],
                    prepared_payload.words[187],
                    prepared_payload.words[188],
                    prepared_payload.words[189],
                    prepared_payload.words[190],
                    prepared_payload.words[191],
                    prepared_payload.words[192],
                    prepared_payload.words[193],
                    prepared_payload.words[194],
                    prepared_payload.words[195],
                    prepared_payload.words[196],
                    prepared_payload.words[197],
                    prepared_payload.words[198],
                    prepared_payload.words[199],
                    prepared_payload.words[200],
                    prepared_payload.words[201],
                    prepared_payload.words[202],
                    prepared_payload.words[203],
                    prepared_payload.words[204],
                    prepared_payload.words[205],
                    prepared_payload.words[206],
                    prepared_payload.words[207],
                    prepared_payload.words[208],
                    prepared_payload.words[209],
                    prepared_payload.words[210],
                    prepared_payload.words[211],
                    prepared_payload.words[212],
                    prepared_payload.words[213],
                    prepared_payload.words[214],
                    prepared_payload.words[215],
                    prepared_payload.words[216],
                ];
                let backend_returns = libs::public_call::call(state_backend_address, backend_calldata);
                settled_by_backend = aztec::protocol::traits::Deserialize::deserialize(backend_returns.as_array());
            }
        }
        if !settled_by_backend {
        let source_loc: Field = prepared_payload.words[0];
        let target_loc: Field = prepared_payload.words[1];
        let target_level: u8 = (prepared_payload.words[2] as u8);
        let moved_artifact_id: Field = prepared_payload.words[3];
        let source_activated_artifact_id: Field = prepared_payload.words[4];
        let target_activated_artifact_id: Field = prepared_payload.words[5];
        let timestamp: u64 = (prepared_payload.words[6] as u64);
        let config_hashes: [Field; 9] = [prepared_payload.words[7], prepared_payload.words[8], prepared_payload.words[9], prepared_payload.words[10], prepared_payload.words[11], prepared_payload.words[12], prepared_payload.words[13], prepared_payload.words[14], prepared_payload.words[15]];
        let artifacts_config_hash: Field = prepared_payload.words[16];
        let planet_default_stats_hash: Field = prepared_payload.words[17];
        let source_planet_hash: Field = prepared_payload.words[18];
        let source_planet_artifacts_state_hash: Field = prepared_payload.words[19];
        let source_planet_events_state_hash: Field = prepared_payload.words[20];
        let target_planet_hash: Field = prepared_payload.words[21];
        let target_planet_artifacts_state_hash: Field = prepared_payload.words[22];
        let target_planet_events_state_hash: Field = prepared_payload.words[23];
        let world_hash: Field = prepared_payload.words[24];
        let moved_artifact_hash: Field = prepared_payload.words[25];
        let source_activated_artifact_hash: Field = prepared_payload.words[26];
        let target_activated_artifact_hash: Field = prepared_payload.words[27];
        let new_source_planet: Planet = Planet { perlin: (prepared_payload.words[28] as u8), created_at: (prepared_payload.words[29] as u64), owner: AztecAddress::from_field(prepared_payload.words[30]), planet_level: (prepared_payload.words[31] as u8), planet_type: (prepared_payload.words[32] as u8), space_type: (prepared_payload.words[33] as u8), is_home_planet: (prepared_payload.words[34] == 1), is_initialized: (prepared_payload.words[35] == 1), destroyed: (prepared_payload.words[36] == 1), invader: AztecAddress::from_field(prepared_payload.words[37]), capturer: AztecAddress::from_field(prepared_payload.words[38]), invade_start_block: (prepared_payload.words[39] as u32), population_cap: (prepared_payload.words[40] as u128), population_growth: (prepared_payload.words[41] as u128), range: (prepared_payload.words[42] as u128), speed: (prepared_payload.words[43] as u128), defense: (prepared_payload.words[44] as u128), silver_cap: (prepared_payload.words[45] as u128), silver_growth: (prepared_payload.words[46] as u128), population: (prepared_payload.words[47] as u128), silver: (prepared_payload.words[48] as u128), upgrade_state_0: (prepared_payload.words[49] as u8), upgrade_state_1: (prepared_payload.words[50] as u8), upgrade_state_2: (prepared_payload.words[51] as u8), last_updated: (prepared_payload.words[52] as u64), pausers: (prepared_payload.words[53] as u128), energy_gro_doublers: (prepared_payload.words[54] as u128), silver_gro_doublers: (prepared_payload.words[55] as u128), hat_level: (prepared_payload.words[56] as u128), space_junk: (prepared_payload.words[57] as u128), has_tried_finding_artifact: (prepared_payload.words[58] == 1), prospected_block_number: (prepared_payload.words[59] as u32) };
        let new_source_planet_artifacts_state: PlanetArtifacts = PlanetArtifacts { ids: [prepared_payload.words[60], prepared_payload.words[61], prepared_payload.words[62], prepared_payload.words[63], prepared_payload.words[64], prepared_payload.words[65], prepared_payload.words[66], prepared_payload.words[67], prepared_payload.words[68], prepared_payload.words[69], prepared_payload.words[70], prepared_payload.words[71], prepared_payload.words[72], prepared_payload.words[73], prepared_payload.words[74], prepared_payload.words[75], prepared_payload.words[76], prepared_payload.words[77], prepared_payload.words[78], prepared_payload.words[79]], count: (prepared_payload.words[80] as u32), last_updated: (prepared_payload.words[81] as u64) };
        let new_source_planet_events_state: PlanetEvents = PlanetEvents { events: [PlanetEventMetadata { id: prepared_payload.words[82] }, PlanetEventMetadata { id: prepared_payload.words[83] }, PlanetEventMetadata { id: prepared_payload.words[84] }, PlanetEventMetadata { id: prepared_payload.words[85] }, PlanetEventMetadata { id: prepared_payload.words[86] }, PlanetEventMetadata { id: prepared_payload.words[87] }, PlanetEventMetadata { id: prepared_payload.words[88] }, PlanetEventMetadata { id: prepared_payload.words[89] }, PlanetEventMetadata { id: prepared_payload.words[90] }, PlanetEventMetadata { id: prepared_payload.words[91] }, PlanetEventMetadata { id: prepared_payload.words[92] }, PlanetEventMetadata { id: prepared_payload.words[93] }, PlanetEventMetadata { id: prepared_payload.words[94] }, PlanetEventMetadata { id: prepared_payload.words[95] }, PlanetEventMetadata { id: prepared_payload.words[96] }, PlanetEventMetadata { id: prepared_payload.words[97] }, PlanetEventMetadata { id: prepared_payload.words[98] }, PlanetEventMetadata { id: prepared_payload.words[99] }, PlanetEventMetadata { id: prepared_payload.words[100] }, PlanetEventMetadata { id: prepared_payload.words[101] }], count: (prepared_payload.words[102] as u32), last_updated: (prepared_payload.words[103] as u64) };
        let new_target_planet: Planet = Planet { perlin: (prepared_payload.words[104] as u8), created_at: (prepared_payload.words[105] as u64), owner: AztecAddress::from_field(prepared_payload.words[106]), planet_level: (prepared_payload.words[107] as u8), planet_type: (prepared_payload.words[108] as u8), space_type: (prepared_payload.words[109] as u8), is_home_planet: (prepared_payload.words[110] == 1), is_initialized: (prepared_payload.words[111] == 1), destroyed: (prepared_payload.words[112] == 1), invader: AztecAddress::from_field(prepared_payload.words[113]), capturer: AztecAddress::from_field(prepared_payload.words[114]), invade_start_block: (prepared_payload.words[115] as u32), population_cap: (prepared_payload.words[116] as u128), population_growth: (prepared_payload.words[117] as u128), range: (prepared_payload.words[118] as u128), speed: (prepared_payload.words[119] as u128), defense: (prepared_payload.words[120] as u128), silver_cap: (prepared_payload.words[121] as u128), silver_growth: (prepared_payload.words[122] as u128), population: (prepared_payload.words[123] as u128), silver: (prepared_payload.words[124] as u128), upgrade_state_0: (prepared_payload.words[125] as u8), upgrade_state_1: (prepared_payload.words[126] as u8), upgrade_state_2: (prepared_payload.words[127] as u8), last_updated: (prepared_payload.words[128] as u64), pausers: (prepared_payload.words[129] as u128), energy_gro_doublers: (prepared_payload.words[130] as u128), silver_gro_doublers: (prepared_payload.words[131] as u128), hat_level: (prepared_payload.words[132] as u128), space_junk: (prepared_payload.words[133] as u128), has_tried_finding_artifact: (prepared_payload.words[134] == 1), prospected_block_number: (prepared_payload.words[135] as u32) };
        let new_target_planet_artifacts_state: PlanetArtifacts = PlanetArtifacts { ids: [prepared_payload.words[136], prepared_payload.words[137], prepared_payload.words[138], prepared_payload.words[139], prepared_payload.words[140], prepared_payload.words[141], prepared_payload.words[142], prepared_payload.words[143], prepared_payload.words[144], prepared_payload.words[145], prepared_payload.words[146], prepared_payload.words[147], prepared_payload.words[148], prepared_payload.words[149], prepared_payload.words[150], prepared_payload.words[151], prepared_payload.words[152], prepared_payload.words[153], prepared_payload.words[154], prepared_payload.words[155]], count: (prepared_payload.words[156] as u32), last_updated: (prepared_payload.words[157] as u64) };
        let new_target_planet_events_state_input: PlanetEvents = PlanetEvents { events: [PlanetEventMetadata { id: prepared_payload.words[158] }, PlanetEventMetadata { id: prepared_payload.words[159] }, PlanetEventMetadata { id: prepared_payload.words[160] }, PlanetEventMetadata { id: prepared_payload.words[161] }, PlanetEventMetadata { id: prepared_payload.words[162] }, PlanetEventMetadata { id: prepared_payload.words[163] }, PlanetEventMetadata { id: prepared_payload.words[164] }, PlanetEventMetadata { id: prepared_payload.words[165] }, PlanetEventMetadata { id: prepared_payload.words[166] }, PlanetEventMetadata { id: prepared_payload.words[167] }, PlanetEventMetadata { id: prepared_payload.words[168] }, PlanetEventMetadata { id: prepared_payload.words[169] }, PlanetEventMetadata { id: prepared_payload.words[170] }, PlanetEventMetadata { id: prepared_payload.words[171] }, PlanetEventMetadata { id: prepared_payload.words[172] }, PlanetEventMetadata { id: prepared_payload.words[173] }, PlanetEventMetadata { id: prepared_payload.words[174] }, PlanetEventMetadata { id: prepared_payload.words[175] }, PlanetEventMetadata { id: prepared_payload.words[176] }, PlanetEventMetadata { id: prepared_payload.words[177] }], count: (prepared_payload.words[178] as u32), last_updated: (prepared_payload.words[179] as u64) };
        let new_arrival_input: Arrival = Arrival { id: prepared_payload.words[180], player: AztecAddress::from_field(prepared_payload.words[181]), from_planet: prepared_payload.words[182], to_planet: prepared_payload.words[183], pop_arriving: (prepared_payload.words[184] as u128), silver_moved: (prepared_payload.words[185] as u128), departure_time: (prepared_payload.words[186] as u64), arrival_time: (prepared_payload.words[187] as u64), arrival_type: (prepared_payload.words[188] as u8), carried_artifact_id: prepared_payload.words[189], distance: (prepared_payload.words[190] as u128) };
        let new_moved_artifact_location_input: ArtifactLocation = ArtifactLocation { planet_id: prepared_payload.words[191], voyage_id: prepared_payload.words[192], last_updated: (prepared_payload.words[193] as u64) };
        let new_source_activated_artifact: Artifact = Artifact { planet_discovered_on: prepared_payload.words[194], rarity: (prepared_payload.words[195] as u8), planet_biome: (prepared_payload.words[196] as u8), minted_at_timestamp: (prepared_payload.words[197] as u64), discoverer: AztecAddress::from_field(prepared_payload.words[198]), artifact_type: (prepared_payload.words[199] as u8), activations: (prepared_payload.words[200] as u128), last_activated: (prepared_payload.words[201] as u64), last_deactivated: (prepared_payload.words[202] as u64), wormhole_to: prepared_payload.words[203], owner: AztecAddress::from_field(prepared_payload.words[204]), controller: AztecAddress::from_field(prepared_payload.words[205]), last_updated: (prepared_payload.words[206] as u64) };
        let new_source_activated_artifact_location: ArtifactLocation = ArtifactLocation { planet_id: prepared_payload.words[207], voyage_id: prepared_payload.words[208], last_updated: (prepared_payload.words[209] as u64) };

            let source_arrival_ids: [Field; 20] = [0; 20];
            let source_arrival_hashes: [Field; 20] = [0; 20];
            let source_arrival_artifact_ids: [Field; 20] = [0; 20];
            let source_arrival_artifact_hashes: [Field; 20] = [0; 20];
            let source_arrival_artifact_location_hashes: [Field; 20] = [0; 20];
            let original_source_arrivals_count: u32 = 0;
            let target_arrival_ids: [Field; 20] = [0; 20];
            let target_arrival_hashes: [Field; 20] = [0; 20];
            let target_arrival_artifact_ids: [Field; 20] = [0; 20];
            let target_arrival_artifact_hashes: [Field; 20] = [0; 20];
            let target_arrival_artifact_location_hashes: [Field; 20] = [0; 20];
            let original_target_arrivals_count: u32 = 0;
            let new_source_arrival_artifact_locations: [ArtifactLocation; 20] = [ArtifactLocation { planet_id: prepared_payload.words[217], voyage_id: prepared_payload.words[218], last_updated: (prepared_payload.words[219] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[220], voyage_id: prepared_payload.words[221], last_updated: (prepared_payload.words[222] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[223], voyage_id: prepared_payload.words[224], last_updated: (prepared_payload.words[225] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[226], voyage_id: prepared_payload.words[227], last_updated: (prepared_payload.words[228] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[229], voyage_id: prepared_payload.words[230], last_updated: (prepared_payload.words[231] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[232], voyage_id: prepared_payload.words[233], last_updated: (prepared_payload.words[234] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[235], voyage_id: prepared_payload.words[236], last_updated: (prepared_payload.words[237] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[238], voyage_id: prepared_payload.words[239], last_updated: (prepared_payload.words[240] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[241], voyage_id: prepared_payload.words[242], last_updated: (prepared_payload.words[243] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[244], voyage_id: prepared_payload.words[245], last_updated: (prepared_payload.words[246] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[247], voyage_id: prepared_payload.words[248], last_updated: (prepared_payload.words[249] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[250], voyage_id: prepared_payload.words[251], last_updated: (prepared_payload.words[252] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[253], voyage_id: prepared_payload.words[254], last_updated: (prepared_payload.words[255] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[256], voyage_id: prepared_payload.words[257], last_updated: (prepared_payload.words[258] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[259], voyage_id: prepared_payload.words[260], last_updated: (prepared_payload.words[261] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[262], voyage_id: prepared_payload.words[263], last_updated: (prepared_payload.words[264] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[265], voyage_id: prepared_payload.words[266], last_updated: (prepared_payload.words[267] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[268], voyage_id: prepared_payload.words[269], last_updated: (prepared_payload.words[270] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[271], voyage_id: prepared_payload.words[272], last_updated: (prepared_payload.words[273] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[274], voyage_id: prepared_payload.words[275], last_updated: (prepared_payload.words[276] as u64) }];
            let new_target_arrival_artifact_locations: [ArtifactLocation; 20] = [ArtifactLocation { planet_id: prepared_payload.words[277], voyage_id: prepared_payload.words[278], last_updated: (prepared_payload.words[279] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[280], voyage_id: prepared_payload.words[281], last_updated: (prepared_payload.words[282] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[283], voyage_id: prepared_payload.words[284], last_updated: (prepared_payload.words[285] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[286], voyage_id: prepared_payload.words[287], last_updated: (prepared_payload.words[288] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[289], voyage_id: prepared_payload.words[290], last_updated: (prepared_payload.words[291] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[292], voyage_id: prepared_payload.words[293], last_updated: (prepared_payload.words[294] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[295], voyage_id: prepared_payload.words[296], last_updated: (prepared_payload.words[297] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[298], voyage_id: prepared_payload.words[299], last_updated: (prepared_payload.words[300] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[301], voyage_id: prepared_payload.words[302], last_updated: (prepared_payload.words[303] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[304], voyage_id: prepared_payload.words[305], last_updated: (prepared_payload.words[306] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[307], voyage_id: prepared_payload.words[308], last_updated: (prepared_payload.words[309] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[310], voyage_id: prepared_payload.words[311], last_updated: (prepared_payload.words[312] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[313], voyage_id: prepared_payload.words[314], last_updated: (prepared_payload.words[315] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[316], voyage_id: prepared_payload.words[317], last_updated: (prepared_payload.words[318] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[319], voyage_id: prepared_payload.words[320], last_updated: (prepared_payload.words[321] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[322], voyage_id: prepared_payload.words[323], last_updated: (prepared_payload.words[324] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[325], voyage_id: prepared_payload.words[326], last_updated: (prepared_payload.words[327] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[328], voyage_id: prepared_payload.words[329], last_updated: (prepared_payload.words[330] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[331], voyage_id: prepared_payload.words[332], last_updated: (prepared_payload.words[333] as u64) }, ArtifactLocation { planet_id: prepared_payload.words[334], voyage_id: prepared_payload.words[335], last_updated: (prepared_payload.words[336] as u64) }];

        _move_public_legacy(
            self.context,
            source_loc,
            target_loc,
            target_level,
            moved_artifact_id,
            source_activated_artifact_id,
            target_activated_artifact_id,
            timestamp,
            config_hashes,
            artifacts_config_hash,
            planet_default_stats_hash,
            source_planet_hash,
            source_planet_artifacts_state_hash,
            source_planet_events_state_hash,
            source_arrival_ids,
            source_arrival_hashes,
            source_arrival_artifact_ids,
            source_arrival_artifact_hashes,
            source_arrival_artifact_location_hashes,
            original_source_arrivals_count,
            target_planet_hash,
            target_planet_artifacts_state_hash,
            target_planet_events_state_hash,
            target_arrival_ids,
            target_arrival_hashes,
            target_arrival_artifact_ids,
            target_arrival_artifact_hashes,
            target_arrival_artifact_location_hashes,
            original_target_arrivals_count,
            world_hash,
            moved_artifact_hash,
            source_activated_artifact_hash,
            target_activated_artifact_hash,
            new_source_planet,
            new_source_planet_artifacts_state,
            new_source_planet_events_state,
            new_source_arrival_artifact_locations,
            new_target_planet,
            new_target_planet_artifacts_state,
            new_target_planet_events_state_input,
            new_target_arrival_artifact_locations,
            new_arrival_input,
            new_moved_artifact_location_input,
            new_source_activated_artifact,
            new_source_activated_artifact_location,
        );

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


    #[inline_never]
    #[contract_library_method]
    unconstrained fn _move_public_legacy(
        context: aztec::context::PublicContext,
        source_loc: Field,
        target_loc: Field,
        target_level: u8,
        moved_artifact_id: Field,
        source_activated_artifact_id: Field,
        target_activated_artifact_id: Field,
        timestamp: u64,
        config_hashes: [Field; 9],
        artifacts_config_hash: Field,
        planet_default_stats_hash: Field,
        source_planet_hash: Field,
        source_planet_artifacts_state_hash: Field,
        source_planet_events_state_hash: Field,
        source_arrival_ids: [Field; 20],
        source_arrival_hashes: [Field; 20],
        source_arrival_artifact_ids: [Field; 20],
        source_arrival_artifact_hashes: [Field; 20],
        source_arrival_artifact_location_hashes: [Field; 20],
        original_source_arrivals_count: u32,
        target_planet_hash: Field,
        target_planet_artifacts_state_hash: Field,
        target_planet_events_state_hash: Field,
        target_arrival_ids: [Field; 20],
        target_arrival_hashes: [Field; 20],
        target_arrival_artifact_ids: [Field; 20],
        target_arrival_artifact_hashes: [Field; 20],
        target_arrival_artifact_location_hashes: [Field; 20],
        original_target_arrivals_count: u32,
        world_hash: Field,
        moved_artifact_hash: Field,
        source_activated_artifact_hash: Field,
        target_activated_artifact_hash: Field,
        new_source_planet: Planet,
        new_source_planet_artifacts_state: PlanetArtifacts,
        new_source_planet_events_state: PlanetEvents,
        new_source_arrival_artifact_locations: [ArtifactLocation; 20],
        new_target_planet: Planet,
        new_target_planet_artifacts_state: PlanetArtifacts,
        new_target_planet_events_state_input: PlanetEvents,
        new_target_arrival_artifact_locations: [ArtifactLocation; 20],
        new_arrival_input: Arrival,
        new_moved_artifact_location_input: ArtifactLocation,
        new_source_activated_artifact: Artifact,
        new_source_activated_artifact_location: ArtifactLocation,
    ) {
        let mut self = __aztec_nr_internals__create_public_self_from_context(context);
        let mut new_target_planet_events_state = new_target_planet_events_state_input;
        let mut new_arrival = new_arrival_input;
        let mut new_moved_artifact_location = new_moved_artifact_location_input;

        // Verify timestamp
        let actual_timestamp = self.context.timestamp();
        assert_public_timestamp(timestamp, actual_timestamp);

        let config = Config::at(self.storage.config_storage_address.read());
        let world_storage = WorldStorage::at(self.storage.world_storage_address.read());
        let planet_storage = PlanetStorage::at(self.storage.planet_storage_address.read());
        let planet_events_storage =
            PlanetEventsStorage::at(self.storage.planet_events_storage_address.read());
        let planet_artifacts_storage =
            PlanetArtifactsStorage::at(self.storage.planet_artifacts_storage_address.read());
        let arrivals_storage = ArrivalStorage::at(self.storage.arrivals_storage_address.read());
        let artifact_location_storage =
            ArtifactLocationStorage::at(self.storage.artifact_location_storage_address.read());
        let artifact_storage = ArtifactStorage::at(self.storage.artifact_storage_address.read());

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

        // Verify source planet state hashes
        assert(
            self.view(planet_storage.verify_hash(source_loc, source_planet_hash)),
            "Source planet hash mismatch",
        );

        assert(
            self.view(planet_artifacts_storage.verify_hash(
                source_loc,
                source_planet_artifacts_state_hash,
            )),
            "Source planet artifacts hash mismatch",
        );

        assert(
            self.view(planet_events_storage.verify_hash(source_loc, source_planet_events_state_hash)),
            "Source planet events hash mismatch",
        );

        assert(
            self.view(arrivals_storage.verify_hashes_batch(
                source_arrival_ids,
                source_arrival_hashes,
                original_source_arrivals_count,
            )),
            "Source arrival hash mismatch",
        );
        assert(
            self.view(artifact_storage.verify_hashes_batch(
                source_arrival_artifact_ids,
                source_arrival_artifact_hashes,
                original_source_arrivals_count,
            )),
            "Source artifact hash mismatch",
        );
        assert(
            self.view(artifact_location_storage.verify_hashes_batch(
                source_arrival_artifact_ids,
                source_arrival_artifact_location_hashes,
                original_source_arrivals_count,
            )),
            "Source artifact location hash mismatch",
        );

        // Verify target planet state hashes
        assert(
            self.view(planet_storage.verify_hash(target_loc, target_planet_hash)),
            "Target planet hash mismatch",
        );

        assert(
            self.view(planet_artifacts_storage.verify_hash(
                target_loc,
                target_planet_artifacts_state_hash,
            )),
            "Target planet artifacts hash mismatch",
        );

        assert(
            self.view(planet_events_storage.verify_hash(target_loc, target_planet_events_state_hash)),
            "Target planet events hash mismatch",
        );

        // Batch verify target arrivals, artifacts, artifact_locations (3 calls instead of 60)
        assert(
            self.view(arrivals_storage.verify_hashes_batch(
                target_arrival_ids,
                target_arrival_hashes,
                original_target_arrivals_count,
            )),
            "Target arrival hash mismatch",
        );

        assert(
            self.view(artifact_storage.verify_hashes_batch(
                target_arrival_artifact_ids,
                target_arrival_artifact_hashes,
                original_target_arrivals_count,
            )),
            "Target artifact hash mismatch",
        );

        assert(
            self.view(artifact_location_storage.verify_hashes_batch(
                target_arrival_artifact_ids,
                target_arrival_artifact_location_hashes,
                original_target_arrivals_count,
            )),
            "Target artifact location hash mismatch",
        );

        // Verify world, moved artifact, and activated artifact hashes
        assert(self.view(world_storage.verify_hash(0, world_hash)), "World hash mismatch");

        assert(
            self.view(artifact_storage.verify_hash(moved_artifact_id, moved_artifact_hash)),
            "Moved artifact hash mismatch",
        );

        assert(
            self.view(artifact_storage.verify_hash(
                source_activated_artifact_id,
                source_activated_artifact_hash,
            )),
            "Activated artifact hash mismatch",
        );

        assert(
            self.view(artifact_storage.verify_hash(
                target_activated_artifact_id,
                target_activated_artifact_hash,
            )),
            "Target activated artifact hash mismatch",
        );

        // Allocate a unique event ID from the atomic counter in ArrivalStorage,
        // then patch the placeholder IDs in arrival, planet events, and artifact location.
        let event_id: Field = self.call(arrivals_storage.allocate_event_id());
        new_arrival.id = event_id;

        // Patch the last event in target planet events (the one just added in private)
        assert(new_target_planet_events_state.count > 0, "Expected at least one planet event");
        new_target_planet_events_state.events[new_target_planet_events_state.count - 1].id =
            event_id;

        if moved_artifact_id != 0 {
            new_moved_artifact_location.voyage_id = event_id;
        }

        // Write new states to storage
        self.call(planet_storage.set(source_loc, new_source_planet));
        self.call(planet_artifacts_storage.set(source_loc, new_source_planet_artifacts_state));
        self.call(planet_events_storage.set(source_loc, new_source_planet_events_state));

        // Batch write source arrival artifact locations (1 call instead of up to 20)
        self.call(artifact_location_storage.set_arrival_locations_max20(
            source_arrival_artifact_ids,
            new_source_arrival_artifact_locations,
            original_source_arrivals_count,
        ));

        self.call(planet_storage.set(target_loc, new_target_planet));
        self.call(planet_artifacts_storage.set(target_loc, new_target_planet_artifacts_state));
        self.call(planet_events_storage.set(target_loc, new_target_planet_events_state));

        // Batch write target arrival artifact locations (1 call instead of up to 20)
        self.call(artifact_location_storage.set_arrival_locations_max20(
            target_arrival_artifact_ids,
            new_target_arrival_artifact_locations,
            original_target_arrivals_count,
        ));

        self.call(arrivals_storage.set(new_arrival.id, new_arrival));

        if moved_artifact_id != 0 {
            self.call(artifact_location_storage.set(moved_artifact_id, new_moved_artifact_location));
        }

        // Write back deactivated/burned source activated artifact
        if source_activated_artifact_id != 0 {
            self.call(artifact_storage.set(
                source_activated_artifact_id,
                new_source_activated_artifact,
            ));

            // PhotoidCannon and PlanetaryShield are burned on deactivation
            let is_burn_type = (
                new_source_activated_artifact.artifact_type == ArtifactType::PhotoidCannon
            )
                | (new_source_activated_artifact.artifact_type == ArtifactType::PlanetaryShield);

            let was_deactivated = new_source_activated_artifact.last_deactivated
                >= new_source_activated_artifact.last_activated;
            if is_burn_type & was_deactivated {
                self.call(artifact_location_storage.set(
                    source_activated_artifact_id,
                    new_source_activated_artifact_location,
                ));
            }
        }
    }
}
