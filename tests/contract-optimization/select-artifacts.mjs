import assert from "node:assert/strict";
import { lstat, mkdir, realpath, symlink, unlink } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));
const source = await realpath(
  process.argv[2] ?? path.join(root, "../../contracts/target"),
);
const folder = path.join(root, "artifacts");
const target = path.join(folder, "target");
await mkdir(folder, { recursive: true });
const existing = await lstat(target).catch((error) => {
  if (error.code !== "ENOENT") throw error;
});
if (existing) {
  assert(
    existing.isSymbolicLink(),
    `Refusing to replace a real directory: ${target}`,
  );
  await unlink(target);
}
await symlink(source, target, "dir");
console.log(`Contract test artifacts: ${source}`);
