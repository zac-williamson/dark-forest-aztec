/** Build all native contracts and publish only after API, class and size checks. */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';

const repository=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../..');
const tooling=path.join(repository,'contracts/scripts/dev/api-compatible-build');
const args=process.argv.slice(2);
if(args.some(arg=>arg!=='--check'))throw new Error('Usage: node scripts/dev/build-api-compatible.mjs [--check]');
const check=args.includes('--check');
const work=fs.mkdtempSync(path.join(os.tmpdir(),'df-api-compatible-build-'));
const plan=path.join(work,'plan.json');
const native=process.env.DF_NATIVE_OUTPUT?path.resolve(process.env.DF_NATIVE_OUTPUT):path.join(work,'native');
const python=process.env.DF_PYTHON??'python3';
const env={...process.env,DF_NODE:process.execPath,RAYON_NUM_THREADS:'2',HARDWARE_CONCURRENCY:'2'};
function run(script,argv){
  const result=spawnSync(python,[path.join(tooling,script),...argv],{cwd:repository,stdio:'inherit',env});
  if(result.error||result.status!==0)throw new Error(`${script} failed. Build evidence remains in ${work}: ${result.error??result.status}`);
}
run('prepare-plan.py',['--root',repository,'--plan',plan,'--output',native]);
run('build.py',[plan]);
if(!check){
  const digest=createHash('sha256').update(fs.readFileSync(plan)).digest('hex');
  run('build.py',[plan,'--execute','--reviewed-plan-sha',digest]);
  run('publish.py',['--root',repository,'--native',native]);
}
console.log(`${check?'Preflight passed':'Published 20 checked native contracts'}. Evidence: ${work}`);
