import test from 'node:test';
import assert from 'node:assert/strict';
import {DIRECT_ROUTES, DELEGATED_ROUTES, SYSTEM_PAYLOADS, assertSettlementCoverage, assertSystemPayloads} from './trust-routes.mjs';

const fixture = () => Object.entries({...DIRECT_ROUTES, ...DELEGATED_ROUTES}).map(([name, length]) => ({
  name, parameters: [{name: 'payload', type: {kind: 'struct', fields: [
    {name: 'words', type: {kind: 'array', length, type: {kind: 'field'}}},
  ]}}],
}));
test('the complete current route inventory distinguishes direct and delegated callers', () => {
  const coverage = assertSettlementCoverage(fixture());
  assert(coverage.direct.includes('try_settle_initialize_new'));
  assert(coverage.direct.includes('try_settle_refresh_empty'));
  assert.equal(coverage.direct.length, 6);
  assert.equal(coverage.delegated.length, 2);
});
test('missing, additional, and obsolete settlement methods cannot silently pass', () => {
  assert.throws(() => assertSettlementCoverage([]));
  assert.throws(() => assertSettlementCoverage(fixture().slice(1)));
  assert.throws(() => assertSettlementCoverage([...fixture(), {...fixture()[0], name: 'try_settle_uncovered'}]));
  assert.throws(() => assertSettlementCoverage([...fixture(), {...fixture()[0], name: 'commit_initialize_new'}]));
});
test('wrong or truncated FieldBuffer schemas fail before hostile simulations start', () => {
  const functions = fixture();
  functions.find(fn => fn.name === 'try_settle_refresh_empty').parameters[0].type.fields[0].type.length = 84;
  assert.throws(() => assertSettlementCoverage(functions));
  const extra = fixture();
  extra[0].parameters.push({name: 'actor', type: {kind: 'field'}});
  assert.throws(() => assertSettlementCoverage(extra));
});

test('final Core144 and Move337 retain all fallback fields and only_self guards', () => {
  for (const [role, methods] of Object.entries(SYSTEM_PAYLOADS)) {
    const functions = Object.entries(methods).map(([name, length]) => ({
      ...fixture()[0], name, isOnlySelf: true,
      parameters: [{name: 'payload', type: {kind: 'struct', fields: [
        {name: 'words', type: {kind: 'array', length, type: {kind: 'field'}}},
      ]}}],
    }));
    assertSystemPayloads(role, functions);
    assert.throws(() => assertSystemPayloads(role, functions.slice(1)));
    const empty = functions.find(fn => /empty/.test(fn.name));
    empty.parameters[0].type.fields[0].type.length = role === 'core' ? 84 : 217;
    assert.throws(() => assertSystemPayloads(role, functions));
  }
});

import {UNIFIED_ROUTES, ROUTE_INVENTORIES, trustVersion, assertCallbackCoverage} from './trust-routes.mjs';
const versionFixture = version => Object.entries({...ROUTE_INVENTORIES[version].direct, ...ROUTE_INVENTORIES[version].delegated, ...ROUTE_INVENTORIES[version].unified}).map(([name, length]) => ({
  name, parameters: [{name: 'payload', type: {kind: 'struct', fields: [
    {name: 'words', type: {kind: 'array', length, type: {kind: 'field'}}},
  ]}}],
}));
test('provisional V5 has seven direct and two unified routes, with obsolete delegated/Tiny endpoints rejected', () => {
  const actual = versionFixture('v5');
  const coverage = assertSettlementCoverage(actual, 'v5');
  assert.equal(coverage.direct.length, 7); assert.equal(coverage.delegated.length, 0);
  assert.deepEqual(coverage.unified, Object.keys(UNIFIED_ROUTES));
  assert.throws(() => assertSettlementCoverage([...actual, versionFixture('v4').at(-1)], 'v5'));
  for(const name of ['assert_write_authorized','set_arrival_locations_max20','set_spaceship_locations_max5','set_spaceships_max5','legacy_set_root'])assert.throws(() => assertSettlementCoverage([...actual, {...actual[0],name}], 'v5'));
  assert.throws(() => assertSettlementCoverage(actual.filter(f => f.name !== 'commit_reveal'), 'v5'));
  assert.throws(() => assertSettlementCoverage([...actual, {...actual[0], name: 'commit_plan_tiny'}], 'v5'));
  actual.find(f => f.name === 'commit_reveal').parameters[0].type.fields[0].type.length = 51;
  assert.throws(() => assertSettlementCoverage(actual, 'v5'));
});
test('version labels cannot silently replay the wrong compiled route family', () => {
  for (const version of ['v4', 'v5']) {
    assert.equal(trustVersion(`candidate-${version}`, versionFixture(version)), version);
    assert.equal(trustVersion('isolated-test', versionFixture(version)), version);
  }
  assert.throws(() => trustVersion('candidate-v4', versionFixture('v5')));
  assert.throws(() => trustVersion('candidate-v5', versionFixture('v4')));
  assert.throws(() => trustVersion('custom', versionFixture('v5'), 'v6'));
});
const callbackFixture = version => [
  {name: 'emit_example_update', parameters: [{name: 'id', type: {kind: 'field'}}, {name: 'state', type: {kind: 'struct', fields: [
    {name: 'count', type: {kind: 'integer', width: 32}}, {name: 'values', type: {kind: 'array', length: 2, type: {kind: 'field'}}},
  ]}}]},
  {name: 'emit_example_fields', parameters: ['id', ...(version === 'v5' ? ['root'] : []), 'field_0', 'field_1', 'field_2'].map(name => ({name, type: {kind: 'field'}}))},
];
test('all raw callback fields and V5 authoritative root remain full-width and correctly positioned', () => {
  for (const version of ['v4', 'v5']) assert.equal(assertCallbackCoverage('example', callbackFixture(version), version).stateFields, 3);
  assert.throws(() => assertCallbackCoverage('example', callbackFixture('v4'), 'v5'));
  const truncated = callbackFixture('v5'); truncated[1].parameters.pop();
  assert.throws(() => assertCallbackCoverage('example', truncated, 'v5'));
  const narrow = callbackFixture('v5'); narrow[1].parameters[1].type = {kind: 'integer', width: 128};
  assert.throws(() => assertCallbackCoverage('example', narrow, 'v5'));
  const moved = callbackFixture('v5'); [moved[1].parameters[1], moved[1].parameters[2]] = [moved[1].parameters[2], moved[1].parameters[1]];
  assert.throws(() => assertCallbackCoverage('example', moved, 'v5'));
});
