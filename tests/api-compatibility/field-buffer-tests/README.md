# Production FieldBuffer boundary tests

This package imports `contracts/libs` directly; it does not contain a copied decoder. It currently has 39 Noir tests: one successful round trip and one short-reader rejection for each of 19 widths, plus a constant-expression width check.

The V5 additions cover widths 35, 52, 141, 186, 257, 263, 270 and 279, together with the ordinary 397-word decoder. Every position in these added round trips receives zero, the maximal Field value and a distinct value above u128 across three rotations. Each test checks the complete returned array, prefix/suffix reader positions, writer completion, and direct serialization/deserialization identity. A reader with one missing word must reject.

`test_field_buffer.py` checks that every width selected in the production manifest has both executable boundary cases, so changing decoder selection cannot silently omit these tests. It also checks the production-library import and the full-array, cursor, range and short-reader assertions. This source coverage check is not a substitute for executing Noir tests.

Run from the repository root, only after the coordinator releases the compiler window:

```sh
RAYON_NUM_THREADS=2 HARDWARE_CONCURRENCY=2 /tmp/df-noir-beta22/nargo test --program-dir tests/api-compatibility/field-buffer-tests --silence-warnings
```

The lightweight coverage check needs no compiler, chain or prover:

```sh
python3 -m unittest discover -s tests/api-compatibility -p test_field_buffer.py -v
```

All 39 tests passed with the pinned compiler and two threads; the exact command, tested source hashes and test names are recorded in [the V5 execution report](../../../docs/api-compatibility/field-buffer-boundary-tests-v5.json), with its [complete sanitized log](../../../docs/api-compatibility/field-buffer-boundary-tests-v5.txt). These tests generate no transaction proof or verification key and make no transaction-fee or proving-latency claim.

V6 retires the unused 35/52-word transports after restoring original Reveal/SafeOwner private entry points. Their historical tests are preserved in `../snapshots/field-buffer-boundaries-v5.nr`; the active 35 boundary tests cover every selected current width.
