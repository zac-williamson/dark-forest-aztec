# Battery mode: proof generation deferred

The user requested tests with proof generation disabled because the laptop is running on battery without a charger, then clarified that complete transaction fee information is the priority and proof-disabled fee/runtime testing should continue. Native proof profiling, proved-and-mined replay and browser proving remain off. The coordinator is preparing the final genuine artifacts with a bounded two-thread toolchain, including required verification-key preparation; that is separate from transaction proving. No battery percentage has been measured or assumed.

The fee wallet already sets `proverEnabled:false`. That disables private proof generation during fee runs, but it does **not** make missing application verification keys optional. The complete V4 fee/runtime matrix is authorized to continue as soon as the final immutable artifacts contain genuine matching keys and the coordinator gives GO. There are no complete V4 fee results yet. Existing V1–V3 receipts and reports remain unchanged.

## Checks that do not generate proofs or keys

Run from the repository root. These source, ABI and harness checks do not open a node or wallet:

```sh
python3 -m unittest discover -s tests/api-compatibility -p 'test_*.py' -v
python3 tests/api-compatibility/check.py check --strict
node --test experiments/api-compatible-benchmark/resume-guards.test.mjs experiments/api-compatible-benchmark/utilities.test.mjs
node --check experiments/api-compatible-benchmark/run.mjs
node --check experiments/api-compatible-benchmark/run-plan-v4.mjs
NODE_BACKEND=js node --import ./node_modules/tsx/dist/loader.mjs experiments/api-compatible-benchmark/validate-run-plan-v4.mjs
```

The standalone Noir test packages execute constraints and assertions without making cryptographic proofs or verification keys. Run them individually against the current completed source, rather than starting a full workspace build:

```sh
/tmp/df-noir-beta22/nargo test --program-dir tests/api-compatibility/noir-payload-tests --silence-warnings
/tmp/df-noir-beta22/nargo test --program-dir tests/api-compatibility/field-buffer-tests --silence-warnings
```

These tests still compile and execute their small test programs. Passing them establishes their tested source behavior; it does not establish final native class identity, successful deployment, complete transaction fees or proving latency.

The following command only prints the future45-pair plan:

```sh
node experiments/api-compatible-benchmark/run-plan-v4.mjs
```

After genuine final artifacts exist and the coordinator gives GO, the authorized fee/runtime command is:

```sh
node experiments/api-compatible-benchmark/run-plan-v4.mjs --execute all > /tmp/df-api-compatible-candidate-v4-full.log 2>&1
```

It keeps `proverEnabled:false`, applies the strict first-four gate, then runs all45 planned comparisons. The command does not invoke native/browser profiles, proved-and-mined replay or the deferred profile-fixture phase. Proof-disabled mined fees remain separate from proving/UX evidence. Do not run `profile.mjs`, `prove-and-mine.mjs` or browser proof commands under the current instruction.

## Why a missing key cannot produce an authentic final class

The pinned SDK5.2 implementation requires the verification key of every private function when computing its contract-class leaf (`computeVerificationKeyHash` in `@aztec/stdlib/dest/contract/contract_class.js`). A missing key throws. The private function simulator also reads `artifact.verificationKey` into its execution result (`@aztec/pxe/dest/contract_function_simulator/oracle/private_execution.js`). The proof-disabled kernel path still converts that key into fields and obtains the function membership witness (`@aztec/pxe/dest/private_kernel/private_kernel_execution_prover.js`). Disabling proof generation therefore does not remove the key from class identity or kernel inputs.

`bb aztec_process --help` describes native transpilation plus private-key generation and exposes input, output and force-regeneration options. It provides no skip-private-key mode. The complete build currently invokes that processor and calculates real class IDs before binding the backend's trusted classes.

Raw private ACIR can be executed below those SDK layers, and the SDK supports contract overrides only while skipping kernels. Such diagnostics can test computation or public execution, but they do not produce the legitimate complete class of a changed private circuit. They must not be reported as final deployable artifacts or complete mined V4 fees. No fake, empty or mismatched verification keys will be inserted.

Genuine existing keys can be reused only when the private bytecode and compatible compiler/prover format match exactly. An earlier read-only audit found13 of14 target private functions byte-identical to frozen V3, with Refresh changed. **That audit predates the subsequent Move fallback correction from217 to337 fields.** The final comparison must be repeated: both changed Refresh and changed Move need their own genuine keys unless an exact matching key already exists. No key was copied or generated during the audit.

Current work may establish final class admission, all45 complete fee comparisons and proof-disabled negative runtime checks. Transaction proving and proof-latency/UX conclusions remain deferred. Public AVM diagnostic profiling is also off in the default fee plan. The local node has been recovered from its local LMDB failure using the same L1/genesis and a preserved database copy; saved receipt canonicality, baseline classes, roots and counter passed live verification. See [RECOVERY-v4.md](RECOVERY-v4.md). The fee runner retains exclusive ownership of its mutation wallet and the coordinator schedules other runtime suites explicitly.
