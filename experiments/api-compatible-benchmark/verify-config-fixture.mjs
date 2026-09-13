import fs from 'node:fs';
import assert from 'node:assert/strict';
import {Contract} from '@aztec/aztec.js/contracts';
import {AztecAddress} from '@aztec/aztec.js/addresses';
import {loadContractArtifact} from '@aztec/stdlib/abi';
import {openRuntime,stateDirectory,resultsDirectory} from './runtime.mjs';
import {json} from './fixtures.mjs';

const baseline=process.argv[2]??'baseline-v2',candidate=process.argv[3]??'candidate-v2';
const runtime=await openRuntime(candidate,process.argv[4]??'/tmp/df-api-compatible-v2-native');
const beforeAddress=AztecAddress.fromStringUnsafe(JSON.parse(fs.readFileSync(new URL(`${baseline}-deployments.json`,stateDirectory))).config);
const original=loadContractArtifact(JSON.parse(fs.readFileSync('/tmp/df-fee-tools/artifacts/baseline/config-Config.json')));
await runtime.wallet.registerContract(await runtime.node.getContract(beforeAddress),original);
const before=await Contract.at(beforeAddress,original,runtime.wallet),after=runtime.contracts.config;
const specs=['snark_config','world_config','game_config_core','planet_level_thresholds','space_junk_config','artifacts_config','spaceships_config','upgrade_config'].map(name=>[`get_${name}`,[]]);
for(let tier=0;tier<4;tier++)specs.push(['get_planet_type_weights_tier',[BigInt(tier)]]);
for(let level=0;level<4;level++)specs.push(['get_planet_default_stats',[BigInt(level)]]);
for(let branch=0;branch<3;branch++)specs.push(['get_upgrade_by_branch_level',[BigInt(branch),0n]]);
const checks=[];
try{
 for(const [method,args] of specs){
  const oldPublic=(await before.methods[method](...args).simulate(runtime.opts)).result;
  const newPublic=(await after.methods[method](...args).simulate(runtime.opts)).result;
  const oldUtility=(await before.methods[`${method}_unconstrained`](...args).simulate(runtime.opts)).result;
  const newUtility=(await after.methods[`${method}_unconstrained`](...args).simulate(runtime.opts)).result;
  assert.equal(json(newPublic),json(oldPublic),`${method}: complete typed configuration differs`);
  assert.equal(json(oldUtility),json(oldPublic),`${method}: original utility differs from public getter`);
  assert.equal(json(newUtility),json(newPublic),`${method}: candidate utility differs from public getter`);
  checks.push({method,args,exactOriginalTypedValue:true,publicAndUtilityEqual:true});
 }
 const report={baseline,candidate,transactionsSent:0,checkedAtBlock:await runtime.node.getBlockNumber(),checks};
 fs.writeFileSync(new URL(`config-fixture-${candidate}.json`,resultsDirectory),json(report));
 console.log(JSON.stringify({candidate,exactTypedConfigPairs:checks.length,transactionsSent:0}));
}finally{await runtime.close();}
