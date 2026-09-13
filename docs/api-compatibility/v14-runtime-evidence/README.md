# V14 targeted compatibility checks

All **381 targeted checks passed** on the exact classes used for the 58 V14 fee comparisons. Every wallet had proofs disabled; profiling remained off.

| Suite | Passed checks |
|---|---:|
| read-only | 162 |
| trust | 183 |
| batch-caller | 36 |

These are assertion counts, not transaction counts. The 183 trust checks comprise 179 diagnostic simulations and four compiled ABI-absence assertions. The 36 Give checks comprise 12 private-entry rejection simulations, 12 direct-caller rejection simulations and 12 rollback comparisons. No gameplay transaction was sent by these suites.

The Give setup used 13 fresh instances and 46 successful setup transactions. Every final transaction was journaled before broadcast, including its exact bytes and hash; deployment intent also retained the address, salt and class. Each receipt matched the journaled hash. No uncertain send or automatic retry occurred.

The reader registers only the nine facade artifacts, checking the original utility/public readers without Backend artifact registration. Trust tests the actual audited System/Worker routes and spoofed callers. Custom Arrival, Artifact and Location batch verifiers check zero-count Give calls, original System caller identity, false/sentinel behavior, inactive data and unchanged state.

The [75 V14 touch-specific checks](../v14-touch-runtime/README.md) and [58 fee comparisons](../v14-fee-evidence/README.md) are separate completed evidence. The earlier [1,429 V12 checks](../v12-runtime-evidence/README.md) remain historical V12 evidence; the unchanged 792-check storage suite was not repeated or relabeled.

[Exact runtime summary](runtime-summary.json), [completion journal](runtime-completion-v14-targeted.json), [reviewed plan](runtime-plan-v14.json).
Full immutable source/results/transaction-journal snapshot: `/tmp/df-v14-targeted-runtime-frozen` (113 hashed files).

This report makes no proof-speed, UI-latency or live-network fee claim.
