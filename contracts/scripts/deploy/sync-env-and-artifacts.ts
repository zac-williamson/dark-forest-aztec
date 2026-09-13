/** Sync the checked deployment addresses and all twenty client artifacts together. */
import { loadContractArtifact } from "@aztec/stdlib/abi";
import { generateTypescriptContractInterface } from "@aztec/builder/codegen";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { getContractsEnvFilePath, loadContractsEnv } from "../utils/env.ts";
import { syncClientDeployment } from "./sync-client-deployment.ts";
import { generateClientIndex } from "./client-deployment-index.ts";

const directory = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(directory, "../../..");
const require = createRequire(import.meta.url);
function packageVersion(spec: string): string {
  const expected = spec.split("/").slice(0, 2).join("/");
  let current = path.dirname(fs.realpathSync(require.resolve(spec)));
  while (true) {
    const file = path.join(current, "package.json");
    if (fs.existsSync(file)) {
      const metadata = JSON.parse(fs.readFileSync(file, "utf8"));
      if (metadata.name === expected) return metadata.version;
    }
    const parent = path.dirname(current);
    assert(parent !== current, `Missing package metadata: ${expected}`);
    current = parent;
  }
}

async function main(): Promise<void> {
  assert.equal(packageVersion("@aztec/stdlib/abi"), "5.0.1");
  assert.equal(packageVersion("@aztec/builder/codegen"), "5.0.1");
  loadContractsEnv();
  const result = await syncClientDeployment({
    repositoryRoot: root,
    manifestPath: path.join(
      root,
      "contracts/target/api-compatible-build-provenance.json",
    ),
    envPath: getContractsEnvFilePath(),
    indexPath: path.join(root, "packages/contracts/src/index.ts"),
    artifactsSource: path.join(root, "contracts/scripts/artifacts"),
    artifactsDestination: path.join(root, "packages/contracts/src/artifacts"),
    generateIndex: generateClientIndex,
    generateWrapper: async (raw, importPath) => {
      const artifact = loadContractArtifact(JSON.parse(raw));
      return {
        name: artifact.name,
        source: await generateTypescriptContractInterface(artifact, importPath),
      };
    },
  });
  console.log(
    `Synced deployment addresses and all ${result.contracts} checked client interfaces (${result.files} files).`,
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
