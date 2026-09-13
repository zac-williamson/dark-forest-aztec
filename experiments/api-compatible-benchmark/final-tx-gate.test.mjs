import test from 'node:test';
import assert from 'node:assert/strict';
import {Buffer} from 'node:buffer';
import {createFinalTxGate} from './final-tx-gate.mjs';

function fixture({simulate, send, gas = {daGas: 23, l2Gas: 9007199254740993n}} = {}) {
  const events = [];
  const hash = {toString: () => '0x0123'};
  const tx = {bytes: Buffer.from('exact final transaction'), getTxHash: () => hash,
    toBuffer() { return this.bytes; }};
  const output = {txEffect: {txHash: hash, revertCode: {isOK: () => true}, changes: ['original state']},
    gasUsed: {billedGas: gas}};
  const node = {
    marker: 'original node',
    async simulatePublicCalls(actual, skipFeeEnforcement) {
      assert.equal(this, node);assert.equal(actual, tx);assert.equal(skipFeeEnforcement, false);
      events.push('simulate');
      return simulate ? await simulate(actual, output) : output;
    },
    async sendTx(actual) {
      assert.equal(this, node);assert.equal(actual, tx);events.push('send');
      return send ? await send(actual) : 'sent result';
    },
    getMarker() { assert.equal(this, node);return this.marker; },
    get label() { assert.equal(this, node);return this.marker; },
  };
  return {tx, hash, output, events, node, gate: createFinalTxGate(node)};
}

test('Unarmed setup passes through without simulation and other node methods retain this', async () => {
  const f = fixture();
  assert.equal(await f.gate.node.sendTx(f.tx), 'sent result');
  assert.deepEqual(f.events, ['send']);
  const read = f.gate.node.getMarker;
  assert.equal(read(), 'original node');assert.equal(f.gate.node.label, 'original node');
  assert.equal(f.gate.node.getMarker, read);assert.equal(f.gate.disarm(), undefined);
});

test('Actual final tx and hash are checked, journaled, and forwarded once with exact BigInt billed gas', async () => {
  const f = fixture();let captured;
  f.gate.arm({beforeSend: async result => {
    captured = result;
    assert.equal(result.tx, f.tx);assert.equal(result.hash, f.hash);assert.equal(result.publicOutput, f.output);
    assert.deepEqual(result.publicOutput.txEffect.changes, ['original state']);f.events.push('validate');
    assert.deepEqual(result.billedGas, {daGas: 23n, l2Gas: 9007199254740993n});
    assert.equal(result.billedGas.daGas * 5n + result.billedGas.l2Gas * 7n, 63050394783187066n);
    assert.throws(() => { result.billedGas.l2Gas = 0n; }, TypeError);
    f.events.push('journal');
  }});
  assert.equal(await f.gate.node.sendTx(f.tx), 'sent result');
  assert.deepEqual(f.events, ['simulate', 'validate', 'journal', 'send']);
  await assert.rejects(f.gate.node.sendTx(f.tx), /already consumed/);
  assert.deepEqual(f.events, ['simulate', 'validate', 'journal', 'send']);
  assert.equal(f.gate.disarm(), captured);
});

test('Public revert reason or revert code rejects before validation, journaling, or forwarding', async () => {
  for (const change of [o => { o.revertReason = Error('reverted'); },
    o => { o.txEffect.revertCode.isOK = () => false; }, o => { delete o.txEffect.revertCode; }]) {
    const f = fixture({simulate: (_, output) => { change(output);return output; }});
    f.gate.arm({beforeSend: () => assert.fail('must not validate a reverted transaction')});
    await assert.rejects(f.gate.node.sendTx(f.tx), /simulation/);
    assert.deepEqual(f.events, ['simulate']);
  }
});

test('Effect mismatch or journal failure never forwards and cannot implicitly retry', async () => {
  for (const phase of ['effect mismatch', 'journal failure']) {
    const f = fixture();
    f.gate.arm({beforeSend: () => { f.events.push(phase);throw Error(phase); }});
    await assert.rejects(f.gate.node.sendTx(f.tx), new RegExp(phase));
    await assert.rejects(f.gate.node.sendTx(f.tx), /already consumed/);
    assert.deepEqual(f.events, ['simulate', phase]);
  }
});

test('Simulation error and malformed effect identity never forward', async () => {
  for (const simulate of [() => { throw Error('node simulation failed'); },
    (_, output) => { output.txEffect.txHash = {toString: () => 'different'};return output; }]) {
    const f = fixture({simulate});
    f.gate.arm({beforeSend: () => assert.fail('invalid simulation must not reach the journal')});
    await assert.rejects(f.gate.node.sendTx(f.tx), /simulation failed|different hash/);
    assert.deepEqual(f.events, ['simulate']);
  }
});

test('Mutating final transaction bytes during simulation or journal fails closed', async () => {
  for (const phase of ['simulation', 'journal']) {
    const f = fixture({simulate: (tx, output) => {
      if (phase === 'simulation') tx.bytes[0] ^= 1;
      return output;
    }});
    f.gate.arm({beforeSend: ({tx}) => { tx.bytes[0] ^= 1; }});
    await assert.rejects(f.gate.node.sendTx(f.tx), /bytes changed/);
    assert.deepEqual(f.events, ['simulate']);
  }
});

test('Unsafe or negative billed gas is rejected without rounding or forwarding', async () => {
  for (const gas of [{daGas: -1, l2Gas: 1}, {daGas: 1, l2Gas: Number.MAX_SAFE_INTEGER + 1},
    {daGas: 1, l2Gas: 1.5}, {daGas: 1, l2Gas: '1'}, {daGas: 1, l2Gas: -1n}]) {
    const f = fixture({gas});
    f.gate.arm({beforeSend: () => assert.fail('invalid gas must not reach validation')});
    await assert.rejects(f.gate.node.sendTx(f.tx), /exact integer|nonnegative/);
    assert.deepEqual(f.events, ['simulate']);
  }
});

test('An uncertain broadcast is attempted once and retains exact journal context', async () => {
  const f = fixture({send: () => { throw Error('connection lost after send'); }});let captured;
  f.gate.arm({beforeSend: result => { captured = result;f.events.push('journal'); }});
  await assert.rejects(f.gate.node.sendTx(f.tx), /connection lost/);
  await assert.rejects(f.gate.node.sendTx(f.tx), /already consumed/);
  assert.deepEqual(f.events, ['simulate', 'journal', 'send']);
  assert.equal(f.gate.disarm(), captured);
});

test('A gate cannot be replaced, disarmed, or consumed concurrently while a send is pending', async () => {
  let release;
  const held = new Promise(resolve => { release = resolve; });
  const f = fixture({simulate: async (_, output) => { await held;return output; }});
  f.gate.arm({beforeSend: () => {}});
  const sending = f.gate.node.sendTx(f.tx);
  assert.throws(() => f.gate.arm({beforeSend: () => {}}), /already armed/);
  assert.throws(() => f.gate.disarm(), /during a send/);
  await assert.rejects(f.gate.node.sendTx(f.tx), /already consumed/);
  release();await sending;
  assert.deepEqual(f.events, ['simulate', 'send']);f.gate.disarm();
  assert.throws(() => f.gate.arm(), /validation is required/);
});

test('A gameplay gate cannot begin during an unarmed setup send', async () => {
  let release;
  const held = new Promise(resolve => { release = resolve; });
  const f = fixture({send: () => held});
  const sending = f.gate.node.sendTx(f.tx);
  assert.throws(() => f.gate.arm({beforeSend: () => {}}), /during a setup send/);
  release();await sending;
  f.gate.arm({beforeSend: () => {}});f.gate.disarm();
});
