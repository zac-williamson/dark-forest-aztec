use artifact::ArtifactStorage;
use aztec::test::helpers::test_environment::TestEnvironment;
use types::storage::artifact::Artifact;

#[test]
unconstrained fn triple_matches_scalar_including_zero_duplicates_and_bad_hashes() {
    let mut env = TestEnvironment::new();
    let admin = env.create_light_account();
    let address = env.deploy("artifacts@artifact/ArtifactStorage").with_public_initializer(
        admin,
        ArtifactStorage::interface().constructor(admin),
    );
    let store = ArtifactStorage::at(address);
    let mut roots = [0; 3];
    for i in 0..3 {
        let mut state = Artifact::zero();
        state.last_updated = (i + 1) as u64;
        env.call_public(admin, store.set(i as Field, state));
        roots[i] = env.execute_utility(store.get_state_root_unconstrained(i as Field));
        assert(roots[i] != 0);
    }
    for a in 0..3 {
        for b in 0..3 {
            for c in 0..3 {
                let ids = [a as Field, b as Field, c as Field];
                for bad in 0..4 {
                    let mut hashes = [roots[a], roots[b], roots[c]];
                    if bad < 3 {
                        hashes[bad] = 0;
                    }
                    let result = env.view_public(store.verify_hashes_three(ids, hashes));
                    for j in 0..3 {
                        let scalar = env.view_public(store.verify_hash(ids[j], hashes[j]));
                        assert_eq(result[j], scalar);
                        assert_eq(result[j], bad != j);
                    }
                }
            }
        }
    }
    assert_eq(
        env.view_public(store.verify_hashes_three([0, 9, 9], [0, 0, 1])),
        [false, true, false],
    );
}
