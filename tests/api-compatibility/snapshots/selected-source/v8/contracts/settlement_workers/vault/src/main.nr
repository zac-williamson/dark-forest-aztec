// Generated stateless settlement worker. The actor is its authenticated System caller.
mod system_class;
use ::aztec::macros::aztec;

#[aztec]
pub contract VaultSettlementWorker {
    use aztec::protocol::traits::FromField;

    use aztec::protocol::traits::Deserialize;

    use aztec::protocol::traits::ToField;

    use ::game_state_backend::GameStateBackend;

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
        reserved: PublicMutable<Field,Context>,
    }
    #[external("public")] #[initializer]
    fn constructor() {}
    #[external("public")]
    fn try_deposit_artifact_public_prepared(payload: ::libs::field_buffer::FieldBuffer<279>) -> bool {
        let caller_class = aztec::oracle::get_contract_instance::get_contract_instance_current_class_id_avm(self.msg_sender());
        assert(caller_class.is_some(), "Only audited system");
        assert(caller_class.unwrap().to_field() == super::system_class::SYSTEM_CLASS, "Only audited system");
        let state_backend_address=AztecAddress::from_field(payload.words[0]);
        let plan_addresses=[AztecAddress::from_field(payload.words[1]), AztecAddress::from_field(payload.words[2]), AztecAddress::from_field(payload.words[3]), AztecAddress::from_field(payload.words[4]), AztecAddress::from_field(payload.words[5]), AztecAddress::from_field(payload.words[6]), AztecAddress::from_field(payload.words[7]), AztecAddress::from_field(payload.words[8]), AztecAddress::from_field(payload.words[9]), AztecAddress::from_field(payload.words[10])];
        let system_admin=AztecAddress::from_field(payload.words[11]);
        let location_id: Field = payload.words[12];
        let artifact_id: Field = payload.words[13];
        let timestamp: u64 = (payload.words[14] as u64);
        let planet_hash: Field = payload.words[15];
        let planet_artifacts_state_hash: Field = payload.words[16];
        let planet_events_state_hash: Field = payload.words[17];
        let origin_arrivals_count: u32 = (payload.words[18] as u32);
        let arrival_ids: [Field; 20] = [payload.words[19], payload.words[20], payload.words[21], payload.words[22], payload.words[23], payload.words[24], payload.words[25], payload.words[26], payload.words[27], payload.words[28], payload.words[29], payload.words[30], payload.words[31], payload.words[32], payload.words[33], payload.words[34], payload.words[35], payload.words[36], payload.words[37], payload.words[38]];
        let arrival_hashes: [Field; 20] = [payload.words[39], payload.words[40], payload.words[41], payload.words[42], payload.words[43], payload.words[44], payload.words[45], payload.words[46], payload.words[47], payload.words[48], payload.words[49], payload.words[50], payload.words[51], payload.words[52], payload.words[53], payload.words[54], payload.words[55], payload.words[56], payload.words[57], payload.words[58]];
        let artifact_ids: [Field; 20] = [payload.words[59], payload.words[60], payload.words[61], payload.words[62], payload.words[63], payload.words[64], payload.words[65], payload.words[66], payload.words[67], payload.words[68], payload.words[69], payload.words[70], payload.words[71], payload.words[72], payload.words[73], payload.words[74], payload.words[75], payload.words[76], payload.words[77], payload.words[78]];
        let artifact_hashes: [Field; 20] = [payload.words[79], payload.words[80], payload.words[81], payload.words[82], payload.words[83], payload.words[84], payload.words[85], payload.words[86], payload.words[87], payload.words[88], payload.words[89], payload.words[90], payload.words[91], payload.words[92], payload.words[93], payload.words[94], payload.words[95], payload.words[96], payload.words[97], payload.words[98]];
        let artifact_location_hashes: [Field; 20] = [payload.words[99], payload.words[100], payload.words[101], payload.words[102], payload.words[103], payload.words[104], payload.words[105], payload.words[106], payload.words[107], payload.words[108], payload.words[109], payload.words[110], payload.words[111], payload.words[112], payload.words[113], payload.words[114], payload.words[115], payload.words[116], payload.words[117], payload.words[118]];
        let artifact_hash: Field = payload.words[119];
        let artifact_location_hash: Field = payload.words[120];
        let world_hash: Field = payload.words[121];
        let new_planet: Planet = ::types::storage::planet::Planet { perlin: (payload.words[122] as u8), created_at: (payload.words[123] as u64), owner: AztecAddress::from_field(payload.words[124]), planet_level: (payload.words[125] as u8), planet_type: (payload.words[126] as u8), space_type: (payload.words[127] as u8), is_home_planet: (payload.words[128] == 1), is_initialized: (payload.words[129] == 1), destroyed: (payload.words[130] == 1), invader: AztecAddress::from_field(payload.words[131]), capturer: AztecAddress::from_field(payload.words[132]), invade_start_block: (payload.words[133] as u32), population_cap: (payload.words[134] as u128), population_growth: (payload.words[135] as u128), range: (payload.words[136] as u128), speed: (payload.words[137] as u128), defense: (payload.words[138] as u128), silver_cap: (payload.words[139] as u128), silver_growth: (payload.words[140] as u128), population: (payload.words[141] as u128), silver: (payload.words[142] as u128), upgrade_state_0: (payload.words[143] as u8), upgrade_state_1: (payload.words[144] as u8), upgrade_state_2: (payload.words[145] as u8), last_updated: (payload.words[146] as u64), pausers: (payload.words[147] as u128), energy_gro_doublers: (payload.words[148] as u128), silver_gro_doublers: (payload.words[149] as u128), hat_level: (payload.words[150] as u128), space_junk: (payload.words[151] as u128), has_tried_finding_artifact: (payload.words[152] == 1), prospected_block_number: (payload.words[153] as u32) };
        let new_planet_artifacts_state: PlanetArtifacts = ::types::storage::planet::PlanetArtifacts { ids: [payload.words[154], payload.words[155], payload.words[156], payload.words[157], payload.words[158], payload.words[159], payload.words[160], payload.words[161], payload.words[162], payload.words[163], payload.words[164], payload.words[165], payload.words[166], payload.words[167], payload.words[168], payload.words[169], payload.words[170], payload.words[171], payload.words[172], payload.words[173]], count: (payload.words[174] as u32), last_updated: (payload.words[175] as u64) };
        let new_planet_events_state: PlanetEvents = ::types::storage::planet::PlanetEvents { events: [::types::storage::planet::PlanetEventMetadata { id: payload.words[176] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[177] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[178] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[179] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[180] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[181] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[182] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[183] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[184] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[185] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[186] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[187] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[188] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[189] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[190] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[191] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[192] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[193] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[194] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[195] }], count: (payload.words[196] as u32), last_updated: (payload.words[197] as u64) };
        let new_artifact_locations: [ArtifactLocation; 20] = [::types::storage::artifact::ArtifactLocation { planet_id: payload.words[198], voyage_id: payload.words[199], last_updated: (payload.words[200] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[201], voyage_id: payload.words[202], last_updated: (payload.words[203] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[204], voyage_id: payload.words[205], last_updated: (payload.words[206] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[207], voyage_id: payload.words[208], last_updated: (payload.words[209] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[210], voyage_id: payload.words[211], last_updated: (payload.words[212] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[213], voyage_id: payload.words[214], last_updated: (payload.words[215] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[216], voyage_id: payload.words[217], last_updated: (payload.words[218] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[219], voyage_id: payload.words[220], last_updated: (payload.words[221] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[222], voyage_id: payload.words[223], last_updated: (payload.words[224] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[225], voyage_id: payload.words[226], last_updated: (payload.words[227] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[228], voyage_id: payload.words[229], last_updated: (payload.words[230] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[231], voyage_id: payload.words[232], last_updated: (payload.words[233] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[234], voyage_id: payload.words[235], last_updated: (payload.words[236] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[237], voyage_id: payload.words[238], last_updated: (payload.words[239] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[240], voyage_id: payload.words[241], last_updated: (payload.words[242] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[243], voyage_id: payload.words[244], last_updated: (payload.words[245] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[246], voyage_id: payload.words[247], last_updated: (payload.words[248] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[249], voyage_id: payload.words[250], last_updated: (payload.words[251] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[252], voyage_id: payload.words[253], last_updated: (payload.words[254] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[255], voyage_id: payload.words[256], last_updated: (payload.words[257] as u64) }];
        let new_artifact: Artifact = ::types::storage::artifact::Artifact { planet_discovered_on: payload.words[258], rarity: (payload.words[259] as u8), planet_biome: (payload.words[260] as u8), minted_at_timestamp: (payload.words[261] as u64), discoverer: AztecAddress::from_field(payload.words[262]), artifact_type: (payload.words[263] as u8), activations: (payload.words[264] as u128), last_activated: (payload.words[265] as u64), last_deactivated: (payload.words[266] as u64), wormhole_to: payload.words[267], owner: AztecAddress::from_field(payload.words[268]), controller: AztecAddress::from_field(payload.words[269]), last_updated: (payload.words[270] as u64) };
        let new_artifact_location: ArtifactLocation = ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[271], voyage_id: payload.words[272], last_updated: (payload.words[273] as u64) };
        let prepared_new_planet_root: Field = payload.words[274];
        let prepared_new_planet_artifacts_state_root: Field = payload.words[275];
        let prepared_new_planet_events_state_root: Field = payload.words[276];
        let prepared_new_artifact_root: Field = payload.words[277];
        let prepared_new_artifact_location_root: Field = payload.words[278];
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
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[6], location_id, planet_artifacts_state_hash),
            "planet_artifacts hash mismatch",
        );
        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[5], location_id, planet_events_state_hash),
            "planet_events hash mismatch",
        );

        if origin_arrivals_count != 0 {
            assert(
                ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[7], arrival_ids, arrival_hashes, origin_arrivals_count as u32),
                "arrivals hash mismatch",
            );
            if ::libs::batch_utils::has_nonzero_ids(artifact_ids, origin_arrivals_count as u32) {
                assert(
                    ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[8], artifact_ids, artifact_hashes, origin_arrivals_count as u32),
                    "artifacts hash mismatch",
                );

                assert(
                    ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[9], artifact_ids, artifact_location_hashes, origin_arrivals_count as u32),
                    "artifact locations hash mismatch",
                );
            }
        }

        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[8], artifact_id, artifact_hash),
            "artifact hash mismatch",
        );
        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[9], artifact_id, artifact_location_hash),
            "artifact location hash mismatch",
        );

        assert(::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[1], 0, world_hash), "world hash mismatch");

        write_plan.set(3, location_id, prepared_new_planet_root, true, new_planet.serialize());
        write_plan.set(6, location_id, prepared_new_planet_artifacts_state_root, true, new_planet_artifacts_state.serialize());
        write_plan.set(5, location_id, prepared_new_planet_events_state_root, true, new_planet_events_state.serialize());
        {
            let batch_start=write_plan.start_batch(9, origin_arrivals_count as u32, 20);
            let bounded_count = if (origin_arrivals_count as u32) <= 20 { origin_arrivals_count as u32 } else { 20 };
            for plan_i in 0..bounded_count { if artifact_ids[plan_i] != 0 {
                write_plan.append_batch_item(batch_start, artifact_ids[plan_i], new_artifact_locations[plan_i].serialize());
            } }
        };

        write_plan.set(8, artifact_id, prepared_new_artifact_root, true, new_artifact.serialize());
        write_plan.set(9, artifact_id, prepared_new_artifact_location_root, true, new_artifact_location.serialize());

            _commit_plan_for_system(self.context, state_backend_address, plan_addresses, 1002, write_plan);
        }
        supported
    }

    #[external("public")]
    fn try_withdraw_artifact_public_prepared(payload: ::libs::field_buffer::FieldBuffer<279>) -> bool {
        let caller_class = aztec::oracle::get_contract_instance::get_contract_instance_current_class_id_avm(self.msg_sender());
        assert(caller_class.is_some(), "Only audited system");
        assert(caller_class.unwrap().to_field() == super::system_class::SYSTEM_CLASS, "Only audited system");
        let state_backend_address=AztecAddress::from_field(payload.words[0]);
        let plan_addresses=[AztecAddress::from_field(payload.words[1]), AztecAddress::from_field(payload.words[2]), AztecAddress::from_field(payload.words[3]), AztecAddress::from_field(payload.words[4]), AztecAddress::from_field(payload.words[5]), AztecAddress::from_field(payload.words[6]), AztecAddress::from_field(payload.words[7]), AztecAddress::from_field(payload.words[8]), AztecAddress::from_field(payload.words[9]), AztecAddress::from_field(payload.words[10])];
        let system_admin=AztecAddress::from_field(payload.words[11]);
        let location_id: Field = payload.words[12];
        let artifact_id: Field = payload.words[13];
        let timestamp: u64 = (payload.words[14] as u64);
        let planet_hash: Field = payload.words[15];
        let planet_artifacts_state_hash: Field = payload.words[16];
        let planet_events_state_hash: Field = payload.words[17];
        let origin_arrivals_count: u32 = (payload.words[18] as u32);
        let arrival_ids: [Field; 20] = [payload.words[19], payload.words[20], payload.words[21], payload.words[22], payload.words[23], payload.words[24], payload.words[25], payload.words[26], payload.words[27], payload.words[28], payload.words[29], payload.words[30], payload.words[31], payload.words[32], payload.words[33], payload.words[34], payload.words[35], payload.words[36], payload.words[37], payload.words[38]];
        let arrival_hashes: [Field; 20] = [payload.words[39], payload.words[40], payload.words[41], payload.words[42], payload.words[43], payload.words[44], payload.words[45], payload.words[46], payload.words[47], payload.words[48], payload.words[49], payload.words[50], payload.words[51], payload.words[52], payload.words[53], payload.words[54], payload.words[55], payload.words[56], payload.words[57], payload.words[58]];
        let artifact_ids: [Field; 20] = [payload.words[59], payload.words[60], payload.words[61], payload.words[62], payload.words[63], payload.words[64], payload.words[65], payload.words[66], payload.words[67], payload.words[68], payload.words[69], payload.words[70], payload.words[71], payload.words[72], payload.words[73], payload.words[74], payload.words[75], payload.words[76], payload.words[77], payload.words[78]];
        let artifact_hashes: [Field; 20] = [payload.words[79], payload.words[80], payload.words[81], payload.words[82], payload.words[83], payload.words[84], payload.words[85], payload.words[86], payload.words[87], payload.words[88], payload.words[89], payload.words[90], payload.words[91], payload.words[92], payload.words[93], payload.words[94], payload.words[95], payload.words[96], payload.words[97], payload.words[98]];
        let artifact_location_hashes: [Field; 20] = [payload.words[99], payload.words[100], payload.words[101], payload.words[102], payload.words[103], payload.words[104], payload.words[105], payload.words[106], payload.words[107], payload.words[108], payload.words[109], payload.words[110], payload.words[111], payload.words[112], payload.words[113], payload.words[114], payload.words[115], payload.words[116], payload.words[117], payload.words[118]];
        let artifact_hash: Field = payload.words[119];
        let artifact_location_hash: Field = payload.words[120];
        let world_hash: Field = payload.words[121];
        let new_planet: Planet = ::types::storage::planet::Planet { perlin: (payload.words[122] as u8), created_at: (payload.words[123] as u64), owner: AztecAddress::from_field(payload.words[124]), planet_level: (payload.words[125] as u8), planet_type: (payload.words[126] as u8), space_type: (payload.words[127] as u8), is_home_planet: (payload.words[128] == 1), is_initialized: (payload.words[129] == 1), destroyed: (payload.words[130] == 1), invader: AztecAddress::from_field(payload.words[131]), capturer: AztecAddress::from_field(payload.words[132]), invade_start_block: (payload.words[133] as u32), population_cap: (payload.words[134] as u128), population_growth: (payload.words[135] as u128), range: (payload.words[136] as u128), speed: (payload.words[137] as u128), defense: (payload.words[138] as u128), silver_cap: (payload.words[139] as u128), silver_growth: (payload.words[140] as u128), population: (payload.words[141] as u128), silver: (payload.words[142] as u128), upgrade_state_0: (payload.words[143] as u8), upgrade_state_1: (payload.words[144] as u8), upgrade_state_2: (payload.words[145] as u8), last_updated: (payload.words[146] as u64), pausers: (payload.words[147] as u128), energy_gro_doublers: (payload.words[148] as u128), silver_gro_doublers: (payload.words[149] as u128), hat_level: (payload.words[150] as u128), space_junk: (payload.words[151] as u128), has_tried_finding_artifact: (payload.words[152] == 1), prospected_block_number: (payload.words[153] as u32) };
        let new_planet_artifacts_state: PlanetArtifacts = ::types::storage::planet::PlanetArtifacts { ids: [payload.words[154], payload.words[155], payload.words[156], payload.words[157], payload.words[158], payload.words[159], payload.words[160], payload.words[161], payload.words[162], payload.words[163], payload.words[164], payload.words[165], payload.words[166], payload.words[167], payload.words[168], payload.words[169], payload.words[170], payload.words[171], payload.words[172], payload.words[173]], count: (payload.words[174] as u32), last_updated: (payload.words[175] as u64) };
        let new_planet_events_state: PlanetEvents = ::types::storage::planet::PlanetEvents { events: [::types::storage::planet::PlanetEventMetadata { id: payload.words[176] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[177] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[178] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[179] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[180] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[181] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[182] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[183] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[184] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[185] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[186] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[187] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[188] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[189] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[190] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[191] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[192] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[193] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[194] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[195] }], count: (payload.words[196] as u32), last_updated: (payload.words[197] as u64) };
        let new_artifact_locations: [ArtifactLocation; 20] = [::types::storage::artifact::ArtifactLocation { planet_id: payload.words[198], voyage_id: payload.words[199], last_updated: (payload.words[200] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[201], voyage_id: payload.words[202], last_updated: (payload.words[203] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[204], voyage_id: payload.words[205], last_updated: (payload.words[206] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[207], voyage_id: payload.words[208], last_updated: (payload.words[209] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[210], voyage_id: payload.words[211], last_updated: (payload.words[212] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[213], voyage_id: payload.words[214], last_updated: (payload.words[215] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[216], voyage_id: payload.words[217], last_updated: (payload.words[218] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[219], voyage_id: payload.words[220], last_updated: (payload.words[221] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[222], voyage_id: payload.words[223], last_updated: (payload.words[224] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[225], voyage_id: payload.words[226], last_updated: (payload.words[227] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[228], voyage_id: payload.words[229], last_updated: (payload.words[230] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[231], voyage_id: payload.words[232], last_updated: (payload.words[233] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[234], voyage_id: payload.words[235], last_updated: (payload.words[236] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[237], voyage_id: payload.words[238], last_updated: (payload.words[239] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[240], voyage_id: payload.words[241], last_updated: (payload.words[242] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[243], voyage_id: payload.words[244], last_updated: (payload.words[245] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[246], voyage_id: payload.words[247], last_updated: (payload.words[248] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[249], voyage_id: payload.words[250], last_updated: (payload.words[251] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[252], voyage_id: payload.words[253], last_updated: (payload.words[254] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[255], voyage_id: payload.words[256], last_updated: (payload.words[257] as u64) }];
        let new_artifact: Artifact = ::types::storage::artifact::Artifact { planet_discovered_on: payload.words[258], rarity: (payload.words[259] as u8), planet_biome: (payload.words[260] as u8), minted_at_timestamp: (payload.words[261] as u64), discoverer: AztecAddress::from_field(payload.words[262]), artifact_type: (payload.words[263] as u8), activations: (payload.words[264] as u128), last_activated: (payload.words[265] as u64), last_deactivated: (payload.words[266] as u64), wormhole_to: payload.words[267], owner: AztecAddress::from_field(payload.words[268]), controller: AztecAddress::from_field(payload.words[269]), last_updated: (payload.words[270] as u64) };
        let new_artifact_location: ArtifactLocation = ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[271], voyage_id: payload.words[272], last_updated: (payload.words[273] as u64) };
        let prepared_new_planet_root: Field = payload.words[274];
        let prepared_new_planet_artifacts_state_root: Field = payload.words[275];
        let prepared_new_planet_events_state_root: Field = payload.words[276];
        let prepared_new_artifact_root: Field = payload.words[277];
        let prepared_new_artifact_location_root: Field = payload.words[278];
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
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[6], location_id, planet_artifacts_state_hash),
            "planet_artifacts hash mismatch",
        );
        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[5], location_id, planet_events_state_hash),
            "planet_events hash mismatch",
        );

        if origin_arrivals_count != 0 {
            assert(
                ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[7], arrival_ids, arrival_hashes, origin_arrivals_count as u32),
                "arrivals hash mismatch",
            );
            if ::libs::batch_utils::has_nonzero_ids(artifact_ids, origin_arrivals_count as u32) {
                assert(
                    ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[8], artifact_ids, artifact_hashes, origin_arrivals_count as u32),
                    "artifacts hash mismatch",
                );

                assert(
                    ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[9], artifact_ids, artifact_location_hashes, origin_arrivals_count as u32),
                    "artifact locations hash mismatch",
                );
            }
        }

        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[8], artifact_id, artifact_hash),
            "artifact hash mismatch",
        );
        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[9], artifact_id, artifact_location_hash),
            "artifact location hash mismatch",
        );

        assert(::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[1], 0, world_hash), "world hash mismatch");

        write_plan.set(3, location_id, prepared_new_planet_root, true, new_planet.serialize());
        write_plan.set(6, location_id, prepared_new_planet_artifacts_state_root, true, new_planet_artifacts_state.serialize());
        write_plan.set(5, location_id, prepared_new_planet_events_state_root, true, new_planet_events_state.serialize());
        {
            let batch_start=write_plan.start_batch(9, origin_arrivals_count as u32, 20);
            let bounded_count = if (origin_arrivals_count as u32) <= 20 { origin_arrivals_count as u32 } else { 20 };
            for plan_i in 0..bounded_count { if artifact_ids[plan_i] != 0 {
                write_plan.append_batch_item(batch_start, artifact_ids[plan_i], new_artifact_locations[plan_i].serialize());
            } }
        };

        write_plan.set(8, artifact_id, prepared_new_artifact_root, true, new_artifact.serialize());
        write_plan.set(9, artifact_id, prepared_new_artifact_location_root, true, new_artifact_location.serialize());

            _commit_plan_for_system(self.context, state_backend_address, plan_addresses, 1002, write_plan);
        }
        supported
    }

    #[external("public")]
    fn try_give_spaceships_public_prepared(payload: ::libs::field_buffer::FieldBuffer<353>) -> bool {
        let caller_class = aztec::oracle::get_contract_instance::get_contract_instance_current_class_id_avm(self.msg_sender());
        assert(caller_class.is_some(), "Only audited system");
        assert(caller_class.unwrap().to_field() == super::system_class::SYSTEM_CLASS, "Only audited system");
        let state_backend_address=AztecAddress::from_field(payload.words[0]);
        let plan_addresses=[AztecAddress::from_field(payload.words[1]), AztecAddress::from_field(payload.words[2]), AztecAddress::from_field(payload.words[3]), AztecAddress::from_field(payload.words[4]), AztecAddress::from_field(payload.words[5]), AztecAddress::from_field(payload.words[6]), AztecAddress::from_field(payload.words[7]), AztecAddress::from_field(payload.words[8]), AztecAddress::from_field(payload.words[9]), AztecAddress::from_field(payload.words[10])];
        let system_admin=AztecAddress::from_field(payload.words[11]);
        let sender: AztecAddress = AztecAddress::from_field(payload.words[12]);
        let location_id: Field = payload.words[13];
        let timestamp: u64 = (payload.words[14] as u64);
        let planet_hash: Field = payload.words[15];
        let planet_artifacts_state_hash: Field = payload.words[16];
        let planet_events_state_hash: Field = payload.words[17];
        let arrival_ids: [Field; 20] = [payload.words[18], payload.words[19], payload.words[20], payload.words[21], payload.words[22], payload.words[23], payload.words[24], payload.words[25], payload.words[26], payload.words[27], payload.words[28], payload.words[29], payload.words[30], payload.words[31], payload.words[32], payload.words[33], payload.words[34], payload.words[35], payload.words[36], payload.words[37]];
        let arrival_hashes: [Field; 20] = [payload.words[38], payload.words[39], payload.words[40], payload.words[41], payload.words[42], payload.words[43], payload.words[44], payload.words[45], payload.words[46], payload.words[47], payload.words[48], payload.words[49], payload.words[50], payload.words[51], payload.words[52], payload.words[53], payload.words[54], payload.words[55], payload.words[56], payload.words[57]];
        let artifact_ids: [Field; 20] = [payload.words[58], payload.words[59], payload.words[60], payload.words[61], payload.words[62], payload.words[63], payload.words[64], payload.words[65], payload.words[66], payload.words[67], payload.words[68], payload.words[69], payload.words[70], payload.words[71], payload.words[72], payload.words[73], payload.words[74], payload.words[75], payload.words[76], payload.words[77]];
        let artifact_hashes: [Field; 20] = [payload.words[78], payload.words[79], payload.words[80], payload.words[81], payload.words[82], payload.words[83], payload.words[84], payload.words[85], payload.words[86], payload.words[87], payload.words[88], payload.words[89], payload.words[90], payload.words[91], payload.words[92], payload.words[93], payload.words[94], payload.words[95], payload.words[96], payload.words[97]];
        let artifact_location_hashes: [Field; 20] = [payload.words[98], payload.words[99], payload.words[100], payload.words[101], payload.words[102], payload.words[103], payload.words[104], payload.words[105], payload.words[106], payload.words[107], payload.words[108], payload.words[109], payload.words[110], payload.words[111], payload.words[112], payload.words[113], payload.words[114], payload.words[115], payload.words[116], payload.words[117]];
        let origin_arrivals_count: u32 = (payload.words[118] as u32);
        let player_hash: Field = payload.words[119];
        let new_planet: Planet = ::types::storage::planet::Planet { perlin: (payload.words[120] as u8), created_at: (payload.words[121] as u64), owner: AztecAddress::from_field(payload.words[122]), planet_level: (payload.words[123] as u8), planet_type: (payload.words[124] as u8), space_type: (payload.words[125] as u8), is_home_planet: (payload.words[126] == 1), is_initialized: (payload.words[127] == 1), destroyed: (payload.words[128] == 1), invader: AztecAddress::from_field(payload.words[129]), capturer: AztecAddress::from_field(payload.words[130]), invade_start_block: (payload.words[131] as u32), population_cap: (payload.words[132] as u128), population_growth: (payload.words[133] as u128), range: (payload.words[134] as u128), speed: (payload.words[135] as u128), defense: (payload.words[136] as u128), silver_cap: (payload.words[137] as u128), silver_growth: (payload.words[138] as u128), population: (payload.words[139] as u128), silver: (payload.words[140] as u128), upgrade_state_0: (payload.words[141] as u8), upgrade_state_1: (payload.words[142] as u8), upgrade_state_2: (payload.words[143] as u8), last_updated: (payload.words[144] as u64), pausers: (payload.words[145] as u128), energy_gro_doublers: (payload.words[146] as u128), silver_gro_doublers: (payload.words[147] as u128), hat_level: (payload.words[148] as u128), space_junk: (payload.words[149] as u128), has_tried_finding_artifact: (payload.words[150] == 1), prospected_block_number: (payload.words[151] as u32) };
        let new_planet_events_state: PlanetEvents = ::types::storage::planet::PlanetEvents { events: [::types::storage::planet::PlanetEventMetadata { id: payload.words[152] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[153] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[154] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[155] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[156] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[157] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[158] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[159] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[160] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[161] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[162] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[163] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[164] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[165] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[166] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[167] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[168] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[169] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[170] }, ::types::storage::planet::PlanetEventMetadata { id: payload.words[171] }], count: (payload.words[172] as u32), last_updated: (payload.words[173] as u64) };
        let new_planet_artifacts_state: PlanetArtifacts = ::types::storage::planet::PlanetArtifacts { ids: [payload.words[174], payload.words[175], payload.words[176], payload.words[177], payload.words[178], payload.words[179], payload.words[180], payload.words[181], payload.words[182], payload.words[183], payload.words[184], payload.words[185], payload.words[186], payload.words[187], payload.words[188], payload.words[189], payload.words[190], payload.words[191], payload.words[192], payload.words[193]], count: (payload.words[194] as u32), last_updated: (payload.words[195] as u64) };
        let new_artifact_locations: [ArtifactLocation; 20] = [::types::storage::artifact::ArtifactLocation { planet_id: payload.words[196], voyage_id: payload.words[197], last_updated: (payload.words[198] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[199], voyage_id: payload.words[200], last_updated: (payload.words[201] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[202], voyage_id: payload.words[203], last_updated: (payload.words[204] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[205], voyage_id: payload.words[206], last_updated: (payload.words[207] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[208], voyage_id: payload.words[209], last_updated: (payload.words[210] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[211], voyage_id: payload.words[212], last_updated: (payload.words[213] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[214], voyage_id: payload.words[215], last_updated: (payload.words[216] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[217], voyage_id: payload.words[218], last_updated: (payload.words[219] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[220], voyage_id: payload.words[221], last_updated: (payload.words[222] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[223], voyage_id: payload.words[224], last_updated: (payload.words[225] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[226], voyage_id: payload.words[227], last_updated: (payload.words[228] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[229], voyage_id: payload.words[230], last_updated: (payload.words[231] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[232], voyage_id: payload.words[233], last_updated: (payload.words[234] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[235], voyage_id: payload.words[236], last_updated: (payload.words[237] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[238], voyage_id: payload.words[239], last_updated: (payload.words[240] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[241], voyage_id: payload.words[242], last_updated: (payload.words[243] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[244], voyage_id: payload.words[245], last_updated: (payload.words[246] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[247], voyage_id: payload.words[248], last_updated: (payload.words[249] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[250], voyage_id: payload.words[251], last_updated: (payload.words[252] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[253], voyage_id: payload.words[254], last_updated: (payload.words[255] as u64) }];
        let new_player: Player = ::types::storage::player::Player { init_timestamp: (payload.words[256] as u64), home_planet_id: payload.words[257], last_reveal_timestamp: (payload.words[258] as u64), score: (payload.words[259] as u128), space_junk: (payload.words[260] as u128), space_junk_limit: (payload.words[261] as u128), claimed_ships: (payload.words[262] == 1), last_updated: (payload.words[263] as u64) };
        let spaceships_ids: [Field; 5] = [payload.words[264], payload.words[265], payload.words[266], payload.words[267], payload.words[268]];
        let spaceships: [Artifact; 5] = [::types::storage::artifact::Artifact { planet_discovered_on: payload.words[269], rarity: (payload.words[270] as u8), planet_biome: (payload.words[271] as u8), minted_at_timestamp: (payload.words[272] as u64), discoverer: AztecAddress::from_field(payload.words[273]), artifact_type: (payload.words[274] as u8), activations: (payload.words[275] as u128), last_activated: (payload.words[276] as u64), last_deactivated: (payload.words[277] as u64), wormhole_to: payload.words[278], owner: AztecAddress::from_field(payload.words[279]), controller: AztecAddress::from_field(payload.words[280]), last_updated: (payload.words[281] as u64) }, ::types::storage::artifact::Artifact { planet_discovered_on: payload.words[282], rarity: (payload.words[283] as u8), planet_biome: (payload.words[284] as u8), minted_at_timestamp: (payload.words[285] as u64), discoverer: AztecAddress::from_field(payload.words[286]), artifact_type: (payload.words[287] as u8), activations: (payload.words[288] as u128), last_activated: (payload.words[289] as u64), last_deactivated: (payload.words[290] as u64), wormhole_to: payload.words[291], owner: AztecAddress::from_field(payload.words[292]), controller: AztecAddress::from_field(payload.words[293]), last_updated: (payload.words[294] as u64) }, ::types::storage::artifact::Artifact { planet_discovered_on: payload.words[295], rarity: (payload.words[296] as u8), planet_biome: (payload.words[297] as u8), minted_at_timestamp: (payload.words[298] as u64), discoverer: AztecAddress::from_field(payload.words[299]), artifact_type: (payload.words[300] as u8), activations: (payload.words[301] as u128), last_activated: (payload.words[302] as u64), last_deactivated: (payload.words[303] as u64), wormhole_to: payload.words[304], owner: AztecAddress::from_field(payload.words[305]), controller: AztecAddress::from_field(payload.words[306]), last_updated: (payload.words[307] as u64) }, ::types::storage::artifact::Artifact { planet_discovered_on: payload.words[308], rarity: (payload.words[309] as u8), planet_biome: (payload.words[310] as u8), minted_at_timestamp: (payload.words[311] as u64), discoverer: AztecAddress::from_field(payload.words[312]), artifact_type: (payload.words[313] as u8), activations: (payload.words[314] as u128), last_activated: (payload.words[315] as u64), last_deactivated: (payload.words[316] as u64), wormhole_to: payload.words[317], owner: AztecAddress::from_field(payload.words[318]), controller: AztecAddress::from_field(payload.words[319]), last_updated: (payload.words[320] as u64) }, ::types::storage::artifact::Artifact { planet_discovered_on: payload.words[321], rarity: (payload.words[322] as u8), planet_biome: (payload.words[323] as u8), minted_at_timestamp: (payload.words[324] as u64), discoverer: AztecAddress::from_field(payload.words[325]), artifact_type: (payload.words[326] as u8), activations: (payload.words[327] as u128), last_activated: (payload.words[328] as u64), last_deactivated: (payload.words[329] as u64), wormhole_to: payload.words[330], owner: AztecAddress::from_field(payload.words[331]), controller: AztecAddress::from_field(payload.words[332]), last_updated: (payload.words[333] as u64) }];
        let spaceships_locations: [ArtifactLocation; 5] = [::types::storage::artifact::ArtifactLocation { planet_id: payload.words[334], voyage_id: payload.words[335], last_updated: (payload.words[336] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[337], voyage_id: payload.words[338], last_updated: (payload.words[339] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[340], voyage_id: payload.words[341], last_updated: (payload.words[342] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[343], voyage_id: payload.words[344], last_updated: (payload.words[345] as u64) }, ::types::storage::artifact::ArtifactLocation { planet_id: payload.words[346], voyage_id: payload.words[347], last_updated: (payload.words[348] as u64) }];
        let prepared_new_planet_root: Field = payload.words[349];
        let prepared_new_planet_events_state_root: Field = payload.words[350];
        let prepared_new_planet_artifacts_state_root: Field = payload.words[351];
        let prepared_new_player_root: Field = payload.words[352];
        let supported = ::state_backend_readonly::public_read::can_settle(state_backend_address, plan_addresses, 1004);
        if supported {
            let mut write_plan = ::libs::state_plan::WritePlan::new();

        let actual_timestamp = self.context.timestamp();
        assert_public_timestamp(timestamp, actual_timestamp);









        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[3], location_id, planet_hash),
            "planet hash mismatch",
        );
        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[6], location_id, planet_artifacts_state_hash),
            "planet_artifacts hash mismatch",
        );
        assert(
            ::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[5], location_id, planet_events_state_hash),
            "planet_events hash mismatch",
        );

        if origin_arrivals_count != 0 {
            assert(
                ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[7], arrival_ids, arrival_hashes, origin_arrivals_count as u32),
                "arrivals hash mismatch",
            );

            if ::libs::batch_utils::has_nonzero_ids(artifact_ids, origin_arrivals_count as u32) {
                assert(
                    ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[8], artifact_ids, artifact_hashes, origin_arrivals_count as u32),
                    "artifacts hash mismatch",
                );

                assert(
                    ::state_backend_readonly::public_read::verify_hashes_batch_20(state_backend_address, plan_addresses[9], artifact_ids, artifact_location_hashes, origin_arrivals_count as u32),
                    "artifact locations hash mismatch",
                );
            }
        }

        assert(::state_backend_readonly::public_read::verify_hash(state_backend_address, plan_addresses[2], (sender).to_field(), player_hash), "player hash mismatch");

        write_plan.set(3, location_id, prepared_new_planet_root, true, new_planet.serialize());
        write_plan.set(5, location_id, prepared_new_planet_events_state_root, true, new_planet_events_state.serialize());
        write_plan.set(6, location_id, prepared_new_planet_artifacts_state_root, true, new_planet_artifacts_state.serialize());
        {
            let batch_start=write_plan.start_batch(9, origin_arrivals_count as u32, 20);
            let bounded_count = if (origin_arrivals_count as u32) <= 20 { origin_arrivals_count as u32 } else { 20 };
            for plan_i in 0..bounded_count { if artifact_ids[plan_i] != 0 {
                write_plan.append_batch_item(batch_start, artifact_ids[plan_i], new_artifact_locations[plan_i].serialize());
            } }
        };
        write_plan.set(2, (sender).to_field(), prepared_new_player_root, true, new_player.serialize());

        {
            let batch_start=write_plan.start_batch(8, 5, 5);
            let bounded_count = if (5) <= 5 { 5 } else { 5 };
            for plan_i in 0..bounded_count { if spaceships_ids[plan_i] != 0 {
                write_plan.append_batch_item(batch_start, spaceships_ids[plan_i], spaceships[plan_i].serialize());
            } }
        };

        {
            let batch_start=write_plan.start_batch(9, 5, 5);
            let bounded_count = if (5) <= 5 { 5 } else { 5 };
            for plan_i in 0..bounded_count { if spaceships_ids[plan_i] != 0 {
                write_plan.append_batch_item(batch_start, spaceships_ids[plan_i], spaceships_locations[plan_i].serialize());
            } }
        };

            _commit_plan_for_system(self.context, state_backend_address, plan_addresses, 1004, write_plan);
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
        } else {
            let selector = comptime { aztec::protocol::abis::function_selector::FunctionSelector::from_signature("commit_plan(([Field;397]))") };
            let calldata=[selector.to_field(), self.msg_sender().to_field(), addresses[0].to_field(), addresses[1].to_field(), addresses[2].to_field(), addresses[3].to_field(), addresses[4].to_field(), addresses[5].to_field(), addresses[6].to_field(), addresses[7].to_field(), addresses[8].to_field(), addresses[9].to_field(), required_mask as Field, plan.words[0], plan.words[1], plan.words[2], plan.words[3], plan.words[4], plan.words[5], plan.words[6], plan.words[7], plan.words[8], plan.words[9], plan.words[10], plan.words[11], plan.words[12], plan.words[13], plan.words[14], plan.words[15], plan.words[16], plan.words[17], plan.words[18], plan.words[19], plan.words[20], plan.words[21], plan.words[22], plan.words[23], plan.words[24], plan.words[25], plan.words[26], plan.words[27], plan.words[28], plan.words[29], plan.words[30], plan.words[31], plan.words[32], plan.words[33], plan.words[34], plan.words[35], plan.words[36], plan.words[37], plan.words[38], plan.words[39], plan.words[40], plan.words[41], plan.words[42], plan.words[43], plan.words[44], plan.words[45], plan.words[46], plan.words[47], plan.words[48], plan.words[49], plan.words[50], plan.words[51], plan.words[52], plan.words[53], plan.words[54], plan.words[55], plan.words[56], plan.words[57], plan.words[58], plan.words[59], plan.words[60], plan.words[61], plan.words[62], plan.words[63], plan.words[64], plan.words[65], plan.words[66], plan.words[67], plan.words[68], plan.words[69], plan.words[70], plan.words[71], plan.words[72], plan.words[73], plan.words[74], plan.words[75], plan.words[76], plan.words[77], plan.words[78], plan.words[79], plan.words[80], plan.words[81], plan.words[82], plan.words[83], plan.words[84], plan.words[85], plan.words[86], plan.words[87], plan.words[88], plan.words[89], plan.words[90], plan.words[91], plan.words[92], plan.words[93], plan.words[94], plan.words[95], plan.words[96], plan.words[97], plan.words[98], plan.words[99], plan.words[100], plan.words[101], plan.words[102], plan.words[103], plan.words[104], plan.words[105], plan.words[106], plan.words[107], plan.words[108], plan.words[109], plan.words[110], plan.words[111], plan.words[112], plan.words[113], plan.words[114], plan.words[115], plan.words[116], plan.words[117], plan.words[118], plan.words[119], plan.words[120], plan.words[121], plan.words[122], plan.words[123], plan.words[124], plan.words[125], plan.words[126], plan.words[127], plan.words[128], plan.words[129], plan.words[130], plan.words[131], plan.words[132], plan.words[133], plan.words[134], plan.words[135], plan.words[136], plan.words[137], plan.words[138], plan.words[139], plan.words[140], plan.words[141], plan.words[142], plan.words[143], plan.words[144], plan.words[145], plan.words[146], plan.words[147], plan.words[148], plan.words[149], plan.words[150], plan.words[151], plan.words[152], plan.words[153], plan.words[154], plan.words[155], plan.words[156], plan.words[157], plan.words[158], plan.words[159], plan.words[160], plan.words[161], plan.words[162], plan.words[163], plan.words[164], plan.words[165], plan.words[166], plan.words[167], plan.words[168], plan.words[169], plan.words[170], plan.words[171], plan.words[172], plan.words[173], plan.words[174], plan.words[175], plan.words[176], plan.words[177], plan.words[178], plan.words[179], plan.words[180], plan.words[181], plan.words[182], plan.words[183], plan.words[184], plan.words[185], plan.words[186], plan.words[187], plan.words[188], plan.words[189], plan.words[190], plan.words[191], plan.words[192], plan.words[193], plan.words[194], plan.words[195], plan.words[196], plan.words[197], plan.words[198], plan.words[199], plan.words[200], plan.words[201], plan.words[202], plan.words[203], plan.words[204], plan.words[205], plan.words[206], plan.words[207], plan.words[208], plan.words[209], plan.words[210], plan.words[211], plan.words[212], plan.words[213], plan.words[214], plan.words[215], plan.words[216], plan.words[217], plan.words[218], plan.words[219], plan.words[220], plan.words[221], plan.words[222], plan.words[223], plan.words[224], plan.words[225], plan.words[226], plan.words[227], plan.words[228], plan.words[229], plan.words[230], plan.words[231], plan.words[232], plan.words[233], plan.words[234], plan.words[235], plan.words[236], plan.words[237], plan.words[238], plan.words[239], plan.words[240], plan.words[241], plan.words[242], plan.words[243], plan.words[244], plan.words[245], plan.words[246], plan.words[247], plan.words[248], plan.words[249], plan.words[250], plan.words[251], plan.words[252], plan.words[253], plan.words[254], plan.words[255], plan.words[256], plan.words[257], plan.words[258], plan.words[259], plan.words[260], plan.words[261], plan.words[262], plan.words[263], plan.words[264], plan.words[265], plan.words[266], plan.words[267], plan.words[268], plan.words[269], plan.words[270], plan.words[271], plan.words[272], plan.words[273], plan.words[274], plan.words[275], plan.words[276], plan.words[277], plan.words[278], plan.words[279], plan.words[280], plan.words[281], plan.words[282], plan.words[283], plan.words[284], plan.words[285], plan.words[286], plan.words[287], plan.words[288], plan.words[289], plan.words[290], plan.words[291], plan.words[292], plan.words[293], plan.words[294], plan.words[295], plan.words[296], plan.words[297], plan.words[298], plan.words[299], plan.words[300], plan.words[301], plan.words[302], plan.words[303], plan.words[304], plan.words[305], plan.words[306], plan.words[307], plan.words[308], plan.words[309], plan.words[310], plan.words[311], plan.words[312], plan.words[313], plan.words[314], plan.words[315], plan.words[316], plan.words[317], plan.words[318], plan.words[319], plan.words[320], plan.words[321], plan.words[322], plan.words[323], plan.words[324], plan.words[325], plan.words[326], plan.words[327], plan.words[328], plan.words[329], plan.words[330], plan.words[331], plan.words[332], plan.words[333], plan.words[334], plan.words[335], plan.words[336], plan.words[337], plan.words[338], plan.words[339], plan.words[340], plan.words[341], plan.words[342], plan.words[343], plan.words[344], plan.words[345], plan.words[346], plan.words[347], plan.words[348], plan.words[349], plan.words[350], plan.words[351], plan.words[352], plan.words[353], plan.words[354], plan.words[355], plan.words[356], plan.words[357], plan.words[358], plan.words[359], plan.words[360], plan.words[361], plan.words[362], plan.words[363], plan.words[364], plan.words[365], plan.words[366], plan.words[367], plan.words[368], plan.words[369], plan.words[370], plan.words[371], plan.words[372], plan.words[373], plan.words[374], plan.words[375], plan.words[376], plan.words[377], plan.words[378], plan.words[379], plan.words[380], plan.words[381], plan.words[382], plan.words[383], plan.length as Field];

            let result=::libs::public_call::call(backend_address,calldata);
            assert(result.len()==0, "Unexpected settlement result");
        }
    }

}
