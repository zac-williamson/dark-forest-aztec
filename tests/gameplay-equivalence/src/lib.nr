use types::storage::{artifact::{Artifact, ArtifactLocation}, planet::PlanetArtifacts};
pub mod reference_lazy;
mod reference_planet;
use aztec::protocol::{address::AztecAddress, traits::FromField};
use libs::lazy_update::apply_pending_events;
use types::storage::{arrival::Arrival, planet::{Planet, PlanetEvents}};

fn fixture(count: u32, seed: u32) -> (Planet, PlanetEvents, [Arrival; 20]) {
    let mut p = Planet::zero();
    p.owner = AztecAddress::from_field(1);
    p.population = 500;
    p.population_cap = 100000;
    p.population_growth = 10;
    p.silver_cap = 100000;
    p.silver_growth = 5;
    p.defense = 100;
    p.planet_type = (seed % 5) as u8;
    p.destroyed = seed % 13 == 0;
    p.pausers = if seed % 7 == 0 { 1 } else { 0 };
    let mut e = PlanetEvents::zero();
    e.count = count;
    e.last_updated = 123;
    let mut a = [Arrival::zero(); 20];
    for i in 0..20 {
        // Includes duplicate and zero IDs, and populated slots beyond count.
        e.events[i].id = if seed % 3 == 0 {
            (i % 4) as Field
        } else {
            i as Field + 1
        };
        a[i].id = e.events[i].id;
        a[i].player = AztecAddress::from_field(((i + seed) % 3) as Field);
        a[i].pop_arriving = (100 + (i * 37) % 600) as u128;
        a[i].silver_moved = i as u128 * 3;
        a[i].arrival_type = ((i + seed) % 4) as u8;
        a[i].arrival_time = ((i * 17 + seed * 13) % 101) as u64;
        if seed % 5 == 0 {
            a[i].arrival_time = 25;
        }
        if seed % 11 == 0 {
            a[i].arrival_time = 18446744073709551615;
        }
        if i % 3 == 0 {
            a[i].carried_artifact_id = i as Field + 100;
        }
    }
    (p, e, a)
}
#[test]
unconstrained fn differential_queue_matrix() {
    for count in 0..22 {
        for seed in 0..32 {
            let (p, e, a) = fixture(count, seed);
            assert_eq(
                apply_pending_events(50, p, e, a),
                reference_lazy::apply_pending_events(50, p, e, a),
            );
        }
    }
    println("704 old/new full-output comparisons passed");
}
#[test]
fn constrained_full_queue_equivalence() {
    let (p, e, a) = fixture(20, 3);
    assert_eq(
        apply_pending_events(100, p, e, a),
        reference_lazy::apply_pending_events(100, p, e, a),
    );
}
#[test]
fn ties_and_duplicate_ids_preserve_order() {
    let (mut p, mut e, mut a) = fixture(4, 5);
    p.destroyed = false;
    e.events[0].id = 9;
    e.events[1].id = 2;
    e.events[2].id = 9;
    e.events[3].id = 3;
    for i in 0..20 {
        a[i].arrival_time = 0;
    }
    let result = apply_pending_events(0, p, e, a);
    assert_eq(result, reference_lazy::apply_pending_events(0, p, e, a));
    assert_eq(result.1.count, 3);
    assert_eq(result.1.events[0].id, 9);
    assert_eq(result.1.events[1].id, 2);
    assert_eq(result.1.events[2].id, 3);
}
#[test(should_fail)]
fn old_rejects_timestamp_underflow() {
    let (mut p, e, a) = fixture(20, 5);
    p.last_updated = 30;
    reference_lazy::apply_pending_events(50, p, e, a);
}
#[test(should_fail)]
fn new_rejects_timestamp_underflow() {
    let (mut p, e, a) = fixture(20, 5);
    p.last_updated = 30;
    apply_pending_events(50, p, e, a);
}

#[test]
unconstrained fn full_refresh_outputs_match() {
    for count in 0..21 {
        for seed in 0..16 {
            let (p, e, a) = fixture(count, seed);
            let mut artifacts = [Artifact::zero(); 20];
            let mut locations = [ArtifactLocation::zero(); 20];
            for i in 0..20 {
                artifacts[i].artifact_type = (10 + i % 5) as u8;
                locations[i].voyage_id = a[i].id;
            }
            assert_eq(
                libs::planet::refresh_planet_v1(
                    100,
                    99,
                    p,
                    e,
                    a,
                    artifacts,
                    locations,
                    PlanetArtifacts::zero(),
                ),
                reference_planet::refresh_planet_v1(
                    100,
                    99,
                    p,
                    e,
                    a,
                    artifacts,
                    locations,
                    PlanetArtifacts::zero(),
                ),
            );
            assert_eq(
                libs::planet::refresh_planet_v2(
                    100,
                    99,
                    p,
                    e,
                    a,
                    artifacts,
                    locations,
                    PlanetArtifacts::zero(),
                ),
                reference_planet::refresh_planet_v2(
                    100,
                    99,
                    p,
                    e,
                    a,
                    artifacts,
                    locations,
                    PlanetArtifacts::zero(),
                ),
            );
        }
    }
    println(
        "672 complete refresh output comparisons passed, including artifact effects and locations",
    );
}

#[test]
unconstrained fn artifact_batch_guard_preserves_active_prefix() {
    let mut ids:[Field;20]=[0;20];
    for count in 0..21 {assert(!libs::batch_utils::has_nonzero_ids(ids,count));}
    for position in 0..20 {
        ids[position]=123;
        for count in 0..21 {assert_eq(libs::batch_utils::has_nonzero_ids(ids,count),count>position);}
        ids[position]=0;
    }
}
#[test(should_fail_with = "count exceeds batch size")]
unconstrained fn artifact_batch_guard_preserves_bound_rejection() {
    libs::batch_utils::has_nonzero_ids([0;20],21);
}
