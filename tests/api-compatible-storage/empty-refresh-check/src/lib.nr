use aztec::protocol::{hash::poseidon2_hash, traits::Serialize};
use types::storage::{
    planet::{Planet, PlanetArtifacts, PlanetEvents},
    arrival::Arrival,
    artifact::{Artifact, ArtifactLocation},
};
use libs::batch_utils::{assert_planet_timestamp_freshness, compute_planet_hashes};
use libs::planet::refresh_planet_v1;

#[test]
fn zero_count_ignores_arrivals_but_preserves_full_planet_component_tails() {
    let mut planet=Planet::zero();
    planet.is_initialized=true;
    planet.population_cap=100000;
    planet.population=50000;
    planet.last_updated=1;
    let mut pa=PlanetArtifacts::zero(); pa.last_updated=1; pa.ids[19]=-1;
    let mut pe=PlanetEvents::zero(); pe.last_updated=1; pe.events[19].id=-2;
    let mut arrivals=[Arrival::zero();20];
    arrivals[19].id=-3; arrivals[19].carried_artifact_id=-4;
    arrivals[19].departure_time=18446744073709551615;
    let mut artifacts=[Artifact::zero();20];
    artifacts[19].last_updated=18446744073709551615;
    let mut locations=[ArtifactLocation::zero();20];
    locations[19].planet_id=-5; locations[19].voyage_id=-6;
    locations[19].last_updated=18446744073709551615;

    // These future timestamps are allowed outside the original active count.
    assert_planet_timestamp_freshness(20,planet,pa,pe,arrivals,artifacts,locations);
    let hashes=compute_planet_hashes(42,planet,pa,pe,arrivals,artifacts,locations);
    assert(hashes.9==0);
    assert(hashes.4==[0;20]); assert(hashes.5==[0;20]);
    assert(hashes.6==[0;20]); assert(hashes.7==[0;20]); assert(hashes.8==[0;20]);
    assert(hashes.2==poseidon2_hash(pa.serialize()));
    assert(hashes.3==poseidon2_hash(pe.serialize()));

    let result=refresh_planet_v1(20,42,planet,pe,arrivals,artifacts,locations,pa);
    assert(result.1==pe); assert(result.2==pa); assert(result.3==locations);
    // Core subsequently updates the three timestamps and this ignored location.
    let mut next_planet=result.0; next_planet.last_updated=20;
    let mut next_pe=result.1; next_pe.last_updated=20;
    let mut next_pa=result.2; next_pa.last_updated=20;
    let mut ignored_locations=result.3; ignored_locations[19].last_updated=20;
    assert(ignored_locations[19]!=ArtifactLocation::zero());
    assert(next_pa.ids[19]==-1); assert(next_pe.events[19].id==-2);
    assert(next_pa.serialize()[19]==-1); assert(next_pe.serialize()[19]==-2);
    // The actual compact schema includes all 32+22+22 serialized snapshot fields.
    assert(next_planet.serialize().len()+next_pa.serialize().len()+next_pe.serialize().len()==76);
}

#[test]
fn nonzero_count_requires_the_general_path_even_for_zero_event_ids() {
    let planet=Planet::zero();
    let pa=PlanetArtifacts::zero();
    let mut pe=PlanetEvents::zero(); pe.count=1;
    let hashes=compute_planet_hashes(0,planet,pa,pe,[Arrival::zero();20],[Artifact::zero();20],[ArtifactLocation::zero();20]);
    assert(hashes.9==1);
    assert(hashes.4==[0;20]);
    // Eligibility is the original count, not inferred from zero IDs or hashes.
    assert(!(hashes.9==0));
}

#[test(should_fail_with = "Timestamp must be >= arrival's departure_time")]
fn active_arrival_freshness_is_not_relaxed_by_zero_carried_artifact() {
    let mut pe=PlanetEvents::zero(); pe.count=1;
    let mut arrivals=[Arrival::zero();20]; arrivals[0].departure_time=21;
    assert_planet_timestamp_freshness(20,Planet::zero(),PlanetArtifacts::zero(),pe,arrivals,[Artifact::zero();20],[ArtifactLocation::zero();20]);
}
