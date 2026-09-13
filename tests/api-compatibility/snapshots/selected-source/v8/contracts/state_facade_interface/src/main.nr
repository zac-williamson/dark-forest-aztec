// Call signatures only. This contract is never deployed.
use aztec::macros::aztec;
#[aztec]
pub contract StateFacadeInterface {
    use aztec::macros::functions::{external,view};
    use aztec::protocol::{address::AztecAddress, hash::poseidon2_hash, traits::{Serialize,ToField,FromField}};
    use types::storage::{world::World, player::Player, planet::{Planet,PlanetArtifacts,PlanetEvents,PlanetEventMetadata,PlanetRevealedCoords}, arrival::Arrival, artifact::{Artifact,ArtifactLocation}};
    #[external("public")]
    fn emit_world_update(_id: Field, _state: World) { assert(false, "Interface only"); }
    #[external("public")]
    fn emit_world_fields(_id: Field, _root: Field, _field_0: Field, _field_1: Field, _field_2: Field, _field_3: Field) { assert(false, "Interface only"); }
    #[external("public")]
    fn emit_player_update(_id: AztecAddress, _state: Player) { assert(false, "Interface only"); }
    #[external("public")]
    fn emit_player_fields(_id: Field, _root: Field, _field_0: Field, _field_1: Field, _field_2: Field, _field_3: Field, _field_4: Field, _field_5: Field, _field_6: Field, _field_7: Field) { assert(false, "Interface only"); }
    #[external("public")]
    fn emit_planet_update(_id: Field, _state: Planet) { assert(false, "Interface only"); }
    #[external("public")]
    fn emit_planet_fields(_id: Field, _root: Field, _field_0: Field, _field_1: Field, _field_2: Field, _field_3: Field, _field_4: Field, _field_5: Field, _field_6: Field, _field_7: Field, _field_8: Field, _field_9: Field, _field_10: Field, _field_11: Field, _field_12: Field, _field_13: Field, _field_14: Field, _field_15: Field, _field_16: Field, _field_17: Field, _field_18: Field, _field_19: Field, _field_20: Field, _field_21: Field, _field_22: Field, _field_23: Field, _field_24: Field, _field_25: Field, _field_26: Field, _field_27: Field, _field_28: Field, _field_29: Field, _field_30: Field, _field_31: Field) { assert(false, "Interface only"); }
    #[external("public")]
    fn emit_planet_revealed_coords_update(_id: Field, _state: PlanetRevealedCoords) { assert(false, "Interface only"); }
    #[external("public")]
    fn emit_planet_revealed_coords_fields(_id: Field, _root: Field, _field_0: Field, _field_1: Field, _field_2: Field, _field_3: Field) { assert(false, "Interface only"); }
    #[external("public")]
    fn emit_planet_events_update(_id: Field, _state: PlanetEvents) { assert(false, "Interface only"); }
    #[external("public")]
    fn emit_planet_events_fields(_id: Field, _root: Field, _field_0: Field, _field_1: Field, _field_2: Field, _field_3: Field, _field_4: Field, _field_5: Field, _field_6: Field, _field_7: Field, _field_8: Field, _field_9: Field, _field_10: Field, _field_11: Field, _field_12: Field, _field_13: Field, _field_14: Field, _field_15: Field, _field_16: Field, _field_17: Field, _field_18: Field, _field_19: Field, _field_20: Field, _field_21: Field) { assert(false, "Interface only"); }
    #[external("public")]
    fn emit_planet_artifacts_update(_id: Field, _state: PlanetArtifacts) { assert(false, "Interface only"); }
    #[external("public")]
    fn emit_planet_artifacts_fields(_id: Field, _root: Field, _field_0: Field, _field_1: Field, _field_2: Field, _field_3: Field, _field_4: Field, _field_5: Field, _field_6: Field, _field_7: Field, _field_8: Field, _field_9: Field, _field_10: Field, _field_11: Field, _field_12: Field, _field_13: Field, _field_14: Field, _field_15: Field, _field_16: Field, _field_17: Field, _field_18: Field, _field_19: Field, _field_20: Field, _field_21: Field) { assert(false, "Interface only"); }
    #[external("public")]
    fn emit_arrival_update(_id: Field, _state: Arrival) { assert(false, "Interface only"); }
    #[external("public")]
    fn emit_arrival_fields(_id: Field, _root: Field, _field_0: Field, _field_1: Field, _field_2: Field, _field_3: Field, _field_4: Field, _field_5: Field, _field_6: Field, _field_7: Field, _field_8: Field, _field_9: Field, _field_10: Field) { assert(false, "Interface only"); }
    #[external("public")]
    fn emit_artifact_update(_id: Field, _state: Artifact) { assert(false, "Interface only"); }
    #[external("public")]
    fn emit_artifact_fields(_id: Field, _root: Field, _field_0: Field, _field_1: Field, _field_2: Field, _field_3: Field, _field_4: Field, _field_5: Field, _field_6: Field, _field_7: Field, _field_8: Field, _field_9: Field, _field_10: Field, _field_11: Field, _field_12: Field) { assert(false, "Interface only"); }
    #[external("public")]
    fn emit_artifact_location_update(_id: Field, _state: ArtifactLocation) { assert(false, "Interface only"); }
    #[external("public")]
    fn emit_artifact_location_fields(_id: Field, _root: Field, _field_0: Field, _field_1: Field, _field_2: Field) { assert(false, "Interface only"); }
    #[external("public")]
    fn emit_artifact_location_batch_max5(_ids:[Field;5], _fields:[[Field;3];5], _count:u32) { assert(false,"Interface only"); }
    #[external("public")]
    fn emit_artifact_location_batch_max20(_ids:[Field;20], _fields:[[Field;3];20], _count:u32) { assert(false,"Interface only"); }
    #[external("public")]
    fn emit_artifact_batch_max5(_ids:[Field;5], _fields:[[Field;13];5], _count:u32) { assert(false,"Interface only"); }
}
