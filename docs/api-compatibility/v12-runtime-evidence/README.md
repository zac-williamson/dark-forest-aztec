# V12 runtime compatibility checks

All **1,429 checks passed** against the exact classes used for the 58 Fee Juice comparisons. Every wallet had proofs disabled; profiling remained off.

| Suite | Passed checks |
|---|---:|
| read-only | 162 |
| trust | 183 |
| run | 792 |
| config-caller | 34 |
| location-caller | 20 |
| batch-caller | 238 |

These are check counts, not transaction counts. The 183 trust checks comprise 179 simulations and 4 compiled ABI-absence assertions. The 486 independent physical root and permission observations are included in the 792 storage checks.

The fresh reader registers only the nine facade artifacts. Storage tests compare exact original event fields, typed state hashes and independently read physical roots and permissions across overwrites and grant/admin transitions. Caller-sensitive Config, Location and batch verifiers preserve original callers, counts, inactive inputs, ordering and rejection behavior. Setup uses isolated namespaces/clones; the fee namespaces remain unchanged.

One initial reader process stalled before its first assertion and sent no transactions. Its logs and stopped fresh PXE were preserved. The identical frozen reader passed on a fresh bounded retry with startup logging; subsequent suites completed serially. No node restart, state reset, production change or duplicated send was used.

[Exact runtime summary](runtime-summary.json), [completion journal](runtime-completion-v12.json), [reviewed plan](runtime-plan-v12.json).
Full immutable source/results/recovery snapshot: `/tmp/df-v12-runtime-suites-frozen` (111 hashed files).

The separate [fee report](../v12-fee-evidence/README.md) records 57 cheaper cases and one small public artifact-update regression across 58 original comparisons. This runtime report does not claim proof speed, UI latency or live-network fee quotes.
