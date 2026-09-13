# V14 touch compatibility:75 checks passed

All75 targeted runtime checks passed. The run used55 canonical setup/test transactions on10 fresh contracts, plus explicitly labeled no-send rejection simulations. These are different counts; the suite makes no fee or proof-speed claim.

Both Artifact and Location retained complete original events and exact physical hashes across zero, high-Field and maximum typed inputs. Admin/grant/revoke/transfer behavior matched the expected original authorization. Isolated touch transactions contained no write to the target root leaf. Same-transaction freshness and rejected-operation rollback passed.

The custom Artifact setter actually changed Location to a different root. Both original and V14 Vault then executed the required original second setter: each produced exactly Artifact(requested), Location(replacement), Location(requested), committed seen_sets=1, and restored the requested full Location root. The paired successful account transaction mined at block4661. Wrong admin, either wrong hash and either missing Location writer grant rejected with state rollback.

The runner pinned all20 V14 classes and the matching genuine state-first public-only sentinel. Proofs/profiling were disabled, child environments used two threads, and the isolated wallet closed cleanly. Existing fee gameplay namespaces were not mutated. The historical V12 suite remains separate; no inherited result is relabeled V14.

[Exact checks, raw errors, canonical receipts and events](runtime-checks.json), [scope summary](summary.json), [log](runtime.log), [reviewed inputs](execution-inputs.json).

Full immutable snapshot: `/tmp/df-v14-touch-runtime-frozen`. The broader V14 fee matrix and later targeted runtime checks are separate evidence.
