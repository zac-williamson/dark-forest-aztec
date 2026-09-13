import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";

const [baselineDir, optimizedDir] = process.argv.slice(2);
assert(
  baselineDir && optimizedDir,
  "Usage: node compare-artifacts.mjs BASELINE_DIR OPTIMIZED_DIR",
);
let privateFunctions = 0;
let contracts = 0;
for (const file of (await readdir(baselineDir))
  .filter((f) => f.endsWith(".json"))
  .sort()) {
  const baseline = JSON.parse(
    await readFile(path.join(baselineDir, file), "utf8"),
  );
  if (!Array.isArray(baseline.functions)) continue;
  const optimized = JSON.parse(
    await readFile(path.join(optimizedDir, file), "utf8"),
  );
  assert.equal(optimized.name, baseline.name, file);
  // Use matching compilation stages: raw vs raw, or postprocessed vs postprocessed.
  assert.equal(
    Boolean(optimized.transpiled),
    Boolean(baseline.transpiled),
    `${file}: compilation stages differ`,
  );
  assert.deepEqual(
    optimized.outputs,
    baseline.outputs,
    `${file}: event/struct output schemas changed`,
  );
  assert.deepEqual(
    optimized.functions.map((f) => f.name),
    baseline.functions.map((f) => f.name),
    `${file}: function set changed`,
  );
  for (const before of baseline.functions) {
    const after = optimized.functions.find((f) => f.name === before.name);
    assert.deepEqual(
      after.abi.parameters,
      before.abi.parameters,
      `${file}:${before.name}: parameters changed`,
    );
    assert.deepEqual(
      after.abi.return_type,
      before.abi.return_type,
      `${file}:${before.name}: return type changed`,
    );
    assert.deepEqual(
      after.custom_attributes,
      before.custom_attributes,
      `${file}:${before.name}: function permissions changed`,
    );
    if (!before.is_unconstrained) {
      assert.equal(
        after.bytecode,
        before.bytecode,
        `${file}:${before.name}: private bytecode changed`,
      );
      privateFunctions++;
    }
  }
  contracts++;
}
console.log(
  JSON.stringify(
    {
      contracts,
      privateFunctions,
      privateBytecodeUnchanged: true,
      functionSignaturesAndOutputSchemasUnchanged: true,
    },
    null,
    2,
  ),
);
