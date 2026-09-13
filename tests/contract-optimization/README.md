# Historical standalone-storage tests

This suite preserves the earlier standalone-storage optimization tests and gas harness. It is historical evidence, not a passing test suite for the current API-compatible deployment.

Its setup deploys each original storage contract in isolation and immediately writes state. The current facades require a completed, class-verified backend binding first. Running this suite unchanged against the current facades therefore fails with `State backend not bound`; its old failure expectations and gas measurements must not be presented as V5 results. The historical Noir source remains unchanged.

The local `../optimization-benchmark` dependency is retained so the historical source package is complete. Neither package is invoked by the active API-compatible build or its test runner.

Use [the current bound storage/runtime suites](../api-compatible-storage/README.md) for the current deployment. They deploy isolated namespaces, bind them to the verified backend, and compare the original APIs, events, roots and authorization behavior. Run them only after the final native build/deployment and the coordinator's runtime release, passing the explicit candidate variant and artifact directory. The new [custom batch-verifier suite](../api-compatible-storage/caller-batch/README.md) covers the original empty-batch fallback behavior. No historical pass count establishes those results.
