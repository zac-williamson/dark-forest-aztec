# Frozen V4 benchmark sequence

**Proof-disabled fees authorized:** the user clarified that complete fee information is the priority. Continue the45-pair fee/runtime matrix with `proverEnabled:false` after final genuine artifacts and coordinator GO. Read [BATTERY-MODE.md](BATTERY-MODE.md) for the bounded build/test policy. All real transaction proving, native/browser profiling and proved-and-mined commands below remain deferred. No simulation-only substitute is an accepted final artifact.

This plan is ready but has not been executed. Wait for the coordinator's explicit GO and a complete, frozen `/tmp/df-api-compatible-v4-native/build-provenance.json`. The runner verifies all20 artifact SHA256 values against that successful manifest before opening a wallet.

Run from `/Users/zac/Documents/ChatGPT/Dark Forest/dark-forest-aztec`. Keep the existing network running: Aztec RPC8097/admin8897 PID26340; Anvil8551 PID8919. Do not restart `start --local-network`: it redeploys L1 contracts and resets the chain. Only the benchmark runner may use `/tmp/df-api-compatible-wallet52-v2` during its mutation window.

The chain has been recovered and verified at the exact recorded height278. The original node encountered a local LMDB failure; its L1 pending/proven tips both remained278. The replacement node resumed a preserved copy of the same databases, with the same L1 addresses and genesis and no deployment/account setup. All12 saved current-chain receipts,17 baseline classes,11 baseline state roots and Arrivalcounter2 were rechecked live. See [RECOVERY-v4.md](RECOVERY-v4.md). A fresh chain would require new variant labels, deployments and paired receipts. Old seed101 expires at block357. The V4 sequence creates a fresh `v4` seed after final deployment and configuration, then uses it identically for original and candidate Find under `find_v4`. It never changes `ordinary`, V3 data or an existing seed file.

## Launch after GO

The full command runs the first four, checks their decision gate, then continues automatically through the45-pair matrix:

```sh
node experiments/api-compatible-benchmark/run-plan-v4.mjs --execute all > /tmp/df-api-compatible-candidate-v4-full.log 2>&1
```

To release only the early four first:

```sh
node experiments/api-compatible-benchmark/run-plan-v4.mjs --execute first4 > /tmp/df-api-compatible-candidate-v4-first.log 2>&1
```

After that gate passes, the `--execute all` command resumes from verified rows and finishes the matrix. Setup markers and row identity prevent repeating completed deployments or actions. If an action was mined but its verification failed, stop and inspect that saved receipt; do not delete its row or resend it.

Resume checks run before fixture mutation. They reject duplicate identities, failed/unverified rows, mismatched deployment files, changed artifact snapshots and any saved submitted transaction without a reconciled row. Stored mined and reference-price fees are recomputed exactly from full billed gas. Candidate artifact hashes are frozen before the first deployment; newly measured rows also retain all artifact hashes. A successful row is never reused merely because its method/case name matches.

The top-level runner is offline unless `--execute` is passed. Its child commands explicitly set:

```text
BENCH_WALLET_DIRECTORY=/tmp/df-api-compatible-wallet52-v2
BENCH_BASELINE_VARIANT=baseline-v2
BENCH_FIND_PAIR=v4
AZTEC_NODE_URL=http://127.0.0.1:8097
NODE_BACKEND=js
LOG_LEVEL=error
```

It removes inherited `BENCH_*` variables before each child, then applies that child's exact method, case and payment settings. The default45-pair run also leaves public AVM diagnostic profiling off to avoid extra CPU work during the final build and battery testing. Child processes use the repository's tsx loader and the harness's pinned SDK5.2 dependency link. There is no shell command interpolation.

## Order and gates

1. Deploy/bind20 final candidate contracts, apply original address APIs and permissions, then configure the identical19 typed settings. These setup commands use existing seed label `v2`, so they cannot prematurely create `v4`'s fresh anchor.
2. Run candidate initialization first. **Find seeds Player, so candidate Find cannot precede fresh initialization.** Initialization, Refresh and Move use `BENCH_PROFILE_NODE_PID=26340`: diagnostics wrap only the first simulation and are disabled before the normal mined send.
3. Run original Find then candidate Find with `BENCH_CASES=find_v4` and shared `BENCH_FIND_PAIR=v4`. The original256-block rule remains enforced. Bookkeeping case labels were checked offline against the exact original ABI; they change no gameplay input, seed or configuration value for a given anchor.
4. Run candidate ordinary Refresh and Move. Match all four candidate receipts to verified current-chain baseline-v2 rows, including fresh Find. Every candidate must preserve exact original ordered events, every state field and resulting roots; every billed fee must reconcile to its mined receipt. The early gate also requires **no complete-transaction fee increase** in any of these four. Failure stops before the rest of the matrix and retains evidence for another optimization pass.
5. Run the remaining ten ordinary original private actions, then their ten candidate matches. Together with the first four this supplies saved current-chain fixtures for all14 original private APIs. Run the twelve public Admin/Vault actions on original then candidate. Run Refresh20 and Move20 on original then candidate. **Move20 must be the second allocated Move on each deployment**, before all other additional Move cases, preserving exact arrival IDs.
6. Run two initialization edges on original then candidate: fresh zero Planet with nonzero unused PA/PE tails, and existing unowned Planet through the general branch. The fixtures use distinct funded actors1/2 and check preserved unused component roots. Run empty Refresh with nonzero inactive PA/PE and ignored carried-artifact location witnesses, then count1 general Refresh. The ignored location's stored value intentionally differs from the unused witness and must remain unchanged.
7. Preserve the earlier ten additional Move cases: queue1, queue5, artifact carry, artifact arrival, Photoid, wormhole, conquest, artifact alias, future queue and nonzero padding. Both deployments use that identical order. Add artifact-arrival Refresh.
8. Run original then candidate ordinary Refresh and Move using SponsoredFPC. These two actual complete receipts test the sponsored payment flow. All other rows use the account payment flow. Sponsored initialization is deliberately not duplicated on an already initialized player.

This is28 primary pairs, four edge pairs, eleven retained branch pairs and two sponsored pairs: **45 distinct comparisons**. The early four stop on a fee increase. Subsequent fee increases are recorded and reported while the remaining matrix completes, so the full set can reveal systemic regressions; any state/effect failure stops immediately.

Individual phase execution also verifies all prerequisite phases. Saved Move cases must form a prefix of the planned allocation order. Immediately before any new measured Move, the original counter getter must equal the last allocation in saved receipts, and the candidate's next ID must equal its matched original ID. This catches a hidden or manually submitted Move before another fixture is seeded. Initialization edge actors are explicitly compared across saved fixtures and receipts, independently of the setup administrator.

Success writes `results/coverage-candidate-v4.json`. It names every required method/case/payment pair and reports exact baseline, candidate and saved fees. No workload average is implied. All detailed receipts remain append-only in `results/transactions.json`; per-action fixtures and submitted transactions remain under `.state` and `results/traces`. Proof generation is disabled in these fee runs. No UX conclusion follows from simulation timing.

## Before the14-method native proof profile

This section is deferred under the current user instruction. Neither the native profile nor its extra preparation phase is part of the authorized45-pair fee run. Preserve it only as a future procedure if transaction proving is later reauthorized.

Finish all other chain-writing regression tests, including the caller-sensitive Config and storage suites. If they advance blocks, the earlier Find anchor may expire. Create a separate fresh matched fee/state pair immediately before the isolated proof window:

```sh
node experiments/api-compatible-benchmark/run-plan-v4.mjs --execute profileFixtures > /tmp/df-api-compatible-candidate-v4-profile-fixtures.log 2>&1
```

This uses `BENCH_FIND_PAIR=v4_profile` and `BENCH_CASES=find_v4_profile`; it does not overwrite earlier Find evidence. Keep the chain idle afterward. Select these fresh Find fixtures explicitly while retaining ordinary fixtures for the other13 APIs:

```sh
AZTEC_NODE_URL=http://127.0.0.1:8097 \
PROFILE_BASELINE_VARIANT=baseline-v2 \
PROFILE_CANDIDATE_VARIANT=candidate-v4 \
PROFILE_BASELINE_ARTIFACTS=/tmp/df-fee-tools/artifacts/baseline \
PROFILE_CANDIDATE_ARTIFACTS=/tmp/df-api-compatible-v4-native \
PROFILE_CASES_JSON='{"find_artifact":"find_v4_profile"}' \
PROFILE_OUTPUT=docs/api-compatibility/native-proof-profile-v4.json \
PROFILE_ROUNDS=2 NODE_BACKEND=js LOG_LEVEL=error \
node --import ./node_modules/tsx/dist/loader.mjs experiments/api-compatible-benchmark/profile.mjs
```

The proof command requires its own coordinator release; it is **not** part of `--execute all`. It validates every fixture and artifact against the actual deployed class, requires identical paired actors and Find anchors, and rejects an expired Find witness before opening the prover. It records the selected case for every sample, creates a separate PXE directory, generates/verifies real whole private transaction proofs and never sends gameplay. Actual proved-and-mined Move and browser proving remain separate coordinated checks.

To inspect the plan without any node or wallet access:

```sh
node experiments/api-compatible-benchmark/run-plan-v4.mjs
NODE_BACKEND=js node --import ./node_modules/tsx/dist/loader.mjs experiments/api-compatible-benchmark/validate-run-plan-v4.mjs
```
