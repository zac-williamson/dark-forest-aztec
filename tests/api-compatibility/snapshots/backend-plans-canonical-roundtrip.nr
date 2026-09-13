// Generated generic plan execution. Original System continuations retain all game checks.
    use aztec::protocol::traits::Deserialize;
    #[internal("public")]
    fn _read_state_plan(addresses: [AztecAddress;10], required_mask: u16, checks: [Field;320], length: u32) -> (bool, [bool;16]) {
        let mut results = [true;16];
        let supported = self.internal._can_settle(addresses, required_mask);
        if supported {
            assert(length <= checks.len(), "Read plan length exceeded");
            assert(length % 3 == 0, "Malformed read plan");
            let mut cursor = 0;
            while cursor < length {
                let descriptor = checks[cursor] as u32;
                assert(descriptor as Field == checks[cursor], "Invalid read descriptor");
                assert(descriptor < 512, "Invalid read descriptor");
                let namespace = descriptor & 15;
                let group = (descriptor >> 4) & 15;
                let initialized = descriptor & 256 != 0;
                assert(namespace >= 1 & namespace <= 9, "Invalid read namespace");
                assert((required_mask & (1u16 << (namespace as u16))) != 0, "Unvalidated read namespace");
                // A batch stops reading after its first mismatch, as the old store does.
                if results[group] {
                    let root = self.storage.roots.at(addresses[namespace]).at(checks[cursor+1]).read();
                    results[group] = if initialized { root != 0 } else { root == checks[cursor+2] };
                }
                cursor += 3;
            }
        }
        (supported, results)
    }
    #[external("public")] #[view]
    fn read_plan_small(addresses:[AztecAddress;10], required_mask:u16, checks:[Field;32], length:u32) -> (bool,[bool;16]) {
        assert(length <= 32, "Read plan length exceeded");
        let mut expanded = [0;320];
        for i in 0..length { expanded[i] = checks[i]; }
        let checks = expanded;
        self.internal._read_state_plan(addresses,required_mask,checks,length)
    }
    #[external("public")] #[view]
    fn read_plan(addresses:[AztecAddress;10], required_mask:u16, checks:[Field;320], length:u32) -> (bool,[bool;16]) {
        self.internal._read_state_plan(addresses,required_mask,checks,length)
    }
    #[internal("public")]
    fn _commit_state_plan(addresses:[AztecAddress;10], required_mask:u16, words:[Field;384], length:u32) {
        assert(self.internal._can_settle(addresses,required_mask), "Settlement namespaces changed");
        assert(length <= words.len(), "Write plan length exceeded");
        let actor = self.msg_sender();
        let mut cursor = 0;
        while cursor < length {
            assert(cursor + 3 <= length, "Truncated write header");
            let descriptor = words[cursor] as u32;
            assert(descriptor as Field == words[cursor], "Invalid write descriptor");
            assert(descriptor < 64, "Invalid write descriptor");
            let namespace = descriptor & 15;
            let prepared = descriptor & 16 != 0;
            let auth_only = descriptor & 32 != 0;
            assert(namespace >= 1 & namespace <= 9, "Invalid write namespace");
            assert((required_mask & (1u16 << (namespace as u16))) != 0, "Unvalidated write namespace");
            let ns = addresses[namespace];
            let key = words[cursor+1];
            let root = words[cursor+2];
            cursor += 3;
            if auth_only {
                self.internal._assert_authorized(ns,actor);
                let count = key as u32;
                let maximum = root as u32;
                assert(count as Field == key, "Invalid batch count");
                assert(maximum as Field == root, "Invalid batch maximum");
                assert(((namespace == 9) & ((maximum == 5) | (maximum == 20))) | ((namespace == 8) & (maximum == 5)), "Invalid batch kind");
                assert(count <= maximum, "count exceeds batch size");
            } else {
                if namespace == 2 {
                    assert(cursor + 8 <= length, "Truncated player payload");
                    let fields: [Field;8] = ::libs::state_plan::take(words,cursor);
                    let state = Player::deserialize(fields);
                    // Reject noncanonical integer/bool payloads on this additive API.
                    assert(state.serialize() == fields, "Noncanonical player payload");
                    self.internal._set_player(ns,actor,key,state,root,prepared);
                    cursor += 8;
                }
                else if namespace == 3 {
                    assert(cursor + 32 <= length, "Truncated planet payload");
                    let fields: [Field;32] = ::libs::state_plan::take(words,cursor);
                    let state = Planet::deserialize(fields);
                    // Reject noncanonical integer/bool payloads on this additive API.
                    assert(state.serialize() == fields, "Noncanonical planet payload");
                    self.internal._set_planet(ns,actor,key,state,root,prepared);
                    cursor += 32;
                }
                else if namespace == 4 {
                    assert(cursor + 4 <= length, "Truncated planet_revealed_coords payload");
                    let fields: [Field;4] = ::libs::state_plan::take(words,cursor);
                    let state = PlanetRevealedCoords::deserialize(fields);
                    // Reject noncanonical integer/bool payloads on this additive API.
                    assert(state.serialize() == fields, "Noncanonical planet_revealed_coords payload");
                    self.internal._set_planet_revealed_coords(ns,actor,key,state,root,prepared);
                    cursor += 4;
                }
                else if namespace == 5 {
                    assert(cursor + 22 <= length, "Truncated planet_events payload");
                    let fields: [Field;22] = ::libs::state_plan::take(words,cursor);
                    let state = PlanetEvents::deserialize(fields);
                    // Reject noncanonical integer/bool payloads on this additive API.
                    assert(state.serialize() == fields, "Noncanonical planet_events payload");
                    self.internal._set_planet_events(ns,actor,key,state,root,prepared);
                    cursor += 22;
                }
                else if namespace == 6 {
                    assert(cursor + 22 <= length, "Truncated planet_artifacts payload");
                    let fields: [Field;22] = ::libs::state_plan::take(words,cursor);
                    let state = PlanetArtifacts::deserialize(fields);
                    // Reject noncanonical integer/bool payloads on this additive API.
                    assert(state.serialize() == fields, "Noncanonical planet_artifacts payload");
                    self.internal._set_planet_artifacts(ns,actor,key,state,root,prepared);
                    cursor += 22;
                }
                else if namespace == 8 {
                    assert(cursor + 13 <= length, "Truncated artifact payload");
                    let fields: [Field;13] = ::libs::state_plan::take(words,cursor);
                    let state = Artifact::deserialize(fields);
                    // Reject noncanonical integer/bool payloads on this additive API.
                    assert(state.serialize() == fields, "Noncanonical artifact payload");
                    self.internal._set_artifact(ns,actor,key,state,root,prepared);
                    cursor += 13;
                }
                else if namespace == 9 {
                    assert(cursor + 3 <= length, "Truncated artifact_location payload");
                    let fields: [Field;3] = ::libs::state_plan::take(words,cursor);
                    let state = ArtifactLocation::deserialize(fields);
                    // Reject noncanonical integer/bool payloads on this additive API.
                    assert(state.serialize() == fields, "Noncanonical artifact_location payload");
                    self.internal._set_artifact_location(ns,actor,key,state,root,prepared);
                    cursor += 3;
                }
                else { assert(false, "Unsupported write namespace"); }
            }
        }
    }
    #[external("public")]
    fn commit_plan_small(addresses:[AztecAddress;10],required_mask:u16,words:[Field;128],length:u32) {
        assert(length <= 128, "Write plan length exceeded");
        let mut expanded = [0;384];
        for i in 0..length { expanded[i] = words[i]; }
        let words = expanded;
        self.internal._commit_state_plan(addresses,required_mask,words,length);
    }
    #[external("public")]
    fn commit_plan(addresses:[AztecAddress;10],required_mask:u16,words:[Field;384],length:u32) {
        self.internal._commit_state_plan(addresses,required_mask,words,length);
    }
