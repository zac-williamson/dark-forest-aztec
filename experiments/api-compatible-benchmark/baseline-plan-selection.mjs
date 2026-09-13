import assert from 'node:assert/strict';

export function baselinePlanModule(candidate){
  const version=/^candidate-v([56])(?:-[a-z0-9_-]+)?$/.exec(candidate??'')?.[1];
  assert(version,'Cached-original preflight requires an explicit supported V5/V6 candidate');
  return `./run-plan-v${version}.mjs`;
}
