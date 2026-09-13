use arrival::ArrivalStorage;
use artifact::ArtifactStorage;
use artifact_location::ArtifactLocationStorage;
use aztec::{protocol::address::AztecAddress, test::helpers::test_environment::TestEnvironment};
use planet::PlanetStorage;
use planet_artifacts::PlanetArtifactsStorage;
use planet_events::PlanetEventsStorage;
use planet_revealed_coords::PlanetRevealedCoordsStorage;
use player::PlayerStorage;
use types::storage::arrival::Arrival;
use types::storage::artifact::Artifact;
use types::storage::artifact::ArtifactLocation;
use types::storage::planet::Planet;
use types::storage::planet::PlanetArtifacts;
use types::storage::planet::PlanetEvents;
use types::storage::planet::PlanetRevealedCoords;
use types::storage::player::Player;
use types::storage::world::World;
use world::WorldStorage;

unconstrained fn setup_arrival() -> (TestEnvironment, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let admin = env.create_light_account();
    let address = env.deploy("artifacts@arrival/ArrivalStorage").with_public_initializer(
        admin,
        ArrivalStorage::interface().constructor(admin),
    );
    (env, address, admin)
}

#[test]
unconstrained fn arrival_admin_and_authorized_write_same_hash() {
    let (mut env, address, admin) = setup_arrival();
    let writer = env.create_light_account();
    let storage_contract = ArrivalStorage::at(address);
    let state = Arrival::zero();
    env.call_public(admin, storage_contract.set(0, state));
    let expected = env.execute_utility(storage_contract.get_state_root_unconstrained(0));
    env.call_public(admin, storage_contract.add_authorized_contract(writer));
    env.call_public(writer, storage_contract.set(0, state));
    assert_eq(env.execute_utility(storage_contract.get_state_root_unconstrained(0)), expected);
    // Revoking the extra grant must not revoke the administrator's own rights.
    env.call_public(admin, storage_contract.add_authorized_contract(admin));
    env.call_public(admin, storage_contract.remove_authorized_contract(admin));
    env.call_public(admin, storage_contract.set(0, state));
}

#[test(should_fail_with = "Not authorized")]
unconstrained fn arrival_rejects_unapproved_writer() {
    let (mut env, address, _admin) = setup_arrival();
    let stranger = env.create_light_account();
    env.call_public(stranger, ArrivalStorage::at(address).set(0, Arrival::zero()));
}

#[test(should_fail_with = "Not authorized")]
unconstrained fn arrival_rejects_revoked_writer() {
    let (mut env, address, admin) = setup_arrival();
    let writer = env.create_light_account();
    let storage_contract = ArrivalStorage::at(address);
    env.call_public(admin, storage_contract.add_authorized_contract(writer));
    env.call_public(admin, storage_contract.remove_authorized_contract(writer));
    env.call_public(writer, storage_contract.set(0, Arrival::zero()));
}

unconstrained fn setup_artifact() -> (TestEnvironment, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let admin = env.create_light_account();
    let address = env.deploy("artifacts@artifact/ArtifactStorage").with_public_initializer(
        admin,
        ArtifactStorage::interface().constructor(admin),
    );
    (env, address, admin)
}

#[test]
unconstrained fn artifact_admin_and_authorized_write_same_hash() {
    let (mut env, address, admin) = setup_artifact();
    let writer = env.create_light_account();
    let storage_contract = ArtifactStorage::at(address);
    let state = Artifact::zero();
    env.call_public(admin, storage_contract.set(0, state));
    let expected = env.execute_utility(storage_contract.get_state_root_unconstrained(0));
    env.call_public(admin, storage_contract.add_authorized_contract(writer));
    env.call_public(writer, storage_contract.set(0, state));
    assert_eq(env.execute_utility(storage_contract.get_state_root_unconstrained(0)), expected);
    // Revoking the extra grant must not revoke the administrator's own rights.
    env.call_public(admin, storage_contract.add_authorized_contract(admin));
    env.call_public(admin, storage_contract.remove_authorized_contract(admin));
    env.call_public(admin, storage_contract.set(0, state));
}

#[test(should_fail_with = "Not authorized")]
unconstrained fn artifact_rejects_unapproved_writer() {
    let (mut env, address, _admin) = setup_artifact();
    let stranger = env.create_light_account();
    env.call_public(stranger, ArtifactStorage::at(address).set(0, Artifact::zero()));
}

#[test(should_fail_with = "Not authorized")]
unconstrained fn artifact_rejects_revoked_writer() {
    let (mut env, address, admin) = setup_artifact();
    let writer = env.create_light_account();
    let storage_contract = ArtifactStorage::at(address);
    env.call_public(admin, storage_contract.add_authorized_contract(writer));
    env.call_public(admin, storage_contract.remove_authorized_contract(writer));
    env.call_public(writer, storage_contract.set(0, Artifact::zero()));
}

unconstrained fn setup_artifact_location() -> (TestEnvironment, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let admin = env.create_light_account();
    let address = env
        .deploy("artifacts@artifact_location/ArtifactLocationStorage")
        .with_public_initializer(admin, ArtifactLocationStorage::interface().constructor(admin));
    (env, address, admin)
}

#[test]
unconstrained fn artifact_location_admin_and_authorized_write_same_hash() {
    let (mut env, address, admin) = setup_artifact_location();
    let writer = env.create_light_account();
    let storage_contract = ArtifactLocationStorage::at(address);
    let state = ArtifactLocation::zero();
    env.call_public(admin, storage_contract.set(0, state));
    let expected = env.execute_utility(storage_contract.get_state_root_unconstrained(0));
    env.call_public(admin, storage_contract.add_authorized_contract(writer));
    env.call_public(writer, storage_contract.set(0, state));
    assert_eq(env.execute_utility(storage_contract.get_state_root_unconstrained(0)), expected);
    // Revoking the extra grant must not revoke the administrator's own rights.
    env.call_public(admin, storage_contract.add_authorized_contract(admin));
    env.call_public(admin, storage_contract.remove_authorized_contract(admin));
    env.call_public(admin, storage_contract.set(0, state));
}

#[test(should_fail_with = "Not authorized")]
unconstrained fn artifact_location_rejects_unapproved_writer() {
    let (mut env, address, _admin) = setup_artifact_location();
    let stranger = env.create_light_account();
    env.call_public(stranger, ArtifactLocationStorage::at(address).set(0, ArtifactLocation::zero()));
}

#[test(should_fail_with = "Not authorized")]
unconstrained fn artifact_location_rejects_revoked_writer() {
    let (mut env, address, admin) = setup_artifact_location();
    let writer = env.create_light_account();
    let storage_contract = ArtifactLocationStorage::at(address);
    env.call_public(admin, storage_contract.add_authorized_contract(writer));
    env.call_public(admin, storage_contract.remove_authorized_contract(writer));
    env.call_public(writer, storage_contract.set(0, ArtifactLocation::zero()));
}

unconstrained fn setup_planet() -> (TestEnvironment, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let admin = env.create_light_account();
    let address = env.deploy("artifacts@planet/PlanetStorage").with_public_initializer(
        admin,
        PlanetStorage::interface().constructor(admin),
    );
    (env, address, admin)
}

#[test]
unconstrained fn planet_admin_and_authorized_write_same_hash() {
    let (mut env, address, admin) = setup_planet();
    let writer = env.create_light_account();
    let storage_contract = PlanetStorage::at(address);
    let state = Planet::zero();
    env.call_public(admin, storage_contract.set(0, state));
    let expected = env.execute_utility(storage_contract.get_state_root_unconstrained(0));
    env.call_public(admin, storage_contract.add_authorized_contract(writer));
    env.call_public(writer, storage_contract.set(0, state));
    assert_eq(env.execute_utility(storage_contract.get_state_root_unconstrained(0)), expected);
    // Revoking the extra grant must not revoke the administrator's own rights.
    env.call_public(admin, storage_contract.add_authorized_contract(admin));
    env.call_public(admin, storage_contract.remove_authorized_contract(admin));
    env.call_public(admin, storage_contract.set(0, state));
}

#[test(should_fail_with = "Not authorized")]
unconstrained fn planet_rejects_unapproved_writer() {
    let (mut env, address, _admin) = setup_planet();
    let stranger = env.create_light_account();
    env.call_public(stranger, PlanetStorage::at(address).set(0, Planet::zero()));
}

#[test(should_fail_with = "Not authorized")]
unconstrained fn planet_rejects_revoked_writer() {
    let (mut env, address, admin) = setup_planet();
    let writer = env.create_light_account();
    let storage_contract = PlanetStorage::at(address);
    env.call_public(admin, storage_contract.add_authorized_contract(writer));
    env.call_public(admin, storage_contract.remove_authorized_contract(writer));
    env.call_public(writer, storage_contract.set(0, Planet::zero()));
}

unconstrained fn setup_planet_artifacts() -> (TestEnvironment, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let admin = env.create_light_account();
    let address = env
        .deploy("artifacts@planet_artifacts/PlanetArtifactsStorage")
        .with_public_initializer(admin, PlanetArtifactsStorage::interface().constructor(admin));
    (env, address, admin)
}

#[test]
unconstrained fn planet_artifacts_admin_and_authorized_write_same_hash() {
    let (mut env, address, admin) = setup_planet_artifacts();
    let writer = env.create_light_account();
    let storage_contract = PlanetArtifactsStorage::at(address);
    let state = PlanetArtifacts::zero();
    env.call_public(admin, storage_contract.set(0, state));
    let expected = env.execute_utility(storage_contract.get_state_root_unconstrained(0));
    env.call_public(admin, storage_contract.add_authorized_contract(writer));
    env.call_public(writer, storage_contract.set(0, state));
    assert_eq(env.execute_utility(storage_contract.get_state_root_unconstrained(0)), expected);
    // Revoking the extra grant must not revoke the administrator's own rights.
    env.call_public(admin, storage_contract.add_authorized_contract(admin));
    env.call_public(admin, storage_contract.remove_authorized_contract(admin));
    env.call_public(admin, storage_contract.set(0, state));
}

#[test(should_fail_with = "Not authorized")]
unconstrained fn planet_artifacts_rejects_unapproved_writer() {
    let (mut env, address, _admin) = setup_planet_artifacts();
    let stranger = env.create_light_account();
    env.call_public(stranger, PlanetArtifactsStorage::at(address).set(0, PlanetArtifacts::zero()));
}

#[test(should_fail_with = "Not authorized")]
unconstrained fn planet_artifacts_rejects_revoked_writer() {
    let (mut env, address, admin) = setup_planet_artifacts();
    let writer = env.create_light_account();
    let storage_contract = PlanetArtifactsStorage::at(address);
    env.call_public(admin, storage_contract.add_authorized_contract(writer));
    env.call_public(admin, storage_contract.remove_authorized_contract(writer));
    env.call_public(writer, storage_contract.set(0, PlanetArtifacts::zero()));
}

unconstrained fn setup_planet_events() -> (TestEnvironment, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let admin = env.create_light_account();
    let address = env.deploy("artifacts@planet_events/PlanetEventsStorage").with_public_initializer(
        admin,
        PlanetEventsStorage::interface().constructor(admin),
    );
    (env, address, admin)
}

#[test]
unconstrained fn planet_events_admin_and_authorized_write_same_hash() {
    let (mut env, address, admin) = setup_planet_events();
    let writer = env.create_light_account();
    let storage_contract = PlanetEventsStorage::at(address);
    let state = PlanetEvents::zero();
    env.call_public(admin, storage_contract.set(0, state));
    let expected = env.execute_utility(storage_contract.get_state_root_unconstrained(0));
    env.call_public(admin, storage_contract.add_authorized_contract(writer));
    env.call_public(writer, storage_contract.set(0, state));
    assert_eq(env.execute_utility(storage_contract.get_state_root_unconstrained(0)), expected);
    // Revoking the extra grant must not revoke the administrator's own rights.
    env.call_public(admin, storage_contract.add_authorized_contract(admin));
    env.call_public(admin, storage_contract.remove_authorized_contract(admin));
    env.call_public(admin, storage_contract.set(0, state));
}

#[test(should_fail_with = "Not authorized")]
unconstrained fn planet_events_rejects_unapproved_writer() {
    let (mut env, address, _admin) = setup_planet_events();
    let stranger = env.create_light_account();
    env.call_public(stranger, PlanetEventsStorage::at(address).set(0, PlanetEvents::zero()));
}

#[test(should_fail_with = "Not authorized")]
unconstrained fn planet_events_rejects_revoked_writer() {
    let (mut env, address, admin) = setup_planet_events();
    let writer = env.create_light_account();
    let storage_contract = PlanetEventsStorage::at(address);
    env.call_public(admin, storage_contract.add_authorized_contract(writer));
    env.call_public(admin, storage_contract.remove_authorized_contract(writer));
    env.call_public(writer, storage_contract.set(0, PlanetEvents::zero()));
}

unconstrained fn setup_planet_revealed_coords() -> (TestEnvironment, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let admin = env.create_light_account();
    let address = env
        .deploy("artifacts@planet_revealed_coords/PlanetRevealedCoordsStorage")
        .with_public_initializer(admin, PlanetRevealedCoordsStorage::interface().constructor(admin))
        ;
    (env, address, admin)
}

#[test]
unconstrained fn planet_revealed_coords_admin_and_authorized_write_same_hash() {
    let (mut env, address, admin) = setup_planet_revealed_coords();
    let writer = env.create_light_account();
    let storage_contract = PlanetRevealedCoordsStorage::at(address);
    let state = PlanetRevealedCoords::zero();
    env.call_public(admin, storage_contract.set(0, state));
    let expected = env.execute_utility(storage_contract.get_state_root_unconstrained(0));
    env.call_public(admin, storage_contract.add_authorized_contract(writer));
    env.call_public(writer, storage_contract.set(0, state));
    assert_eq(env.execute_utility(storage_contract.get_state_root_unconstrained(0)), expected);
    // Revoking the extra grant must not revoke the administrator's own rights.
    env.call_public(admin, storage_contract.add_authorized_contract(admin));
    env.call_public(admin, storage_contract.remove_authorized_contract(admin));
    env.call_public(admin, storage_contract.set(0, state));
}

#[test(should_fail_with = "Not authorized")]
unconstrained fn planet_revealed_coords_rejects_unapproved_writer() {
    let (mut env, address, _admin) = setup_planet_revealed_coords();
    let stranger = env.create_light_account();
    env.call_public(
        stranger,
        PlanetRevealedCoordsStorage::at(address).set(0, PlanetRevealedCoords::zero()),
    );
}

#[test(should_fail_with = "Not authorized")]
unconstrained fn planet_revealed_coords_rejects_revoked_writer() {
    let (mut env, address, admin) = setup_planet_revealed_coords();
    let writer = env.create_light_account();
    let storage_contract = PlanetRevealedCoordsStorage::at(address);
    env.call_public(admin, storage_contract.add_authorized_contract(writer));
    env.call_public(admin, storage_contract.remove_authorized_contract(writer));
    env.call_public(writer, storage_contract.set(0, PlanetRevealedCoords::zero()));
}

unconstrained fn setup_player() -> (TestEnvironment, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let admin = env.create_light_account();
    let address = env.deploy("artifacts@player/PlayerStorage").with_public_initializer(
        admin,
        PlayerStorage::interface().constructor(admin),
    );
    (env, address, admin)
}

#[test]
unconstrained fn player_admin_and_authorized_write_same_hash() {
    let (mut env, address, admin) = setup_player();
    let writer = env.create_light_account();
    let storage_contract = PlayerStorage::at(address);
    let state = Player::zero();
    env.call_public(admin, storage_contract.set(AztecAddress::zero(), state));
    let expected =
        env.execute_utility(storage_contract.get_state_root_unconstrained(AztecAddress::zero()));
    env.call_public(admin, storage_contract.add_authorized_contract(writer));
    env.call_public(writer, storage_contract.set(AztecAddress::zero(), state));
    assert_eq(
        env.execute_utility(storage_contract.get_state_root_unconstrained(AztecAddress::zero())),
        expected,
    );
    // Revoking the extra grant must not revoke the administrator's own rights.
    env.call_public(admin, storage_contract.add_authorized_contract(admin));
    env.call_public(admin, storage_contract.remove_authorized_contract(admin));
    env.call_public(admin, storage_contract.set(AztecAddress::zero(), state));
}

#[test(should_fail_with = "Not authorized")]
unconstrained fn player_rejects_unapproved_writer() {
    let (mut env, address, _admin) = setup_player();
    let stranger = env.create_light_account();
    env.call_public(stranger, PlayerStorage::at(address).set(AztecAddress::zero(), Player::zero()));
}

#[test(should_fail_with = "Not authorized")]
unconstrained fn player_rejects_revoked_writer() {
    let (mut env, address, admin) = setup_player();
    let writer = env.create_light_account();
    let storage_contract = PlayerStorage::at(address);
    env.call_public(admin, storage_contract.add_authorized_contract(writer));
    env.call_public(admin, storage_contract.remove_authorized_contract(writer));
    env.call_public(writer, storage_contract.set(AztecAddress::zero(), Player::zero()));
}

unconstrained fn setup_world() -> (TestEnvironment, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let admin = env.create_light_account();
    let address = env.deploy("artifacts@world/WorldStorage").with_public_initializer(
        admin,
        WorldStorage::interface().constructor(admin),
    );
    (env, address, admin)
}

#[test]
unconstrained fn world_admin_and_authorized_write_same_hash() {
    let (mut env, address, admin) = setup_world();
    let writer = env.create_light_account();
    let storage_contract = WorldStorage::at(address);
    let state = World::zero();
    env.call_public(admin, storage_contract.set(0, state));
    let expected = env.execute_utility(storage_contract.get_state_root_unconstrained(0));
    env.call_public(admin, storage_contract.add_authorized_contract(writer));
    env.call_public(writer, storage_contract.set(0, state));
    assert_eq(env.execute_utility(storage_contract.get_state_root_unconstrained(0)), expected);
    // Revoking the extra grant must not revoke the administrator's own rights.
    env.call_public(admin, storage_contract.add_authorized_contract(admin));
    env.call_public(admin, storage_contract.remove_authorized_contract(admin));
    env.call_public(admin, storage_contract.set(0, state));
}

#[test(should_fail_with = "Not authorized")]
unconstrained fn world_rejects_unapproved_writer() {
    let (mut env, address, _admin) = setup_world();
    let stranger = env.create_light_account();
    env.call_public(stranger, WorldStorage::at(address).set(0, World::zero()));
}

#[test(should_fail_with = "Not authorized")]
unconstrained fn world_rejects_revoked_writer() {
    let (mut env, address, admin) = setup_world();
    let writer = env.create_light_account();
    let storage_contract = WorldStorage::at(address);
    env.call_public(admin, storage_contract.add_authorized_contract(writer));
    env.call_public(admin, storage_contract.remove_authorized_contract(writer));
    env.call_public(writer, storage_contract.set(0, World::zero()));
}

#[test]
unconstrained fn arrival_batch_matches_scalar_verification() {
    let (env, address, _admin) = setup_arrival();
    let storage_contract = ArrivalStorage::at(address);
    let ids: [Field; 20] = [9; 20];
    let hashes: [Field; 20] = [0; 20];
    for count in 0..21 {
        assert(env.view_public(storage_contract.verify_hashes_batch(ids, hashes, count)));
        for bad_index in 0..20 {
            let mut bad = hashes;
            bad[bad_index] = 123;
            assert_eq(
                env.view_public(storage_contract.verify_hashes_batch(ids, bad, count)),
                bad_index >= count,
            );
        }
    }
    // Reserved ID zero is intentionally ignored even when its hash is nonzero.
    assert(env.view_public(storage_contract.verify_hashes_batch([0; 20], [123; 20], 20)));
}

#[test(should_fail_with = "count exceeds batch size")]
unconstrained fn arrival_rejects_oversized_batch() {
    let (env, address, _admin) = setup_arrival();
    env.view_public(ArrivalStorage::at(address).verify_hashes_batch([0; 20], [0; 20], 21));
}

#[test]
unconstrained fn artifact_batch_matches_scalar_verification() {
    let (env, address, _admin) = setup_artifact();
    let storage_contract = ArtifactStorage::at(address);
    let ids: [Field; 20] = [9; 20];
    let hashes: [Field; 20] = [0; 20];
    for count in 0..21 {
        assert(env.view_public(storage_contract.verify_hashes_batch(ids, hashes, count)));
        for bad_index in 0..20 {
            let mut bad = hashes;
            bad[bad_index] = 123;
            assert_eq(
                env.view_public(storage_contract.verify_hashes_batch(ids, bad, count)),
                bad_index >= count,
            );
        }
    }
    // Reserved ID zero is intentionally ignored even when its hash is nonzero.
    assert(env.view_public(storage_contract.verify_hashes_batch([0; 20], [123; 20], 20)));
}

#[test(should_fail_with = "count exceeds batch size")]
unconstrained fn artifact_rejects_oversized_batch() {
    let (env, address, _admin) = setup_artifact();
    env.view_public(ArtifactStorage::at(address).verify_hashes_batch([0; 20], [0; 20], 21));
}

#[test]
unconstrained fn artifact_location_batch_matches_scalar_verification() {
    let (env, address, _admin) = setup_artifact_location();
    let storage_contract = ArtifactLocationStorage::at(address);
    let ids: [Field; 20] = [9; 20];
    let hashes: [Field; 20] = [0; 20];
    for count in 0..21 {
        assert(env.view_public(storage_contract.verify_hashes_batch(ids, hashes, count)));
        for bad_index in 0..20 {
            let mut bad = hashes;
            bad[bad_index] = 123;
            assert_eq(
                env.view_public(storage_contract.verify_hashes_batch(ids, bad, count)),
                bad_index >= count,
            );
        }
    }
    // Reserved ID zero is intentionally ignored even when its hash is nonzero.
    assert(env.view_public(storage_contract.verify_hashes_batch([0; 20], [123; 20], 20)));
}

#[test(should_fail_with = "count exceeds batch size")]
unconstrained fn artifact_location_rejects_oversized_batch() {
    let (env, address, _admin) = setup_artifact_location();
    env.view_public(ArtifactLocationStorage::at(address).verify_hashes_batch([0; 20], [0; 20], 21));
}

use optimization_benchmark::OptimizationBenchmark;

#[test]
unconstrained fn benchmark_storage_gas() {
    let (mut env, arrivals, admin) = setup_arrival();
    let bench = env
        .deploy("../optimization-benchmark@optimization_benchmark/OptimizationBenchmark")
        .without_initializer();
    let locations = env
        .deploy("artifacts@artifact_location/ArtifactLocationStorage")
        .with_public_initializer(admin, ArtifactLocationStorage::interface().constructor(admin));
    let planet = env.deploy("artifacts@planet/PlanetStorage").with_public_initializer(
        admin,
        PlanetStorage::interface().constructor(admin),
    );
    env.call_public(admin, ArtifactLocationStorage::at(locations).add_authorized_contract(bench));
    env.call_public(admin, PlanetStorage::at(planet).add_authorized_contract(bench));
    for count in [0, 1, 5, 20] {
        let verify_gas =
            env.call_public(admin, OptimizationBenchmark::at(bench).arrival_batch(arrivals, count));
        println(f"BENCH arrival_verify count={count} gas={verify_gas}");
        let write_gas = env.call_public(
            admin,
            OptimizationBenchmark::at(bench).location_batch(locations, count),
        );
        println(f"BENCH location_write count={count} gas={write_gas}");
    }
    let planet_gas = env.call_public(admin, OptimizationBenchmark::at(bench).planet_write(planet));
    println(f"BENCH planet_write gas={planet_gas}");
}

#[test]
unconstrained fn location_batch_preserves_order_and_ignores_padding() {
    let (env, address, admin) = setup_artifact_location();
    let storage_contract = ArtifactLocationStorage::at(address);
    let mut ids: [Field; 20] = [0; 20];
    let mut states = [ArtifactLocation::zero(); 20];
    ids[0] = 7;
    ids[2] = 7;
    ids[3] = 8;
    states[0].planet_id = 11;
    states[2].planet_id = 12;
    states[3].planet_id = 13;
    env.call_public(admin, storage_contract.set_arrival_locations_max20(ids, states, 3));
    assert(env.view_public(storage_contract.verify(7, states[2])));
    assert_eq(env.execute_utility(storage_contract.get_state_root_unconstrained(8)), 0);
    assert_eq(env.execute_utility(storage_contract.get_state_root_unconstrained(0)), 0);
    env.call_public(admin, storage_contract.set_arrival_locations_max20(ids, states, 0));
    assert(env.view_public(storage_contract.verify(7, states[2])));
    env.call_public(
        admin,
        storage_contract.set_spaceship_locations_max5(
            [7, 0, 7, 8, 9],
            [states[0], states[1], states[2], states[3], states[4]],
            3,
        ),
    );
    assert(env.view_public(storage_contract.verify(7, states[2])));
    assert_eq(env.execute_utility(storage_contract.get_state_root_unconstrained(8)), 0);
}

#[test(should_fail_with = "count exceeds batch size")]
unconstrained fn location_rejects_oversized_write_batch() {
    let (env, address, admin) = setup_artifact_location();
    env.call_public(
        admin,
        ArtifactLocationStorage::at(address).set_arrival_locations_max20(
            [0; 20],
            [ArtifactLocation::zero(); 20],
            21,
        ),
    );
}

#[test(should_fail_with = "count exceeds batch size")]
unconstrained fn location_rejects_oversized_spaceship_batch() {
    let (env, address, admin) = setup_artifact_location();
    env.call_public(
        admin,
        ArtifactLocationStorage::at(address).set_spaceship_locations_max5(
            [0; 5],
            [ArtifactLocation::zero(); 5],
            6,
        ),
    );
}
