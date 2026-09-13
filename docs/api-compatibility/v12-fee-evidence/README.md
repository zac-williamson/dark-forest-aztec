# V12 complete transaction fees

All 58 paired cases passed their original state/event checks. **57 cost less than the original; one costs slightly more.** Updating an artifact rises from 1.776739074088281272 to 1.777815749197884848 Fee Juice: +0.001076675109603576 (+0.060598%).

These are complete mined local mock-network transactions with proofs disabled, normalized to one observed price schedule. Each actual local receipt fee was separately reconciled. They are not live-network receipt quotes, proof-speed measurements or setup-inclusive workload estimates.

The full 20 genuinely built contracts retain 447 compiled original methods. Inputs and original acceptance remain exact apart from explicit transaction-time rebasing; every deployment’s real state hashes were verified independently. Six Find pairs use fresh common archive entropy. No found artifact IDs were normalized.

Compared with 48 same-case V8 results (fresh Find and new cases excluded), V12 is cheaper in 27, higher in 13 and identical in 8. This is a tradeoff, not a Pareto improvement. Full exact V8 differences are in fee-summary.json.

The separate API/storage runtime suites are pending in this fee-only snapshot. Their historical pass counts are not V12 results.

| Action / case | Original FJ | V12 FJ | Saved |
|---|---:|---:|---:|
| initialize_player / ordinary (account) | 2.292480 | 1.895053 | 17.34% |
| find_artifact / find_v12 (account) | 5.650908 | 3.628518 | 35.79% |
| refresh_planet / ordinary (account) | 4.165899 | 2.019898 | 51.51% |
| move / ordinary (account) | 8.432787 | 3.308645 | 60.76% |
| reveal_location / ordinary (account) | 2.188669 | 2.053048 | 6.20% |
| upgrade_planet / ordinary (account) | 4.340982 | 3.208120 | 26.10% |
| withdraw_silver / ordinary (account) | 4.472542 | 3.304985 | 26.11% |
| safe_set_owner / ordinary (account) | 1.810493 | 1.739860 | 3.90% |
| prospect_planet / ordinary (account) | 4.907929 | 2.841314 | 42.11% |
| deposit_artifact / ordinary (account) | 4.635532 | 3.331284 | 28.14% |
| withdraw_artifact / ordinary (account) | 4.635713 | 3.331645 | 28.13% |
| give_spaceships / ordinary (account) | 5.919303 | 3.737130 | 36.87% |
| activate_artifact / ordinary (account) | 4.792319 | 3.318317 | 30.76% |
| deactivate_artifact / ordinary (account) | 4.669243 | 3.193195 | 31.61% |
| pause / ordinary (account) | 1.525368 | 1.489904 | 2.32% |
| unpause / ordinary (account) | 1.525548 | 1.490085 | 2.32% |
| admin_set_world_radius / ordinary (account) | 1.528130 | 1.492593 | 2.33% |
| set_owner / ordinary (account) | 1.815435 | 1.691035 | 6.85% |
| add_score / ordinary (account) | 1.545925 | 1.506355 | 2.56% |
| deduct_score / ordinary (account) | 1.545945 | 1.506375 | 2.56% |
| create_planet / ordinary (account) | 2.251609 | 2.246225 | 0.24% |
| admin_initialize_planet / ordinary (account) | 4.257722 | 4.252017 | 0.13% |
| create_artifact / ordinary (account) | 1.658753 | 1.657295 | 0.09% |
| update_artifact / ordinary (account) | 1.776739 | 1.777816 | -0.06% |
| admin_give_artifact / ordinary (account) | 2.174224 | 2.149240 | 1.15% |
| admin_give_spaceship / ordinary (account) | 2.567201 | 2.535684 | 1.23% |
| move / 20 (account) | 8.645715 | 3.855315 | 55.41% |
| refresh_planet / 20 (account) | 4.272363 | 3.225293 | 24.51% |
| initialize_player / init_unused_padding (account) | 2.292480 | 1.895053 | 17.34% |
| initialize_player / init_existing_planet (account) | 4.515448 | 3.350031 | 25.81% |
| refresh_planet / refresh_unused_padding (account) | 4.165899 | 2.019898 | 51.51% |
| refresh_planet / 1 (account) | 4.171222 | 3.076377 | 26.25% |
| move / 1 (account) | 8.443433 | 3.550368 | 57.95% |
| move / 5 (account) | 8.486019 | 3.614568 | 57.41% |
| move / artifact_move (account) | 8.560448 | 3.523073 | 58.84% |
| move / artifact_arrival (account) | 8.535089 | 3.699389 | 56.66% |
| move / photoid (account) | 8.745172 | 3.605355 | 58.77% |
| move / wormhole (account) | 8.617659 | 3.470164 | 59.73% |
| move / conquest (account) | 8.443433 | 3.550368 | 57.95% |
| move / artifact_alias (account) | 8.872833 | 3.814981 | 57.00% |
| move / future_queue (account) | 8.635068 | 3.839265 | 55.54% |
| move / nonzero_padding (account) | 8.432787 | 3.308645 | 60.76% |
| refresh_planet / artifact_arrival (account) | 4.262878 | 3.167685 | 25.69% |
| move / ordinary (sponsored) | 8.432787 | 3.308645 | 60.76% |
| refresh_planet / ordinary (sponsored) | 4.165899 | 2.019898 | 51.51% |
| refresh_planet / carried_arrivals_5 (account) | 4.650793 | 3.564267 | 23.36% |
| move / carried_arrivals_5 (account) | 9.402575 | 4.803302 | 48.92% |
| refresh_planet / carried_arrivals_20 (account) | 6.105475 | 5.051450 | 17.26% |
| move / carried_arrivals_20 (account) | 12.311938 | 8.491081 | 31.03% |
| find_artifact / carried_find_2 (account) | 5.844866 | 4.013789 | 31.33% |
| find_artifact / carried_find_5 (account) | 6.135802 | 4.352594 | 29.06% |
| deposit_artifact / carried_deposit_5 (account) | 5.120426 | 4.054585 | 20.82% |
| find_artifact / boundary_find_1_due_1_future (account) | 5.763856 | 3.832883 | 33.50% |
| find_artifact / boundary_find_12_due_1_future (account) | 6.830623 | 5.461908 | 20.04% |
| find_artifact / boundary_find_13_due_1_future (account) | 6.927602 | 5.684263 | 17.95% |
| deposit_artifact / boundary_deposit_4_due_0_future (account) | 5.023447 | 3.921454 | 21.94% |
| deposit_artifact / boundary_deposit_4_due_11_future (account) | 6.090214 | 5.484567 | 9.94% |
| deposit_artifact / boundary_deposit_4_due_12_future (account) | 6.187193 | 5.692878 | 7.99% |

Exact integer accounting, 58 paired receipts and checked states: [fee summary](fee-summary.json), [paired transactions](paired-transactions.json).

Full immutable runtime snapshot: `/tmp/df-api-compatible-v12-fees-frozen` (475 hashed files). [Input manifest](execution-inputs-manifest.json), [native admission](native-build-provenance.json), [runtime log](runtime.log).

The first launch failed before RPC/wallet startup because its copied loader path was unavailable. The isolated launcher-path fix was re-frozen and reviewed; the subsequent full run completed without ambiguous or repeated sends. The original failed launch remains archived.
