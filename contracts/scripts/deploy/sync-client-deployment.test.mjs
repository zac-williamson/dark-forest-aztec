import { adaptCheckedArtifactWrapper } from '../dev/api-compatible-build/wrapper-compatibility.ts';
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createHash } from "node:crypto";
import {
  CONTRACT_FILES,
  syncClientDeployment,
} from "./sync-client-deployment.ts";
import {
  generateClientIndex,
  ORIGINAL_CONTRACT_ADDRESS_KEYS,
} from "./client-deployment-index.ts";
import { AztecAddress } from "@aztec/stdlib/aztec-address";

const address = (value) => `0x${BigInt(value).toString(16).padStart(64, "0")}`;
const ADDITIVE_ADDRESS_KEYS = [
  "GAME_STATE_BACKEND_CONTRACT_ADDRESS",
  "CORE_SETTLEMENT_WORKER_CONTRACT_ADDRESS",
  "VAULT_SETTLEMENT_WORKER_CONTRACT_ADDRESS",
];
function completeEnvironment(extra = "", omitted = []) {
  const entries = {
    ACCOUNT_ADDRESS: address(99),
    START_BLOCK: "42",
    ...Object.fromEntries(
      ORIGINAL_CONTRACT_ADDRESS_KEYS.map((key, i) => [key, address(i + 1)]),
    ),
  };
  return (
    Object.entries(entries)
      .filter(([key]) => !omitted.includes(key))
      .map(([key, value]) => `${key}=${value}`)
      .join("\n") +
    "\n" +
    extra
  );
}

const sha = (bytes) => createHash("sha256").update(bytes).digest("hex");
const sdkFixture = (name, importPath) => `import ${name}ContractArtifactJson from ${JSON.stringify(importPath)};
loadContractArtifact(${name}ContractArtifactJson as NoirCompiledContract);
loadContractArtifactForPublic(${name}ContractArtifactJson as NoirCompiledContract);
`;

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "df-client-sync-test-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const artifactsSource = path.join(root, "source"),
    parent = path.join(root, "client");
  fs.mkdirSync(artifactsSource);
  fs.mkdirSync(parent);
  const options = {
    repositoryRoot: root,
    manifestPath: path.join(root, "build.json"),
    envPath: path.join(root, "game.env"),
    indexPath: path.join(parent, "index.ts"),
    artifactsSource,
    artifactsDestination: path.join(parent, "artifacts"),
    generateIndex: generateClientIndex,
    generateWrapper: async (raw, importPath) => ({
      name: JSON.parse(raw).name,
      source: sdkFixture(JSON.parse(raw).name, importPath),
    }),
  };
  fs.writeFileSync(
    options.envPath,
    completeEnvironment(
      "ACCOUNT_SECRET_KEY=never-copy\nCORE_DEPLOYMENT_SALT=0x789\n",
    ),
  );
  fs.writeFileSync(options.indexPath, "old addresses\n");
  fs.mkdirSync(options.artifactsDestination);
  fs.writeFileSync(
    path.join(options.artifactsDestination, "old.txt"),
    "old artifacts\n",
  );
  const sourceFiles = {};
  for (let i = 0; i < 349; i++) {
    const n = `input${i}.nr`;
    fs.writeFileSync(path.join(root, n), "source");
    sourceFiles[n] = sha(Buffer.from("source"));
  }
  const artifacts = Object.entries(CONTRACT_FILES).map(([name, file], i) => {
    const bytes = Buffer.from(JSON.stringify({ name, transpiled: true }));
    fs.writeFileSync(path.join(artifactsSource, file), bytes);
    fs.writeFileSync(
      path.join(artifactsSource, `${name}.ts`),
      adaptCheckedArtifactWrapper(sdkFixture(name, `./${file}`), name),
    );
    return { file, sha256: sha(bytes), classId: `0x${(i + 1).toString(16)}` };
  });
  const manifest = {
    passed: true,
    proofsGenerated: 0,
    newKeysGenerated: 0,
    secondIdentityPass: 19,
    sourceFiles,
    privateMethods: { private: Array(14).fill({}) },
    artifacts,
    classIds: Object.fromEntries(
      artifacts.map((row) => [row.file, row.classId]),
    ),
  };
  fs.writeFileSync(options.manifestPath, JSON.stringify(manifest));
  const unchanged = () => {
    assert.equal(fs.readFileSync(options.indexPath, "utf8"), "old addresses\n");
    assert.deepEqual(fs.readdirSync(options.artifactsDestination), ["old.txt"]);
    assert.equal(
      fs.readFileSync(
        path.join(options.artifactsDestination, "old.txt"),
        "utf8",
      ),
      "old artifacts\n",
    );
  };
  return { root, parent, options, manifest, unchanged };
}
test("sync automatically publishes exactly20 checked interfaces and the matching public exports", async (t) => {
  const f = fixture(t),
    result = await syncClientDeployment(f.options);
  assert.deepEqual(result, { contracts: 20, files: 40 });
  assert.equal(fs.readdirSync(f.options.artifactsDestination).length, 40);
  assert.equal(
    fs.readFileSync(f.options.indexPath, "utf8"),
    generateClientIndex(fs.readFileSync(f.options.envPath, "utf8")),
  );
  assert(!fs.readFileSync(f.options.indexPath, "utf8").includes("never-copy"));
  assert.deepEqual(fs.readdirSync(f.parent).sort(), ["artifacts", "index.ts"]);
});
for (const [label, mutate] of [
  [
    "changed native hash",
    (f) =>
      fs.appendFileSync(
        path.join(f.options.artifactsSource, "core-Core.json"),
        " ",
      ),
  ],
  [
    "stale generated wrapper",
    (f) =>
      fs.appendFileSync(
        path.join(f.options.artifactsSource, "Core.ts"),
        "stale",
      ),
  ],
  [
    "changed source input",
    (f) => fs.appendFileSync(path.join(f.root, "input12.nr"), "changed"),
  ],
  [
    "extra artifact file",
    (f) =>
      fs.writeFileSync(
        path.join(f.options.artifactsSource, "unexpected.txt"),
        "x",
      ),
  ],
  [
    "duplicate native inventory",
    (f) => {
      f.manifest.artifacts[0] = f.manifest.artifacts[1];
      fs.writeFileSync(f.options.manifestPath, JSON.stringify(f.manifest));
    },
  ],
])
  test(`${label} rejects before staging or either client output changes`, async (t) => {
    const f = fixture(t);
    mutate(f);
    await assert.rejects(syncClientDeployment(f.options));
    f.unchanged();
    assert.deepEqual(fs.readdirSync(f.parent).sort(), [
      "artifacts",
      "index.ts",
    ]);
  });
test("failure installing index after new artifact directory restores both previous outputs", async (t) => {
  const f = fixture(t);
  let failure = false;
  const fileSystem = {
    ...fs,
    renameSync(from, to) {
      if (from.endsWith("index-next") && !failure) {
        failure = true;
        throw new Error("injected index install error");
      }
      return fs.renameSync(from, to);
    },
  };
  await assert.rejects(
    syncClientDeployment({ ...f.options, fileSystem }),
    /injected index install/,
  );
  assert(failure);
  f.unchanged();
  assert.deepEqual(fs.readdirSync(f.parent).sort(), ["artifacts", "index.ts"]);
});
test("failure backing up index restores the already backed-up artifact directory", async (t) => {
  const f = fixture(t);
  let failure = false;
  const fileSystem = {
    ...fs,
    renameSync(from, to) {
      if (from === f.options.indexPath && !failure) {
        failure = true;
        throw new Error("injected index backup error");
      }
      return fs.renameSync(from, to);
    },
  };
  await assert.rejects(
    syncClientDeployment({ ...f.options, fileSystem }),
    /injected index backup/,
  );
  f.unchanged();
});
test("failure staging a wrapper leaves both current client outputs untouched", async (t) => {
  const f = fixture(t);
  const fileSystem = {
    ...fs,
    writeFileSync(file, ...args) {
      if (
        String(file).includes("artifacts-next") &&
        String(file).endsWith("Core.ts")
      )
        throw new Error("injected staging error");
      return fs.writeFileSync(file, ...args);
    },
  };
  await assert.rejects(
    syncClientDeployment({ ...f.options, fileSystem }),
    /injected staging/,
  );
  f.unchanged();
});
test("missing original destinations roll back to absence after publication failure", async (t) => {
  const f = fixture(t);
  fs.rmSync(f.options.indexPath);
  fs.rmSync(f.options.artifactsDestination, { recursive: true });
  const fileSystem = {
    ...fs,
    renameSync(from, to) {
      if (from.endsWith("index-next")) throw new Error("install error");
      return fs.renameSync(from, to);
    },
  };
  await assert.rejects(
    syncClientDeployment({ ...f.options, fileSystem }),
    /install error/,
  );
  assert(!fs.existsSync(f.options.indexPath));
  assert(!fs.existsSync(f.options.artifactsDestination));
});
test("rollback failure preserves recovery copies and reports the recovery directory", async (t) => {
  const f = fixture(t);
  const fileSystem = {
    ...fs,
    renameSync(from, to) {
      if (from.endsWith("index-next") || from.endsWith("artifacts-previous"))
        throw new Error("injected rename error");
      return fs.renameSync(from, to);
    },
  };
  await assert.rejects(
    syncClientDeployment({ ...f.options, fileSystem }),
    /recovery needs attention.*client-sync-/,
  );
  const temp = fs
    .readdirSync(f.parent)
    .find((n) => n.startsWith(".client-sync-"));
  assert(temp);
  assert.equal(
    fs.readFileSync(
      path.join(f.parent, temp, "artifacts-previous/old.txt"),
      "utf8",
    ),
    "old artifacts\n",
  );
});
test("complete17 publishes successfully without requiring additive addresses or deployment metadata", async (t) => {
  const f = fixture(t);
  await syncClientDeployment(f.options);
  const index = fs.readFileSync(f.options.indexPath, "utf8");
  assert.equal(ORIGINAL_CONTRACT_ADDRESS_KEYS.length, 17);
  for (const key of ORIGINAL_CONTRACT_ADDRESS_KEYS)
    assert(index.includes(`export const ${key} = `));
  for (const key of ADDITIVE_ADDRESS_KEYS)
    assert(!index.includes(`export const ${key} = `));
  for (const key of ORIGINAL_CONTRACT_ADDRESS_KEYS) {
    const prefix = key.slice(0, -"_CONTRACT_ADDRESS".length);
    assert(index.includes(`export const ${prefix}_DEPLOYER_ADDRESS = "";`));
    assert(index.includes(`export const ${prefix}_DEPLOYMENT_SALT = `));
  }
});
test("complete20 validates and exports optional Backend and Worker addresses", async (t) => {
  const f = fixture(t);
  fs.writeFileSync(
    f.options.envPath,
    completeEnvironment(
      ADDITIVE_ADDRESS_KEYS.map((key, i) => `${key}=${address(i + 101)}`).join(
        "\n",
      ),
    ),
  );
  await syncClientDeployment(f.options);
  const index = fs.readFileSync(f.options.indexPath, "utf8");
  ADDITIVE_ADDRESS_KEYS.forEach((key, i) =>
    assert(index.includes(`export const ${key} = "${address(i + 101)}";`)),
  );
});
test("each missing original contract address rejects before publication", async (t) => {
  for (const key of ORIGINAL_CONTRACT_ADDRESS_KEYS)
    await t.test(key, async (t) => {
      const f = fixture(t);
      fs.writeFileSync(f.options.envPath, completeEnvironment("", [key]));
      await assert.rejects(
        syncClientDeployment(f.options),
        new RegExp(`Missing client value: ${key}`),
      );
      f.unchanged();
      assert.deepEqual(fs.readdirSync(f.parent).sort(), [
        "artifacts",
        "index.ts",
      ]);
    });
});
test("dotenv quotes, comments, export syntax and duplicate values match deployment parsing", async (t) => {
  const f = fixture(t);
  const replacement = address(101);
  fs.writeFileSync(
    f.options.envPath,
    completeEnvironment(
      `export CORE_CONTRACT_ADDRESS="${replacement}" # current Core\nMOVE_CONTRACT_ADDRESS='${address(102)}' # Move\nSTART_BLOCK="00123" # indexed from here\nCONFIG_DEPLOYER_ADDRESS="${address(103)}" # known deployer\nCONFIG_DEPLOYMENT_SALT='0x456' # optional metadata\nACCOUNT_SECRET_KEY="never-copy-r3"\n`,
    ),
  );
  await syncClientDeployment(f.options);
  const index = fs.readFileSync(f.options.indexPath, "utf8");
  assert(index.includes(`CORE_CONTRACT_ADDRESS = "${replacement}";`));
  assert(index.includes(`MOVE_CONTRACT_ADDRESS = "${address(102)}";`));
  assert(index.includes("START_BLOCK = 123;"));
  assert(index.includes(`CONFIG_DEPLOYER_ADDRESS = "${address(103)}";`));
  assert(index.includes('CONFIG_DEPLOYMENT_SALT = "0x456";'));
  assert(!index.includes("current Core"));
  assert(!index.includes("never-copy-r3"));
});
for (const [name, extra, omitted] of [
  ["empty original address", "CORE_CONTRACT_ADDRESS=", []],
  ["short original address", "CORE_CONTRACT_ADDRESS=0x123", []],
  ["nonhex original address", `CORE_CONTRACT_ADDRESS=0x${"g".repeat(64)}`, []],
  [
    "out-of-field original address",
    `CORE_CONTRACT_ADDRESS=0x${"f".repeat(64)}`,
    [],
  ],
  ...ADDITIVE_ADDRESS_KEYS.map((key) => [
    `invalid optional ${key}`,
    `${key}=bad`,
    [],
  ]),
  ["invalid supplied deployer", "CORE_DEPLOYER_ADDRESS=0x123", []],
  ["invalid account", "ACCOUNT_ADDRESS=nope", []],
  ["missing account", "", ["ACCOUNT_ADDRESS"]],
  ["missing start block", "", ["START_BLOCK"]],
  ["negative start block", "START_BLOCK=-1", []],
  ["fractional start block", "START_BLOCK=1.2", []],
  ["unsafe start block", "START_BLOCK=9007199254740992", []],
  ["invalid export identifier", `bad.key_CONTRACT_ADDRESS=${address(1)}`, []],
])
  test(`${name} rejects before either client output changes`, async (t) => {
    const f = fixture(t);
    fs.writeFileSync(f.options.envPath, completeEnvironment(extra, omitted));
    await assert.rejects(syncClientDeployment(f.options));
    f.unchanged();
    assert.deepEqual(fs.readdirSync(f.parent).sort(), [
      "artifacts",
      "index.ts",
    ]);
  });
test("SDK-representable zero/full-range/unprefixed hex addresses remain accepted strings", () => {
  const modulus =
    21888242871839275222246405745257275088548364400416034343698204186575808495617n;
  for (const value of [
    address(0),
    address(modulus - 1n),
    address(123).slice(2),
  ]) {
    assert(AztecAddress.isAddress(value));
    AztecAddress.fromStringUnsafe(value);
    const index = generateClientIndex(
      completeEnvironment(`CORE_CONTRACT_ADDRESS=${value}\n`),
    );
    assert(index.includes(`CORE_CONTRACT_ADDRESS = "${value}";`));
  }
});
test("all current WalletManager metadata imports exist with unchanged empty-registration fallback", () => {
  const source = fs.readFileSync(
    new URL(
      "../../../client/src/Session/WalletManager/WalletManager.ts",
      import.meta.url,
    ),
    "utf8",
  );
  const names = source
    .match(/import\s*\{([^}]+)\}\s*from\s*["']@dfpunk\/contracts["']/)[1]
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  const index = generateClientIndex(completeEnvironment());
  for (const name of names)
    assert(index.includes(`export const ${name} = `), name);
  assert(source.includes("if (!deployer || !salt) continue;"));
  const missingMetadata = generateClientIndex(
    completeEnvironment(
      'CONFIG_DEPLOYER_ADDRESS=""\nCONFIG_DEPLOYMENT_SALT=""\n',
    ),
  );
  assert(missingMetadata.includes('CONFIG_DEPLOYER_ADDRESS = "";'));
  assert(missingMetadata.includes('CONFIG_DEPLOYMENT_SALT = "";'));
});
