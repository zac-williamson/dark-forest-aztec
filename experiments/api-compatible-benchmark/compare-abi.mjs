import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {compareApi} from './abi-utils.mjs';
const [originalDirectory,candidateDirectory]=process.argv.slice(2).filter(arg=>!arg.startsWith('--'));
if(!originalDirectory||!candidateDirectory)throw Error('Usage: node compare-abi.mjs ORIGINAL_ARTIFACT_DIR CANDIDATE_ARTIFACT_DIR [--allow-additional]');
const rows=[];
for(const filename of fs.readdirSync(originalDirectory).filter(name=>name.endsWith('.json')).sort()){
  const candidatePath=path.join(candidateDirectory,filename);
  if(!fs.existsSync(candidatePath)){rows.push({filename,compatible:false,missingArtifact:true});continue;}
  const before=fs.readFileSync(path.join(originalDirectory,filename)),after=fs.readFileSync(candidatePath);
  const sha=value=>createHash('sha256').update(value).digest('hex');
  rows.push({filename,originalSha256:sha(before),candidateSha256:sha(after),...compareApi(JSON.parse(before),JSON.parse(after),{allowAdditional:process.argv.includes('--allow-additional')})});
}
const passed=rows.every(row=>row.compatible&&row.sameContractName);
console.log(JSON.stringify({passed,scope:'All original externally callable names, caller argument order/names/widths/arrays/fields, return types, visibility, only-self/initializer attributes and event names/layouts. Compiler context inputs are excluded from caller signatures. Nominal module-path differences are reported separately.',rows},null,2));
if(!passed)process.exitCode=1;
