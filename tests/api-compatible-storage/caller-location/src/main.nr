use aztec::macros::aztec;

// Test-only original storage selectors. A final sentinel reverts the complete
// gameplay simulation after checking the caller, batch order, and all60 fields.
#[aztec]
contract CallerSensitiveLocation {
    use aztec::{
        macros::{functions::{external, initializer, view}, storage::storage},
        protocol::{address::AztecAddress, hash::poseidon2_hash, traits::Serialize},
        state_vars::PublicMutable,
    };
    use types::storage::artifact::ArtifactLocation;

    #[storage]
    struct Storage<Context> {
        expected_caller: PublicMutable<AztecAddress, Context>,
        expected_first: PublicMutable<Field, Context>,
        expected_second: PublicMutable<Field, Context>,
        expected_batches: PublicMutable<u8, Context>,
        seen_batches: PublicMutable<u8, Context>,
    }

    #[external("public")]
    #[initializer]
    fn constructor(expected_caller: AztecAddress, expected_first: Field, expected_second: Field, expected_batches: u8) {
        assert((expected_batches == 1) | (expected_batches == 2), "Expected one or two batches");
        self.storage.expected_caller.write(expected_caller);
        self.storage.expected_first.write(expected_first);
        self.storage.expected_second.write(expected_second);
        self.storage.expected_batches.write(expected_batches);
        self.storage.seen_batches.write(0);
    }

    #[external("public")]
    #[view]
    fn verify_hashes_batch(ids: [Field;20], hashes: [Field;20], count: u32) -> bool {
        assert(self.msg_sender() == self.storage.expected_caller.read(), "Location caller changed");
        assert(count == 0, "Location batch count changed");
        assert(ids == [0;20], "Location batch IDs changed");
        assert(hashes == [0;20], "Location batch hashes changed");
        true
    }

    #[external("public")]
    fn set_arrival_locations_max20(ids: [Field;20], states: [ArtifactLocation;20], count: u32) {
        assert(self.msg_sender() == self.storage.expected_caller.read(), "Location caller changed");
        assert(count == 0, "Location batch count changed");
        assert(ids == [0;20], "Location batch IDs changed");
        let index = self.storage.seen_batches.read();
        let expected_batches = self.storage.expected_batches.read();
        assert(index < expected_batches, "Too many location batches");
        let expected = if index == 0 { self.storage.expected_first.read() } else { self.storage.expected_second.read() };
        assert(poseidon2_hash(states.serialize()) == expected, "Arrival location payload changed");
        self.storage.seen_batches.write(index + 1);
        assert(index + 1 < expected_batches, "Original inactive locations observed");
    }

    #[external("public")]
    #[view]
    fn get_seen_batches() -> u8 {
        self.storage.seen_batches.read()
    }
}
