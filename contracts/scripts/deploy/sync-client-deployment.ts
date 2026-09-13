import { adaptCheckedArtifactWrapper } from '../dev/api-compatible-build/wrapper-compatibility.ts';
/** Verify and publish the local client address/artifact pair. No wallet or node. */
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";

export const CONTRACT_FILES = Object.freeze({
  Config: "config-Config.json",
  WorldStorage: "world-WorldStorage.json",
  PlayerStorage: "player-PlayerStorage.json",
  PlanetStorage: "planet-PlanetStorage.json",
  PlanetRevealedCoordsStorage:
    "planet_revealed_coords-PlanetRevealedCoordsStorage.json",
  PlanetEventsStorage: "planet_events-PlanetEventsStorage.json",
  PlanetArtifactsStorage: "planet_artifacts-PlanetArtifactsStorage.json",
  ArrivalStorage: "arrival-ArrivalStorage.json",
  ArtifactStorage: "artifact-ArtifactStorage.json",
  ArtifactLocationStorage: "artifact_location-ArtifactLocationStorage.json",
  Admin: "admin-Admin.json",
  Core: "core-Core.json",
  Move: "move-Move.json",
  ArtifactAction: "artifact_action-ArtifactAction.json",
  ArtifactFind: "artifact_find-ArtifactFind.json",
  ArtifactProspect: "artifact_prospect-ArtifactProspect.json",
  ArtifactValut: "artifact_valut-ArtifactValut.json",
  CoreSettlementWorker: "core_settlement_worker-CoreSettlementWorker.json",
  VaultSettlementWorker: "vault_settlement_worker-VaultSettlementWorker.json",
  GameStateBackend: "game_state_backend-GameStateBackend.json",
});

export type SyncOptions = {
  repositoryRoot: string;
  manifestPath: string;
  envPath: string;
  indexPath: string;
  artifactsSource: string;
  artifactsDestination: string;
  generateIndex: (environment: string) => string;
  generateWrapper: (
    rawArtifact: string,
    importPath: string,
  ) => Promise<{ name: string; source: string }>;
  fileSystem?: typeof fs;
};

type BuildManifest = {
  passed: boolean;
  proofsGenerated: number;
  newKeysGenerated: number;
  secondIdentityPass: number;
  sourceFiles: Record<string, string>;
  privateMethods: Record<string, unknown[]>;
  classIds: Record<string, string>;
  artifacts: Array<{ file: string; sha256: string; classId: string }>;
};
const digest = (bytes: Buffer) =>
  createHash("sha256").update(bytes).digest("hex");
const validHash = (value: string) => /^[a-f0-9]{64}$/.test(value);

export async function syncClientDeployment(
  options: SyncOptions,
): Promise<{ contracts: number; files: number }> {
  const io = options.fileSystem ?? fs;
  const regular = (file: string): Buffer => {
    const stat = io.lstatSync(file);
    assert(
      stat.isFile() && !stat.isSymbolicLink(),
      `Expected regular file: ${file}`,
    );
    return io.readFileSync(file);
  };
  const manifest = JSON.parse(
    regular(options.manifestPath).toString(),
  ) as BuildManifest;
  assert(manifest.passed, "Native build did not pass");
  assert.equal(manifest.proofsGenerated, 0);
  assert.equal(manifest.newKeysGenerated, 0);
  assert.equal(manifest.secondIdentityPass, 19);
  assert.equal(
    Object.values(manifest.privateMethods).reduce(
      (n, rows) => n + rows.length,
      0,
    ),
    14,
  );
  assert.equal(Object.keys(manifest.sourceFiles).length, 349);
  for (const [relative, expected] of Object.entries(manifest.sourceFiles)) {
    assert(
      !path.isAbsolute(relative) && !relative.split(/[\\/]/).includes(".."),
      "Invalid source path",
    );
    assert(validHash(expected));
    assert.equal(
      digest(regular(path.join(options.repositoryRoot, relative))),
      expected,
      `Source changed: ${relative}`,
    );
  }
  const expectedFiles = Object.values(CONTRACT_FILES).sort();
  assert.deepEqual(
    manifest.artifacts.map((row) => row.file).sort(),
    expectedFiles,
    "Exactly twenty checked artifacts required",
  );
  const stagedFiles = new Map<string, Buffer>();
  for (const row of manifest.artifacts) {
    assert.equal(path.basename(row.file), row.file);
    assert(validHash(row.sha256));
    assert.match(row.classId, /^0x[0-9a-f]+$/i);
    assert.equal(manifest.classIds[row.file], row.classId);
    const bytes = regular(path.join(options.artifactsSource, row.file));
    assert.equal(digest(bytes), row.sha256, `Artifact changed: ${row.file}`);
    assert.equal(
      JSON.parse(bytes.toString()).transpiled,
      true,
      `Native artifact required: ${row.file}`,
    );
    const generated = await options.generateWrapper(
      bytes.toString(),
      `./${row.file}`,
    );
    assert.equal(
      CONTRACT_FILES[generated.name as keyof typeof CONTRACT_FILES],
      row.file,
      "Unexpected contract identity",
    );
    const wrapperName = `${generated.name}.ts`;
    const wrapper = Buffer.from(adaptCheckedArtifactWrapper(generated.source, generated.name));
    assert(
      regular(path.join(options.artifactsSource, wrapperName)).equals(wrapper),
      `Stale generated interface: ${generated.name}`,
    );
    stagedFiles.set(row.file, bytes);
    assert(!stagedFiles.has(wrapperName), "Duplicate interface");
    stagedFiles.set(wrapperName, wrapper);
  }
  assert.equal(stagedFiles.size, 40);
  assert.deepEqual(
    io.readdirSync(options.artifactsSource).sort(),
    [...stagedFiles.keys()].sort(),
    "Unexpected files in checked artifact source",
  );
  const indexBytes = Buffer.from(
    options.generateIndex(io.readFileSync(options.envPath).toString()),
  );
  const parent = path.dirname(options.indexPath);
  assert.equal(
    path.dirname(options.artifactsDestination),
    parent,
    "Client outputs must share one parent",
  );
  for (const destination of [options.indexPath, options.artifactsDestination]) {
    if (io.existsSync(destination))
      assert(
        !io.lstatSync(destination).isSymbolicLink(),
        "Client destination must not be a symlink",
      );
  }
  // All provenance and interface validation above completes before any write.
  io.mkdirSync(parent, { recursive: true });
  const temporary = io.mkdtempSync(path.join(parent, ".client-sync-"));
  const nextArtifacts = path.join(temporary, "artifacts-next");
  const nextIndex = path.join(temporary, "index-next");
  const entries = [
    {
      destination: options.artifactsDestination,
      next: nextArtifacts,
      previous: path.join(temporary, "artifacts-previous"),
      backedUp: false,
      installed: false,
    },
    {
      destination: options.indexPath,
      next: nextIndex,
      previous: path.join(temporary, "index-previous"),
      backedUp: false,
      installed: false,
    },
  ];
  let retainRecovery = false;
  try {
    io.mkdirSync(nextArtifacts);
    for (const [name, bytes] of stagedFiles) {
      io.writeFileSync(path.join(nextArtifacts, name), bytes);
      assert(regular(path.join(nextArtifacts, name)).equals(bytes));
    }
    io.writeFileSync(nextIndex, indexBytes);
    assert(regular(nextIndex).equals(indexBytes));
    for (const entry of entries) {
      if (io.existsSync(entry.destination)) {
        io.renameSync(entry.destination, entry.previous);
        entry.backedUp = true;
      }
    }
    for (const entry of entries) {
      io.renameSync(entry.next, entry.destination);
      entry.installed = true;
    }
    assert(regular(options.indexPath).equals(indexBytes));
    for (const [name, bytes] of stagedFiles)
      assert(
        regular(path.join(options.artifactsDestination, name)).equals(bytes),
      );
  } catch (error) {
    const recoveryErrors: unknown[] = [];
    for (const entry of [...entries].reverse()) {
      try {
        if (entry.installed) io.rmSync(entry.destination, { recursive: true });
        if (entry.backedUp) io.renameSync(entry.previous, entry.destination);
      } catch (recoveryError) {
        recoveryErrors.push(recoveryError);
      }
    }
    if (recoveryErrors.length) {
      retainRecovery = true;
      const failure = new Error(
        `Client sync failed and recovery needs attention; previous outputs retained at ${temporary}`,
      );
      Object.assign(failure, { cause: error, recoveryErrors });
      throw failure;
    }
    throw error;
  } finally {
    if (!retainRecovery) io.rmSync(temporary, { recursive: true, force: true });
  }
  return { contracts: manifest.artifacts.length, files: stagedFiles.size };
}
