// Generated from original public continuations. Do not edit by hand.
// Required masks use [config, world, player, planet, coords, events, planet_artifacts, arrival, artifact, location].

    #[external("public")]
    fn try_settle_core_refresh_planet(
        addresses: [AztecAddress; 10],
        location: Field,
        timestamp: u64,
        planet_state_hash: Field,
        planet_artifacts_state_hash: Field,
        planet_events_state_hash: Field,
        original_arrivals_count: u32,
        arrival_ids: [Field; 20],
        arrival_hashes: [Field; 20],
        arrival_artifact_ids: [Field; 20],
        arrival_artifact_hashes: [Field; 20],
        arrival_artifact_location_hashes: [Field; 20],
        new_planet: Planet,
        new_planet_artifacts_state: PlanetArtifacts,
        new_planet_events_state: PlanetEvents,
        new_arrival_artifact_locations: [ArtifactLocation; 20],
        prepared_new_planet_root: Field,
        prepared_new_planet_artifacts_state_root: Field,
        prepared_new_planet_events_state_root: Field,
    ) -> bool {
        if self.internal._can_settle(addresses, 1000) {
            let actor = self.msg_sender();

            let actual_timestamp = self.context.timestamp();
            assert_public_timestamp(timestamp, actual_timestamp);

            
            
            
            
            
            

            assert(
                self.internal._verify_hash(addresses[3], location, planet_state_hash),
                "Planet state hash mismatch",
            );
            assert(
                self.internal._verify_hash(addresses[6], location, planet_artifacts_state_hash),
                "Planet artifacts state hash mismatch",
            );
            assert(
                self.internal._verify_hash(addresses[5], location, planet_events_state_hash),
                "Planet events state hash mismatch",
            );

            if original_arrivals_count != 0 {
                assert(
                    self.internal._verify_hashes_batch(addresses[7], arrival_ids, arrival_hashes, original_arrivals_count),
                    "Arrival hash mismatch",
                );
                if ::libs::batch_utils::has_nonzero_ids(arrival_artifact_ids, original_arrivals_count) {
                    assert(
                        self.internal._verify_hashes_batch(addresses[8], arrival_artifact_ids, arrival_artifact_hashes, original_arrivals_count),
                        "Artifact hash mismatch",
                    );

                    assert(
                        self.internal._verify_hashes_batch(addresses[9], arrival_artifact_ids, arrival_artifact_location_hashes, original_arrivals_count),
                        "Artifact location hash mismatch",
                    );
                }
            }

            self.internal._set_planet(addresses[3], actor, location, new_planet, prepared_new_planet_root, true);
            self.internal._set_planet_artifacts(addresses[6], actor, location, new_planet_artifacts_state, prepared_new_planet_artifacts_state_root, true);
            self.internal._set_planet_events(addresses[5], actor, location, new_planet_events_state, prepared_new_planet_events_state_root, true);
            self.internal._set_arrival_locations_max20(addresses[9], actor, arrival_artifact_ids, new_arrival_artifact_locations, original_arrivals_count);
        
            true
        } else {
            false
        }
    }

    #[external("public")]
    fn try_settle_core_upgrade_planet(
        addresses: [AztecAddress; 10],
        location: Field,
        sender: AztecAddress,
        branch: u8,
        current_branch_level: u8,
        timestamp: u64,
        planet_state_hash: Field,
        planet_artifacts_state_hash: Field,
        planet_events_state_hash: Field,
        original_arrivals_count: u32,
        arrival_ids: [Field; 20],
        arrival_hashes: [Field; 20],
        arrival_artifact_ids: [Field; 20],
        arrival_artifact_hashes: [Field; 20],
        arrival_artifact_location_hashes: [Field; 20],
        upgrade_config_hash: Field,
        upgrade_hash: Field,
        world_hash: Field,
        new_planet: Planet,
        new_planet_events_state: PlanetEvents,
        new_planet_artifacts_state: PlanetArtifacts,
        new_arrival_artifact_locations: [ArtifactLocation; 20],
        prepared_new_planet_root: Field,
        prepared_new_planet_events_state_root: Field,
        prepared_new_planet_artifacts_state_root: Field,
    ) -> bool {
        if self.internal._can_settle(addresses, 1002) {
            let actor = self.msg_sender();

            let actual_timestamp = self.context.timestamp();
            assert_public_timestamp(timestamp, actual_timestamp);

            let config = Config::at(addresses[0]);
            
            
            
            
            
            
            

            assert(
                self.internal._verify_hash(addresses[3], location, planet_state_hash),
                "Planet state hash mismatch",
            );
            assert(
                self.internal._verify_hash(addresses[6], location, planet_artifacts_state_hash),
                "Planet artifacts state hash mismatch",
            );
            assert(
                self.internal._verify_hash(addresses[5], location, planet_events_state_hash),
                "Planet events state hash mismatch",
            );

            if original_arrivals_count != 0 {
                assert(
                    self.internal._verify_hashes_batch(addresses[7], arrival_ids, arrival_hashes, original_arrivals_count),
                    "Arrival hash mismatch",
                );
                if ::libs::batch_utils::has_nonzero_ids(arrival_artifact_ids, original_arrivals_count) {
                    assert(
                        self.internal._verify_hashes_batch(addresses[8], arrival_artifact_ids, arrival_artifact_hashes, original_arrivals_count),
                        "Artifact hash mismatch",
                    );

                    assert(
                        self.internal._verify_hashes_batch(addresses[9], arrival_artifact_ids, arrival_artifact_location_hashes, original_arrivals_count),
                        "Artifact location hash mismatch",
                    );
                }
            }

            assert(
                self.view(config.verify_upgrade_config_hash(upgrade_config_hash)),
                "Upgrade config hash mismatch",
            );

            assert(
                self.view(config.verify_upgrade_hash_by_branch_level(
                    branch as u128,
                    current_branch_level as u128,
                    upgrade_hash,
                )),
                "Upgrade hash mismatch",
            );

            assert(self.internal._verify_hash(addresses[1], 0, world_hash), "World state hash mismatch");

            assert(new_planet.owner == sender, "Planet owner mismatch");
            self.internal._set_planet(addresses[3], actor, location, new_planet, prepared_new_planet_root, true);
            self.internal._set_planet_events(addresses[5], actor, location, new_planet_events_state, prepared_new_planet_events_state_root, true);
            self.internal._set_planet_artifacts(addresses[6], actor, location, new_planet_artifacts_state, prepared_new_planet_artifacts_state_root, true);
            self.internal._set_arrival_locations_max20(addresses[9], actor, arrival_artifact_ids, new_arrival_artifact_locations, original_arrivals_count);
        
            true
        } else {
            false
        }
    }

    #[external("public")]
    fn try_settle_core_withdraw_silver(
        addresses: [AztecAddress; 10],
        location: Field,
        sender: AztecAddress,
        timestamp: u64,
        planet_state_hash: Field,
        planet_artifacts_state_hash: Field,
        planet_events_state_hash: Field,
        original_arrivals_count: u32,
        arrival_ids: [Field; 20],
        arrival_hashes: [Field; 20],
        arrival_artifact_ids: [Field; 20],
        arrival_artifact_hashes: [Field; 20],
        arrival_artifact_location_hashes: [Field; 20],
        player_state_hash: Field,
        world_config_hash: Field,
        world_hash: Field,
        new_planet: Planet,
        new_planet_events_state: PlanetEvents,
        new_planet_artifacts_state: PlanetArtifacts,
        new_arrival_artifact_locations: [ArtifactLocation; 20],
        new_player: Player,
        prepared_new_planet_root: Field,
        prepared_new_planet_events_state_root: Field,
        prepared_new_planet_artifacts_state_root: Field,
        prepared_new_player_root: Field,
    ) -> bool {
        if self.internal._can_settle(addresses, 1006) {
            let actor = self.msg_sender();

            let actual_timestamp = self.context.timestamp();
            assert_public_timestamp(timestamp, actual_timestamp);

            let config = Config::at(addresses[0]);
            
            
            
            
            
            
            
            

            assert(
                self.view(config.verify_world_config_hash(world_config_hash)),
                "World config hash mismatch",
            );

            assert(
                self.internal._verify_hash(addresses[3], location, planet_state_hash),
                "Planet state hash mismatch",
            );
            assert(
                self.internal._verify_hash(addresses[6], location, planet_artifacts_state_hash),
                "Planet artifacts state hash mismatch",
            );
            assert(
                self.internal._verify_hash(addresses[5], location, planet_events_state_hash),
                "Planet events state hash mismatch",
            );

            if original_arrivals_count != 0 {
                assert(
                    self.internal._verify_hashes_batch(addresses[7], arrival_ids, arrival_hashes, original_arrivals_count),
                    "Arrival hash mismatch",
                );
                if ::libs::batch_utils::has_nonzero_ids(arrival_artifact_ids, original_arrivals_count) {
                    assert(
                        self.internal._verify_hashes_batch(addresses[8], arrival_artifact_ids, arrival_artifact_hashes, original_arrivals_count),
                        "Artifact hash mismatch",
                    );

                    assert(
                        self.internal._verify_hashes_batch(addresses[9], arrival_artifact_ids, arrival_artifact_location_hashes, original_arrivals_count),
                        "Artifact location hash mismatch",
                    );
                }
            }

            assert(
                self.internal._verify_hash(addresses[2], (sender).to_field(), player_state_hash),
                "Player state hash mismatch",
            );

            assert(self.internal._verify_hash(addresses[1], 0, world_hash), "World state hash mismatch");

            self.internal._set_planet(addresses[3], actor, location, new_planet, prepared_new_planet_root, true);
            self.internal._set_planet_events(addresses[5], actor, location, new_planet_events_state, prepared_new_planet_events_state_root, true);
            self.internal._set_planet_artifacts(addresses[6], actor, location, new_planet_artifacts_state, prepared_new_planet_artifacts_state_root, true);
            self.internal._set_arrival_locations_max20(addresses[9], actor, arrival_artifact_ids, new_arrival_artifact_locations, original_arrivals_count);
            self.internal._set_player(addresses[2], actor, (sender).to_field(), new_player, prepared_new_player_root, true);
        
            true
        } else {
            false
        }
    }

    #[external("public")]
    fn try_settle_core_reveal_location(
        addresses: [AztecAddress; 10],
        location: Field,
        sender: AztecAddress,
        timestamp: u64,
        is_admin: bool,
        config_hashes: [Field; 9],
        planet_default_stats_hash: Field,
        planet_state_hash: Field,
        planet_revealed_coords_hash: Field,
        player_state_hash: Field,
        world_hash: Field,
        new_planet: Planet,
        new_planet_revealed_coords: PlanetRevealedCoords,
        new_player_state: Player,
        prepared_new_planet_root: Field,
        prepared_new_planet_revealed_coords_root: Field,
        prepared_new_player_state_root: Field,
    ) -> bool {
        if self.internal._can_settle(addresses, 30) {
            let actor = self.msg_sender();

            let actual_timestamp = self.context.timestamp();
            assert_public_timestamp(timestamp, actual_timestamp);

            if is_admin {
                assert(sender == self.internal._get_system_admin(actor), "Only admin can bypass cooldown");
            }

            let config = Config::at(addresses[0]);
            
            
            
            

            assert(
                self.view(config.verify_config_hashes(
                    new_planet.planet_level,
                    planet_default_stats_hash,
                    config_hashes,
                )),
                "Config hash mismatch",
            );

            if planet_state_hash != 0 {
                assert(
                    self.internal._verify_hash(addresses[3], location, planet_state_hash),
                    "Planet state hash mismatch",
                );
            }

            assert(
                !self.internal._is_initialized(addresses[4], location),
                "Planet already revealed",
            );

            assert(player_state_hash != 0, "Player state must be initialized");
            assert(
                self.internal._verify_hash(addresses[2], (sender).to_field(), player_state_hash),
                "Player state hash mismatch",
            );

            assert(world_hash != 0, "World state must be initialized");
            assert(self.internal._verify_hash(addresses[1], 0, world_hash), "World state hash mismatch");

            self.internal._set_planet(addresses[3], actor, location, new_planet, prepared_new_planet_root, true);
            self.internal._set_planet_revealed_coords(addresses[4], actor, location, new_planet_revealed_coords, prepared_new_planet_revealed_coords_root, true);
            self.internal._set_player(addresses[2], actor, (sender).to_field(), new_player_state, prepared_new_player_state_root, true);
        
            true
        } else {
            false
        }
    }

    #[external("public")]
    fn try_settle_core_initialize_player(
        addresses: [AztecAddress; 10],
        sender: AztecAddress,
        location_id: Field,
        timestamp: u64,
        config_hashes: [Field; 9],
        planet_default_stats_hash: Field,
        planet_state_hash: Field,
        planet_artifacts_state_hash: Field,
        planet_events_state_hash: Field,
        original_arrivals_count: u32,
        arrival_ids: [Field; 20],
        arrival_hashes: [Field; 20],
        arrival_artifact_ids: [Field; 20],
        arrival_artifact_hashes: [Field; 20],
        arrival_artifact_location_hashes: [Field; 20],
        player_state_hash: Field,
        world_hash: Field,
        new_planet: Planet,
        new_planet_events_state: PlanetEvents,
        new_planet_artifacts_state: PlanetArtifacts,
        new_arrival_artifact_locations: [ArtifactLocation; 20],
        new_player: Player,
        prepared_new_planet_root: Field,
        prepared_new_planet_events_state_root: Field,
        prepared_new_planet_artifacts_state_root: Field,
        prepared_new_player_root: Field,
    ) -> bool {
        if self.internal._can_settle(addresses, 1006) {
            let actor = self.msg_sender();

            let actual_timestamp = self.context.timestamp();
            assert_public_timestamp(timestamp, actual_timestamp);

            let config = Config::at(addresses[0]);
            
            
            

            // Verify config hashes
            assert(
                self.view(config.verify_config_hashes(
                    new_planet.planet_level,
                    planet_default_stats_hash,
                    config_hashes,
                )),
                "Config hash mismatch",
            );

            // Verify player not yet initialized
            assert(!self.internal._is_initialized(addresses[2], (sender).to_field()), "Player already initialized");

            // Verify world state
            assert(world_hash != 0, "World state must be initialized");
            assert(self.internal._verify_hash(addresses[1], 0, world_hash), "World state hash mismatch");

            // Planet: verify hashes and write states
            if planet_state_hash == 0 {
                // New planet - just write it
                self.internal._set_planet(addresses[3], actor, location_id, new_planet, prepared_new_planet_root, true);
            } else {
                // Existing planet - verify all hashes then write refreshed states
                
                
                
                
                

                assert(
                    self.internal._verify_hash(addresses[3], location_id, planet_state_hash),
                    "Planet state hash mismatch",
                );
                assert(
                    self.internal._verify_hash(addresses[6], location_id, planet_artifacts_state_hash),
                    "Planet artifacts state hash mismatch",
                );
                assert(
                    self.internal._verify_hash(addresses[5], location_id, planet_events_state_hash),
                    "Planet events state hash mismatch",
                );
                if original_arrivals_count != 0 {
                    assert(
                        self.internal._verify_hashes_batch(addresses[7], arrival_ids, arrival_hashes, original_arrivals_count),
                        "Arrival hash mismatch",
                    );
                    if ::libs::batch_utils::has_nonzero_ids(
                        arrival_artifact_ids,
                        original_arrivals_count,
                    ) {
                        assert(
                            self.internal._verify_hashes_batch(addresses[8], arrival_artifact_ids, arrival_artifact_hashes, original_arrivals_count),
                            "Artifact hash mismatch",
                        );

                        assert(
                            self.internal._verify_hashes_batch(addresses[9], arrival_artifact_ids, arrival_artifact_location_hashes, original_arrivals_count),
                            "Artifact location hash mismatch",
                        );
                    }
                }

                self.internal._set_planet(addresses[3], actor, location_id, new_planet, prepared_new_planet_root, true);
                self.internal._set_planet_events(addresses[5], actor, location_id, new_planet_events_state, prepared_new_planet_events_state_root, true);
                self.internal._set_planet_artifacts(addresses[6], actor, location_id, new_planet_artifacts_state, prepared_new_planet_artifacts_state_root, true);
                self.internal._set_arrival_locations_max20(addresses[9], actor, arrival_artifact_ids, new_arrival_artifact_locations, original_arrivals_count);
            }

            // Write new player
            self.internal._set_player(addresses[2], actor, (sender).to_field(), new_player, prepared_new_player_root, true);
        
            true
        } else {
            false
        }
    }

    #[external("public")]
    fn try_settle_artifact_action_activate_artifact(
        addresses: [AztecAddress; 10],
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
        prepared_new_planet_root: Field,
        prepared_new_planet_events_state_root: Field,
        prepared_new_planet_artifacts_state_root: Field,
        prepared_new_artifact_root: Field,
        prepared_new_artifact_location_root: Field,
    ) -> bool {
        if self.internal._can_settle(addresses, 1002) {
            let actor = self.msg_sender();

            let actual_timestamp = self.context.timestamp();
            assert_public_timestamp(timestamp, actual_timestamp);

            
            
            
            
            
            
            
            let config = Config::at(addresses[0]);

            // Verify planet state hashes
            assert(
                self.internal._verify_hash(addresses[3], location_id, planet_hash),
                "planet hash mismatch",
            );
            assert(
                self.internal._verify_hash(addresses[5], location_id, planet_events_state_hash),
                "planet_events hash mismatch",
            );
            assert(
                self.internal._verify_hash(addresses[6], location_id, planet_artifacts_state_hash),
                "planet_artifacts hash mismatch",
            );

            // Batch verify arrival hashes
            if origin_arrivals_count != 0 {
                assert(
                    self.internal._verify_hashes_batch(addresses[7], arrival_ids, arrival_hashes, origin_arrivals_count),
                    "arrivals hash mismatch",
                );
                if ::libs::batch_utils::has_nonzero_ids(arrival_artifact_ids, origin_arrivals_count) {
                    assert(
                        self.internal._verify_hashes_batch(addresses[8], arrival_artifact_ids, arrival_artifact_hashes, origin_arrivals_count),
                        "arrival artifacts hash mismatch",
                    );

                    assert(
                        self.internal._verify_hashes_batch(addresses[9], arrival_artifact_ids, arrival_artifact_location_hashes, origin_arrivals_count),
                        "arrival artifact locations hash mismatch",
                    );
                }
            }

            // Verify the artifact being activated
            assert(
                self.internal._verify_hash(addresses[8], artifact_id, artifact_hash),
                "artifact hash mismatch",
            );
            assert(
                self.internal._verify_hash(addresses[9], artifact_id, artifact_location_hash),
                "artifact_location hash mismatch",
            );

            // Verify world hash
            assert(self.internal._verify_hash(addresses[1], 0, world_hash), "world hash mismatch");

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
            self.internal._set_planet(addresses[3], actor, location_id, new_planet, prepared_new_planet_root, true);
            self.internal._set_planet_events(addresses[5], actor, location_id, new_planet_events_state, prepared_new_planet_events_state_root, true);
            self.internal._set_planet_artifacts(addresses[6], actor, location_id, new_planet_artifacts_state, prepared_new_planet_artifacts_state_root, true);

            // Batch write changed artifact locations from refresh
            self.internal._set_arrival_locations_max20(addresses[9], actor, change_artifact_location_ids, change_artifact_locations, change_artifact_location_count);

            // Write the activated artifact and its location
            self.internal._set_artifact(addresses[8], actor, artifact_id, new_artifact, prepared_new_artifact_root, true);
            self.internal._set_artifact_location(addresses[9], actor, artifact_id, new_artifact_location, prepared_new_artifact_location_root, true);
        
            true
        } else {
            false
        }
    }

    #[external("public")]
    fn try_settle_artifact_action_deactivate_artifact(
        addresses: [AztecAddress; 10],
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
        prepared_new_planet_root: Field,
        prepared_new_planet_events_state_root: Field,
        prepared_new_planet_artifacts_state_root: Field,
        prepared_new_artifact_root: Field,
        prepared_new_artifact_location_root: Field,
    ) -> bool {
        if self.internal._can_settle(addresses, 1002) {
            let actor = self.msg_sender();

            let actual_timestamp = self.context.timestamp();
            assert_public_timestamp(timestamp, actual_timestamp);

            
            
            
            
            
            
            

            assert(
                self.internal._verify_hash(addresses[3], location_id, planet_hash),
                "planet hash mismatch",
            );
            assert(
                self.internal._verify_hash(addresses[5], location_id, planet_events_state_hash),
                "planet_events hash mismatch",
            );
            assert(
                self.internal._verify_hash(addresses[6], location_id, planet_artifacts_state_hash),
                "planet_artifacts hash mismatch",
            );

            if origin_arrivals_count != 0 {
                assert(
                    self.internal._verify_hashes_batch(addresses[7], arrival_ids, arrival_hashes, origin_arrivals_count),
                    "arrivals hash mismatch",
                );
                if ::libs::batch_utils::has_nonzero_ids(arrival_artifact_ids, origin_arrivals_count) {
                    assert(
                        self.internal._verify_hashes_batch(addresses[8], arrival_artifact_ids, arrival_artifact_hashes, origin_arrivals_count),
                        "arrival artifacts hash mismatch",
                    );

                    assert(
                        self.internal._verify_hashes_batch(addresses[9], arrival_artifact_ids, arrival_artifact_location_hashes, origin_arrivals_count),
                        "arrival artifact locations hash mismatch",
                    );
                }
            }

            assert(
                self.internal._verify_hash(addresses[8], artifact_id, artifact_hash),
                "artifact hash mismatch",
            );
            assert(
                self.internal._verify_hash(addresses[9], artifact_id, artifact_location_hash),
                "artifact_location hash mismatch",
            );

            assert(self.internal._verify_hash(addresses[1], 0, world_hash), "world hash mismatch");

            self.internal._set_planet(addresses[3], actor, location_id, new_planet, prepared_new_planet_root, true);
            self.internal._set_planet_events(addresses[5], actor, location_id, new_planet_events_state, prepared_new_planet_events_state_root, true);
            self.internal._set_planet_artifacts(addresses[6], actor, location_id, new_planet_artifacts_state, prepared_new_planet_artifacts_state_root, true);

            self.internal._set_arrival_locations_max20(addresses[9], actor, change_artifact_location_ids, change_artifact_locations, change_artifact_location_count);

            self.internal._set_artifact(addresses[8], actor, artifact_id, new_artifact, prepared_new_artifact_root, true);
            self.internal._set_artifact_location(addresses[9], actor, artifact_id, new_artifact_location, prepared_new_artifact_location_root, true);
        
            true
        } else {
            false
        }
    }

    #[external("public")]
    fn try_settle_artifact_find_find_artifact(
        addresses: [AztecAddress; 10],
        location_id: Field,
        artifact_id: Field,
        timestamp: u64,
        snark_config_hash: Field,
        game_config_core_hash: Field,
        world_config_hash: Field,
        artifacts_config_hash: Field,
        player_hash: Field,
        planet_hash: Field,
        planet_events_state_hash: Field,
        arrival_ids: [Field; 20],
        arrival_hashes: [Field; 20],
        arrival_artifact_ids: [Field; 20],
        arrival_artifact_hashes: [Field; 20],
        arrival_artifact_location_hashes: [Field; 20],
        origin_arrivals_count: u32,
        planet_artifacts_state_hash: Field,
        owned_artifact_ids: [Field; 20],
        owned_artifact_hashes: [Field; 20],
        owned_artifact_location_hashes: [Field; 20],
        owned_artifact_count: u32,
        world_hash: Field,
        new_planet: Planet,
        new_planet_events_state: PlanetEvents,
        new_planet_artifacts_state: PlanetArtifacts,
        change_artifact_location_count: u32,
        change_artifact_location_ids: [Field; 20],
        change_artifact_locations: [ArtifactLocation; 20],
        new_artifact: Artifact,
        new_artifact_location: ArtifactLocation,
        new_player: Player,
        prepared_new_planet_root: Field,
        prepared_new_planet_events_state_root: Field,
        prepared_new_planet_artifacts_state_root: Field,
        prepared_new_artifact_root: Field,
        prepared_new_artifact_location_root: Field,
        prepared_new_player_root: Field,
    ) -> bool {
        if self.internal._can_settle(addresses, 1006) {
            let actor = self.msg_sender();

            let actual_timestamp = self.context.timestamp();
            assert_public_timestamp(timestamp, actual_timestamp);

            let block_number = self.context.block_number();

            assert(
                new_planet.prospected_block_number < block_number,
                "can only find artifact after prospected block",
            );
            assert(
                (block_number - new_planet.prospected_block_number) < 256,
                "planet prospect expired",
            );

            
            
            
            
            
            
            
            
            let config = Config::at(addresses[0]);

            assert(
                self.internal._verify_hash(addresses[3], location_id, planet_hash),
                "planet hash mismatch",
            );
            assert(
                self.internal._verify_hash(addresses[5], location_id, planet_events_state_hash),
                "planet_events hash mismatch",
            );
            assert(
                self.internal._verify_hash(addresses[6], location_id, planet_artifacts_state_hash),
                "planet_artifacts hash mismatch",
            );

            if origin_arrivals_count != 0 {
                assert(
                    self.internal._verify_hashes_batch(addresses[7], arrival_ids, arrival_hashes, origin_arrivals_count),
                    "arrivals hash mismatch",
                );
                if ::libs::batch_utils::has_nonzero_ids(arrival_artifact_ids, origin_arrivals_count) {
                    assert(
                        self.internal._verify_hashes_batch(addresses[8], arrival_artifact_ids, arrival_artifact_hashes, origin_arrivals_count),
                        "arrival artifacts hash mismatch",
                    );

                    assert(
                        self.internal._verify_hashes_batch(addresses[9], arrival_artifact_ids, arrival_artifact_location_hashes, origin_arrivals_count),
                        "arrival artifact locations hash mismatch",
                    );
                }
            }

            if owned_artifact_count != 0 {
                if ::libs::batch_utils::has_nonzero_ids(owned_artifact_ids, owned_artifact_count) {
                    assert(
                        self.internal._verify_hashes_batch(addresses[8], owned_artifact_ids, owned_artifact_hashes, owned_artifact_count),
                        "owned artifact hashes mismatch",
                    );

                    assert(
                        self.internal._verify_hashes_batch(addresses[9], owned_artifact_ids, owned_artifact_location_hashes, owned_artifact_count),
                        "owned artifact locations hash mismatch",
                    );
                }
            }

            assert(self.internal._verify_hash(addresses[1], 0, world_hash), "world hash mismatch");

            assert(
                self.view(config.verify_snark_config_hash(snark_config_hash)),
                "snark config hash mismatch",
            );
            assert(
                self.view(config.verify_game_config_core_hash(game_config_core_hash)),
                "game config core hash mismatch",
            );
            assert(
                self.view(config.verify_world_config_hash(world_config_hash)),
                "world config hash mismatch",
            );
            assert(
                self.view(config.verify_artifacts_config_hash(artifacts_config_hash)),
                "artifacts config hash mismatch",
            );

            let sender = new_planet.owner;
            assert(self.internal._verify_hash(addresses[2], (sender).to_field(), player_hash), "player hash mismatch");

            self.internal._set_planet(addresses[3], actor, location_id, new_planet, prepared_new_planet_root, true);
            self.internal._set_planet_events(addresses[5], actor, location_id, new_planet_events_state, prepared_new_planet_events_state_root, true);
            self.internal._set_planet_artifacts(addresses[6], actor, location_id, new_planet_artifacts_state, prepared_new_planet_artifacts_state_root, true);

            self.internal._set_arrival_locations_max20(addresses[9], actor, change_artifact_location_ids, change_artifact_locations, change_artifact_location_count);

            self.internal._set_artifact(addresses[8], actor, artifact_id, new_artifact, prepared_new_artifact_root, true);
            self.internal._set_artifact_location(addresses[9], actor, artifact_id, new_artifact_location, prepared_new_artifact_location_root, true);

            self.internal._set_player(addresses[2], actor, (sender).to_field(), new_player, prepared_new_player_root, true);
        
            true
        } else {
            false
        }
    }

    #[external("public")]
    fn try_settle_artifact_prospect_prospect_planet(
        addresses: [AztecAddress; 10],
        location_id: Field,
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
        world_hash: Field,
        new_planet: Planet,
        new_planet_artifacts_state: PlanetArtifacts,
        new_planet_events_state: PlanetEvents,
        change_artifact_location_count: u32,
        change_artifact_location_ids: [Field; 20],
        change_artifact_locations: [ArtifactLocation; 20],
        owned_artifact_ids: [Field; 20],
        owned_artifact_hashes: [Field; 20],
        owned_artifact_location_hashes: [Field; 20],
        owned_artifact_count: u32,
        prepared_new_planet_artifacts_state_root: Field,
        prepared_new_planet_events_state_root: Field,
    ) -> bool {
        if self.internal._can_settle(addresses, 1002) {
            let actor = self.msg_sender();

            let actual_timestamp = self.context.timestamp();

            assert_public_timestamp(timestamp, actual_timestamp);

            
            
            
            
            
            
            

            assert(
                self.internal._verify_hash(addresses[3], location_id, planet_hash),
                "planet hash mismatch",
            );
            assert(
                self.internal._verify_hash(addresses[6], location_id, planet_artifacts_state_hash),
                "planet_artifacts hash mismatch",
            );
            assert(
                self.internal._verify_hash(addresses[5], location_id, planet_events_state_hash),
                "planet_events hash mismatch",
            );

            if origin_arrivals_count != 0 {
                assert(
                    self.internal._verify_hashes_batch(addresses[7], arrival_ids, arrival_hashes, origin_arrivals_count as u32),
                    "arrivals hash mismatch",
                );
                if ::libs::batch_utils::has_nonzero_ids(artifact_ids, origin_arrivals_count as u32) {
                    assert(
                        self.internal._verify_hashes_batch(addresses[8], artifact_ids, artifact_hashes, origin_arrivals_count as u32),
                        "artifacts hash mismatch",
                    );

                    assert(
                        self.internal._verify_hashes_batch(addresses[9], artifact_ids, artifact_location_hashes, origin_arrivals_count as u32),
                        "artifact locations hash mismatch",
                    );
                }
            }

            if owned_artifact_count != 0 {
                if ::libs::batch_utils::has_nonzero_ids(owned_artifact_ids, owned_artifact_count as u32)
                     {
                        assert(
                            self.internal._verify_hashes_batch(addresses[8], owned_artifact_ids, owned_artifact_hashes, owned_artifact_count as u32),
                            "owned artifact hashes mismatch",
                        );

                        assert(
                            self.internal._verify_hashes_batch(addresses[9], owned_artifact_ids, owned_artifact_location_hashes, owned_artifact_count as u32),
                            "owned artifact locations hash mismatch",
                        );
                    }
            }

            assert(self.internal._verify_hash(addresses[1], 0, world_hash), "world hash mismatch");

            let mut prospect_planet = new_planet;
            prospect_planet.prospected_block_number = self.context.block_number();

            self.internal._set_planet(addresses[3], actor, location_id, prospect_planet, 0, false);
            self.internal._set_planet_artifacts(addresses[6], actor, location_id, new_planet_artifacts_state, prepared_new_planet_artifacts_state_root, true);
            self.internal._set_planet_events(addresses[5], actor, location_id, new_planet_events_state, prepared_new_planet_events_state_root, true);
            self.internal._set_arrival_locations_max20(addresses[9], actor, change_artifact_location_ids, change_artifact_locations, change_artifact_location_count);
        
            true
        } else {
            false
        }
    }

    #[external("public")]
    fn try_settle_artifact_valut_deposit_artifact(
        addresses: [AztecAddress; 10],
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
        prepared_new_planet_root: Field,
        prepared_new_planet_artifacts_state_root: Field,
        prepared_new_planet_events_state_root: Field,
        prepared_new_artifact_root: Field,
        prepared_new_artifact_location_root: Field,
    ) -> bool {
        if self.internal._can_settle(addresses, 1002) {
            let actor = self.msg_sender();

            let actual_timestamp = self.context.timestamp();

            assert_public_timestamp(timestamp, actual_timestamp);

            
            
            
            
            
            
            

            assert(
                self.internal._verify_hash(addresses[3], location_id, planet_hash),
                "planet hash mismatch",
            );
            assert(
                self.internal._verify_hash(addresses[6], location_id, planet_artifacts_state_hash),
                "planet_artifacts hash mismatch",
            );
            assert(
                self.internal._verify_hash(addresses[5], location_id, planet_events_state_hash),
                "planet_events hash mismatch",
            );

            if origin_arrivals_count != 0 {
                assert(
                    self.internal._verify_hashes_batch(addresses[7], arrival_ids, arrival_hashes, origin_arrivals_count as u32),
                    "arrivals hash mismatch",
                );
                if ::libs::batch_utils::has_nonzero_ids(artifact_ids, origin_arrivals_count as u32) {
                    assert(
                        self.internal._verify_hashes_batch(addresses[8], artifact_ids, artifact_hashes, origin_arrivals_count as u32),
                        "artifacts hash mismatch",
                    );

                    assert(
                        self.internal._verify_hashes_batch(addresses[9], artifact_ids, artifact_location_hashes, origin_arrivals_count as u32),
                        "artifact locations hash mismatch",
                    );
                }
            }

            assert(
                self.internal._verify_hash(addresses[8], artifact_id, artifact_hash),
                "artifact hash mismatch",
            );
            assert(
                self.internal._verify_hash(addresses[9], artifact_id, artifact_location_hash),
                "artifact location hash mismatch",
            );

            assert(self.internal._verify_hash(addresses[1], 0, world_hash), "world hash mismatch");

            self.internal._set_planet(addresses[3], actor, location_id, new_planet, prepared_new_planet_root, true);
            self.internal._set_planet_artifacts(addresses[6], actor, location_id, new_planet_artifacts_state, prepared_new_planet_artifacts_state_root, true);
            self.internal._set_planet_events(addresses[5], actor, location_id, new_planet_events_state, prepared_new_planet_events_state_root, true);
            self.internal._set_arrival_locations_max20(addresses[9], actor, artifact_ids, new_artifact_locations, origin_arrivals_count as u32);

            self.internal._set_artifact(addresses[8], actor, artifact_id, new_artifact, prepared_new_artifact_root, true);
            self.internal._set_artifact_location(addresses[9], actor, artifact_id, new_artifact_location, prepared_new_artifact_location_root, true);
        
            true
        } else {
            false
        }
    }

    #[external("public")]
    fn try_settle_artifact_valut_withdraw_artifact(
        addresses: [AztecAddress; 10],
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
        prepared_new_planet_root: Field,
        prepared_new_planet_artifacts_state_root: Field,
        prepared_new_planet_events_state_root: Field,
        prepared_new_artifact_root: Field,
        prepared_new_artifact_location_root: Field,
    ) -> bool {
        if self.internal._can_settle(addresses, 1002) {
            let actor = self.msg_sender();

            let actual_timestamp = self.context.timestamp();
            assert_public_timestamp(timestamp, actual_timestamp);

            
            
            
            
            
            
            

            assert(
                self.internal._verify_hash(addresses[3], location_id, planet_hash),
                "planet hash mismatch",
            );
            assert(
                self.internal._verify_hash(addresses[6], location_id, planet_artifacts_state_hash),
                "planet_artifacts hash mismatch",
            );
            assert(
                self.internal._verify_hash(addresses[5], location_id, planet_events_state_hash),
                "planet_events hash mismatch",
            );

            if origin_arrivals_count != 0 {
                assert(
                    self.internal._verify_hashes_batch(addresses[7], arrival_ids, arrival_hashes, origin_arrivals_count as u32),
                    "arrivals hash mismatch",
                );
                if ::libs::batch_utils::has_nonzero_ids(artifact_ids, origin_arrivals_count as u32) {
                    assert(
                        self.internal._verify_hashes_batch(addresses[8], artifact_ids, artifact_hashes, origin_arrivals_count as u32),
                        "artifacts hash mismatch",
                    );

                    assert(
                        self.internal._verify_hashes_batch(addresses[9], artifact_ids, artifact_location_hashes, origin_arrivals_count as u32),
                        "artifact locations hash mismatch",
                    );
                }
            }

            assert(
                self.internal._verify_hash(addresses[8], artifact_id, artifact_hash),
                "artifact hash mismatch",
            );
            assert(
                self.internal._verify_hash(addresses[9], artifact_id, artifact_location_hash),
                "artifact location hash mismatch",
            );

            assert(self.internal._verify_hash(addresses[1], 0, world_hash), "world hash mismatch");

            self.internal._set_planet(addresses[3], actor, location_id, new_planet, prepared_new_planet_root, true);
            self.internal._set_planet_artifacts(addresses[6], actor, location_id, new_planet_artifacts_state, prepared_new_planet_artifacts_state_root, true);
            self.internal._set_planet_events(addresses[5], actor, location_id, new_planet_events_state, prepared_new_planet_events_state_root, true);
            self.internal._set_arrival_locations_max20(addresses[9], actor, artifact_ids, new_artifact_locations, origin_arrivals_count as u32);

            self.internal._set_artifact(addresses[8], actor, artifact_id, new_artifact, prepared_new_artifact_root, true);
            self.internal._set_artifact_location(addresses[9], actor, artifact_id, new_artifact_location, prepared_new_artifact_location_root, true);
        
            true
        } else {
            false
        }
    }

    #[external("public")]
    fn try_settle_artifact_valut_give_spaceships(
        addresses: [AztecAddress; 10],
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
        prepared_new_planet_root: Field,
        prepared_new_planet_events_state_root: Field,
        prepared_new_planet_artifacts_state_root: Field,
        prepared_new_player_root: Field,
    ) -> bool {
        if self.internal._can_settle(addresses, 1004) {
            let actor = self.msg_sender();

            let actual_timestamp = self.context.timestamp();
            assert_public_timestamp(timestamp, actual_timestamp);

            
            
            
            
            
            
            

            assert(
                self.internal._verify_hash(addresses[3], location_id, planet_hash),
                "planet hash mismatch",
            );
            assert(
                self.internal._verify_hash(addresses[6], location_id, planet_artifacts_state_hash),
                "planet_artifacts hash mismatch",
            );
            assert(
                self.internal._verify_hash(addresses[5], location_id, planet_events_state_hash),
                "planet_events hash mismatch",
            );

            if origin_arrivals_count != 0 {
                assert(
                    self.internal._verify_hashes_batch(addresses[7], arrival_ids, arrival_hashes, origin_arrivals_count as u32),
                    "arrivals hash mismatch",
                );

                if ::libs::batch_utils::has_nonzero_ids(artifact_ids, origin_arrivals_count as u32) {
                    assert(
                        self.internal._verify_hashes_batch(addresses[8], artifact_ids, artifact_hashes, origin_arrivals_count as u32),
                        "artifacts hash mismatch",
                    );

                    assert(
                        self.internal._verify_hashes_batch(addresses[9], artifact_ids, artifact_location_hashes, origin_arrivals_count as u32),
                        "artifact locations hash mismatch",
                    );
                }
            }

            assert(self.internal._verify_hash(addresses[2], (sender).to_field(), player_hash), "player hash mismatch");

            self.internal._set_planet(addresses[3], actor, location_id, new_planet, prepared_new_planet_root, true);
            self.internal._set_planet_events(addresses[5], actor, location_id, new_planet_events_state, prepared_new_planet_events_state_root, true);
            self.internal._set_planet_artifacts(addresses[6], actor, location_id, new_planet_artifacts_state, prepared_new_planet_artifacts_state_root, true);
            self.internal._set_arrival_locations_max20(addresses[9], actor, artifact_ids, new_artifact_locations, origin_arrivals_count as u32);
            self.internal._set_player(addresses[2], actor, (sender).to_field(), new_player, prepared_new_player_root, true);

            self.internal._set_spaceships_max5(addresses[8], actor, spaceships_ids, spaceships, 5);

            self.internal._set_spaceship_locations_max5(addresses[9], actor, spaceships_ids, spaceships_locations, 5);
        
            true
        } else {
            false
        }
    }

    #[external("public")]
    fn try_settle_admin_safe_set_owner(
        addresses: [AztecAddress; 10],
        sender: AztecAddress,
        location_id: Field,
        level: u8,
        timestamp: u64,
        planet_default_stats_hash: Field,
        config_hashes: [Field; 9],
        world_state_hash: Field,
        planet_state_hash: Field,
        new_planet: Planet,
        prepared_new_planet_root: Field,
    ) -> bool {
        if self.internal._can_settle(addresses, 10) {
            let actor = self.msg_sender();

            assert(sender == self.internal._get_system_admin(actor), "Only admin");

            assert_public_timestamp(timestamp, self.context.timestamp());

            let config = Config::at(addresses[0]);
            
            

            assert(
                self.view(config.verify_config_hashes(level, planet_default_stats_hash, config_hashes)),
                "Config hash mismatch",
            );

            assert(
                self.internal._verify_hash(addresses[1], 0, world_state_hash),
                "World state hash mismatch",
            );

            assert(
                self.internal._verify_hash(addresses[3], location_id, planet_state_hash),
                "Planet state hash mismatch",
            );

            self.internal._set_planet(addresses[3], actor, location_id, new_planet, prepared_new_planet_root, true);
        
            true
        } else {
            false
        }
    }
