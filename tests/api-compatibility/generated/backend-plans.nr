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
