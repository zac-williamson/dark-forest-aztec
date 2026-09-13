// Generated stateless settlement worker. The actor is its authenticated System caller.
mod system_class;
use ::aztec::macros::aztec;

#[aztec]
pub contract CoreSettlementWorker {
    use aztec::protocol::traits::FromField;

    use aztec::protocol::traits::Deserialize;

    use aztec::protocol::traits::ToField;

    use ::game_state_backend::GameStateBackend;

    use ::aztec::{
        macros::{
            events::event,
            functions::{external, initializer, internal, only_self, view},
            storage::storage,
        },
        protocol::{address::AztecAddress, hash::poseidon2_hash, traits::Serialize},
    };
    use ::aztec::state_vars::{Map, PublicMutable};

    use ::types::args::{
        AdminCreatePlanetArgs, DFPCreateArrivalArgs, DFPInitPlanetArgs, DFPMoveArgs,
    };

    use ::types::config::{
        capture_zones::CaptureZonesConfig,
        default_stats::PlanetDefaultStats,
        game::{GameConfigCore, PlanetLevelThresholds, PlanetTypeWeightsTier},
        snark::SnarkConfig,
        space_junk::SpaceJunkConfig,
        spaceships::SpaceshipsConfig,
        upgrade::{Upgrade, UpgradeConfig},
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
    use ::types::system_storage_addresses::CoreSystemStorageAddresses;

    use ::libs::batch_utils::{
        assert_planet_timestamp_freshness, assert_public_timestamp, compute_config_hashes,
        compute_planet_hashes, compute_planet_revealed_coords_hash, compute_planet_state_hash,
        compute_player_hash, compute_world_hash,
    };
    use ::libs::game_utils::{_buff_planet, revert_if_bad_snark_perlin_flags};

    use ::libs::planet::{
        check_player_init, initialize_planet_with_defaults, refresh_planet_v1,
        validate_upgrade_planet,
    };

    use ::arrival_storage::ArrivalStorage;
    use ::artifact_location_storage::ArtifactLocationStorage;
    use ::artifact_storage::ArtifactStorage;
    use ::config::Config;
    use ::planet_artifacts_storage::PlanetArtifactsStorage;
    use ::planet_events_storage::PlanetEventsStorage;
    use ::planet_revealed_coords_storage::PlanetRevealedCoordsStorage;
    use ::planet_storage::PlanetStorage;
    use ::player_storage::PlayerStorage;
    use ::world_storage::WorldStorage;

    #[storage]
    struct Storage<Context> {
        reserved: PublicMutable<Field,Context>,
    }
    #[external("public")] #[initializer]
    fn constructor() {}
    #[external("public")]
    fn try_refresh_planet_public_prepared(payload: ::libs::field_buffer::FieldBuffer<257>) -> bool {
        let caller_class = aztec::oracle::get_contract_instance::get_contract_instance_current_class_id_avm(self.msg_sender());
        assert(caller_class.is_some(), "Only audited system");
        assert(caller_class.unwrap().to_field() == super::system_class::SYSTEM_CLASS, "Only audited system");
        let state_backend_address=AztecAddress::from_field(payload.words[0]);
        let plan_addresses=[AztecAddress::from_field(payload.words[1]), AztecAddress::from_field(payload.words[2]), AztecAddress::from_field(payload.words[3]), AztecAddress::from_field(payload.words[4]), AztecAddress::from_field(payload.words[5]), AztecAddress::from_field(payload.words[6]), AztecAddress::from_field(payload.words[7]), AztecAddress::from_field(payload.words[8]), AztecAddress::from_field(payload.words[9]), AztecAddress::from_field(payload.words[10])];
        let system_admin=AztecAddress::from_field(payload.words[11]);
        let location: Field = payload.words[12];
        let timestamp: u64 = (payload.words[13] as u64);
        let planet_state_hash: Field = payload.words[14];
        let planet_artifacts_state_hash: Field = payload.words[15];
        let planet_events_state_hash: Field = payload.words[16];
        let original_arrivals_count: u32 = (payload.words[17] as u32);
        let arrival_ids: [Field; 20] = [payload.words[18], payload.words[19], payload.words[20], payload.words[21], payload.words[22], payload.words[23], payload.words[24], payload.words[25], payload.words[26], payload.words[27], payload.words[28], payload.words[29], payload.words[30], payload.words[31], payload.words[32], payload.words[33], payload.words[34], payload.words[35], payload.words[36], payload.words[37]];
        let arrival_hashes: [Field; 20] = [payload.words[38], payload.words[39], payload.words[40], payload.words[41], payload.words[42], payload.words[43], payload.words[44], payload.words[45], payload.words[46], payload.words[47], payload.words[48], payload.words[49], payload.words[50], payload.words[51], payload.words[52], payload.words[53], payload.words[54], payload.words[55], payload.words[56], payload.words[57]];
        let arrival_artifact_ids: [Field; 20] = [payload.words[58], payload.words[59], payload.words[60], payload.words[61], payload.words[62], payload.words[63], payload.words[64], payload.words[65], payload.words[66], payload.words[67], payload.words[68], payload.words[69], payload.words[70], payload.words[71], payload.words[72], payload.words[73], payload.words[74], payload.words[75], payload.words[76], payload.words[77]];
        let arrival_artifact_hashes: [Field; 20] = [payload.words[78], payload.words[79], payload.words[80], payload.words[81], payload.words[82], payload.words[83], payload.words[84], payload.words[85], payload.words[86], payload.words[87], payload.words[88], payload.words[89], payload.words[90], payload.words[91], payload.words[92], payload.words[93], payload.words[94], payload.words[95], payload.words[96], payload.words[97]];
        let arrival_artifact_location_hashes: [Field; 20] = [payload.words[98], payload.words[99], payload.words[100], payload.words[101], payload.words[102], payload.words[103], payload.words[104], payload.words[105], payload.words[106], payload.words[107], payload.words[108], payload.words[109], payload.words[110], payload.words[111], payload.words[112], payload.words[113], payload.words[114], payload.words[115], payload.words[116], payload.words[117]];
        let new_planet: Planet = ::types::storage::planet::Planet { perlin: (payload.words[118] as u8), created_at: (payload.words[119] as u64), owner: AztecAddress::from_field(payload.words[120]), planet_level: (payload.words[121] as u8), planet_type: (payload.words[122] as u8), space_type: (payload.words[123] as u8), is_home_planet: (payload.words[124] == 1), is_initialized: (payload.words[125] == 1), destroyed: (payload.words[126] == 1), invader: AztecAddress::from_field(payload.words[127]), capturer: AztecAddress::from_field(payload.words[128]), invade_start_block: (payload.words[129] as u32), population_cap: (payload.words[130] as u128), population_growth: (payload.words[131] as u128), range: (payload.words[132] as u128), speed: (payload.words[133] as u128), defense: (payload.words[134] as u128), silver_cap: (payload.words[135] as u128), silver_growth: (payload.words[136] as u128), population: (payload.words[137] as u128), silver: (payload.words[138] as u128), upgrade_state_0: (payload.words[139] as u8), upgrade_state_1: (payload.words[140] as u8), upgrade_state_2: (payload.words[141] as u8), last_updated: (payload.words[142] as u64), pausers: (payload.words[143] as u128), energy_gro_doublers: (payload.words[144] as u128), silver_gro_doublers: (payload.words[145] as u128), hat_level: (payload.words[146] as u128), space_junk: (payload.words[147] as u128), has_tried_finding_artifact: (payload.words[148] == 1), prospected_block_number: (payload.words[149] as u32) };
        let new_planet_artifacts_state: PlanetArtifacts = ::types::storage::planet::PlanetArtifacts { ids: [payload.words[150], payload.words[151], payload.words[152], payload.words[153], payload.words[154], payload.words[155], payload.words[156], payload.words[157], payload.words[158], payload.words[159], payload.words[160], payload.words[161], payload.words[162], payload.words[163], payload.words[164], payload.words[165], payload.words[166], payload.words[167], payload.words[168], payload.words[169]], count: (payload.words[170] as u32), last_updated: (payload.words[171] as u64) };
        let new_planet_events_state: PlanetEvents = ::types::storage::planet::PlanetEvents { events: [::types::storage::planet::PlanetEventMetadata { id: payload.words[172] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[173] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[174] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[175] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[176] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[177] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[178] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[179] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[180] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[181] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[182] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[183] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[184] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[185] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[186] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[187] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[188] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[189] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[190] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[191] }], count: (payload.words[192] as u32), last_updated: (payload.words[193] as u64) };
        let new_arrival_artifact_locations: [ArtifactLocation; 20] = [::types::storage::artifact::ArtifactLocation { planet_id: payload.words[194], voyage_id: payload.words[195], last_updated: (payload.words[196] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[197], voyage_id: payload.words[198], last_updated: (payload.words[199] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[200], voyage_id: payload.words[201], last_updated: (payload.words[202] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[203], voyage_id: payload.words[204], last_updated: (payload.words[205] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[206], voyage_id: payload.words[207], last_updated: (payload.words[208] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[209], voyage_id: payload.words[210], last_updated: (payload.words[211] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[212], voyage_id: payload.words[213], last_updated: (payload.words[214] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[215], voyage_id: payload.words[216], last_updated: (payload.words[217] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[218], voyage_id: payload.words[219], last_updated: (payload.words[220] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[221], voyage_id: payload.words[222], last_updated: (payload.words[223] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[224], voyage_id: payload.words[225], last_updated: (payload.words[226] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[227], voyage_id: payload.words[228], last_updated: (payload.words[229] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[230], voyage_id: payload.words[231], last_updated: (payload.words[232] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[233], voyage_id: payload.words[234], last_updated: (payload.words[235] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[236], voyage_id: payload.words[237], last_updated: (payload.words[238] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[239], voyage_id: payload.words[240], last_updated: (payload.words[241] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[242], voyage_id: payload.words[243], last_updated: (payload.words[244] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[245], voyage_id: payload.words[246], last_updated: (payload.words[247] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[248], voyage_id: payload.words[249], last_updated: (payload.words[250] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[251], voyage_id: payload.words[252], last_updated: (payload.words[253] as u64) }];
        let prepared_new_planet_root: Field = payload.words[254];
        let prepared_new_planet_artifacts_state_root: Field = payload.words[255];
        let prepared_new_planet_events_state_root: Field = payload.words[256];
        let supported = ::state_backend_readonly::public_read::can_settle(state_backend_address, plan_addresses, 1000);
        if supported {
            let mut write_plan = ::libs::state_plan::WritePlan::new();

        let actual_timestamp = self.context.timestamp();
        assert_public_timestamp(timestamp, actual_timestamp);








        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[3], location, planet_state_hash),
            "Planet state hash mismatch",
        );
        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[6], location, planet_artifacts_state_hash),
            "Planet artifacts state hash mismatch",
        );
        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[5], location, planet_events_state_hash),
            "Planet events state hash mismatch",
        );

        if original_arrivals_count != 0 {
            assert(
                ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[7], arrival_ids, arrival_hashes, original_arrivals_count),
                "Arrival hash mismatch",
            );
            if ::libs::batch_utils::has_nonzero_ids(arrival_artifact_ids, original_arrivals_count) {
                assert(
                    ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[8], arrival_artifact_ids, arrival_artifact_hashes, original_arrivals_count),
                    "Artifact hash mismatch",
                );

                assert(
                    ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[9], arrival_artifact_ids, arrival_artifact_location_hashes, original_arrivals_count),
                    "Artifact location hash mismatch",
                );
            }
        }

        write_plan.set(3, location, prepared_new_planet_root, true, new_planet.serialize());
        write_plan.set(6, location, prepared_new_planet_artifacts_state_root, true, new_planet_artifacts_state.serialize());
        write_plan.set(5, location, prepared_new_planet_events_state_root, true, new_planet_events_state.serialize());
        {
            let batch_start=write_plan.start_batch(9, original_arrivals_count, 20);
            let bounded_count = if (original_arrivals_count) <= 20 { original_arrivals_count } else { 20 };
            for plan_i in 0..bounded_count { if arrival_artifact_ids[plan_i] != 0 {
                write_plan.append_batch_item(batch_start, arrival_artifact_ids[plan_i], new_arrival_artifact_locations[plan_i].serialize());
            } }
        };

            _commit_plan_for_system(self.context, state_backend_address, plan_addresses, 1000, write_plan);
        }
        supported
    }

    #[external("public")]
    fn try_upgrade_planet_public_prepared(payload: ::libs::field_buffer::FieldBuffer<263>) -> bool {
        let caller_class = aztec::oracle::get_contract_instance::get_contract_instance_current_class_id_avm(self.msg_sender());
        assert(caller_class.is_some(), "Only audited system");
        assert(caller_class.unwrap().to_field() == super::system_class::SYSTEM_CLASS, "Only audited system");
        let state_backend_address=AztecAddress::from_field(payload.words[0]);
        let plan_addresses=[AztecAddress::from_field(payload.words[1]), AztecAddress::from_field(payload.words[2]), AztecAddress::from_field(payload.words[3]), AztecAddress::from_field(payload.words[4]), AztecAddress::from_field(payload.words[5]), AztecAddress::from_field(payload.words[6]), AztecAddress::from_field(payload.words[7]), AztecAddress::from_field(payload.words[8]), AztecAddress::from_field(payload.words[9]), AztecAddress::from_field(payload.words[10])];
        let system_admin=AztecAddress::from_field(payload.words[11]);
        let location: Field = payload.words[12];
        let sender: AztecAddress = AztecAddress::from_field(payload.words[13]);
        let branch: u8 = (payload.words[14] as u8);
        let current_branch_level: u8 = (payload.words[15] as u8);
        let timestamp: u64 = (payload.words[16] as u64);
        let planet_state_hash: Field = payload.words[17];
        let planet_artifacts_state_hash: Field = payload.words[18];
        let planet_events_state_hash: Field = payload.words[19];
        let original_arrivals_count: u32 = (payload.words[20] as u32);
        let arrival_ids: [Field; 20] = [payload.words[21], payload.words[22], payload.words[23], payload.words[24], payload.words[25], payload.words[26], payload.words[27], payload.words[28], payload.words[29], payload.words[30], payload.words[31], payload.words[32], payload.words[33], payload.words[34], payload.words[35], payload.words[36], payload.words[37], payload.words[38], payload.words[39], payload.words[40]];
        let arrival_hashes: [Field; 20] = [payload.words[41], payload.words[42], payload.words[43], payload.words[44], payload.words[45], payload.words[46], payload.words[47], payload.words[48], payload.words[49], payload.words[50], payload.words[51], payload.words[52], payload.words[53], payload.words[54], payload.words[55], payload.words[56], payload.words[57], payload.words[58], payload.words[59], payload.words[60]];
        let arrival_artifact_ids: [Field; 20] = [payload.words[61], payload.words[62], payload.words[63], payload.words[64], payload.words[65], payload.words[66], payload.words[67], payload.words[68], payload.words[69], payload.words[70], payload.words[71], payload.words[72], payload.words[73], payload.words[74], payload.words[75], payload.words[76], payload.words[77], payload.words[78], payload.words[79], payload.words[80]];
        let arrival_artifact_hashes: [Field; 20] = [payload.words[81], payload.words[82], payload.words[83], payload.words[84], payload.words[85], payload.words[86], payload.words[87], payload.words[88], payload.words[89], payload.words[90], payload.words[91], payload.words[92], payload.words[93], payload.words[94], payload.words[95], payload.words[96], payload.words[97], payload.words[98], payload.words[99], payload.words[100]];
        let arrival_artifact_location_hashes: [Field; 20] = [payload.words[101], payload.words[102], payload.words[103], payload.words[104], payload.words[105], payload.words[106], payload.words[107], payload.words[108], payload.words[109], payload.words[110], payload.words[111], payload.words[112], payload.words[113], payload.words[114], payload.words[115], payload.words[116], payload.words[117], payload.words[118], payload.words[119], payload.words[120]];
        let upgrade_config_hash: Field = payload.words[121];
        let upgrade_hash: Field = payload.words[122];
        let world_hash: Field = payload.words[123];
        let new_planet: Planet = ::types::storage::planet::Planet { perlin: (payload.words[124] as u8), created_at: (payload.words[125] as u64), owner: AztecAddress::from_field(payload.words[126]), planet_level: (payload.words[127] as u8), planet_type: (payload.words[128] as u8), space_type: (payload.words[129] as u8), is_home_planet: (payload.words[130] == 1), is_initialized: (payload.words[131] == 1), destroyed: (payload.words[132] == 1), invader: AztecAddress::from_field(payload.words[133]), capturer: AztecAddress::from_field(payload.words[134]), invade_start_block: (payload.words[135] as u32), population_cap: (payload.words[136] as u128), population_growth: (payload.words[137] as u128), range: (payload.words[138] as u128), speed: (payload.words[139] as u128), defense: (payload.words[140] as u128), silver_cap: (payload.words[141] as u128), silver_growth: (payload.words[142] as u128), population: (payload.words[143] as u128), silver: (payload.words[144] as u128), upgrade_state_0: (payload.words[145] as u8), upgrade_state_1: (payload.words[146] as u8), upgrade_state_2: (payload.words[147] as u8), last_updated: (payload.words[148] as u64), pausers: (payload.words[149] as u128), energy_gro_doublers: (payload.words[150] as u128), silver_gro_doublers: (payload.words[151] as u128), hat_level: (payload.words[152] as u128), space_junk: (payload.words[153] as u128), has_tried_finding_artifact: (payload.words[154] == 1), prospected_block_number: (payload.words[155] as u32) };
        let new_planet_events_state: PlanetEvents = ::types::storage::planet::PlanetEvents { events: [::types::storage::planet::PlanetEventMetadata { id: payload.words[156] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[157] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[158] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[159] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[160] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[161] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[162] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[163] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[164] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[165] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[166] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[167] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[168] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[169] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[170] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[171] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[172] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[173] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[174] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[175] }], count: (payload.words[176] as u32), last_updated: (payload.words[177] as u64) };
        let new_planet_artifacts_state: PlanetArtifacts = ::types::storage::planet::PlanetArtifacts { ids: [payload.words[178], payload.words[179], payload.words[180], payload.words[181], payload.words[182], payload.words[183], payload.words[184], payload.words[185], payload.words[186], payload.words[187], payload.words[188], payload.words[189], payload.words[190], payload.words[191], payload.words[192], payload.words[193], payload.words[194], payload.words[195], payload.words[196], payload.words[197]], count: (payload.words[198] as u32), last_updated: (payload.words[199] as u64) };
        let new_arrival_artifact_locations: [ArtifactLocation; 20] = [::types::storage::artifact::ArtifactLocation { planet_id: payload.words[200], voyage_id: payload.words[201], last_updated: (payload.words[202] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[203], voyage_id: payload.words[204], last_updated: (payload.words[205] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[206], voyage_id: payload.words[207], last_updated: (payload.words[208] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[209], voyage_id: payload.words[210], last_updated: (payload.words[211] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[212], voyage_id: payload.words[213], last_updated: (payload.words[214] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[215], voyage_id: payload.words[216], last_updated: (payload.words[217] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[218], voyage_id: payload.words[219], last_updated: (payload.words[220] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[221], voyage_id: payload.words[222], last_updated: (payload.words[223] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[224], voyage_id: payload.words[225], last_updated: (payload.words[226] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[227], voyage_id: payload.words[228], last_updated: (payload.words[229] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[230], voyage_id: payload.words[231], last_updated: (payload.words[232] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[233], voyage_id: payload.words[234], last_updated: (payload.words[235] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[236], voyage_id: payload.words[237], last_updated: (payload.words[238] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[239], voyage_id: payload.words[240], last_updated: (payload.words[241] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[242], voyage_id: payload.words[243], last_updated: (payload.words[244] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[245], voyage_id: payload.words[246], last_updated: (payload.words[247] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[248], voyage_id: payload.words[249], last_updated: (payload.words[250] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[251], voyage_id: payload.words[252], last_updated: (payload.words[253] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[254], voyage_id: payload.words[255], last_updated: (payload.words[256] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[257], voyage_id: payload.words[258], last_updated: (payload.words[259] as u64) }];
        let prepared_new_planet_root: Field = payload.words[260];
        let prepared_new_planet_events_state_root: Field = payload.words[261];
        let prepared_new_planet_artifacts_state_root: Field = payload.words[262];
        let supported = ::state_backend_readonly::public_read::can_settle(state_backend_address, plan_addresses, 1002);
        if supported {
            let mut write_plan = ::libs::state_plan::WritePlan::new();

        let actual_timestamp = self.context.timestamp();
        assert_public_timestamp(timestamp, actual_timestamp);

        let config = Config::at(plan_addresses[0]);








        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[3], location, planet_state_hash),
            "Planet state hash mismatch",
        );
        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[6], location, planet_artifacts_state_hash),
            "Planet artifacts state hash mismatch",
        );
        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[5], location, planet_events_state_hash),
            "Planet events state hash mismatch",
        );

        if original_arrivals_count != 0 {
            assert(
                ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[7], arrival_ids, arrival_hashes, original_arrivals_count),
                "Arrival hash mismatch",
            );
            if ::libs::batch_utils::has_nonzero_ids(arrival_artifact_ids, original_arrivals_count) {
                assert(
                    ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[8], arrival_artifact_ids, arrival_artifact_hashes, original_arrivals_count),
                    "Artifact hash mismatch",
                );

                assert(
                    ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[9], arrival_artifact_ids, arrival_artifact_location_hashes, original_arrivals_count),
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

        assert(::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[1], 0, world_hash), "World state hash mismatch");

        assert(new_planet.owner == sender, "Planet owner mismatch");
        write_plan.set(3, location, prepared_new_planet_root, true, new_planet.serialize());
        write_plan.set(5, location, prepared_new_planet_events_state_root, true, new_planet_events_state.serialize());
        write_plan.set(6, location, prepared_new_planet_artifacts_state_root, true, new_planet_artifacts_state.serialize());
        {
            let batch_start=write_plan.start_batch(9, original_arrivals_count, 20);
            let bounded_count = if (original_arrivals_count) <= 20 { original_arrivals_count } else { 20 };
            for plan_i in 0..bounded_count { if arrival_artifact_ids[plan_i] != 0 {
                write_plan.append_batch_item(batch_start, arrival_artifact_ids[plan_i], new_arrival_artifact_locations[plan_i].serialize());
            } }
        };

            _commit_plan_for_system(self.context, state_backend_address, plan_addresses, 1002, write_plan);
        }
        supported
    }

    #[external("public")]
    fn try_withdraw_silver_public_prepared(payload: ::libs::field_buffer::FieldBuffer<270>) -> bool {
        let caller_class = aztec::oracle::get_contract_instance::get_contract_instance_current_class_id_avm(self.msg_sender());
        assert(caller_class.is_some(), "Only audited system");
        assert(caller_class.unwrap().to_field() == super::system_class::SYSTEM_CLASS, "Only audited system");
        let state_backend_address=AztecAddress::from_field(payload.words[0]);
        let plan_addresses=[AztecAddress::from_field(payload.words[1]), AztecAddress::from_field(payload.words[2]), AztecAddress::from_field(payload.words[3]), AztecAddress::from_field(payload.words[4]), AztecAddress::from_field(payload.words[5]), AztecAddress::from_field(payload.words[6]), AztecAddress::from_field(payload.words[7]), AztecAddress::from_field(payload.words[8]), AztecAddress::from_field(payload.words[9]), AztecAddress::from_field(payload.words[10])];
        let system_admin=AztecAddress::from_field(payload.words[11]);
        let location: Field = payload.words[12];
        let sender: AztecAddress = AztecAddress::from_field(payload.words[13]);
        let timestamp: u64 = (payload.words[14] as u64);
        let planet_state_hash: Field = payload.words[15];
        let planet_artifacts_state_hash: Field = payload.words[16];
        let planet_events_state_hash: Field = payload.words[17];
        let original_arrivals_count: u32 = (payload.words[18] as u32);
        let arrival_ids: [Field; 20] = [payload.words[19], payload.words[20], payload.words[21], payload.words[22], payload.words[23], payload.words[24], payload.words[25], payload.words[26], payload.words[27], payload.words[28], payload.words[29], payload.words[30], payload.words[31], payload.words[32], payload.words[33], payload.words[34], payload.words[35], payload.words[36], payload.words[37], payload.words[38]];
        let arrival_hashes: [Field; 20] = [payload.words[39], payload.words[40], payload.words[41], payload.words[42], payload.words[43], payload.words[44], payload.words[45], payload.words[46], payload.words[47], payload.words[48], payload.words[49], payload.words[50], payload.words[51], payload.words[52], payload.words[53], payload.words[54], payload.words[55], payload.words[56], payload.words[57], payload.words[58]];
        let arrival_artifact_ids: [Field; 20] = [payload.words[59], payload.words[60], payload.words[61], payload.words[62], payload.words[63], payload.words[64], payload.words[65], payload.words[66], payload.words[67], payload.words[68], payload.words[69], payload.words[70], payload.words[71], payload.words[72], payload.words[73], payload.words[74], payload.words[75], payload.words[76], payload.words[77], payload.words[78]];
        let arrival_artifact_hashes: [Field; 20] = [payload.words[79], payload.words[80], payload.words[81], payload.words[82], payload.words[83], payload.words[84], payload.words[85], payload.words[86], payload.words[87], payload.words[88], payload.words[89], payload.words[90], payload.words[91], payload.words[92], payload.words[93], payload.words[94], payload.words[95], payload.words[96], payload.words[97], payload.words[98]];
        let arrival_artifact_location_hashes: [Field; 20] = [payload.words[99], payload.words[100], payload.words[101], payload.words[102], payload.words[103], payload.words[104], payload.words[105], payload.words[106], payload.words[107], payload.words[108], payload.words[109], payload.words[110], payload.words[111], payload.words[112], payload.words[113], payload.words[114], payload.words[115], payload.words[116], payload.words[117], payload.words[118]];
        let player_state_hash: Field = payload.words[119];
        let world_config_hash: Field = payload.words[120];
        let world_hash: Field = payload.words[121];
        let new_planet: Planet = ::types::storage::planet::Planet { perlin: (payload.words[122] as u8), created_at: (payload.words[123] as u64), owner: AztecAddress::from_field(payload.words[124]), planet_level: (payload.words[125] as u8), planet_type: (payload.words[126] as u8), space_type: (payload.words[127] as u8), is_home_planet: (payload.words[128] == 1), is_initialized: (payload.words[129] == 1), destroyed: (payload.words[130] == 1), invader: AztecAddress::from_field(payload.words[131]), capturer: AztecAddress::from_field(payload.words[132]), invade_start_block: (payload.words[133] as u32), population_cap: (payload.words[134] as u128), population_growth: (payload.words[135] as u128), range: (payload.words[136] as u128), speed: (payload.words[137] as u128), defense: (payload.words[138] as u128), silver_cap: (payload.words[139] as u128), silver_growth: (payload.words[140] as u128), population: (payload.words[141] as u128), silver: (payload.words[142] as u128), upgrade_state_0: (payload.words[143] as u8), upgrade_state_1: (payload.words[144] as u8), upgrade_state_2: (payload.words[145] as u8), last_updated: (payload.words[146] as u64), pausers: (payload.words[147] as u128), energy_gro_doublers: (payload.words[148] as u128), silver_gro_doublers: (payload.words[149] as u128), hat_level: (payload.words[150] as u128), space_junk: (payload.words[151] as u128), has_tried_finding_artifact: (payload.words[152] == 1), prospected_block_number: (payload.words[153] as u32) };
        let new_planet_events_state: PlanetEvents = ::types::storage::planet::PlanetEvents { events: [::types::storage::planet::PlanetEventMetadata { id: payload.words[154] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[155] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[156] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[157] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[158] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[159] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[160] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[161] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[162] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[163] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[164] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[165] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[166] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[167] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[168] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[169] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[170] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[171] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[172] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[173] }], count: (payload.words[174] as u32), last_updated: (payload.words[175] as u64) };
        let new_planet_artifacts_state: PlanetArtifacts = ::types::storage::planet::PlanetArtifacts { ids: [payload.words[176], payload.words[177], payload.words[178], payload.words[179], payload.words[180], payload.words[181], payload.words[182], payload.words[183], payload.words[184], payload.words[185], payload.words[186], payload.words[187], payload.words[188], payload.words[189], payload.words[190], payload.words[191], payload.words[192], payload.words[193], payload.words[194], payload.words[195]], count: (payload.words[196] as u32), last_updated: (payload.words[197] as u64) };
        let new_arrival_artifact_locations: [ArtifactLocation; 20] = [::types::storage::artifact::ArtifactLocation { planet_id: payload.words[198], voyage_id: payload.words[199], last_updated: (payload.words[200] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[201], voyage_id: payload.words[202], last_updated: (payload.words[203] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[204], voyage_id: payload.words[205], last_updated: (payload.words[206] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[207], voyage_id: payload.words[208], last_updated: (payload.words[209] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[210], voyage_id: payload.words[211], last_updated: (payload.words[212] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[213], voyage_id: payload.words[214], last_updated: (payload.words[215] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[216], voyage_id: payload.words[217], last_updated: (payload.words[218] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[219], voyage_id: payload.words[220], last_updated: (payload.words[221] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[222], voyage_id: payload.words[223], last_updated: (payload.words[224] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[225], voyage_id: payload.words[226], last_updated: (payload.words[227] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[228], voyage_id: payload.words[229], last_updated: (payload.words[230] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[231], voyage_id: payload.words[232], last_updated: (payload.words[233] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[234], voyage_id: payload.words[235], last_updated: (payload.words[236] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[237], voyage_id: payload.words[238], last_updated: (payload.words[239] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[240], voyage_id: payload.words[241], last_updated: (payload.words[242] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[243], voyage_id: payload.words[244], last_updated: (payload.words[245] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[246], voyage_id: payload.words[247], last_updated: (payload.words[248] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[249], voyage_id: payload.words[250], last_updated: (payload.words[251] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[252], voyage_id: payload.words[253], last_updated: (payload.words[254] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[255], voyage_id: payload.words[256], last_updated: (payload.words[257] as u64) }];
        let new_player: Player = ::types::storage::player::Player { init_timestamp: (payload.words[258] as u64), home_planet_id: payload.words[259], last_reveal_timestamp: (payload.words[260] as u64), score: (payload.words[261] as u128), space_junk: (payload.words[262] as u128), space_junk_limit: (payload.words[263] as u128), claimed_ships: (payload.words[264] == 1), last_updated: (payload.words[265] as u64) };
        let prepared_new_planet_root: Field = payload.words[266];
        let prepared_new_planet_events_state_root: Field = payload.words[267];
        let prepared_new_planet_artifacts_state_root: Field = payload.words[268];
        let prepared_new_player_root: Field = payload.words[269];
        let supported = ::state_backend_readonly::public_read::can_settle(state_backend_address, plan_addresses, 1006);
        if supported {
            let mut write_plan = ::libs::state_plan::WritePlan::new();

        let actual_timestamp = self.context.timestamp();
        assert_public_timestamp(timestamp, actual_timestamp);

        let config = Config::at(plan_addresses[0]);









        assert(
            self.view(config.verify_world_config_hash(world_config_hash)),
            "World config hash mismatch",
        );

        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[3], location, planet_state_hash),
            "Planet state hash mismatch",
        );
        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[6], location, planet_artifacts_state_hash),
            "Planet artifacts state hash mismatch",
        );
        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[5], location, planet_events_state_hash),
            "Planet events state hash mismatch",
        );

        if original_arrivals_count != 0 {
            assert(
                ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[7], arrival_ids, arrival_hashes, original_arrivals_count),
                "Arrival hash mismatch",
            );
            if ::libs::batch_utils::has_nonzero_ids(arrival_artifact_ids, original_arrivals_count) {
                assert(
                    ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[8], arrival_artifact_ids, arrival_artifact_hashes, original_arrivals_count),
                    "Artifact hash mismatch",
                );

                assert(
                    ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[9], arrival_artifact_ids, arrival_artifact_location_hashes, original_arrivals_count),
                    "Artifact location hash mismatch",
                );
            }
        }

        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[2], (sender).to_field(), player_state_hash),
            "Player state hash mismatch",
        );

        assert(::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[1], 0, world_hash), "World state hash mismatch");

        write_plan.set(3, location, prepared_new_planet_root, true, new_planet.serialize());
        write_plan.set(5, location, prepared_new_planet_events_state_root, true, new_planet_events_state.serialize());
        write_plan.set(6, location, prepared_new_planet_artifacts_state_root, true, new_planet_artifacts_state.serialize());
        {
            let batch_start=write_plan.start_batch(9, original_arrivals_count, 20);
            let bounded_count = if (original_arrivals_count) <= 20 { original_arrivals_count } else { 20 };
            for plan_i in 0..bounded_count { if arrival_artifact_ids[plan_i] != 0 {
                write_plan.append_batch_item(batch_start, arrival_artifact_ids[plan_i], new_arrival_artifact_locations[plan_i].serialize());
            } }
        };
        write_plan.set(2, (sender).to_field(), prepared_new_player_root, true, new_player.serialize());

            _commit_plan_for_system(self.context, state_backend_address, plan_addresses, 1006, write_plan);
        }
        supported
    }

    #[external("public")]
    fn try_initialize_player_public_prepared(payload: ::libs::field_buffer::FieldBuffer<279>) -> bool {
        let caller_class = aztec::oracle::get_contract_instance::get_contract_instance_current_class_id_avm(self.msg_sender());
        assert(caller_class.is_some(), "Only audited system");
        assert(caller_class.unwrap().to_field() == super::system_class::SYSTEM_CLASS, "Only audited system");
        let state_backend_address=AztecAddress::from_field(payload.words[0]);
        let plan_addresses=[AztecAddress::from_field(payload.words[1]), AztecAddress::from_field(payload.words[2]), AztecAddress::from_field(payload.words[3]), AztecAddress::from_field(payload.words[4]), AztecAddress::from_field(payload.words[5]), AztecAddress::from_field(payload.words[6]), AztecAddress::from_field(payload.words[7]), AztecAddress::from_field(payload.words[8]), AztecAddress::from_field(payload.words[9]), AztecAddress::from_field(payload.words[10])];
        let system_admin=AztecAddress::from_field(payload.words[11]);
        let sender: AztecAddress = AztecAddress::from_field(payload.words[12]);
        let location_id: Field = payload.words[13];
        let timestamp: u64 = (payload.words[14] as u64);
        let config_hashes: [Field; 9] = [payload.words[15], payload.words[16], payload.words[17], payload.words[18], payload.words[19], payload.words[20], payload.words[21], payload.words[22], payload.words[23]];
        let planet_default_stats_hash: Field = payload.words[24];
        let planet_state_hash: Field = payload.words[25];
        let planet_artifacts_state_hash: Field = payload.words[26];
        let planet_events_state_hash: Field = payload.words[27];
        let original_arrivals_count: u32 = (payload.words[28] as u32);
        let arrival_ids: [Field; 20] = [payload.words[29], payload.words[30], payload.words[31], payload.words[32], payload.words[33], payload.words[34], payload.words[35], payload.words[36], payload.words[37], payload.words[38], payload.words[39], payload.words[40], payload.words[41], payload.words[42], payload.words[43], payload.words[44], payload.words[45], payload.words[46], payload.words[47], payload.words[48]];
        let arrival_hashes: [Field; 20] = [payload.words[49], payload.words[50], payload.words[51], payload.words[52], payload.words[53], payload.words[54], payload.words[55], payload.words[56], payload.words[57], payload.words[58], payload.words[59], payload.words[60], payload.words[61], payload.words[62], payload.words[63], payload.words[64], payload.words[65], payload.words[66], payload.words[67], payload.words[68]];
        let arrival_artifact_ids: [Field; 20] = [payload.words[69], payload.words[70], payload.words[71], payload.words[72], payload.words[73], payload.words[74], payload.words[75], payload.words[76], payload.words[77], payload.words[78], payload.words[79], payload.words[80], payload.words[81], payload.words[82], payload.words[83], payload.words[84], payload.words[85], payload.words[86], payload.words[87], payload.words[88]];
        let arrival_artifact_hashes: [Field; 20] = [payload.words[89], payload.words[90], payload.words[91], payload.words[92], payload.words[93], payload.words[94], payload.words[95], payload.words[96], payload.words[97], payload.words[98], payload.words[99], payload.words[100], payload.words[101], payload.words[102], payload.words[103], payload.words[104], payload.words[105], payload.words[106], payload.words[107], payload.words[108]];
        let arrival_artifact_location_hashes: [Field; 20] = [payload.words[109], payload.words[110], payload.words[111], payload.words[112], payload.words[113], payload.words[114], payload.words[115], payload.words[116], payload.words[117], payload.words[118], payload.words[119], payload.words[120], payload.words[121], payload.words[122], payload.words[123], payload.words[124], payload.words[125], payload.words[126], payload.words[127], payload.words[128]];
        let player_state_hash: Field = payload.words[129];
        let world_hash: Field = payload.words[130];
        let new_planet: Planet = ::types::storage::planet::Planet { perlin: (payload.words[131] as u8), created_at: (payload.words[132] as u64), owner: AztecAddress::from_field(payload.words[133]), planet_level: (payload.words[134] as u8), planet_type: (payload.words[135] as u8), space_type: (payload.words[136] as u8), is_home_planet: (payload.words[137] == 1), is_initialized: (payload.words[138] == 1), destroyed: (payload.words[139] == 1), invader: AztecAddress::from_field(payload.words[140]), capturer: AztecAddress::from_field(payload.words[141]), invade_start_block: (payload.words[142] as u32), population_cap: (payload.words[143] as u128), population_growth: (payload.words[144] as u128), range: (payload.words[145] as u128), speed: (payload.words[146] as u128), defense: (payload.words[147] as u128), silver_cap: (payload.words[148] as u128), silver_growth: (payload.words[149] as u128), population: (payload.words[150] as u128), silver: (payload.words[151] as u128), upgrade_state_0: (payload.words[152] as u8), upgrade_state_1: (payload.words[153] as u8), upgrade_state_2: (payload.words[154] as u8), last_updated: (payload.words[155] as u64), pausers: (payload.words[156] as u128), energy_gro_doublers: (payload.words[157] as u128), silver_gro_doublers: (payload.words[158] as u128), hat_level: (payload.words[159] as u128), space_junk: (payload.words[160] as u128), has_tried_finding_artifact: (payload.words[161] == 1), prospected_block_number: (payload.words[162] as u32) };
        let new_planet_events_state: PlanetEvents = ::types::storage::planet::PlanetEvents { events: [::types::storage::planet::PlanetEventMetadata { id: payload.words[163] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[164] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[165] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[166] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[167] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[168] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[169] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[170] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[171] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[172] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[173] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[174] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[175] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[176] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[177] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[178] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[179] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[180] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[181] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[182] }], count: (payload.words[183] as u32), last_updated: (payload.words[184] as u64) };
        let new_planet_artifacts_state: PlanetArtifacts = ::types::storage::planet::PlanetArtifacts { ids: [payload.words[185], payload.words[186], payload.words[187], payload.words[188], payload.words[189], payload.words[190], payload.words[191], payload.words[192], payload.words[193], payload.words[194], payload.words[195], payload.words[196], payload.words[197], payload.words[198], payload.words[199], payload.words[200], payload.words[201], payload.words[202], payload.words[203], payload.words[204]], count: (payload.words[205] as u32), last_updated: (payload.words[206] as u64) };
        let new_arrival_artifact_locations: [ArtifactLocation; 20] = [::types::storage::artifact::ArtifactLocation { planet_id: payload.words[207], voyage_id: payload.words[208], last_updated: (payload.words[209] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[210], voyage_id: payload.words[211], last_updated: (payload.words[212] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[213], voyage_id: payload.words[214], last_updated: (payload.words[215] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[216], voyage_id: payload.words[217], last_updated: (payload.words[218] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[219], voyage_id: payload.words[220], last_updated: (payload.words[221] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[222], voyage_id: payload.words[223], last_updated: (payload.words[224] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[225], voyage_id: payload.words[226], last_updated: (payload.words[227] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[228], voyage_id: payload.words[229], last_updated: (payload.words[230] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[231], voyage_id: payload.words[232], last_updated: (payload.words[233] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[234], voyage_id: payload.words[235], last_updated: (payload.words[236] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[237], voyage_id: payload.words[238], last_updated: (payload.words[239] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[240], voyage_id: payload.words[241], last_updated: (payload.words[242] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[243], voyage_id: payload.words[244], last_updated: (payload.words[245] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[246], voyage_id: payload.words[247], last_updated: (payload.words[248] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[249], voyage_id: payload.words[250], last_updated: (payload.words[251] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[252], voyage_id: payload.words[253], last_updated: (payload.words[254] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[255], voyage_id: payload.words[256], last_updated: (payload.words[257] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[258], voyage_id: payload.words[259], last_updated: (payload.words[260] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[261], voyage_id: payload.words[262], last_updated: (payload.words[263] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[264], voyage_id: payload.words[265], last_updated: (payload.words[266] as u64) }];
        let new_player: Player = ::types::storage::player::Player { init_timestamp: (payload.words[267] as u64), home_planet_id: payload.words[268], last_reveal_timestamp: (payload.words[269] as u64), score: (payload.words[270] as u128), space_junk: (payload.words[271] as u128), space_junk_limit: (payload.words[272] as u128), claimed_ships: (payload.words[273] == 1), last_updated: (payload.words[274] as u64) };
        let prepared_new_planet_root: Field = payload.words[275];
        let prepared_new_planet_events_state_root: Field = payload.words[276];
        let prepared_new_planet_artifacts_state_root: Field = payload.words[277];
        let prepared_new_player_root: Field = payload.words[278];
        let supported = ::state_backend_readonly::public_read::can_settle(state_backend_address, plan_addresses, 1006);
        if supported {
            let mut write_plan = ::libs::state_plan::WritePlan::new();

        let actual_timestamp = self.context.timestamp();
        assert_public_timestamp(timestamp, actual_timestamp);

        let config = Config::at(plan_addresses[0]);




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
        assert(!::state_backend_readonly::public_read::is_initialized(state_backend_address, plan_addresses[2], (sender).to_field()), "Player already initialized");

        // Verify world state
        assert(world_hash != 0, "World state must be initialized");
        assert(::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[1], 0, world_hash), "World state hash mismatch");

        // Planet: verify hashes and write states
        if planet_state_hash == 0 {
            // New planet - just write it
            write_plan.set(3, location_id, prepared_new_planet_root, true, new_planet.serialize());
        } else {
            // Existing planet - verify all hashes then write refreshed states






            assert(
                ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[3], location_id, planet_state_hash),
                "Planet state hash mismatch",
            );
            assert(
                ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[6], location_id, planet_artifacts_state_hash),
                "Planet artifacts state hash mismatch",
            );
            assert(
                ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[5], location_id, planet_events_state_hash),
                "Planet events state hash mismatch",
            );
            if original_arrivals_count != 0 {
                assert(
                    ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[7], arrival_ids, arrival_hashes, original_arrivals_count),
                    "Arrival hash mismatch",
                );
                if ::libs::batch_utils::has_nonzero_ids(
                    arrival_artifact_ids,
                    original_arrivals_count,
                ) {
                    assert(
                        ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[8], arrival_artifact_ids, arrival_artifact_hashes, original_arrivals_count),
                        "Artifact hash mismatch",
                    );

                    assert(
                        ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[9], arrival_artifact_ids, arrival_artifact_location_hashes, original_arrivals_count),
                        "Artifact location hash mismatch",
                    );
                }
            }

            write_plan.set(3, location_id, prepared_new_planet_root, true, new_planet.serialize());
            write_plan.set(5, location_id, prepared_new_planet_events_state_root, true, new_planet_events_state.serialize());
            write_plan.set(6, location_id, prepared_new_planet_artifacts_state_root, true, new_planet_artifacts_state.serialize());
            {
            let batch_start=write_plan.start_batch(9, original_arrivals_count, 20);
            let bounded_count = if (original_arrivals_count) <= 20 { original_arrivals_count } else { 20 };
            for plan_i in 0..bounded_count { if arrival_artifact_ids[plan_i] != 0 {
                write_plan.append_batch_item(batch_start, arrival_artifact_ids[plan_i], new_arrival_artifact_locations[plan_i].serialize());
            } }
        };
        }

        // Write new player
        write_plan.set(2, (sender).to_field(), prepared_new_player_root, true, new_player.serialize());

            _commit_plan_for_system(self.context, state_backend_address, plan_addresses, 1006, write_plan);
        }
        supported
    }

    // Build complete calldata once; the guarded backend accepts canonical fields.
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
        } else if plan.length <= 172 {
            let selector = comptime { aztec::protocol::abis::function_selector::FunctionSelector::from_signature("commit_plan_medium(([Field;185]))") };
            let calldata=[selector.to_field(), self.msg_sender().to_field(), addresses[0].to_field(), addresses[1].to_field(), addresses[2].to_field(), addresses[3].to_field(), addresses[4].to_field(), addresses[5].to_field(), addresses[6].to_field(), addresses[7].to_field(), addresses[8].to_field(), addresses[9].to_field(), required_mask as Field, plan.words[0], plan.words[1], plan.words[2], plan.words[3], plan.words[4], plan.words[5], plan.words[6], plan.words[7], plan.words[8], plan.words[9], plan.words[10], plan.words[11], plan.words[12], plan.words[13], plan.words[14], plan.words[15], plan.words[16], plan.words[17], plan.words[18], plan.words[19], plan.words[20], plan.words[21], plan.words[22], plan.words[23], plan.words[24], plan.words[25], plan.words[26], plan.words[27], plan.words[28], plan.words[29], plan.words[30], plan.words[31], plan.words[32], plan.words[33], plan.words[34], plan.words[35], plan.words[36], plan.words[37], plan.words[38], plan.words[39], plan.words[40], plan.words[41], plan.words[42], plan.words[43], plan.words[44], plan.words[45], plan.words[46], plan.words[47], plan.words[48], plan.words[49], plan.words[50], plan.words[51], plan.words[52], plan.words[53], plan.words[54], plan.words[55], plan.words[56], plan.words[57], plan.words[58], plan.words[59], plan.words[60], plan.words[61], plan.words[62], plan.words[63], plan.words[64], plan.words[65], plan.words[66], plan.words[67], plan.words[68], plan.words[69], plan.words[70], plan.words[71], plan.words[72], plan.words[73], plan.words[74], plan.words[75], plan.words[76], plan.words[77], plan.words[78], plan.words[79], plan.words[80], plan.words[81], plan.words[82], plan.words[83], plan.words[84], plan.words[85], plan.words[86], plan.words[87], plan.words[88], plan.words[89], plan.words[90], plan.words[91], plan.words[92], plan.words[93], plan.words[94], plan.words[95], plan.words[96], plan.words[97], plan.words[98], plan.words[99], plan.words[100], plan.words[101], plan.words[102], plan.words[103], plan.words[104], plan.words[105], plan.words[106], plan.words[107], plan.words[108], plan.words[109], plan.words[110], plan.words[111], plan.words[112], plan.words[113], plan.words[114], plan.words[115], plan.words[116], plan.words[117], plan.words[118], plan.words[119], plan.words[120], plan.words[121], plan.words[122], plan.words[123], plan.words[124], plan.words[125], plan.words[126], plan.words[127], plan.words[128], plan.words[129], plan.words[130], plan.words[131], plan.words[132], plan.words[133], plan.words[134], plan.words[135], plan.words[136], plan.words[137], plan.words[138], plan.words[139], plan.words[140], plan.words[141], plan.words[142], plan.words[143], plan.words[144], plan.words[145], plan.words[146], plan.words[147], plan.words[148], plan.words[149], plan.words[150], plan.words[151], plan.words[152], plan.words[153], plan.words[154], plan.words[155], plan.words[156], plan.words[157], plan.words[158], plan.words[159], plan.words[160], plan.words[161], plan.words[162], plan.words[163], plan.words[164], plan.words[165], plan.words[166], plan.words[167], plan.words[168], plan.words[169], plan.words[170], plan.words[171], plan.length as Field];

            let result=::libs::public_call::call(backend_address,calldata);
            assert(result.len()==0, "Unexpected settlement result");
        } else {
            let selector = comptime { aztec::protocol::abis::function_selector::FunctionSelector::from_signature("commit_plan(([Field;397]))") };
            let mut calldata:[Field;398]=[0;398];
            calldata[0]=selector.to_field();
            calldata[1]=self.msg_sender().to_field();
            for i in 0..10 { calldata[2+i]=addresses[i].to_field(); }
            calldata[12]=required_mask as Field;
            for i in 0..384 { if i < plan.length { calldata[13+i]=plan.words[i]; } }
            calldata[397]=plan.length as Field;

            let result=::libs::public_call::call(backend_address,calldata);
            assert(result.len()==0, "Unexpected settlement result");
        }
    }

}
