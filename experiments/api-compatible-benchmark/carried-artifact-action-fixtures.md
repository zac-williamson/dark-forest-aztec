# New carried-artifact action fixtures

These **new cases are outside the frozen 49-case matrix**. They are offline fixture builders, not accepted gameplay or fee results. The fee harness must first execute the original full private entrypoint successfully with proving disabled, save its exact inputs/seeds/outcomes, then compare V8 and each admitted decoder candidate using the same case, actor, configuration and Find entropy. The helper does not run a wallet/node, build a proof, alter a contract or replace the original transition with a model.

```js
const fixture = buildCarriedArtifactActionCase({runtime, method, caseId, base, input});
```

`input` is the original ABI zero template and is optional if runtime supplies `rawArtifacts` or `artifacts`. The returned shape is `{input, seeds, unchangedSeeds, configUpdates, extra}`, matching the existing action runner. Find requires `base.seedBlock = {number, hash}`. Create one **fresh common historical block anchor** for the new pair/triple, then retain it unchanged through original, V8 and chunk candidates; the usual expiry/setup-block check remains required. Historical Find entropy from an old measured row must not be replayed as if current. The private function itself derives the discovered ID from its real header; no ID normalization or output substitution is supplied.

| Case | Queue/carried | Due/future | Initial inventory | Inventory capacity after action | V8 plan words | V8 commit |
|---|---:|---:|---:|---:|---:|---|
| `carried_find_2` | 2/2 | 2/0 | 1 owned Gear | 4 | 130 | full397 |
| `carried_find_5` | 5/5 | 5/0 | 1 owned Gear | 7 | 142 | full397 |
| `carried_deposit_5` | 5/5 | 4/1 | 0 | 5 | 131 | full397 |

Five distinct **all-due** carried artifacts are invalid for Deposit: the original private action refreshes first, then requires inventory count `<5`, then deposits the sixth artifact. The chosen case therefore has four due arrivals and one future voyage. The future time is a fixed u64 value `2^63`, independent of candidate time. It fits the original type and must remain greater than the eventual action timestamp. Original freshness checks constrain departure time and existing artifact/location timestamps, not future arrival time.

The original Deposit refresh leaves that future artifact in voyage. Its public continuation nevertheless writes all nonzero locations from the original arrival count. The private action also stamps their `last_updated`, including the future entry. Thus this valid capacity boundary still exercises five compact location records and the larger397 transport. **Do not put that future Location into `unchangedSeeds`** or assume it produces no event.

Find keeps the enabled Gear requirement and its complete original owned Gear state. All carried templates are neutral Gear ships from a previously executed arrival fixture. Friendly arrival owner, location, combat, ordering and due-time inputs come from the frozen target-side queue; only explicit new full-Field arrival/artifact IDs and the documented future time are changed. IDs use fixed disjoint domains and never vary with candidate addresses, timestamps or receipt counters. The helper seeds the exact full Arrival, Artifact and current voyage Location for every active entry; all inactive original input entries remain present. Arrival and carried Artifact seeds are returned as `unchangedSeeds`; actual original execution determines all updated Location/planet/inventory/event states.

The V8 plan-size derivation is source-backed, not a gas estimate. Deposit's five scalar records occupy107 words; Find's six occupy118. A nonempty batch contributes4 header words plus4 per Location item. Therefore the new plans exceed128 and select retained `commit_plan(([Field;397]))`. They do not demonstrate use of185: that endpoint remains outside these legitimate V8 routes.

Eight offline tests pass against the original native ABI and frozen V8 source. They check full input serialization, exact current preimage seeding, distinct full-Field identities, unchanged inputs, fresh supplied entropy, the strict original Deposit capacity check, due/future semantics and independently computed plan sizes from actual scalar schemas. The test's historical files supply known accepted base-state shapes only; synthetic common entropy is used for offline checks and has not been executed. Runtime acceptance, actual route/gas evidence and whole-transaction Fee Juice remain pending.
