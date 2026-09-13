import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';

// Every suite uses its own fresh PXE; this configuration never shares the fee
// runner's mutable wallet directory. Explicit old JSON paths remain supported.
export function storageInvocation(reportName,argv=process.argv.slice(2),env=process.env){
  // Bound lazy native SDK workers as well as the outer launch environment.
  // All runtime entry points call this before creating a PXE or hashing classes.
  process.env.RAYON_NUM_THREADS='2';process.env.HARDWARE_CONCURRENCY='2';
  const root=fileURLToPath(new URL('../../',import.meta.url));
  const firstIsVariant=argv[0]&&/^[a-z0-9_-]+$/.test(argv[0]);
  const variant=(firstIsVariant?argv[0]:undefined)??env.STORAGE_VARIANT??'candidate-v4';
  assert(/^[a-z0-9_-]+$/.test(variant),'Invalid storage deployment variant');
  const deployment=path.resolve((firstIsVariant?undefined:argv[0])??env.STORAGE_DEPLOYMENTS??
    path.join(root,'experiments/api-compatible-benchmark/.state',`${variant}-deployments.json`));
  const artifacts=path.resolve(argv[1]??env.STORAGE_ARTIFACTS??'/tmp/df-api-compatible-v4-native');
  const output=path.resolve(argv[2]??env.STORAGE_OUTPUT??
    path.join(root,'docs/api-compatibility',`${reportName}-${variant}.json`));
  return {variant,deployment,artifacts,output,nodeUrl:env.AZTEC_NODE_URL??'http://127.0.0.1:8097'};
}
