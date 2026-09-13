# V5 fee run — prepared, not executed

Run only after the coordinator freezes the genuine20-contract V5 build and releases the local network. Transaction proofs, proof profiles and AVM diagnostics remain disabled. The candidate label is `candidate-v5`; all V4 receipts, fixtures, coverage and native artifacts remain separate.

```sh
node experiments/api-compatible-benchmark/run-plan-v5.mjs --execute all > /tmp/df-api-compatible-candidate-v5-full.log 2>&1
```

The runner defaults to `/tmp/df-api-compatible-v5-native`, original `/tmp/df-fee-tools/artifacts/baseline`, baseline `baseline-v2`, RPC8097 and a new wallet directory `/tmp/df-api-compatible-wallet52-v5`. The existing node and Anvil must remain on the preserved chain. It never restarts either service. `API_BENCH_CANDIDATE` accepts a fresh `candidate-v5-*` label, `API_BENCH_ARTIFACTS` changes the native directory, `API_BENCH_WALLET_DIRECTORY` changes the isolated wallet directory, and `API_BENCH_FIND_PAIR` accepts `v5_*` for a newly matched Find replay. Overrides propagate to every child and output label. Inherited `BENCH_*` controls are cleared, then exact selections are applied.

Before opening a wallet, the runner verifies the successful20-artifact manifest, all actual file hashes, the pinned original manifest, cached row identity and fee arithmetic, and absence of unreconciled submissions. A read-only preflight then rechecks44 original canonical receipts,17 actual original classes and the original Arrival counter derived from all cached Moves (currently14). It deliberately does not require historical post-action roots to remain current: later original fixture seeding and actions legitimately replaced some of them. Exact historical comparison uses the preserved mined receipt and its recorded state verification.

Only Find needs a new original measurement. The old Find seed is outside the original256-block window, and its generated artifact ID depends on the historical header hash. The sequence creates a fresh `v5` anchor after deployment/configuration and records the original and candidate actions as `find_v5`, without changing old Find rows or normalizing IDs. Every other original action is reused after canonical verification, without opening the old baseline wallet or resending that action.

The exact order is:

1. Deploy and bind20 candidate contracts using the original address/permission APIs; configure the same19 typed settings. Setup uses existing seed label `v2`, so it cannot create the new `v5` anchor early.
2. Candidate ordinary initialization, then new original Find and candidate Find, then candidate ordinary Refresh and Move. Find seeds Player, so initialization must precede it. These four comparisons must preserve all state/events/roots and have no Fee Juice increase before the rest of the run proceeds.
3. Candidate Reveal, Upgrade, WithdrawSilver, SafeSetOwner, Prospect, DepositArtifact, WithdrawArtifact, GiveSpaceships, ActivateArtifact and DeactivateArtifact, following the original runner's method order.
4. The12 original public Admin/Vault methods; then Refresh20 and Move20.
5. Initialization with unused nonzero padding and initialization of an existing unclaimed planet, using the original distinct actors1/2; then Refresh with unused nonzero padding and count1 Refresh.
6. Move queue1, queue5, artifact carry, artifact arrival, Photoid, wormhole, conquest, artifact-ID alias, future queue and nonzero padding; then artifact-arrival Refresh.
7. Sponsored ordinary Refresh and Move using SponsoredFPC.

Move allocations must remain a strict prefix of this sequence:

| Case | New arrival ID |
|---|---:|
| Ordinary account Move | 2 |
| Move20 | 3 |
| Queue1, queue5 | 4,5 |
| Artifact carry, artifact arrival | 6,7 |
| Photoid, wormhole, conquest | 8,9,10 |
| Artifact alias, future queue, nonzero padding | 11,12,13 |
| Sponsored ordinary Move | 14 |

The fresh candidate starts at counter1. Before each new Move its getter must equal the greatest allocated ID in that candidate's verified receipts, and its next ID must match the cached original row. The original counter14 is never copied into the fresh candidate.

Every candidate fixture is compared against the exact matched original input, actor, deployment and complete ordered seed list before fixture writes. Only the top-level action timestamp is refreshed; historical state timestamps, owners, IDs and inactive fields remain exact. The original fixture's SHA256 is saved in both candidate input and receipt metadata. Public methods also retain a top-level timestamp used solely by the receipt inspector; it is excluded from input equality because it is not part of their original ABI. All44 reusable original fixtures were reconstructed and compared successfully offline.

Success creates45 distinct comparisons:28 primary,4 edges,11 retained branches and2 sponsored. Actual mined fees reconcile to complete billed gas. Comparisons use the same observed Fee Juice price schedule; they are not predicted future network prices. Later fee increases are recorded while the remaining matrix completes; any state/event/root mismatch stops immediately. No proof latency or UX conclusion follows from these proof-disabled timings.

Use `--execute first4` to stop at the early gate. `--execute all` resumes verified rows without resending them. Never remove a failed row or submitted transaction to bypass a guard: reconcile its exact receipt first. An expired partially completed Find pair needs a new `API_BENCH_FIND_PAIR=v5_retry` label and a fresh original/candidate pair, preserving earlier rows.

Offline checks, which open no node or wallet:

```sh
node experiments/api-compatible-benchmark/run-plan-v5.mjs
NODE_BACKEND=js node --import ./node_modules/tsx/dist/loader.mjs experiments/api-compatible-benchmark/validate-run-plan-v5.mjs
node --test experiments/api-compatible-benchmark/fixture-replay.test.mjs
```

The report files are `results/coverage-candidate-v5.json`, the append-only detailed `results/transactions.json`, separate `candidate-v5-*` fixtures/submitted bytes, and `results/candidate-v5-build-provenance.json`. The plan contains no proof-preparation or proof-execution phase.

## Permitted time normalization and pre-send comparison

Historical and new action timestamps differ. A timestamp field is normalized only when it exactly equals its own action's current time: `last_updated`, `created_at`, `init_timestamp`, `last_reveal_timestamp`, `minted_at_timestamp`, `last_activated`, `last_deactivated`, and `departure_time`. Every historical timestamp and unused value remains exact. New Arrival time is compared as the exact travel duration from the action time. Prospect's current block and event block stamps are checked against each transaction's own block. Every other ordered event field, tag, ID, owner, quantity, count and padding value must match.

**Raw roots are not asserted byte-identical across timestamp rebasing.** Each deployment's actual stored root must independently equal the hash of every exact raw field in its own emitted state, including its own timestamps. The comparison between implementations uses the explicitly normalized state fields.

The44 cached fixtures were audited for time-sensitive branches. All growing population inputs are beyond a conservative final cap time of100002, even allowing due arrivals at2; historical actions are after1789175290. Future arrivals remain at4102444800. Photoid is already activated at1 with delay0; Reveal cooldown is0, and artifact activation/deactivation readiness uses unchanged old input records. Mint cutoff is4102444800. The actual future execution still must be verified: these fixture facts are not a substitute for running the contract.

Before every candidate broadcast, the already-required whole-transaction simulation now exposes its prospective ordered public state events. Those complete effects must match the historical pair under the same explicit normalization. A mismatch preserves the fixture and simulation files and stops before sending; it requires investigation and, where time changed the intended branch, a fresh matched baseline case. It does not permit removing fields or broadening normalization. The new preview decoder was checked offline against all45 frozen V4 whole-transaction simulations and their verified mined outputs. See `docs/api-compatibility/time-normalization-audit-v5.json`.
