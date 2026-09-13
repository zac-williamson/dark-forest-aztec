use ::aztec::macros::aztec;

#[aztec]
contract Admin {
    use aztec::protocol::traits::FromField;

    use aztec::protocol::traits::Deserialize;

    use aztec::protocol::traits::ToField;

    use ::game_state_backend::GameStateBackend;

    use ::aztec::{
        macros::{functions::{external, initializer, internal, only_self, view}, storage::storage},
        protocol::{address::AztecAddress, hash::poseidon2_hash, traits::Serialize},
    };
    use ::aztec::state_vars::PublicMutable;

    use ::types::args::{AdminCreatePlanetArgs, DFPInitPlanetArgs};

    use ::types::config::{
        default_stats::PlanetDefaultStats,
        game::{GameConfigCore, PlanetLevelThresholds, PlanetTypeWeightsTier},
        planet_init::PlanetInitConfig,
        snark::SnarkConfig,
        space_junk::SpaceJunkConfig,
        world::WorldConfig,
    };

    use ::types::storage::{planet::Planet, player::Player, world::World};
    use ::types::system_storage_addresses::AdminSystemStorageAddresses;

    use ::libs::batch_utils::{
        assert_public_timestamp, compute_config_hashes, compute_planet_state_hash,
        compute_world_state_hash,
    };
    use ::libs::game_utils::{
        location_id_valid, revert_if_bad_snark_perlin_flags, space_type_from_perlin,
    };
    use ::libs::planet::{_initialize_planet, initialize_planet_with_defaults};

    use ::config::Config;

    use ::planet_storage::PlanetStorage;
    use ::player_storage::PlayerStorage;
    use ::world_storage::WorldStorage;

    #[storage]
    struct Storage<Context> {
        admin: PublicMutable<AztecAddress, Context>,
        config_storage_address: PublicMutable<AztecAddress, Context>,
        world_storage_address: PublicMutable<AztecAddress, Context>,
        player_storage_address: PublicMutable<AztecAddress, Context>,
        planet_storage_address: PublicMutable<AztecAddress, Context>,
        state_backend: PublicMutable<AztecAddress, Context>,
    }

    #[external("public")]
    #[initializer]
    fn constructor(adminAddress: AztecAddress) {
        self.storage.admin.write(adminAddress);
    }

    #[internal("public")]
    fn assert_admin() {
        assert(self.msg_sender() == self.storage.admin.read(), "Only admin");
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

    /// Batch set all storage addresses in a single transaction.
    #[external("public")]
    fn set_all_storage_addresses(
        config_addr: AztecAddress,
        world_addr: AztecAddress,
        player_addr: AztecAddress,
        planet_addr: AztecAddress,
    ) {
        self.internal.assert_admin();
        self.storage.config_storage_address.write(config_addr);
        self.storage.world_storage_address.write(world_addr);
        self.storage.player_storage_address.write(player_addr);
        self.storage.planet_storage_address.write(planet_addr);
    }

    // ================== UTILITY (UNCONSTRAINED) ==================

    #[external("utility")]
    unconstrained fn get_all_storage_addresses_unconstrained() -> AdminSystemStorageAddresses {
        AdminSystemStorageAddresses {
            config_storage_address: self.storage.config_storage_address.read(),
            world_storage_address: self.storage.world_storage_address.read(),
            player_storage_address: self.storage.player_storage_address.read(),
            planet_storage_address: self.storage.planet_storage_address.read(),
        }
    }

    /// Pause the game. Verifies world matches on-chain state via WorldStorage.verify(), then sets paused = true.
    #[external("public")]
    fn pause(world: World) {
        self.internal.assert_admin();

        let world_storage = WorldStorage::at(self.storage.world_storage_address.read());
        let world_valid: bool = _verify_world_for_admin(self.context, self.storage.state_backend.read(), world_storage.target_contract, 0, world);

        assert(world_valid, "World state is not valid");
        assert(!world.paused, "Game is already paused");

        let mut new_world = world;
        new_world.paused = true;
        self.call(world_storage.set(0, new_world));
    }

    #[external("public")]
    fn unpause(world: World) {
        self.internal.assert_admin();
        let world_storage = WorldStorage::at(self.storage.world_storage_address.read());

        let world_valid: bool = _verify_world_for_admin(self.context, self.storage.state_backend.read(), world_storage.target_contract, 0, world);
        assert(world_valid, "World state is not valid");
        assert(world.paused == true, "Game is already unpaused");

        let mut new_world = world;
        new_world.paused = false;
        self.call(world_storage.set(0, new_world));
    }

    #[external("public")]
    fn set_owner(planet_id: Field, planet_state: Planet, new_owner: AztecAddress) {
        self.internal.assert_admin();
        let planet_storage = PlanetStorage::at(self.storage.planet_storage_address.read());

        let planet_valid: bool = _verify_planet_for_admin(self.context, self.storage.state_backend.read(), planet_storage.target_contract, planet_id, planet_state);
        assert(planet_valid, "Planet state is not valid");

        let mut new_planet_state = planet_state;
        new_planet_state.owner = new_owner;
        self.call(planet_storage.set(planet_id, new_planet_state));
    }

    #[external("public")]
    fn deduct_score(player_address: AztecAddress, player_state: Player, amount: u128) {
        self.internal.assert_admin();

        let player_storage = PlayerStorage::at(self.storage.player_storage_address.read());

        let player_valid: bool = _verify_player_for_admin(self.context, self.storage.state_backend.read(), player_storage.target_contract, player_address, player_state);
        assert(player_valid, "Player is not valid");

        let current_timestamp = self.context.timestamp();
        assert(
            current_timestamp >= player_state.last_updated,
            "Timestamp must be >= player's last_updated",
        );

        assert(amount <= player_state.score, "tried to deduct too much score");
        let mut new_player_state = player_state;
        new_player_state.score -= amount;
        new_player_state.last_updated = current_timestamp;
        self.call(player_storage.set(player_address, new_player_state));
    }

    #[external("public")]
    fn add_score(player_address: AztecAddress, player_state: Player, amount: u128) {
        self.internal.assert_admin();

        let player_storage = PlayerStorage::at(self.storage.player_storage_address.read());

        let player_valid: bool = _verify_player_for_admin(self.context, self.storage.state_backend.read(), player_storage.target_contract, player_address, player_state);
        assert(player_valid, "Player is not valid");

        let current_timestamp = self.context.timestamp();
        assert(
            current_timestamp >= player_state.last_updated,
            "Timestamp must be >= player's last_updated",
        );

        let mut new_player_state = player_state;
        new_player_state.score += amount;
        new_player_state.last_updated = current_timestamp;
        self.call(player_storage.set(player_address, new_player_state));
    }

    /// Private function that performs all computation off-chain (in the private circuit).
    /// Config and state data are passed as inputs, validated via hashes in public.
    #[external("private")]
    fn safe_set_owner(
        x: Field, // private
        y: Field, // private
        location_id: Field,
        perlin: u8,
        level: u8,
        new_owner: AztecAddress,
        timestamp: u64, // timestamp for private time-based computations
        // Config inputs (to be validated via hash in public)
        provided_snark_config: SnarkConfig,
        planet_default_stats: PlanetDefaultStats, // it is determined based on the level
        world_config: WorldConfig,
        game_config_core: GameConfigCore,
        planet_level_thresholds: PlanetLevelThresholds,
        space_junk_config: SpaceJunkConfig,
        planet_type_weights_tier_0: PlanetTypeWeightsTier,
        planet_type_weights_tier_1: PlanetTypeWeightsTier,
        planet_type_weights_tier_2: PlanetTypeWeightsTier,
        planet_type_weights_tier_3: PlanetTypeWeightsTier,
        // State inputs (to be validated via hash in public)
        world_state: World,
        planet_state: Planet,
    ) {
        let r = world_state.radius;

        if !provided_snark_config.disable_zk_checks {
            let planet_hash_key = provided_snark_config.planethash_key as Field;
            let space_type_key = provided_snark_config.spacetype_key as Field;
            let scale = provided_snark_config.perlin_length_scale;
            let (expected_hash, expected_perlin) = circuits::reveal::reveal_proof(
                x,
                y,
                planet_hash_key,
                space_type_key,
                scale,
                provided_snark_config.perlin_mirror_x,
                provided_snark_config.perlin_mirror_y,
            );
            assert(expected_hash == location_id, "ZK check: location hash mismatch");
            assert(expected_perlin == perlin, "ZK check: perlin mismatch");
            // Radius check: x^2 + y^2 < r^2
            let r_field = r as Field;
            let dist_sq = (x * x + y * y) as u128;
            let r_sq = (r_field * r_field) as u128;
            assert(dist_sq < r_sq, "ZK check: coordinates outside radius");
        }

        let sender = self.msg_sender();

        let (planet_default_stats_hash, config_hashes) = compute_config_hashes(
            provided_snark_config,
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

        let world_state_hash = compute_world_state_hash(world_state);
        let planet_state_hash = compute_planet_state_hash(planet_state);

        let planet_state_is_initialized: bool = planet_state != Planet::zero();

        let mut new_planet = if !planet_state_is_initialized {
            let mut planet: Planet = initialize_planet_with_defaults(
                location_id,
                perlin,
                false,
                timestamp,
                sender,
                level,
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

            planet.silver = planet.silver_cap;
            planet.population = planet.population_cap;
            planet.owner = new_owner;

            planet
        } else {
            assert(
                timestamp >= planet_state.last_updated,
                "Timestamp must be >= planet's last_updated",
            );

            let mut new_planet_state = planet_state;
            new_planet_state.owner = new_owner;
            new_planet_state.population = new_planet_state.population_cap;
            new_planet_state.silver = new_planet_state.silver_cap;
            new_planet_state.last_updated = timestamp;

            new_planet_state
        };

        new_planet.last_updated = timestamp;

        // Pass hashes and computed results to public for verification and storage
        self.enqueue_self.safe_set_owner_public(
            sender,
            location_id,
            level,
            timestamp,
            planet_default_stats_hash,
            config_hashes,
            world_state_hash,
            planet_state_hash,
            new_planet,
        );
    }

    /// Public function that verifies hashes and writes computed results.
    /// All computation is done in private; this only validates and persists.
    #[external("public")]
    #[only_self]
    fn safe_set_owner_public(
        sender: AztecAddress,
        location_id: Field,
        level: u8,
        timestamp: u64,
        planet_default_stats_hash: Field,
        // [snark, world, game_core, thresholds, space_junk, tier0, tier1, tier2, tier3]
        config_hashes: [Field; 9],
        world_state_hash: Field,
        planet_state_hash: Field,
        new_planet: Planet,
    ) {
        assert(sender == self.storage.admin.read(), "Only admin");

        assert_public_timestamp(timestamp, self.context.timestamp());

        let state_backend_address = self.storage.state_backend.read();
        let config = Config::at(self.storage.config_storage_address.read());
        let world_storage = WorldStorage::at(self.storage.world_storage_address.read());
        let planet_storage = PlanetStorage::at(self.storage.planet_storage_address.read());

        assert(
            self.view(config.verify_config_hashes(level, planet_default_stats_hash, config_hashes)),
            "Config hash mismatch",
        );

        assert(
            (if (if state_backend_address.is_zero() { false } else { ::state_backend_readonly::public_read::get_namespace_kind(state_backend_address, world_storage.target_contract) == 1 }) { ::state_backend_readonly::public_read::get_state_root(state_backend_address, world_storage.target_contract, 0) == world_state_hash } else { self.view(world_storage.verify_hash(0, world_state_hash)) }),
            "World state hash mismatch",
        );

        assert(
            (if (if state_backend_address.is_zero() { false } else { ::state_backend_readonly::public_read::get_namespace_kind(state_backend_address, planet_storage.target_contract) == 3 }) { ::state_backend_readonly::public_read::get_state_root(state_backend_address, planet_storage.target_contract, location_id) == planet_state_hash } else { self.view(planet_storage.verify_hash(location_id, planet_state_hash)) }),
            "Planet state hash mismatch",
        );

        self.call(planet_storage.set(location_id, new_planet));
    }

    #[external("public")]
    fn admin_set_world_radius(new_radius: u128, world: World) {
        self.internal.assert_admin();
        assert(new_radius > 0, "Radius must be positive");
        let world_storage = WorldStorage::at(self.storage.world_storage_address.read());
        let world_valid: bool = _verify_world_for_admin(self.context, self.storage.state_backend.read(), world_storage.target_contract, 0, world);
        assert(world_valid, "World state is not valid");
        let mut new_world = world;
        new_world.radius = new_radius;
        self.call(world_storage.set(0, new_world));
    }

    #[external("public")]
    fn create_planet(args: AdminCreatePlanetArgs) {
        self.internal.assert_admin();

        let sender = self.msg_sender();
        let location_id = args.location;

        let planet_storage = PlanetStorage::at(self.storage.planet_storage_address.read());
        let planet_is_uninitialized: bool =
            self.view(planet_storage.verify(location_id, Planet::zero()));
        assert(planet_is_uninitialized, "Planet already exists at this location");

        let config = Config::at(self.storage.config_storage_address.read());
        let world_config = self.view(config.get_world_config());
        let game_config_core = self.view(config.get_game_config_core());
        let space_junk_config = self.view(config.get_space_junk_config());

        assert(world_config.admin_can_add_planets, "admin can no longer add planets");

        if args.require_valid_location_id {
            assert(
                location_id_valid(args.location, game_config_core.max_location_id),
                "Not a valid planet location",
            );
        }

        let space_type = space_type_from_perlin(args.perlin, game_config_core);

        let init_args = DFPInitPlanetArgs {
            location: args.location,
            perlin: args.perlin,
            level: args.level,
            time_factor_hundredths: world_config.time_factor_hundredths,
            space_type: space_type,
            planet_type: args.planet_type,
            is_home_planet: false,
        };

        let planet_default_stats = self.view(config.get_planet_default_stats(args.level));

        let mut planet: Planet = _initialize_planet(
            init_args,
            self.context.timestamp(),
            sender,
            planet_default_stats,
            world_config,
            space_junk_config,
        );

        self.call(planet_storage.set(location_id, planet));
    }

    #[external("public")]
    fn admin_initialize_planet(location_id: Field, perlin: u8, level: u8) {
        self.internal.assert_admin();
        let sender = self.msg_sender();

        let planet_storage = PlanetStorage::at(self.storage.planet_storage_address.read());
        let planet_is_uninitialized: bool =
            self.view(planet_storage.verify(location_id, Planet::zero()));
        assert(planet_is_uninitialized, "Planet is already initialized");

        let config = Config::at(self.storage.config_storage_address.read());
        let c: PlanetInitConfig = self.view(config.get_planet_init_config(level));

        let planet: Planet = initialize_planet_with_defaults(
            location_id,
            perlin,
            false,
            self.context.timestamp(),
            sender,
            level,
            c.planet_default_stats,
            c.world_config,
            c.planet_level_thresholds,
            c.game_config_core,
            c.space_junk_config,
            c.planet_type_weights_tier_0,
            c.planet_type_weights_tier_1,
            c.planet_type_weights_tier_2,
            c.planet_type_weights_tier_3,
        );

        self.call(planet_storage.set(location_id, planet));
    }


    // Additional hashes are bound by the existing private gameplay proof.


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



    #[inline_never]
    #[contract_library_method]
    unconstrained fn _verify_planet_for_admin(
        context: aztec::context::PublicContext,
        backend: AztecAddress,
        namespace: AztecAddress,
        id: Field,
        state: Planet,
    ) -> bool {
        let mut self = __aztec_nr_internals__create_public_self_from_context(context);
        let recognized = if backend.is_zero() { false } else {
            ::state_backend_readonly::public_read::get_namespace_kind(backend,namespace) == 3
        };
        if recognized {
            let root = ::state_backend_readonly::public_read::get_state_root(backend,namespace,id);
            // Keep verify(state) semantics: explicit H(zero) also accepts zero.
            if root == 0 { state == Planet::zero() } else { poseidon2_hash(state.serialize()) == root }
        } else {
            // Unknown stores keep the original typed call and original Admin caller.
            self.view(PlanetStorage::at(namespace).verify(id,state))
        }
    }


    #[inline_never]
    #[contract_library_method]
    unconstrained fn _verify_player_for_admin(
        context: aztec::context::PublicContext,
        backend: AztecAddress,
        namespace: AztecAddress,
        id: AztecAddress,
        state: Player,
    ) -> bool {
        let mut self = __aztec_nr_internals__create_public_self_from_context(context);
        let recognized = if backend.is_zero() { false } else {
            ::state_backend_readonly::public_read::get_namespace_kind(backend,namespace) == 2
        };
        if recognized {
            let root = ::state_backend_readonly::public_read::get_state_root(backend,namespace,id.to_field());
            // Keep verify(state) semantics: explicit H(zero) also accepts zero.
            if root == 0 { state == Player::zero() } else { poseidon2_hash(state.serialize()) == root }
        } else {
            // Unknown stores keep the original typed call and original Admin caller.
            self.view(PlayerStorage::at(namespace).verify(id,state))
        }
    }


    #[inline_never]
    #[contract_library_method]
    unconstrained fn _verify_world_for_admin(
        context: aztec::context::PublicContext,
        backend: AztecAddress,
        namespace: AztecAddress,
        id: Field,
        state: World,
    ) -> bool {
        let mut self = __aztec_nr_internals__create_public_self_from_context(context);
        let recognized = if backend.is_zero() { false } else {
            ::state_backend_readonly::public_read::get_namespace_kind(backend,namespace) == 1
        };
        if recognized {
            let root = ::state_backend_readonly::public_read::get_state_root(backend,namespace,id);
            // Keep verify(state) semantics: explicit H(zero) also accepts zero.
            if root == 0 { state == World::zero() } else { poseidon2_hash(state.serialize()) == root }
        } else {
            // Unknown stores keep the original typed call and original Admin caller.
            self.view(WorldStorage::at(namespace).verify(id,state))
        }
    }
}
