use aztec::macros::aztec;

// Test-only implementation of the original three stores' common view selector.
// Static calls deliberately do not keep a counter. Asymmetric queue fixtures and
// different zero/nonzero sentinels distinguish Move's source and target checks.
#[aztec]
contract CallerSensitiveBatch {
    use aztec::{
        macros::{functions::{external, initializer, view}, storage::storage},
        protocol::{address::AztecAddress, hash::poseidon2_hash},
        state_vars::PublicMutable,
    };

    #[storage]
    struct Storage<Context> {
        admin: PublicMutable<AztecAddress, Context>,
        expected_caller: PublicMutable<AztecAddress, Context>,
        zero_response: PublicMutable<u8, Context>,
        nonzero_response: PublicMutable<u8, Context>,
        nonzero_count: PublicMutable<u32, Context>,
        nonzero_commitment: PublicMutable<Field, Context>,
    }

    #[external("public")]
    #[initializer]
    fn constructor(admin: AztecAddress) {
        self.storage.admin.write(admin);
        self.storage.expected_caller.write(admin);
        self.storage.zero_response.write(2);
        self.storage.nonzero_response.write(2);
        self.storage.nonzero_count.write(1);
        self.storage.nonzero_commitment.write(0);
    }

    #[external("public")]
    fn set_expectations(expected_caller: AztecAddress, zero_response: u8, nonzero_response: u8, nonzero_count: u32, nonzero_commitment: Field) {
        assert(self.msg_sender() == self.storage.admin.read(), "Only fixture admin");
        assert((zero_response <= 2) & (nonzero_response <= 2), "Invalid fixture response");
        self.storage.expected_caller.write(expected_caller);
        self.storage.zero_response.write(zero_response);
        self.storage.nonzero_response.write(nonzero_response);
        self.storage.nonzero_count.write(nonzero_count);
        self.storage.nonzero_commitment.write(nonzero_commitment);
    }

    #[external("public")]
    #[view]
    fn verify_hashes_batch(ids: [Field; 20], hashes: [Field; 20], count: u32) -> bool {
        assert(self.msg_sender() == self.storage.expected_caller.read(), "Batch verifier caller changed");
        if count == 0 {
            assert(ids == [0; 20], "Zero batch IDs changed");
            assert(hashes == [0; 20], "Zero batch hashes changed");
            let response = self.storage.zero_response.read();
            assert(response != 2, "Original zero batch observed");
            response == 0
        } else {
            assert(count == self.storage.nonzero_count.read(), "Nonzero batch count changed");
            let mut fields: [Field; 41] = [0; 41];
            for i in 0..20 { fields[i] = ids[i]; fields[20 + i] = hashes[i]; }
            fields[40] = count as Field;
            assert(poseidon2_hash(fields) == self.storage.nonzero_commitment.read(), "Nonzero batch payload changed");
            let response = self.storage.nonzero_response.read();
            assert(response != 2, "Original nonzero batch observed");
            response == 0
        }
    }
}
