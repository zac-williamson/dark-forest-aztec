import assert from 'node:assert/strict';
import {Buffer} from 'node:buffer';

function exactGas(value, name) {
  assert(typeof value === 'bigint' || (typeof value === 'number' && Number.isSafeInteger(value)),
    `Final transaction ${name} must be an exact integer`);
  const gas = BigInt(value);
  assert(gas >= 0n, `Final transaction ${name} must be nonnegative`);
  return gas;
}

/**
 * Node adapter for the opt-in V6 benchmark, supplied to EmbeddedWallet.create.
 * Unarmed setup sends pass through. An armed gameplay send validates the actual
 * final transaction before broadcasting it, without another private execution.
 * This does not bypass the wallet's estimation, authorization, or finalization.
 *
 * beforeSend must check prospective effects/fees and then journal the transaction.
 * It must throw on any failure. A failed or completed gate is deliberately not
 * reusable: reconcile an uncertain send before explicitly disarming/rearming.
 */
export function createFinalTxGate(node) {
  assert.equal(typeof node?.sendTx, 'function', 'AztecNode.sendTx is required');
  assert.equal(typeof node?.simulatePublicCalls, 'function', 'AztecNode.simulatePublicCalls is required');
  const send = node.sendTx.bind(node);
  const simulate = node.simulatePublicCalls.bind(node);
  const boundMethods = new WeakMap();
  let active;
  let setupSends = 0;

  async function sendTx(tx) {
    const gate = active;
    if (!gate) {
      setupSends++;
      try { return await send(tx); }
      finally { setupSends--; }
    }
    assert.equal(gate.phase, 'armed', 'Final transaction gate already consumed; reconcile before rearming');
    gate.phase = 'pending';
    try {
      const hash = tx.getTxHash();
      const hashString = hash.toString();
      const bytes = Buffer.from(tx.toBuffer());
      const assertUnchanged = () => {
        assert.equal(tx.getTxHash().toString(), hashString, 'Final transaction hash changed before broadcast');
        assert.deepEqual(Buffer.from(tx.toBuffer()), bytes, 'Final transaction bytes changed before broadcast');
      };
      const publicOutput = await simulate(tx, false);
      assertUnchanged();
      assert(!publicOutput?.revertReason, 'Final transaction public simulation reverted');
      assert.equal(publicOutput?.txEffect?.revertCode?.isOK?.(), true,
        'Final transaction public simulation must have a successful effect');
      assert.equal(publicOutput.txEffect.txHash?.toString(), hashString,
        'Final transaction simulated effect has a different hash');
      const billedGas = Object.freeze({
        daGas: exactGas(publicOutput.gasUsed?.billedGas?.daGas, 'billed DA gas'),
        l2Gas: exactGas(publicOutput.gasUsed?.billedGas?.l2Gas, 'billed L2 gas'),
      });
      const result = Object.freeze({tx, hash, publicOutput, billedGas});
      await gate.beforeSend(result);
      assertUnchanged();
      // This assignment precedes the only broadcast attempt, so a send error
      // cannot turn into an automatic second submission through this gate.
      gate.result = result;
      const sent = await send(tx);
      gate.phase = 'sent';
      return sent;
    } catch (error) {
      gate.phase = 'failed';
      throw error;
    }
  }

  const adapter = new Proxy(node, {
    get(target, property) {
      if (property === 'sendTx') return sendTx;
      const value = Reflect.get(target, property, target);
      if (typeof value !== 'function') return value;
      if (!boundMethods.has(value)) boundMethods.set(value, value.bind(target));
      return boundMethods.get(value);
    },
  });

  return Object.freeze({
    node: adapter,
    arm({beforeSend} = {}) {
      assert(!active, 'Final transaction gate is already armed');
      assert.equal(setupSends, 0, 'Cannot arm a gameplay gate during a setup send');
      assert.equal(typeof beforeSend, 'function', 'Final transaction beforeSend validation is required');
      active = {beforeSend, phase: 'armed', result: undefined};
    },
    disarm() {
      assert(active?.phase !== 'pending', 'Cannot disarm a final transaction gate during a send');
      const result = active?.result;
      active = undefined;
      return result;
    },
  });
}
