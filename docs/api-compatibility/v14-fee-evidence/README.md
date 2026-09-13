# V14 complete transaction fees

All 58 paired cases passed their original state and event checks. **58 cost less than the original; 0 cost more; 0 are identical.**

These are complete mined local mock-network transactions with proofs disabled, normalized to one observed price schedule. Each actual local receipt fee was separately reconciled. They are not live-network receipt quotes, proof-speed measurements or setup-inclusive workload estimates.

Creation still costs **54 more L2 gas than V12 (+0.000120373614738288 Fee Juice)**. Across 52 non-Find cases, V14 is cheaper than V12 in 1, higher in 27 and identical in 24. All differences remain visible in the summary; this is not a Pareto improvement.

The six Find comparisons use fresh common archive entropy within each original/V14 pair. Their comparison with earlier V12 fees uses corresponding fixture shapes with different entropy and actual found artifact IDs; those inputs are not described as identical.

The genuine 20-contract build retains all 447 compiled original methods. Inputs and original acceptance remain exact apart from explicit action-time rebasing; every deployment's real state hashes were verified independently. The two completed public fee cases were reused unchanged, and 56 further candidate transactions completed without repeated sends.

The [75 touch-specific runtime checks](../v14-touch-runtime/README.md) passed separately. The final targeted reader/trust/Give suites are pending in this fee snapshot. Earlier V12 runtime counts are not relabeled as V14 tests.

| Action / case | Original FJ | V14 FJ | Saved |
|---|---:|---:|---:|
| initialize_player / ordinary (account) | 2.292480 | 1.895053 | 17.34% |
| find_artifact / find_v14 (account) | 5.650908 | 3.628879 | 35.78% |
| refresh_planet / ordinary (account) | 4.165899 | 2.019898 | 51.51% |
| move / ordinary (account) | 8.432787 | 3.308645 | 60.76% |
| reveal_location / ordinary (account) | 2.188669 | 2.053048 | 6.20% |
| upgrade_planet / ordinary (account) | 4.340982 | 3.208300 | 26.09% |
| withdraw_silver / ordinary (account) | 4.472542 | 3.305165 | 26.10% |
| safe_set_owner / ordinary (account) | 1.810493 | 1.739860 | 3.90% |
| prospect_planet / ordinary (account) | 4.907929 | 2.841314 | 42.11% |
| deposit_artifact / ordinary (account) | 4.635532 | 3.331766 | 28.13% |
| withdraw_artifact / ordinary (account) | 4.635713 | 3.332127 | 28.12% |
| give_spaceships / ordinary (account) | 5.919303 | 3.737612 | 36.86% |
| activate_artifact / ordinary (account) | 4.792319 | 3.318678 | 30.75% |
| deactivate_artifact / ordinary (account) | 4.669243 | 3.193557 | 31.60% |
| pause / ordinary (account) | 1.525368 | 1.489904 | 2.32% |
| unpause / ordinary (account) | 1.525548 | 1.490085 | 2.32% |
| admin_set_world_radius / ordinary (account) | 1.528130 | 1.492593 | 2.33% |
| set_owner / ordinary (account) | 1.815435 | 1.691035 | 6.85% |
| add_score / ordinary (account) | 1.545925 | 1.506355 | 2.56% |
| deduct_score / ordinary (account) | 1.545945 | 1.506375 | 2.56% |
| create_planet / ordinary (account) | 2.251609 | 2.246225 | 0.24% |
| admin_initialize_planet / ordinary (account) | 4.257722 | 4.252017 | 0.13% |
| create_artifact / ordinary (account) | 1.658753 | 1.657415 | 0.08% |
| update_artifact / ordinary (account) | 1.776739 | 1.658269 | 6.67% |
| admin_give_artifact / ordinary (account) | 2.174224 | 2.149360 | 1.14% |
| admin_give_spaceship / ordinary (account) | 2.567201 | 2.535804 | 1.22% |
| move / 20 (account) | 8.645715 | 3.855315 | 55.41% |
| refresh_planet / 20 (account) | 4.272363 | 3.225473 | 24.50% |
| initialize_player / init_unused_padding (account) | 2.292480 | 1.895053 | 17.34% |
| initialize_player / init_existing_planet (account) | 4.515448 | 3.350212 | 25.81% |
| refresh_planet / refresh_unused_padding (account) | 4.165899 | 2.019898 | 51.51% |
| refresh_planet / 1 (account) | 4.171222 | 3.076558 | 26.24% |
| move / 1 (account) | 8.443433 | 3.550368 | 57.95% |
| move / 5 (account) | 8.486019 | 3.614568 | 57.41% |
| move / artifact_move (account) | 8.560448 | 3.523253 | 58.84% |
| move / artifact_arrival (account) | 8.535089 | 3.699569 | 56.65% |
| move / photoid (account) | 8.745172 | 3.605716 | 58.77% |
| move / wormhole (account) | 8.617659 | 3.470345 | 59.73% |
| move / conquest (account) | 8.443433 | 3.550368 | 57.95% |
| move / artifact_alias (account) | 8.872833 | 3.815523 | 57.00% |
| move / future_queue (account) | 8.635068 | 3.839265 | 55.54% |
| move / nonzero_padding (account) | 8.432787 | 3.308645 | 60.76% |
| refresh_planet / artifact_arrival (account) | 4.262878 | 3.167866 | 25.69% |
| move / ordinary (sponsored) | 8.432787 | 3.308645 | 60.76% |
| refresh_planet / ordinary (sponsored) | 4.165899 | 2.019898 | 51.51% |
| refresh_planet / carried_arrivals_5 (account) | 4.650793 | 3.564448 | 23.36% |
| move / carried_arrivals_5 (account) | 9.402575 | 4.803663 | 48.91% |
| refresh_planet / carried_arrivals_20 (account) | 6.105475 | 5.051630 | 17.26% |
| move / carried_arrivals_20 (account) | 12.311938 | 8.491442 | 31.03% |
| find_artifact / carried_find_2 (account) | 5.844866 | 4.014331 | 31.32% |
| find_artifact / carried_find_5 (account) | 6.135802 | 4.353136 | 29.05% |
| deposit_artifact / carried_deposit_5 (account) | 5.120426 | 4.055247 | 20.80% |
| find_artifact / boundary_find_1_due_1_future (account) | 5.763856 | 3.833425 | 33.49% |
| find_artifact / boundary_find_12_due_1_future (account) | 6.830623 | 5.462450 | 20.03% |
| find_artifact / boundary_find_13_due_1_future (account) | 6.927602 | 5.684804 | 17.94% |
| deposit_artifact / boundary_deposit_4_due_0_future (account) | 5.023447 | 3.922116 | 21.92% |
| deposit_artifact / boundary_deposit_4_due_11_future (account) | 6.090214 | 5.485229 | 9.93% |
| deposit_artifact / boundary_deposit_4_due_12_future (account) | 6.187193 | 5.693540 | 7.98% |

Exact integer accounting, all 58 paired receipts and checked states: [fee summary](fee-summary.json), [paired transactions](paired-transactions.json).

Full immutable runtime snapshot: `/tmp/df-v14-fees-frozen` (846 hashed files). [Input manifest](execution-inputs-manifest.json), [native admission](native-build-provenance.json), [runtime log](runtime.log).
