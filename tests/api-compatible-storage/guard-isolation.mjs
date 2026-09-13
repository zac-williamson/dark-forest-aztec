import assert from 'node:assert/strict';
import {simulateViaNode} from '@aztec/wallet-sdk/base-wallet';
import {GasFees, GasSettings} from '@aztec/stdlib/gas';

// Deliberately isolates the public AVM guard with a supplied existing contract
// msg_sender. The SDK constructs an empty-proof simulated execution. This is
// never submitted and is NOT a valid account transaction or proof/fee evidence.
// Real private-entry transactions separately test the legitimate caller path.
export async function simulateGuardWithInjectedSender({node, wallet, interaction, sender}) {
  const payload = await interaction.request();
  assert.equal(payload.calls.length, 1, 'Guard isolation accepts one public call');
  assert.equal(payload.calls[0].type, 'public', 'Guard isolation must not execute private or utility code');
  assert.equal(payload.authWitnesses.length, 0, 'Guard isolation carries no authorization witnesses');
  const chainInfo = await wallet.getChainInfo();
  const block = await node.getBlock('latest');
  assert(block, 'Guard isolation needs an actual canonical anchor');
  return simulateViaNode(node, payload.calls, sender, chainInfo,
    GasSettings.forEstimation({maxFeesPerGas: new GasFees(0n, 100000000000000n)}),
    block.header, true, async () => undefined);
}
