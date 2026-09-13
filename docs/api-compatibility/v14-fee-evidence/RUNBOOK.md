# V14 full58 — awaiting exact execution review

Continue the already-deployed V14 candidate only after the isolated touch wallet closes and all its sends reconcile. The first-two evidence is frozen separately at `/tmp/df-v14-touch-first2-frozen`; its update/create receipts are retained and must not execute again.

The full run covers58 distinct complete actions:45 main,4 carried-arrival and9 artifact/boundary cases. It executes56 remaining candidate actions, reusing52 cached canonical original non-Find rows and producing6 fresh paired Find originals. Five artifact Find originals use a new baseline-v14-artifacts label pointing to the exact existing original17 addresses/configuration marker; three accepted boundary Deposits remain baseline-v12-artifacts. There is no new original deployment or original Move allocation.

Use only `run-full-v14.mjs --execute` with the separately reviewed hash of `full58-execution-inputs-manifest.json`. This is not the earlier first2 input hash. Children have two-thread environments, proofs disabled and profiling off. Setup/binding reconciliation has the fee gate off, while every candidate action retains the final actual-account transaction gate. Any ambiguous send stops the run for exact reconciliation; there is no automatic replay.

The sequence begins with a read-only52-original preflight, then candidate initialization before fresh Find, ordinary Refresh/Move, and early carriedRefresh20. It preserves main Move IDs2..14 and carried Move5=15/Move20=16. Other artifact cases do not allocate event IDs. Original Init actors and every non-time state/input field stay exact.

Only explicitly rebased action/block timestamps normalize. The candidate must match all remaining event/game fields before broadcast, and each deployment's actual full state roots and untouched seeded roots are checked after mining. Historical and current raw roots are not claimed identical when time fields differ. Found artifact IDs are never normalized; each Find pair shares one fresh actual archive seed within the original validity window.

First4 fees/effects must pass before the rest runs. Completion still requires all58 comparisons, including the already measured two. Keep the creation tradeoff visible: V14 is54 L2 gas above V12, although below the original. A full-candidate claim requires the completed matrix; these instructions do not claim unexecuted results.
