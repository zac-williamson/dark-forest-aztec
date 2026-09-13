use aztec::protocol::{address::AztecAddress, traits::{FromField, ToField}};
use types::storage::arrival::Arrival;

// Exact BN254 Field literals avoid executing exponentiation in public getters.
global TWO64: Field = 0x10000000000000000;
global TWO128: Field = 0x100000000000000000000000000000000;
global TWO192: Field = 0x1000000000000000000000000000000000000000000000000;
global INV_TWO64: Field = 0x24d6ba07f7aa8f04b2d8f06f77f52a93ca478dbeab3c92cd2d3e8053e396ee4d;
global INV_TWO128: Field = 0x133100d71fdf35792b16366f4f7684df54ad7e14a329e70f18ee753c76f9dc6f;


// Preserve every field, including the explicit ID and the complete u128 ranges.
// Neither address/location hashes nor amounts are narrowed to today's fixtures.
pub fn pack_arrival(a: Arrival) -> [Field; 8] {
    [
        a.id,
        a.player.to_field(),
        a.from_planet,
        a.to_planet,
        a.carried_artifact_id,
        a.pop_arriving as Field
            + (a.departure_time as Field) * TWO128
            + (a.arrival_type as Field) * TWO192,
        a.silver_moved as Field + (a.arrival_time as Field) * TWO128,
        a.distance as Field,
    ]
}

pub fn unpack_arrival(fields: [Field; 8]) -> Arrival {
    // Field-to-integer casts retain the low bits. Recompose and compare below
    // to reject every noncanonical high bit rather than silently discarding it.
    // This is constant-work in public getters: no bit loops or exponentiation.
    let pop_arriving = fields[5] as u128;
    let first_upper = (fields[5] - pop_arriving as Field) * INV_TWO128;
    let departure_time = first_upper as u64;
    let arrival_type = ((first_upper - departure_time as Field) * INV_TWO64) as u8;
    let silver_moved = fields[6] as u128;
    let arrival_time = ((fields[6] - silver_moved as Field) * INV_TWO128) as u64;
    let distance = fields[7] as u128;
    let a = Arrival {
        id: fields[0],
        player: AztecAddress::from_field(fields[1]),
        from_planet: fields[2],
        to_planet: fields[3],
        carried_artifact_id: fields[4],
        pop_arriving,
        departure_time,
        arrival_type,
        silver_moved,
        arrival_time,
        distance,
    };
    let canonical = pack_arrival(a);
    assert_eq(canonical[5], fields[5], "Noncanonical packed arrival");
    assert_eq(canonical[6], fields[6], "Noncanonical packed arrival");
    assert_eq(canonical[7], fields[7], "Noncanonical packed arrival");
    a
}

#[test]
fn zero_round_trip() {
    assert_eq(pack_arrival(Arrival::zero()), [0; 8]);
    assert_eq(unpack_arrival([0; 8]), Arrival::zero());
}

#[test]
fn maximal_ranges_round_trip() {
    let a = Arrival {
        id: -1,
        player: AztecAddress::from_field(-2),
        from_planet: -3,
        to_planet: -4,
        carried_artifact_id: -5,
        pop_arriving: 0xffffffffffffffffffffffffffffffff,
        silver_moved: 0xffffffffffffffffffffffffffffffff,
        distance: 0xffffffffffffffffffffffffffffffff,
        departure_time: 0xffffffffffffffff,
        arrival_time: 0xffffffffffffffff,
        arrival_type: 0xff,
    };
    let p = pack_arrival(a);
    assert_eq(p[5], 2.pow_32(200) - 1);
    assert_eq(p[6], 2.pow_32(192) - 1);
    assert_eq(p[7], 2.pow_32(128) - 1);
    assert_eq(unpack_arrival(p), a);
}

#[test]
unconstrained fn every_numeric_bit_round_trips() {
    for bit in 0..128 {
        let mut a = Arrival::zero();
        let value = 2.pow_32(bit as Field) as u128;
        a.pop_arriving = value;
        assert_eq(unpack_arrival(pack_arrival(a)), a);
        a.silver_moved = value;
        assert_eq(unpack_arrival(pack_arrival(a)), a);
        a.distance = value;
        assert_eq(unpack_arrival(pack_arrival(a)), a);
    }
    for bit in 0..64 {
        let mut a = Arrival::zero();
        let value = 2.pow_32(bit as Field) as u64;
        a.departure_time = value;
        assert_eq(unpack_arrival(pack_arrival(a)), a);
        a.arrival_time = value;
        assert_eq(unpack_arrival(pack_arrival(a)), a);
    }
    for bit in 0..8 {
        let mut a = Arrival::zero();
        a.arrival_type = 2.pow_32(bit as Field) as u8;
        assert_eq(unpack_arrival(pack_arrival(a)), a);
    }
}

#[test]
fn zero_id_does_not_erase_nonzero_state() {
    let mut a = Arrival::zero();
    a.player = AztecAddress::from_field(17);
    a.pop_arriving = 23;
    a.carried_artifact_id = -1;
    assert_eq(unpack_arrival(pack_arrival(a)), a);
}

#[test(should_fail)]
fn rejects_overwide_first_word() {
    let mut p = [0; 8];
    p[5] = 2.pow_32(200);
    unpack_arrival(p);
}

#[test(should_fail_with = "Noncanonical packed arrival")]
fn rejects_overwide_second_word() {
    let mut p = [0; 8];
    p[6] = 2.pow_32(192);
    unpack_arrival(p);
}

#[test(should_fail)]
fn rejects_overwide_distance() {
    let mut p = [0; 8];
    p[7] = 2.pow_32(128);
    unpack_arrival(p);
}

#[test]
fn power_constants_and_inverses_are_exact() {
    assert_eq(TWO64, 2.pow_32(64));
    assert_eq(TWO128, 2.pow_32(128));
    assert_eq(TWO192, 2.pow_32(192));
    assert_eq(TWO64 * INV_TWO64, 1);
    assert_eq(TWO128 * INV_TWO128, 1);
}
