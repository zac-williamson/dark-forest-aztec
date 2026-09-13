# Empty and zero-ID batch verifier compatibility

This adds essential coverage beyond the frozen V4 suites. The true original Systems call `verify_hashes_batch([Field;20], [Field;20], u32)` even when `count == 0`, and even when a nonzero count contains only zero artifact IDs. An arbitrary configured store can reject that call or inspect the original System caller. A local shortcut must preserve this behavior through the original fallback.

`CallerSensitiveBatch` has no private functions. Its view selector checks the actual caller and all 40 ID/hash fields. At count zero both arrays must be entirely zero, as emitted by the original private `compute_planet_hashes` boundary. At nonzero count the full 41-word commitment and count must match. Configurable behavior returns false or emits different zero/nonzero assertion markers. The view never writes a call counter.

The runner uses complete original private entry points for Core Refresh, Vault Give, and Move. It creates isolated namespaces, original/candidate Systems, a canonical Config, and two custom verifiers. Only one namespace is replaced by a custom class per case, so a custom Arrival, Artifact, or Location store must independently cause safe fallback. Count-zero fixtures retain nonzero inactive PA/PE/Arrival/location values. Mixed Move queues derive directly from the saved original ordinary and one-arrival fixtures; all unrelated inputs must agree before combining them.

The 66 planned private-entry simulations cover false-return propagation, exact caller/input markers, source-zero/target-one order, source-one/target-zero order, and nonzero-count/all-zero Artifact and Location IDs. An additional 40 direct simulations alter every position in each zero array. Every gameplay case also rejects an account impersonating the System and checks unchanged isolated roots/counter after the reverting simulation: 238 planned logical checks total. These are planned checks until a runtime report says `passed: true`.

The final candidate's genuine native artifacts and explicit runtime release are required. Do not run during historical Find's reserved interval. All setup is isolated; no shared fee wallet or game namespace is changed. No transaction proofs, profiles, or gameplay transactions are produced.

```sh
# Offline fixture review; no node, wallet, or proofs.
node --test tests/api-compatible-storage/caller-batch-fixtures.test.mjs
node --check tests/api-compatible-storage/batch-caller.mjs

# Only after the coordinator releases the two-thread compiler window.
RAYON_NUM_THREADS=2 /tmp/df-noir-beta22/nargo compile --program-dir tests/api-compatible-storage/caller-batch --force
HARDWARE_CONCURRENCY=2 RAYON_NUM_THREADS=2 node_modules/.bin/bb aztec_process -i tests/api-compatible-storage/caller-batch/target/caller_sensitive_batch-CallerSensitiveBatch.json

# Only after final genuine build/deployment and explicit mutation-window release.
RUN_CALLER_BATCH=1 NODE_BACKEND=js LOG_LEVEL=error node --import ./node_modules/tsx/dist/loader.mjs tests/api-compatible-storage/batch-caller.mjs candidate-v5 /tmp/df-api-compatible-v5-native
```

The runtime refuses an existing report path and records exact native hashes/classes, fixture provenance, all expected batch words, nonzero commitments, and setup receipts. `CALLER_BATCH_ARTIFACT` chooses an explicit native fixture artifact; `CALLER_BASELINE_VARIANT` defaults to `baseline-v2`. Per-input overrides are `CALLER_BATCH_CORE_FIXTURE`, `CALLER_BATCH_MOVE_FIXTURE`, `CALLER_BATCH_QUEUEDMOVE_FIXTURE`, and `CALLER_BATCH_ARTIFACT_VALUT_FIXTURE`. This is compatibility evidence, not successful-settlement Fee Juice or proof-latency evidence.
