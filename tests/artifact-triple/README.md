# Historical standalone-artifact tests

This suite preserves the earlier comparison between the additive three-root getter and the original scalar getters. It is historical evidence, not a passing test suite for the current API-compatible deployment.

The test deploys ArtifactStorage alone and calls `set` without binding a backend. Current facades require that deployment binding before writes, so the unchanged test cannot run successfully against them. Its source and earlier evidence remain preserved; no V5 pass is claimed. The active API-compatible build does not invoke this suite.

Use [the current bound storage/runtime suites](../api-compatible-storage/README.md) to check the original storage APIs, same-transaction reads and exact roots on the final deployment. Those runners verify the selected native classes and perform the required isolated namespace binding. They require the coordinator's runtime release; passing historical tests is not a substitute.
