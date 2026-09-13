# Contract API compatibility

The immutable reference is commit `00bfa05c18862cce1c5adb362e4ecebe084c329a`. Its 17 contracts expose 447 public/private/utility functions. `baseline/sources` contains all original Noir sources/manifests and the source files that directly consume these APIs; `baseline/manifest.json` hashes every captured source and normalized metadata file. The captured processed artifacts also retain their original file hashes and owning-source provenance.

The selected integration keeps the V7 cached Core private definitions and compact
Init/Refresh continuations. Four full Core continuations share the exact V8 typed
public bodies in process, retaining every argument, Config/custom-store caller,
assertion and write order. Find and VaultWorker use the measured 185-word medium
plan branch. The vendored public dispatcher combines the exact Field20 cursor
optimization with explicit `SinglePublicArgumentDirectDeserialize` opt-in on the
two FieldBuffer libraries. No serializer or private function body changes.

Source generation is explicit and separate from native compilation/publication:

```sh
python3 tests/api-compatibility/generate-selected-source.py --apply
python3 tests/api-compatibility/generate-selected-source.py --check
python3 tests/api-compatibility/validate-selected-source.py --root .
```

`--apply` is for intentional generated-source edits. The normal checked build
never runs it. The validator authenticates all 347 Noir/license inputs, the five
actual build-derived bindings, 14 private source origins and a fresh source replay.
Its pinned import/reference closure is `generated/selected-validator-inputs.json`.
The two remaining original build inputs are the reviewed package/build entrypoints;
the portable builder freezes their current hashes separately. Build, interface
publication and cached-key-only policy are documented in
`contracts/scripts/dev/api-compatible-build/README.md`.

These source checks are not new runtime, complete-fee or proof-latency evidence.
Historical V8 Core implementation assertions remain under
`snapshots/historical-tests`; active tests verify the selected Core semantics.

Run from the repository root:

```sh
python3 -m unittest discover -s tests/api-compatibility -p 'test_*.py' -v
python3 tests/api-compatibility/check.py check --strict
python3 tests/api-compatibility/check.py check --artifacts contracts/target/api-compatible --strict
```

`--strict` rejects removed/changed functions or events, including parameter names, integer widths, fixed array lengths, nested record fields, return types, execution kind, `only_self`, `view`, and initializer attributes. With artifacts supplied it additionally checks the compiled user ABI and rejects stale artifacts whose embedded owning source differs from the current source. Compiler-generated protocol entry points are recorded separately because their representation differs between raw Noir and processed artifacts.

Reports are written under `docs/api-compatibility`: the complete current inventory, compatibility report, caller references, and transitive writers. The immutable original inventory is always available under `baseline`. Every changed original function body is explicitly marked for semantic review even if its ABI remains identical. Physical storage changes are reported separately: this fresh-deployment redesign does not require migration of existing games.

The checker does not prove semantic equivalence, actual fees, privacy, event order, class identity, or authorization. Those require executable action/storage tests. Caller discovery enumerates literal method names, generated-wrapper usage, intent routing, deployment addresses, wallet registration, and indexer event references; dynamically constructed external integrations still need review. Never infer coverage from a matching selector alone.

`generate_facades.py` copies all nine original storage APIs and event schemas from the snapshot, then replaces their bodies with the canonical-backend implementation. Run it only while the facades are intentionally being regenerated; compiled facade classes must be frozen before backend attestation constants are generated. No migration or legacy-state import is performed.

`generate-backend-move.py --check` reverses the Move transformation and compares every original method with its captured implementation. The unchanged private gameplay result is serialized into 539 fields for the general path. When both arrival counts are zero, the new `only_self` continuation receives 337 fields: the original 217-word settlement prefix plus both complete 60-word location arrays for compatibility fallback. Only the unchanged 217-word prefix is forwarded to the backend; the backend authenticates the actual caller's immutable audited class before reconstructing typed values. Compatibility fallback reconstructs the original arguments and executes the original implementation, including scalar ID-zero reads. Count-zero batches are omitted only from the canonical backend path. Fallback reconstructs the exact original location arrays, zero computed ID/hash arrays and original authorization checks, so arbitrary compatible stores observe the same arguments.

The backend's Config shortcut applies only to the authenticated current Config class. Its cache combines exactly the original nine common hashes plus the artifact configuration hash, and independently checks the requested level's default statistics. A mismatch or unknown class runs both original assertions in their original order. The tests check the hash order and all existing setters that mutate those hashes.

Run the additional serialization checks with the pinned Noir compiler:

```sh
python3 tests/api-compatibility/generate-backend-move.py --check
python3 tests/api-compatibility/verify_move_payload_tests.py
cd tests/api-compatibility/noir-payload-tests
nargo test --silence-warnings
```

The six executable decoder tests preserve every word at zero, maximal field/integer values, and mixed values, including inactive array tails. They test the exact generated decoder bodies against the original ABI schema. These are authenticated-message decoders, not standalone parsers for arbitrary callers; complete-entry authorization tests must also reject forged prepared calls. Actual storage, event, and permission comparisons are provided separately in `tests/api-compatible-storage` and require deployed original and candidate artifacts.

`generate-field-buffer.py` emits concrete `Deserialize` implementations for every
currently used additive `FieldBuffer` width. The measured selection is
56, 60, 88, 141, 186, 227, 257, 263, 270, 279, 337, 539 and 549 words. Selected decoders perform the same
ordered `Reader.read()` operations directly; all other widths keep the original
array decoder, including the 144-word compact Refresh continuation that retains
all inactive fallback location fields. Generic serialization, wire fields, reader bounds/cursor and
original APIs are unchanged. This is public transport optimization; standalone
AVM gas measurements are not complete transaction Fee Juice savings.

```sh
python3 tests/api-compatibility/generate-field-buffer.py --check \
  --output contracts/libs/src/field_buffer.nr \
  --unroll 56,60,88,141,186,227,257,263,270,279,337,539,549 \
  --manifest tests/api-compatibility/generated/field-buffer-selection.json
/tmp/df-noir-beta22/nargo test --program-dir tests/api-compatibility/field-buffer-tests --silence-warnings
```

The decoder tests use the production library and verify every returned field,
reader prefixes/suffixes, full-range values, and truncated-input rejection. Move's
literal calldata transform separately checks the exact selector/address/payload
sequence and reverses to the previous forwarding body without changing the
return decoder, custom-Config guard or legacy fallback. The recorded class-size
probe includes rejected oversized experiments; only the final complete native
build can establish that every deployed class fits the protocol limit.

V6 restores Reveal and SafeOwner's exact original private bodies and enqueues.
Their original public continuations use individually guarded canonical reads and
retain each original typed setter and custom-store call. Other private actions
retain the measured V5 calculation and transport. The retired 35/52-word decoder
boundary tests remain in `snapshots/field-buffer-boundaries-v5.nr`.

The nine facades now own both full-width state roots and original permission
state: admin1, backend2, roots3, explicit grants4, indices5, list6, count7. Backend
owns only namespace kinds1, compact Arrival payloads2, and late counters3. All
original permission bodies are restored from the original Git snapshot; an
implicit admin grant never becomes an explicit list entry. Native metadata and
independent direct storage observations must validate both layouts.

Canonical batches carry explicit boundaries, original counts/maxima, and ordered
nonzero items. Empty batches retain their authorization record; duplicate IDs
remain separate writes/events. Singleton callbacks avoid maximum-sized calldata;
larger batches emit inside the original facade after bound-Backend authentication.
Source and target Move batches remain separated by their original planet events.
No fee saving or original proving-latency parity is inferred from these changes;
complete matched transaction measurements and semantic runtime checks are required.
