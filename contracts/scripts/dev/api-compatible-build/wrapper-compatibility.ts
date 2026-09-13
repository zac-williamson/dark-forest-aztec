/** Preserve SDK5.0.1's supported pre-version artifact loading with strict JSON types. */
import assert from 'node:assert/strict';

export function adaptCheckedArtifactWrapper(source: string, name: string): string {
  assert(/^[A-Za-z_][A-Za-z0-9_]*$/.test(name), 'Invalid checked contract name');
  const operand = `${name}ContractArtifactJson as NoirCompiledContract`;
  assert.equal(source.split(operand).length - 1, 2, 'Expected exactly two SDK artifact assertions');
  for (const loader of ['loadContractArtifact', 'loadContractArtifactForPublic']) {
    assert.equal(source.split(`${loader}(${operand})`).length - 1, 1, `Unexpected SDK ${loader} shape`);
  }
  // The SDK schema deliberately defaults missing aztec_version to its legacy sentinel.
  // This changes types only; do not inject a version or modify native JSON/bytecode.
  return source.split(operand).join(`${name}ContractArtifactJson as unknown as NoirCompiledContract`);
}
