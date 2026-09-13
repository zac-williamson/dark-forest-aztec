# Complete original-API transaction benchmark

This directory measures the pinned original Dark Forest Aztec contracts against a fresh deployment of the canonical-state implementation. It preserves previous optimization reports and deployments. Internal storage can change; all original caller ABIs, original event payloads and ordered state updates are compared.

The isolated Aztec5.2 local network uses RPC8097/admin8897 and Anvil8551. Its data directory and wallet are `/tmp/df-api-compatible-network52` and `/tmp/df-api-compatible-wallet52`. Artifacts and SDK runtime are separate from the repository dependencies. Network changes are local only.

The CLI's `start --local-network` redeploys its L1 contracts on restart; reusing a data directory does not resume that chain. The completed first28 pairs and diagnostic reproduction are frozen at `/tmp/df-api-compatible-v1/benchmark` and `/tmp/df-api-compatible-v1/diagnostic-traces`. Subsequent same-chain comparisons use distinct `baseline-v2` / `candidate-v2` labels, `BENCH_BASELINE_VARIANT=baseline-v2`, and `BENCH_WALLET_DIRECTORY=/tmp/df-api-compatible-wallet52-v2`. Earlier receipts and deployment files are retained.

`setup.mjs baseline` deploys17 original contracts, calls their original address setters and grants their actual required writers. Candidate setup additionally deploys `game_state_backend-GameStateBackend.json`, `core_settlement_worker-CoreSettlementWorker.json` and `vault_settlement_worker-VaultSettlementWorker.json`. It binds the seven systems and nine facades through `set_state_backend`, plus Core and ArtifactValut through `set_state_worker`, before setup writes. The workers are stateless and have no-argument constructors. Backend constructor has no arguments; the original17 constructors retain their admin arguments. Hardcoded supported classes must be frozen before candidate deployment.

`run.mjs baseline` measures all14 private methods. `run.mjs candidate /tmp/df-api-compatible-native` measures the same caller APIs. `BENCH_METHODS` selects names. `BENCH_PUBLIC=1` selects12 direct public Admin/Vault actions. `BENCH_CASES` selects frozen original Move/Refresh witnesses, and `BENCH_SPONSORED=1` uses the local SponsoredFPC. The account transaction and its full public execution are included in every billed fee. Fixture seeding and deployment are recorded separately and excluded from player-action fees.

The run stores actual mined receipts, billed gas, actual block prices and fees valued at the same observed reference schedule from `docs/fee-benchmark/common-fee-schedule.json`. Every receipt fee must exactly equal its billed gas multiplied by the actual mined block prices. Default runs disable proof generation for fee measurement; they do not measure proof latency. Separate real-prover and browser runs must support any proving/UX conclusion.

Each state update is decoded using the original event ABI, including every inactive array slot. Every resulting root is checked against Poseidon2 of every original event field. Candidate events must retain tags, IDs, order and all state values. The harness only substitutes explicitly recognized current transaction timestamps, the transaction block written by Prospect, and the new Move arrival deadline relative to the transaction timestamp. It does not normalize generated IDs, owners, counters, existing timestamps, queue payloads or inactive padding. Unexpected public log emitters fail verification.

Find uses the same historical block on both deployments, with Gear and location/biome checks enabled. Its original256-block expiry remains enforced; candidate Find must run before that block expires. Initialization uses proof-valid rim coordinates `(128,0)` and radius129, with proof checks enabled. Ordinary Find/Reveal use `(1,0)` and the pinned original location hash. Common typed configuration is saved once and reused exactly.

`compare-abi.mjs` compares all17 original native artifacts and recognizes additive methods only with `--allow-additional`. It removes only the injected private-context parameter when counting caller arguments. `compare-fees.mjs` emits paired exact Fee Juice amounts only for mined, verified, state-equivalent rows.

Every new simulation also retains its full transaction bytes and public output under `results/traces`. `BENCH_TRACE_ONLY=1` prepares fixtures and simulates gameplay without mining it or adding fee rows. The optional SDK diagnostic instrumentation uses Aztec's existing C++/TypeScript comparison simulator, which checks both gas and transaction effects, and collects compact executed per-call, per-opcode and per-PC costs. `summarize-avm-profile.mjs` reconciles exclusive call costs to the complete public gas without double counting children. These traces diagnose public execution; they are not proving-time measurements or substitutes for full mined fees. Profiling must be disabled for ordinary timings; the owned-PID-checked toggle closes its temporary loopback inspector and does not restart the chain.

Full-action fixtures cover Core initialize/reveal/upgrade/withdraw/refresh; Admin safe ownership transfer; Move; artifact Prospect/Find/deposit/withdraw/give all five spaceships/activate/deactivate. Public fixtures cover Admin pause/unpause/radius/ownership/score additions and deductions/creation/initialization, plus Vault creation/update/admin artifact/admin spaceship grants. Additional Move/Refresh cases reuse the previously executed original fixtures rather than implementing a parallel game transition in JavaScript.

## Real native proof timing on the fresh v2 deployment

The old ephemeral chain was restarted after v1 evidence was archived. Run the following only when both fresh variants and their ordinary fixtures are complete and the proof-timing CPU window has been released:

```sh
AZTEC_NODE_URL=http://127.0.0.1:8097 \
PROFILE_BASELINE_VARIANT=baseline-v2 \
PROFILE_CANDIDATE_VARIANT=candidate-v2 \
PROFILE_BASELINE_ARTIFACTS=/tmp/df-fee-tools/artifacts/baseline \
PROFILE_CANDIDATE_ARTIFACTS=/tmp/df-api-compatible-v2-native \
PROFILE_OUTPUT=docs/api-compatibility/native-proof-profile-v2.json \
PROFILE_ROUNDS=2 \
NODE_BACKEND=js LOG_LEVEL=error \
node --import ./node_modules/tsx/dist/loader.mjs experiments/api-compatible-benchmark/profile.mjs
```

This reads `.state/baseline-v2-<method>-ordinary.json` and `.state/candidate-v2-<method>-ordinary.json`, with deployment addresses taken from each actual fixture. The default includes all14 original private methods; `PROFILE_METHODS=move,refresh_planet` selects a smaller explicit subset. `PROFILE_STATE_DIRECTORY` can select a different fixture directory. Every artifact's SHA256 and actual deployed class are checked. Missing/stale contracts fail before any proof is generated. The profiler creates a unique PXE directory and never uses the fee runner's mutable wallet.

Each method receives one excluded warmup per variant and two measured paired rounds, alternating the order. The pinned SDK5.2 native prover uses four threads and generates and verifies a real whole-transaction private proof, including the account and private kernels. No transaction is sent; public execution, fees, inclusion time and browser/mobile performance are outside this measurement. A fresh shared chain timestamp is used per pair, while all other fixture witness fields remain unchanged. Partial samples and their proof/artifact hashes are saved after every completion. Existing output files are never overwritten; use a new `PROFILE_OUTPUT` for another run. Higher candidate medians are reported explicitly rather than treated as a pass.
