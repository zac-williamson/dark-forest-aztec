// Offline by default. Execution requires an explicit --execute phase after the
// coordinator releases the benchmark network and freezes the final artifacts.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {uniqueRow,validateSavedRow,assertNoOrphanSubmission} from './resume-guards.mjs';

export const baseline='baseline-v2',candidate='candidate-v4';
const originalArtifacts='/tmp/df-fee-tools/artifacts/baseline';
const candidateArtifacts='/tmp/df-api-compatible-v4-native';
const common={BENCH_WALLET_DIRECTORY:'/tmp/df-api-compatible-wallet52-v2',BENCH_BASELINE_VARIANT:baseline,
  BENCH_FIND_PAIR:'v4',AZTEC_NODE_URL:'http://127.0.0.1:8097',NODE_BACKEND:'js',LOG_LEVEL:'error'};
const remainingPrivate=['reveal_location','upgrade_planet','withdraw_silver','safe_set_owner','prospect_planet',
  'deposit_artifact','withdraw_artifact','give_spaceships','activate_artifact','deactivate_artifact'];
const publicMethods=['pause','unpause','admin_set_world_radius','set_owner','add_score','deduct_score','create_planet',
  'admin_initialize_planet','create_artifact','update_artifact','admin_give_artifact','admin_give_spaceship'];
const moveExtras=['1','5','artifact_move','artifact_arrival','photoid','wormhole','conquest','artifact_alias','future_queue','nonzero_padding'];
const action=(id,variant,env={})=>({id,program:'run.mjs',args:[variant,variant===baseline?originalArtifacts:candidateArtifacts],env:{...common,...env}});
const paired=(id,env)=>[action(`${id}-original`,baseline,env),action(`${id}-candidate`,candidate,env)];
const setup=(program)=>({id:program==='setup.mjs'?'deploy-and-bind':'configure-identically',program,args:[candidate,candidateArtifacts],env:{...common,BENCH_FIND_PAIR:'v2'}});
export const phases={
  first4:[setup('setup.mjs'),setup('configure.mjs'),
    // Find seeds Player, so fresh initialization MUST precede candidate Find.
    action('initialize-first',candidate,{BENCH_METHODS:'initialize_player'}),
    ...paired('fresh-find',{BENCH_METHODS:'find_artifact',BENCH_CASES:'find_v4'}),
    action('refresh-and-move',candidate,{BENCH_METHODS:'refresh_planet,move'})],
  remaining28:[...paired('remaining-private',{BENCH_METHODS:remainingPrivate.join(',')}),
    ...paired('public-admin-and-vault',{BENCH_PUBLIC:'1'}),
    // These must be the second allocated Move IDs on both deployments.
    ...paired('maximum-due-arrivals',{BENCH_METHODS:'refresh_planet,move',BENCH_CASES:'20'})],
  edges:[...paired('initialization-edges',{BENCH_METHODS:'initialize_player',BENCH_CASES:'init_unused_padding,init_existing_planet'}),
    ...paired('refresh-edges',{BENCH_METHODS:'refresh_planet',BENCH_CASES:'refresh_unused_padding,1'})],
  extended:[...paired('retained-move-branches',{BENCH_METHODS:'move',BENCH_CASES:moveExtras.join(',')}),
    ...paired('refresh-artifact-arrival',{BENCH_METHODS:'refresh_planet',BENCH_CASES:'artifact_arrival'})],
  sponsored:paired('sponsored-player-actions',{BENCH_METHODS:'refresh_planet,move',BENCH_SPONSORED:'1'}),
  // Run only after other chain-writing tests finish and just before the isolated
  // native proof window. This creates fresh evidence instead of overwriting Find.
  profileFixtures:paired('fresh-find-for-profile',{BENCH_METHODS:'find_artifact',BENCH_CASES:'find_v4_profile',BENCH_FIND_PAIR:'v4_profile'}),
};

const signature=(method,caseId='ordinary',paymentMode='account')=>({method,caseId,paymentMode});
export const initialCoverage=[signature('initialize_player'),signature('find_artifact','find_v4'),signature('refresh_planet'),signature('move')];
export const ordinaryCoverage=[...initialCoverage,...remainingPrivate.map(method=>signature(method)),...publicMethods.map(method=>signature(method)),signature('move','20'),signature('refresh_planet','20')];
export const edgeCoverage=[signature('initialize_player','init_unused_padding'),signature('initialize_player','init_existing_planet'),signature('refresh_planet','refresh_unused_padding'),signature('refresh_planet','1')];
export const extensionCoverage=[...moveExtras.map(caseId=>signature('move',caseId)),signature('refresh_planet','artifact_arrival')];
export const sponsorCoverage=[signature('move','ordinary','sponsored'),signature('refresh_planet','ordinary','sponsored')];
export const plan={baseline,candidate,originalArtifacts,candidateArtifacts,
  scope:'Local complete mined Fee Juice and exact original state/event/root comparisons. No proofs or network restarts.',
  phases,coverage:{first4:initialCoverage,ordinary28:ordinaryCoverage,edges4:edgeCoverage,extended11:extensionCoverage,sponsored2:sponsorCoverage},
  proofFixtureSelection:{PROFILE_BASELINE_VARIANT:baseline,PROFILE_CANDIDATE_VARIANT:candidate,
    PROFILE_CANDIDATE_ARTIFACTS:candidateArtifacts,PROFILE_CASES_JSON:JSON.stringify({find_artifact:'find_v4_profile'})}};

export function inspectCoverage(records,expected,{requireNoFeeIncrease=false}={}){
  const rows=expected.map(key=>{
    const match=variant=>uniqueRow(records,{variant,...key});
    const before=match(baseline),after=match(candidate);
    assert(before?.verified&&after?.verified&&after.originalStateEquivalent,`Missing verified complete pair: ${JSON.stringify(key)}`);
    validateSavedRow(before);validateSavedRow(after,{referenceSchedule:before.observedLiveFeeSchedule,baselineVariant:baseline});
    const actor=row=>{
      const suffix=row.paymentMode==='sponsored'?'-sponsored':'';
      const fixture=JSON.parse(fs.readFileSync(new URL(`.state/${row.variant}-${row.method}-${row.caseId}${suffix}.json`,import.meta.url)));
      assert.deepEqual(fixture.contracts,row.contracts,'Saved fixture and receipt must refer to identical deployments');
      const actual=fixture.actor??fixture.admin;
      if(row.actor)assert.equal(row.actor,actual,'Saved fixture and receipt must retain the actual actor');
      return actual;
    };
    assert.equal(actor(before),actor(after),'Paired transactions must use the same actor');
    assert.equal(after.baselineVariant,baseline);
    assert.deepEqual(after.state.changes,before.state.changes);
    assert.deepEqual(after.state.unchangedRoots,before.state.unchangedRoots);
    const saved=BigInt(before.feeAtObservedLivePriceWei)-BigInt(after.feeAtObservedLivePriceWei);
    return {...key,baselineFeeWei:before.feeAtObservedLivePriceWei,candidateFeeWei:after.feeAtObservedLivePriceWei,savedFeeWei:saved.toString(),regression:saved<0n};
  });
  if(requireNoFeeIncrease)assert(!rows.some(row=>row.regression),'An early complete transaction costs more; preserve evidence and return it for another optimization pass');
  return rows;
}

export function validateMoveOrder(records,variant){
  const order=[signature('move'),signature('move','20'),...moveExtras.map(caseId=>signature('move',caseId)),signature('move','ordinary','sponsored')];
  let missing=false;
  for(const [index,key] of order.entries()){
    const row=uniqueRow(records,{variant,...key});
    if(!row){missing=true;continue;}
    assert(!missing,'Saved Move cases must be a prefix of the planned exact-ID order');
    const arrivals=row.state?.changes?.filter(change=>change.store==='arrival');assert.equal(arrivals?.length,1);
    assert.equal(BigInt(arrivals[0].id),BigInt(index)+2n,'Saved Move IDs must retain the same sequential allocation on both deployments');
  }
}

const directory=fileURLToPath(new URL('./',import.meta.url)),repo=path.resolve(directory,'../..');
const records=()=>JSON.parse(fs.readFileSync(path.join(directory,'results/transactions.json')));
const coverage=expected=>inspectCoverage(records(),expected);
async function execute(step){
  // Do not inherit a stale method, case, diagnostic or sponsorship selection.
  const env={...process.env};for(const key of Object.keys(env))if(key.startsWith('BENCH_'))delete env[key];
  Object.assign(env,step.env);
  console.log('STEP',step.id);
  const child=spawn(process.execPath,['--import','./node_modules/tsx/dist/loader.mjs',`experiments/api-compatible-benchmark/${step.program}`,...step.args],{cwd:repo,env,stdio:'inherit'});
  await new Promise((resolve,reject)=>{child.on('error',reject);child.on('exit',(code,signal)=>code===0?resolve():reject(Error(`${step.id} failed (${code??signal}); stop without resending a mined row`)));});
}
async function run(phase){for(const step of phases[phase])await execute(step);}
async function main(){
  if(process.argv[2]!=='--execute'){console.log(JSON.stringify(plan,null,2));return;}
  const selected=process.argv[3];assert(['first4','all','remaining28','edges','extended','sponsored','profileFixtures'].includes(selected),'Select an explicit execution phase');
  const manifest=JSON.parse(fs.readFileSync(path.join(candidateArtifacts,'build-provenance.json')));
  assert.equal(manifest.passed,true,'Final candidate native admission/class binding must pass');
  assert.equal(manifest.artifacts.length,20,'Expect the frozen original17 APIs plus backend and two workers');
  for(const item of manifest.artifacts){
    const actual=createHash('sha256').update(fs.readFileSync(path.join(candidateArtifacts,item.file))).digest('hex');
    assert.equal(actual,item.sha256,`Frozen candidate artifact changed: ${item.file}`);
  }
  const saved=records(),expected=[...ordinaryCoverage,...edgeCoverage,...extensionCoverage,...sponsorCoverage,signature('find_artifact','find_v4_profile')];
  const snapshot=path.join(directory,'results/candidate-v4-build-provenance.json');
  if(fs.existsSync(snapshot))assert.deepEqual(JSON.parse(fs.readFileSync(snapshot)),manifest,'This variant label already belongs to a different frozen build');
  else assert(!saved.some(row=>row.variant===candidate),'Existing candidate receipts require their original frozen build snapshot');
  const schedule=JSON.parse(fs.readFileSync(path.join(repo,'docs/fee-benchmark/common-fee-schedule.json')));
  const originalManifest=JSON.parse(fs.readFileSync(path.join(directory,'results/baseline-manifest.json')));
  const role=file=>file.startsWith('game_state_backend-')?'backend':file.split('-')[0];
  const hashes={[candidate]:Object.fromEntries(manifest.artifacts.map(item=>[role(item.file),item.sha256])),[baseline]:{}};
  for(const [file,item] of Object.entries(originalManifest.artifacts)){
    const actual=createHash('sha256').update(fs.readFileSync(path.join(originalArtifacts,file))).digest('hex');
    assert.equal(actual,item.sha256,`Pinned original artifact changed: ${file}`);hashes[baseline][role(file)]=actual;
  }
  for(const variant of [baseline,candidate]){
    validateMoveOrder(saved,variant);
    const file=path.join(directory,`.state/${variant}-deployments.json`),addresses=fs.existsSync(file)?JSON.parse(fs.readFileSync(file)):undefined;
    for(const key of expected){
      const row=uniqueRow(saved,{variant,...key});
      if(row){assert(addresses,'Saved receipt has no matching deployment file');validateSavedRow(row,{addresses,referenceSchedule:schedule,artifactHashes:hashes[variant],baselineVariant:baseline});}
      const submitted=path.join(directory,`results/traces/${variant}-${key.method}-${key.caseId}-${key.paymentMode}.submitted-tx.bin`);
      assertNoOrphanSubmission(fs.existsSync(submitted),row,`${variant}/${key.method}/${key.caseId}`);
    }
  }
  if(!fs.existsSync(snapshot))fs.writeFileSync(snapshot,JSON.stringify(manifest,null,2)+'\n');
  if(selected==='first4'||selected==='all'){
    await run('first4');inspectCoverage(records(),initialCoverage,{requireNoFeeIncrease:true});
  }
  if(selected==='all'){
    for(const phase of ['remaining28','edges','extended','sponsored'])await run(phase);
    const verified=coverage([...ordinaryCoverage,...edgeCoverage,...extensionCoverage,...sponsorCoverage]);
    fs.writeFileSync(path.join(directory,'results/coverage-candidate-v4.json'),JSON.stringify({candidate,verifiedPairs:verified.length,rows:verified},null,2)+'\n');
  }else if(selected!=='first4'){
    if(selected!=='profileFixtures')inspectCoverage(records(),initialCoverage,{requireNoFeeIncrease:true});
    const prerequisites={edges:ordinaryCoverage,extended:[...ordinaryCoverage,...edgeCoverage],sponsored:[...ordinaryCoverage,...edgeCoverage,...extensionCoverage],profileFixtures:[...ordinaryCoverage,...edgeCoverage,...extensionCoverage,...sponsorCoverage]};
    if(prerequisites[selected])coverage(prerequisites[selected]);
    await run(selected);
  }
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))await main();
