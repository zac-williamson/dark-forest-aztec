use aztec::macros::aztec;

// Test-only harness: measures actual nested contract execution using AVM gas counters.
#[aztec]
pub contract OptimizationBenchmark {
    use arrival::ArrivalStorage;
    use artifact_location::ArtifactLocationStorage;
    use aztec::{macros::functions::external, protocol::address::AztecAddress};
    use planet::PlanetStorage;
    use types::storage::{artifact::ArtifactLocation, planet::Planet};

    #[external("public")]
    fn arrival_batch(address: AztecAddress, count: u32) -> (u32, u32) {
        let l2_before = self.context.l2_gas_left();
        let da_before = self.context.da_gas_left();
        assert(self.view(ArrivalStorage::at(address).verify_hashes_batch([9; 20], [0; 20], count)));
        (l2_before - self.context.l2_gas_left(), da_before - self.context.da_gas_left())
    }

    #[external("public")]
    fn location_batch(address: AztecAddress, count: u32) -> (u32, u32) {
        let l2_before = self.context.l2_gas_left();
        let da_before = self.context.da_gas_left();
        self.call(ArtifactLocationStorage::at(address).set_arrival_locations_max20(
            [9; 20],
            [ArtifactLocation::zero(); 20],
            count,
        ));
        (l2_before - self.context.l2_gas_left(), da_before - self.context.da_gas_left())
    }

    #[external("public")]
    fn planet_write(address: AztecAddress) -> (u32, u32) {
        let l2_before = self.context.l2_gas_left();
        let da_before = self.context.da_gas_left();
        self.call(PlanetStorage::at(address).set(9, Planet::zero()));
        (l2_before - self.context.l2_gas_left(), da_before - self.context.da_gas_left())
    }
}
