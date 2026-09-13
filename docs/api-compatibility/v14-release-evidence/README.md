# Completed V14 source installation

The primary checkout now contains the complete tested V14 implementation. The fixed allowlist installed561 source/tool/reference changes:81 replacements were backed up first,480 files were added, and202 allowlisted files were retained. Existing unrelated work, the deployment environment example and the actual client deployment index were preserved. This was a local source installation, not a Git commit or network deployment.

The primary checkout then passed checked native publication, SDK interface generation/copy, the normal deployment typecheck, all447 original compiled API checks with zero breaking changes/stale artifacts/unresolved calls, and25 selected source/semantic/replay checks. All349 compiled sources and20 native artifacts still match the measured V14 build exactly. The strict client check and actual20 wrapper JavaScript/class identity checks are in the preceding [integration package](../v14-integration-evidence/README.md).

No contract compilation, new keys, proofs, wallets or network transactions were used for source installation and verification. The main client index keeps its existing deployment addresses. The integration sync command generates its next index and interfaces together from a deliberate fresh deployment.

The source and previous generated-output backup locations are recorded in source-promotion.json. The native build and generated artifact interfaces remain separate from the source patch. Release packaging integrity is recorded in the accompanying release manifest; it is not a new fee or gameplay measurement.
