// Additional complete-action measurements. The frozen 45-case report is left
// intact; these four pairs have new witnesses and their own coverage report.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {inspectCoverage} from './run-plan-v5.mjs';

const directory=fileURLToPath(new URL('./',import.meta.url)),repo=path.resolve(directory,'../..');
const baseline='baseline-v2',candidate='candidate-v5';
const folders={[baseline]:'/tmp/df-fee-tools/artifacts/baseline',[candidate]:'/tmp/df-api-compatible-v5-native'};
export const cases=[
 {method:'refresh_planet',caseId:'carried_arrivals_5',paymentMode:'account'},
 {method:'move',caseId:'carried_arrivals_5',paymentMode:'account'},
 {method:'refresh_planet',caseId:'carried_arrivals_20',paymentMode:'account'},
 {method:'move',caseId:'carried_arrivals_20',paymentMode:'account'},
];
export const steps=cases.flatMap(key=>[baseline,candidate].map(variant=>({variant,...key})));
const records=()=>JSON.parse(fs.readFileSync(path.join(directory,'results/transactions.json')));
const identity=({method,caseId,paymentMode})=>({method,caseId,paymentMode});
function validateArtifacts(){
 const manifest=JSON.parse(fs.readFileSync(path.join(folders[candidate],'build-provenance.json')));
 assert.equal(manifest.passed,true);assert.equal(manifest.artifacts.length,20);
 for(const item of manifest.artifacts)assert.equal(createHash('sha256').update(fs.readFileSync(path.join(folders[candidate],item.file))).digest('hex'),item.sha256,`Frozen V5 artifact changed: ${item.file}`);
 const original=JSON.parse(fs.readFileSync(path.join(directory,'results/baseline-manifest.json')));
 for(const [file,item] of Object.entries(original.artifacts))assert.equal(createHash('sha256').update(fs.readFileSync(path.join(folders[baseline],file))).digest('hex'),item.sha256,`Original artifact changed: ${file}`);
}
export function validateCarriedEffects(rows,key){
 const count=Number(key.caseId.split('_').at(-1));
 for(const variant of [baseline,candidate]){
  const row=rows.find(item=>item.variant===variant&&item.method===key.method&&item.caseId===key.caseId&&item.paymentMode==='account');
  assert(row?.verified,'Original acceptance and candidate equivalence must both be mined');
  const locations=row.state.changes.filter(change=>change.store==='artifact_location');
  assert.equal(locations.length,count*(key.method==='move'?2:1),'Every due carried artifact must generate its original Location callback');
  assert.equal(new Set(locations.map(change=>String(change.id))).size,locations.length,'All carried artifact IDs must be distinct');
  if(key.method==='move'){
   const arrivals=row.state.changes.filter(change=>change.store==='arrival');assert.equal(arrivals.length,1);
   assert.equal(BigInt(arrivals[0].id),count===5?15n:16n,'Fresh extension must retain sequential paired Arrival IDs after the frozen45');
  }
 }
}
async function main(){
 if(process.argv[2]!=='--execute'){console.log(JSON.stringify({steps,proofsEnabled:false,profilingEnabled:false,threads:2,coverageOutput:'coverage-carried-candidate-v5.json'},null,2));return;}
 validateArtifacts();
 const frozen=JSON.parse(fs.readFileSync(path.join(directory,'results/coverage-candidate-v5.json')));
 assert.equal(frozen.verifiedPairs,45);inspectCoverage(records(),frozen.rows.map(identity));
 for(const step of steps){
  const env={...process.env};for(const key of Object.keys(env))if(key.startsWith('BENCH_'))delete env[key];
  Object.assign(env,{BENCH_METHODS:step.method,BENCH_CASES:step.caseId,BENCH_BASELINE_VARIANT:baseline,BENCH_ASSERT_BASELINE_FIXTURE:'1',
   BENCH_WALLET_DIRECTORY:'/tmp/df-api-compatible-wallet52-v5',BENCH_FIND_PAIR:'v5',AZTEC_NODE_URL:'http://127.0.0.1:8097',
   NODE_BACKEND:'js',LOG_LEVEL:'error',RAYON_NUM_THREADS:'2',HARDWARE_CONCURRENCY:'2'});
  console.log('STEP',step.variant,step.method,step.caseId);
  const child=spawn(process.execPath,['--import','./node_modules/tsx/dist/loader.mjs','experiments/api-compatible-benchmark/run.mjs',step.variant,folders[step.variant]],{cwd:repo,env,stdio:'inherit'});
  await new Promise((resolve,reject)=>{child.on('error',reject);child.on('exit',(code,signal)=>code===0?resolve():reject(Error(`Stopped at ${step.variant}/${step.method}/${step.caseId} (${code??signal}). Preserve original acceptance/rejection and any submission journal; do not resend uncertain transactions.`)));});
  if(step.variant===candidate){inspectCoverage(records(),[identity(step)]);validateCarriedEffects(records(),step);}
 }
 const rows=inspectCoverage(records(),cases);for(const key of cases)validateCarriedEffects(records(),key);
 const report={candidate,baseline,verifiedPairs:rows.length,originalAcceptanceVerified:true,proofsEnabled:false,profilingEnabled:false,
  scope:'Additional original-accepted complete Refresh/Move pairs with 5 or20 distinct due carried arrivals per planet, initially empty inventories and no newly moved artifact. Exact inputs, ordered events, own full state-root hashes, canonical receipts and billed fees verified. Current action time is refreshed; other paired witnesses are identical.',rows};
 fs.writeFileSync(path.join(directory,'results/coverage-carried-candidate-v5.json'),JSON.stringify(report,null,2)+'\n');
 console.log('COMPLETE',rows.length,'additional carried-arrival pairs');
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))await main();
