This test-only contract implements the original `verify_hashes_batch` and
`set_arrival_locations_max20` selectors with caller-sensitive behavior. It checks
all IDs/hashes at count zero and a Poseidon commitment to every one of the 60
serialized location fields. Refresh expects one batch. Move expects distinct
source and target batches in order; only the last expected call reverts with the
success sentinel `Original inactive locations observed`.

`../location-caller.mjs` evaluates the original private Refresh and Move APIs on
original and final System clones. It creates isolated canonical namespaces bound
to the final Backend and substitutes this unregistered custom location contract.
All other required namespace kinds are canonical, so this custom address forces
the optimized continuation's exact original fallback. Both variants use the same
inputs and expected location commitments, including nonzero inactive fields and
Core’s original timestamp update for an inactive carried artifact and Move’s exact retention of inactive timestamps. A changed inactive
witness must produce `Arrival location payload changed`, rather than the success
sentinel. Direct account calls must produce `Location caller changed`.

The runner uses `proverEnabled: false`. It submits isolated setup transactions;
all gameplay operations are reverting simulations, with no transaction proofs or
gameplay sends. It records current deployed class IDs, artifact hashes, full
expected batches, input hashes, and unchanged state roots/counters after each
simulation. This is compatibility evidence, not Fee Juice or proof-latency data.

Do not run alongside the fee runner. After the coordinator releases the mutation
window and this public-only test contract has been compiled/native-processed:

```sh
RUN_CALLER_LOCATION=1 HARDWARE_CONCURRENCY=2 RAYON_NUM_THREADS=2 \
  node tests/api-compatible-storage/location-caller.mjs \
  candidate-v4 /tmp/df-api-compatible-v4-native \
  docs/api-compatibility/location-caller-regressions-candidate-v4.json
```

The default original witnesses are the frozen `baseline-v2` ordinary fixtures.
`CALLER_BASELINE_VARIANT`, `CALLER_BASELINE_ARTIFACTS`,
`CALLER_REFRESH_FIXTURE`, `CALLER_MOVE_EMPTY_FIXTURE`, and
`CALLER_LOCATION_ARTIFACT` allow explicit alternatives. Existing reports are never
overwritten. The driver rejects an expired timestamp instead of weakening the
original five-minute freshness limit.

Offline fixture checks do not open a node or wallet:

```sh
node --test tests/api-compatible-storage/caller-location-fixtures.test.mjs
```
