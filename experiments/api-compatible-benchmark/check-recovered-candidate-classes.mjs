import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createAztecNodeClient} from '@aztec/aztec.js/node';
import {AztecAddress} from '@aztec/aztec.js/addresses';
const node=createAztecNodeClient('http://127.0.0.1:8097'),classes=[];
const deadline=setTimeout(()=>process.exit(1),45000);
for(const variant of ['candidate-v2','candidate-v3']){
  const native=`/tmp/df-api-compatible-${variant.slice('candidate-'.length)}-native`;
  const manifest=JSON.parse(fs.readFileSync(`${native}/build-provenance.json`));assert(manifest.passed);
  const addresses=JSON.parse(fs.readFileSync(new URL(`.state/${variant}-deployments.json`,import.meta.url)));
  for(const artifact of manifest.artifacts){
    assert.equal(createHash('sha256').update(fs.readFileSync(`${native}/${artifact.file}`)).digest('hex'),artifact.sha256);
    const role=artifact.file.startsWith('game_state_backend-')?'backend':artifact.file.split('-')[0];
    const live=await node.getContract(AztecAddress.fromStringUnsafe(addresses[role]));assert(live,`${variant}/${role} absent`);
    assert.equal(live.currentContractClassId.toString(),artifact.classId,`${variant}/${role} class changed`);
    classes.push({variant,role,address:addresses[role],classId:artifact.classId,unchanged:true});
  }
}
const block=await node.getBlockNumber();assert.equal(block,278);
const report={readOnly:true,walletOpened:false,block,classes,passed:true};
const file=new URL('results/recovered-candidate-classes-before-v4.json',import.meta.url);
if(fs.existsSync(file))assert.deepEqual(JSON.parse(fs.readFileSync(file)),report);else fs.writeFileSync(file,JSON.stringify(report,null,2)+'\n');
clearTimeout(deadline);console.log(JSON.stringify({passed:true,block,classes:classes.length,walletOpened:false}));
