// Serial runtime coordinator. The six actual suites come from the frozen V6
// source tree and each opens its own proof-disabled PXE.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('../../',import.meta.url));
const file=path.join(root,'docs/api-compatibility/runtime-plan-v6.json');
const plan=JSON.parse(fs.readFileSync(file));
const hash=file=>createHash('sha256').update(fs.readFileSync(file)).digest('hex');
if(process.argv[2]!=='--execute'){
  console.log(JSON.stringify({runtimeExecution:false,plan:file,steps:plan.steps.map(step=>step.id)}));
}else{
  assert.equal(plan.candidate,'candidate-v6');assert.equal(plan.transactionProofsEnabled,false);assert.equal(plan.profilingEnabled,false);
  const results=new URL('./results/',import.meta.url);
  for(const [name,count] of [['coverage-candidate-v6.json',45],['coverage-carried-candidate-v6.json',4]]){
    const coverage=JSON.parse(fs.readFileSync(new URL(name,results)));
    assert.equal(coverage.candidate,'candidate-v6');assert.equal(coverage.verifiedPairs,count,'Finish exact paired gameplay measurements before isolated runtime mutations');
  }
  const snapshot=JSON.parse(fs.readFileSync(plan.frozenSourceSnapshot));
  assert.equal(hash(snapshot.buildManifest),snapshot.buildManifestSha256);
  for(const [file,expected] of Object.entries(snapshot.files))assert.equal(hash(path.join(snapshot.sourceWorkspace,file)),expected,`Frozen V6 source changed: ${file}`);
  const manifest=JSON.parse(fs.readFileSync(snapshot.buildManifest));assert.equal(manifest.passed,true);assert.equal(manifest.artifacts.length,20);
  for(const entry of manifest.artifacts)assert.equal(hash(path.join(path.dirname(snapshot.buildManifest),entry.file)),entry.sha256);
  for(const fixture of Object.values(plan.fixtureArtifacts))assert.equal(hash(fixture.path),fixture.sha256,'Public-only test fixture changed');
  for(const step of plan.steps){
    assert(!fs.existsSync(step.arguments[2]),`Preserve existing runtime evidence: ${step.arguments[2]}`);
    assert(!fs.existsSync(step.log),`Preserve existing runtime log: ${step.log}`);
    assert.equal(step.environment.RAYON_NUM_THREADS,'2');assert.equal(step.environment.HARDWARE_CONCURRENCY,'2');
  }
  const reports=[];
  for(const step of plan.steps){
    const env={...process.env};
    for(const key of Object.keys(env))if(/^(BENCH_|CALLER_|RUN_CALLER_|STORAGE_)/.test(key))delete env[key];
    Object.assign(env,step.environment);
    const fd=fs.openSync(step.log,'wx');console.log('RUNTIME_STEP',step.id,'log',step.log);
    try{
      const child=spawn(process.execPath,['--import','./node_modules/tsx/dist/loader.mjs',step.program,...step.arguments],{cwd:step.cwd,env,stdio:['ignore',fd,fd]});
      await new Promise((resolve,reject)=>{child.on('error',reject);child.on('exit',(code,signal)=>code===0?resolve():reject(Error(`${step.id} stopped (${code??signal}); inspect its report/log and reconcile setup before any retry`)));});
    }finally{fs.closeSync(fd);}
    const report=JSON.parse(fs.readFileSync(step.arguments[2]));assert.equal(report.passed,true);
    assert(report.checks.every(check=>check.passed===true),'Every recorded runtime check must pass');
    if(Object.hasOwn(report,'proverEnabled'))assert.equal(report.proverEnabled,false);
    reports.push({suite:step.id,report:step.arguments[2],reportSHA256:hash(step.arguments[2]),passedChecks:report.checks.length});
    console.log('RUNTIME_COMPLETE',step.id,report.checks.length);
  }
  const output=path.join(root,'docs/api-compatibility/runtime-complete-v6.json');assert(!fs.existsSync(output));
  fs.writeFileSync(output,JSON.stringify({candidate:'candidate-v6',passed:true,transactionProofsEnabled:false,profilingEnabled:false,threads:2,
    planSHA256:hash(file),buildManifestSHA256:snapshot.buildManifestSha256,reports,totalPassedChecks:reports.reduce((sum,report)=>sum+report.passedChecks,0)},null,2)+'\n');
  console.log('ALL_RUNTIME_COMPLETE',reports.length);
}
