/** Public deployment exports only; never copies account secrets. */
import assert from "node:assert/strict";
import { parse } from "dotenv";
import { AztecAddress } from "@aztec/stdlib/aztec-address";

export const ORIGINAL_CONTRACT_ADDRESS_KEYS = Object.freeze([
  "CONFIG_CONTRACT_ADDRESS",
  "WORLD_STORAGE_CONTRACT_ADDRESS",
  "PLAYER_STORAGE_CONTRACT_ADDRESS",
  "PLANET_STORAGE_CONTRACT_ADDRESS",
  "PLANET_REVEALED_COORDS_STORAGE_CONTRACT_ADDRESS",
  "PLANET_EVENTS_STORAGE_CONTRACT_ADDRESS",
  "PLANET_ARTIFACTS_STORAGE_CONTRACT_ADDRESS",
  "ARRIVAL_STORAGE_CONTRACT_ADDRESS",
  "ARTIFACT_STORAGE_CONTRACT_ADDRESS",
  "ARTIFACT_LOCATION_STORAGE_CONTRACT_ADDRESS",
  "ADMIN_CONTRACT_ADDRESS",
  "CORE_CONTRACT_ADDRESS",
  "MOVE_CONTRACT_ADDRESS",
  "ARTIFACT_ACTION_SYSTEM_CONTRACT_ADDRESS",
  "ARTIFACT_FIND_SYSTEM_CONTRACT_ADDRESS",
  "ARTIFACT_PROSPECT_SYSTEM_CONTRACT_ADDRESS",
  "ARTIFACT_VAULT_SYSTEM_CONTRACT_ADDRESS",
]);

function validateAddress(key: string, value: string): void {
  // Match the client's SDK representation: exact hex length and Fr range.
  // Curve/encryption eligibility and deployed-class identity are not established here.
  assert(AztecAddress.isAddress(value), `Invalid address: ${key}`);
  try {
    AztecAddress.fromStringUnsafe(value);
  } catch {
    throw new Error(`Invalid address: ${key}`);
  }
}

const KEY_COMMENTS: Record<string, string> = {
  ACCOUNT_ADDRESS: "The deployer account address.",
  START_BLOCK: "Block number at deployment start (from deploy script).",
  CONFIG_CONTRACT_ADDRESS: "The address for the Config contract.",
  WORLD_STORAGE_CONTRACT_ADDRESS: "The address for the WorldStorage contract.",
  PLAYER_STORAGE_CONTRACT_ADDRESS:
    "The address for the PlayerStorage contract.",
  PLANET_STORAGE_CONTRACT_ADDRESS:
    "The address for the PlanetStorage contract.",
  PLANET_REVEALED_COORDS_STORAGE_CONTRACT_ADDRESS:
    "The address for the PlanetRevealedCoordsStorage contract.",
  PLANET_EVENTS_STORAGE_CONTRACT_ADDRESS:
    "The address for the PlanetEventsStorage contract.",
  PLANET_ARTIFACTS_STORAGE_CONTRACT_ADDRESS:
    "The address for the PlanetArtifactsStorage contract.",
  ARRIVAL_STORAGE_CONTRACT_ADDRESS:
    "The address for the ArrivalStorage contract.",
  ARTIFACT_STORAGE_CONTRACT_ADDRESS:
    "The address for the ArtifactStorage contract.",
  ARTIFACT_LOCATION_STORAGE_CONTRACT_ADDRESS:
    "The address for the ArtifactLocationStorage contract.",
  ADMIN_CONTRACT_ADDRESS: "The address for the Admin contract.",
  CORE_CONTRACT_ADDRESS: "The address for the Core contract.",
  MOVE_CONTRACT_ADDRESS: "The address for the Move contract.",
  ARTIFACT_ACTION_SYSTEM_CONTRACT_ADDRESS:
    "The address for the ArtifactAction system contract.",
  ARTIFACT_FIND_SYSTEM_CONTRACT_ADDRESS:
    "The address for the ArtifactFind system contract.",
  ARTIFACT_PROSPECT_SYSTEM_CONTRACT_ADDRESS:
    "The address for the ArtifactProspect system contract.",
  ARTIFACT_VAULT_SYSTEM_CONTRACT_ADDRESS:
    "The address for the ArtifactVault system contract.",
  ARTIFACT_SYSTEM_CONTRACT_ADDRESS:
    "The address for the ArtifactSystem contract.",
  ADMIN_DEPLOYER_ADDRESS: "Deployer address for Admin (for PXE registration).",
  ADMIN_DEPLOYMENT_SALT: "Deployment salt for Admin (for PXE registration).",
  CORE_DEPLOYER_ADDRESS: "Deployer address for Core (for PXE registration).",
  CORE_DEPLOYMENT_SALT: "Deployment salt for Core (for PXE registration).",
  MOVE_DEPLOYER_ADDRESS: "Deployer address for Move (for PXE registration).",
  MOVE_DEPLOYMENT_SALT: "Deployment salt for Move (for PXE registration).",
  ARTIFACT_SYSTEM_DEPLOYER_ADDRESS:
    "Deployer address for ArtifactSystem (for PXE registration).",
  ARTIFACT_SYSTEM_DEPLOYMENT_SALT:
    "Deployment salt for ArtifactSystem (for PXE registration).",
  ARTIFACT_ACTION_SYSTEM_DEPLOYER_ADDRESS:
    "Deployer address for ArtifactAction (for PXE registration).",
  ARTIFACT_ACTION_SYSTEM_DEPLOYMENT_SALT:
    "Deployment salt for ArtifactAction (for PXE registration).",
  ARTIFACT_FIND_SYSTEM_DEPLOYER_ADDRESS:
    "Deployer address for ArtifactFind (for PXE registration).",
  ARTIFACT_FIND_SYSTEM_DEPLOYMENT_SALT:
    "Deployment salt for ArtifactFind (for PXE registration).",
  ARTIFACT_PROSPECT_SYSTEM_DEPLOYER_ADDRESS:
    "Deployer address for ArtifactProspect (for PXE registration).",
  ARTIFACT_PROSPECT_SYSTEM_DEPLOYMENT_SALT:
    "Deployment salt for ArtifactProspect (for PXE registration).",
  ARTIFACT_VAULT_SYSTEM_DEPLOYER_ADDRESS:
    "Deployer address for ArtifactVault (for PXE registration).",
  ARTIFACT_VAULT_SYSTEM_DEPLOYMENT_SALT:
    "Deployment salt for ArtifactVault (for PXE registration).",
};

export function generateClientIndex(environment: string): string {
  // Use the same installed dotenv parser as scripts/utils/env.ts, without
  // loading process.env, secrets, a wallet, or a node into this publication step.
  const environmentValues = parse(environment);
  for (const key of [
    ...ORIGINAL_CONTRACT_ADDRESS_KEYS,
    "ACCOUNT_ADDRESS",
    "START_BLOCK",
  ]) {
    assert(
      typeof environmentValues[key] === "string" &&
        environmentValues[key] !== "",
      `Missing client value: ${key}`,
    );
  }
  const values = new Map<string, string>();
  for (const [key, value] of Object.entries(environmentValues)) {
    if (
      key !== "ACCOUNT_ADDRESS" &&
      key !== "START_BLOCK" &&
      !key.endsWith("_CONTRACT_ADDRESS") &&
      !key.endsWith("_DEPLOYER_ADDRESS") &&
      !key.endsWith("_DEPLOYMENT_SALT")
    )
      continue;
    assert(
      /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(key),
      `Invalid client export name: ${key}`,
    );
    if (
      key === "ACCOUNT_ADDRESS" ||
      key.endsWith("_CONTRACT_ADDRESS") ||
      (key.endsWith("_DEPLOYER_ADDRESS") && value !== "")
    )
      validateAddress(key, value);
    values.set(key, value);
  }
  const block = values.get("START_BLOCK")!;
  assert(
    /^\d+$/.test(block) &&
      Number.isSafeInteger(Number(block)) &&
      Number(block) >= 0,
    "Invalid START_BLOCK: expected a nonnegative safe integer",
  );
  // WalletManager imports all original deployer/salt names, and deliberately
  // skips registration when either value is empty. Keep that fallback available.
  for (const key of ORIGINAL_CONTRACT_ADDRESS_KEYS) {
    const prefix = key.slice(0, -"_CONTRACT_ADDRESS".length);
    for (const suffix of ["_DEPLOYER_ADDRESS", "_DEPLOYMENT_SALT"]) {
      if (!values.has(prefix + suffix)) values.set(prefix + suffix, "");
    }
  }
  const format = (key: string, value: string): string =>
    key === "START_BLOCK" ? String(Number(value)) : JSON.stringify(value);
  const lines = [
    "",
    "/**",
    " * ACCOUNT_ADDRESS, START_BLOCK, and contract addresses. Generated from the resolved contracts env file by sync-env-and-artifacts.ts",
    " */",
    "",
  ];
  for (const [key, value] of [...values].sort(([a], [b]) =>
    a.localeCompare(b),
  )) {
    lines.push(
      "/**",
      ` * ${KEY_COMMENTS[key] ?? key}`,
      " */",
      `export const ${key} = ${format(key, value)};`,
      "",
    );
  }
  return lines.join("\n").trimEnd() + "\n";
}
