# Fixed benchmark price provenance

The unchanged reference is **0 Fee Juice base units per DA gas and 2,229,141,013,672 per L2 gas**. It exactly matches the saved [`node_getCurrentMinFees` response](reference-capture/node_getCurrentMinFees.json). The [machine-readable provenance](common-fee-schedule-provenance.json) records original file hashes and the limits below.

The source file’s filesystem modification time is **2026-09-10 20:52:52.120569 UTC**. This is filesystem metadata, **not an embedded RPC capture timestamp**. The response contains no timestamp or block identifier.

Adjacent saved responses identify Aztec node **5.2.0**, Ethereum L1 chain **1**, rollup version **4248422647**, real proofs enabled, and rollup address `0x91ff8bbd8ebb07893010d50a48a1609e5ebd8e34`. Only these selected [network identity fields](reference-capture/node_getNodeInfo.selected.json) are retained. The separately saved [block-number response](reference-capture/node_getBlockNumber.json) is **79426**; it does **not** establish that the quote is block 79426’s price.

The later [live receipt sample](live-receipts.json), explicitly timestamped **2026-09-10 20:54:52.671 UTC**, records a different contemporaneous L2 quote: **2,238,514,407,141**. Its three older finalized transactions also have different block prices:

| Block | L2 price, base units | Saved receipt fee, Fee Juice |
|---|---:|---:|
| 74620 | 2,161,655,650,039 | 8.244070438383137264 |
| 74624 | 2,166,720,888,035 | 8.392648189504074155 |
| 76995 | 2,153,489,950,612 | 8.529564531283515720 |

Those saved fees match their saved transaction-effect fees. Each also equals its own block price multiplied by the recorded gas inferred under a zero-priority-fee assumption. This supports the historical receipt amounts; it does not attribute the fixed reference price to any of those blocks.

Use **“fixed benchmark reference price matching a saved live fee quote”**. Comparisons retain that reference to isolate changes in complete billed gas. Actual locally mined fees are reconciled separately against their own block prices. This reference is neither a current quote nor a forecast.

This attribution was assembled from existing files only. No schedule, report, measurement, RPC endpoint, credential, or node ENR was changed or exposed.
