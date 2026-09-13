# Historical standalone-storage gas harness

This public-only contract is the source dependency of [the historical contract-optimization suite](../contract-optimization/README.md). It preserves the original nested-call gas measurements. It is not part of the 20 deployed production contracts or the current Fee Juice benchmark.

The dependent historical tests do not bind the current storage facades to a backend and cannot run unchanged against the API-compatible deployment. Current complete-transaction measurements and bound runtime checks are documented in [the API-compatible benchmark](../../experiments/api-compatible-benchmark/RUNBOOK-v5.md) and [storage suite](../api-compatible-storage/README.md). Standalone gas counters must not be reported as complete transaction fees.
