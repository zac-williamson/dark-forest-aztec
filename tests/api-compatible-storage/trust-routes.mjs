import assert from 'node:assert/strict';

// Explicit versioned inventories prevent an added trust boundary from silently
// disappearing behind dynamic method discovery. Frozen V4 remains replayable.
const SPECIALIZED = Object.freeze({
  try_settle_move_move: 549,
  try_settle_move_move_empty: 227,
  try_settle_initialize_new: 60,
  try_settle_refresh_empty: 88,
});
export const DIRECT_ROUTES = Object.freeze({...SPECIALIZED, commit_plan_small: 141, commit_plan: 397});
export const DELEGATED_ROUTES = Object.freeze({commit_plan_small_for_system: 141, commit_plan_for_system: 397});
// Provisional V5 inventory: validated again against the final genuine artifact.
export const UNIFIED_ROUTES = Object.freeze({commit_plan_small: 141, commit_plan: 397});
export const V5_REMOVED_METHODS = Object.freeze(['commit_plan_tiny','commit_plan_small_for_system','commit_plan_for_system',
  'legacy_set_root','assert_write_authorized','set_arrival_locations_max20','set_spaceship_locations_max5','set_spaceships_max5']);
export const ROUTE_INVENTORIES = Object.freeze({
  v4: {direct: DIRECT_ROUTES, delegated: DELEGATED_ROUTES, unified: {}},
  v5: {direct: {...SPECIALIZED, commit_reveal: 52, commit_owner: 35, try_settle_give_spaceships: 186}, delegated: {}, unified: UNIFIED_ROUTES},
});
export const SYSTEM_PAYLOADS = Object.freeze({
  core: {initialize_player_new_public_prepared: 56, refresh_planet_empty_public_prepared: 144},
  move: {move_public_prepared: 539, move_public_empty_prepared: 337},
});

export function trustVersion(variant, functions, explicit) {
  const labelled = String(variant).match(/(?:^|-)v([45])(?:$|-)/)?.[1];
  const detected = functions.some(fn => ['commit_reveal','commit_owner','commit_plan_tiny'].includes(fn.name)) ? 'v5' : 'v4';
  const selected = explicit ?? (labelled ? `v${labelled}` : detected);
  assert(ROUTE_INVENTORIES[selected], `Unknown trust inventory ${selected}`);
  assert.equal(selected, detected, 'Variant trust inventory must match its actual compiled endpoints');
  return selected;
}

function assertBuffer(fn, width) {
  assert.equal(fn.parameters.length, 1, `${fn.name} must retain its single typed payload`);
  const payload = fn.parameters[0].type;
  assert.equal(payload.kind, 'struct', `${fn.name} must use FieldBuffer`);
  assert.deepEqual(payload.fields.map(field => field.name), ['words']);
  assert.equal(payload.fields[0].type.kind, 'array');
  assert.equal(payload.fields[0].type.length, width, `${fn.name} payload width changed`);
  assert.equal(payload.fields[0].type.type.kind, 'field');
}

export function assertSystemPayloads(role, functions) {
  assert(SYSTEM_PAYLOADS[role], `No prepared-payload inventory for ${role}`);
  for (const [name, width] of Object.entries(SYSTEM_PAYLOADS[role])) {
    const matches = functions.filter(fn => fn.name === name);
    assert.equal(matches.length, 1, `${role}.${name} must appear exactly once`);
    assert.equal(matches[0].isOnlySelf, true, `${role}.${name} must retain only_self`);
    assertBuffer(matches[0], width);
  }
}

export function assertSettlementCoverage(functions, version = 'v4') {
  const inventory = ROUTE_INVENTORIES[version];
  assert(inventory, `Unknown trust inventory ${version}`);
  if(version==='v5')for(const name of V5_REMOVED_METHODS)
    assert(!functions.some(fn=>fn.name===name),`V5 must not retain obsolete Backend endpoint ${name}`);
  const actual = functions.filter(fn => /^(?:try_settle_|commit_)/.test(fn.name));
  const expected = {...inventory.direct, ...inventory.delegated, ...inventory.unified};
  assert.deepEqual(actual.map(fn => fn.name).sort(), Object.keys(expected).sort(),
    'Every compiled settlement trust boundary must have a nonvacuous hostile test');
  for (const fn of actual) assertBuffer(fn, expected[fn.name]);
  return {version, direct: Object.keys(inventory.direct), delegated: Object.keys(inventory.delegated), unified: Object.keys(inventory.unified)};
}

function fieldWidth(type) {
  if (type.kind === 'array') return type.length * fieldWidth(type.type);
  if (type.kind === 'struct') return type.fields.reduce((n, field) => n + fieldWidth(field.type), 0);
  assert(['field', 'integer', 'boolean'].includes(type.kind), `Unrecognized callback scalar ${type.kind}`);
  return 1;
}
export function assertCallbackCoverage(role, functions, version) {
  assert(ROUTE_INVENTORIES[version], `Unknown trust inventory ${version}`);
  const typedName = `emit_${role}_update`, rawName = `emit_${role}_fields`;
  const typed = functions.filter(fn => fn.name === typedName), raw = functions.filter(fn => fn.name === rawName);
  assert.equal(typed.length, 1); assert.equal(raw.length, 1);
  assert.equal(typed[0].parameters.length, 2, 'Original typed callback must retain key and state');
  const stateFields = fieldWidth(typed[0].parameters[1].type);
  const expectedNames = ['id', ...(version === 'v5' ? ['root'] : []), ...Array.from({length: stateFields}, (_, i) => `field_${i}`)];
  assert.deepEqual(raw[0].parameters.map(p => p.name), expectedNames, `${role} raw callback root position must match ${version}`);
  assert.equal(fieldWidth(typed[0].parameters[0].type), 1, 'Callback key must occupy exactly one Field');
  for (const parameter of raw[0].parameters) assert.equal(parameter.type.kind, 'field', 'Every raw callback scalar, including key and root, must retain the full Field range');
  return {typed: typedName, raw: rawName, stateFields, rootInRawCallback: version === 'v5'};
}
