# Checked API-compatible build

The normal `pnpm --filter contracts build-contracts` entrypoint compiles all20
contracts, derives the five immutable class-binding files, checks all447 original
API methods/events and publishes native JSON plus TypeScript interfaces to the
existing paths. It uses the installed Aztec JavaScript SDK5.0.1 and Noir
1.0.0-beta.22+c57152. `DF_NARGO` can select that compiler explicitly.

Compilation occurs in a fresh temporary source copy. All349 production inputs,
the selected-source validator closure, build tooling, JavaScript package locks
and168 external Noir dependency bodies are frozen before execution. Both Config
class files, both Worker initiating classes and the Backend trusted classes are
derived from actual native artifacts. A second compilation checks all19 classes
that the Backend trusts. Native protocol caps, original API/event compatibility,
raw selectors, protected self-call entrypoints and storage-reader layouts must
pass before publication.

The battery constraint is enforced: no transaction proofs or profiling are run.
All14 private circuits must match the admitted V7 Core / V8 other System circuits
and their existing public verification keys. The native processor is invoked only
as `aztec_process -i ARTIFACT`, through a guard that refuses an unknown circuit,
missing/changed cached key, or extra flags. This deliberately fails on a machine
without the required existing keys; it never generates replacement keys. The
production wallet configuration is unaffected.

`node contracts/scripts/dev/build-api-compatible.mjs --check` resolves the build plan and
runs the read-only structural preflight without compilation or publication. The
printed temporary directory retains the plan, hashes and any failure logs.
`DF_NATIVE_OUTPUT` may select a fresh native-output directory outside the source
tree. `DF_PYTHON`, `DF_NODE`, `DF_NARGO` and `DF_NATIVE_PROCESSOR`
can select installed tools; every resolved file is pinned before execution.
The pinned compiler uses its existing `~/nargo` dependency cache. A different
`DF_NARGO_CACHE` is rejected so the authenticated dependency bodies are the ones
that compilation actually consumes.

Interface generation uses the project's installed builder directly and always
regenerates every interface. Copying verifies all20 JSON hashes and compares each
TypeScript wrapper with fresh generation before replacing `scripts/artifacts`.
The pinned SDK accepts pre-version native artifacts at runtime, but its generated
JSON assertions require version metadata statically. A checked adapter changes
only those two type assertions to pass through `unknown`, retaining the SDK
schema's legacy version sentinel and identical executable JavaScript. Both
generation and client-sync verification use that same adapter; native JSON,
class IDs, contract APIs and bytecode are unchanged.
The successful build manifest stays outside the codegen artifact directory.
Ordinary publication failures restore the prior bindings and artifact directory.

## Installing the prebuilt release

After applying the release source patch, extract the matching native archive to
a separate directory. It contains the 20 native artifacts, their build manifest
and all349 authenticated final build inputs. From the repository root, run:

```sh
python3 contracts/scripts/dev/api-compatible-build/publish.py --root . --native /path/to/extracted-native --check
python3 contracts/scripts/dev/api-compatible-build/publish.py --root . --native /path/to/extracted-native
pnpm --filter contracts codegen-contracts
pnpm --filter contracts copy-artifacts
pnpm --filter contracts scripts:typecheck
```

This path installs the checked artifacts and generates their interfaces without
compiling contracts, opening a wallet, generating proofs or requiring the Noir
verification-key cache. Interface generation uses the installed SDK5.0.1. The
installer accepts the complete original build-input snapshot or its complete
final source snapshot, including the five derived bindings; it rejects mixed or
edited snapshots. The separate normal rebuild path still has the cached-key
requirements described above.

Run the offline build and publication checks with:

```sh
python3 -m unittest discover -s contracts/scripts/dev/api-compatible-build -p 'test_*.py'
```

Reference JSON contains public circuit bytecode, public verification keys, API
metadata and fixture provenance. It contains no wallet or account secret keys.
Historical absolute paths in reference provenance identify prior experiments;
they are not execution dependencies. The selected source and test closure lives
in `tests/api-compatibility/generated/selected-validator-inputs.json`.

Passing this build establishes artifact/API identity and deployability. It is not
a new transaction-fee measurement or a proof-latency measurement.
