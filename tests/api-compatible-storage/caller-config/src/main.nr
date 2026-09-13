use aztec::macros::aztec;

// Test-only original Config selectors with caller-sensitive behavior. Mode zero
// returns true; modes one through five stop at the selected verified caller boundary.
#[aztec]
contract CallerSensitiveConfig {
    use aztec::{
        macros::{functions::{external, initializer, view}, storage::storage},
        protocol::address::AztecAddress,
        state_vars::PublicMutable,
    };

    #[storage]
    struct Storage<Context> {
        expected_caller: PublicMutable<AztecAddress, Context>,
        stop_after: PublicMutable<u8, Context>,
    }

    #[external("public")]
    #[initializer]
    fn constructor(expected_caller: AztecAddress, stop_after: u8) {
        self.storage.expected_caller.write(expected_caller);
        self.storage.stop_after.write(stop_after);
    }

    #[external("public")]
    #[view]
    fn verify_config_hashes(level: u8, planet_default_stats_hash: Field, hashes: [Field;9]) -> bool {
        assert(self.msg_sender() == self.storage.expected_caller.read(), "Config caller changed");
        assert(self.storage.stop_after.read() != 1, "Original Config caller observed");
        true
    }

    #[external("public")]
    #[view]
    fn verify_artifacts_config_hash(hash: Field) -> bool {
        assert(self.msg_sender() == self.storage.expected_caller.read(), "Config caller changed");
        assert(self.storage.stop_after.read() != 2, "Original artifact Config caller observed");
        true
    }

    #[external("public")]
    #[view]
    fn verify_world_config_hash(hash: Field) -> bool {
        assert(self.msg_sender() == self.storage.expected_caller.read(), "Config caller changed");
        assert(self.storage.stop_after.read() != 3, "Original world Config caller observed");
        true
    }

    #[external("public")]
    #[view]
    fn verify_upgrade_config_hash(hash: Field) -> bool {
        assert(self.msg_sender() == self.storage.expected_caller.read(), "Config caller changed");
        assert(self.storage.stop_after.read() != 4, "Original upgrade Config caller observed");
        true
    }

    #[external("public")]
    #[view]
    fn verify_upgrade_hash_by_branch_level(branch: u128, level: u128, hash: Field) -> bool {
        assert(self.msg_sender() == self.storage.expected_caller.read(), "Config caller changed");
        assert(self.storage.stop_after.read() != 5, "Original branch upgrade Config caller observed");
        true
    }
}
