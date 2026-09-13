import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {apiSurface,callerParameters} from './abi-utils.mjs';
const directory=process.argv[2]??'/tmp/df-fee-tools/artifacts/baseline';
const rows=fs.readdirSync(directory).filter(file=>file.endsWith('.json')).sort().map(file=>{
  const wire=fs.readFileSync(path.join(directory,file)),artifact=JSON.parse(wire),surface=apiSurface(artifact);
  return {file,name:artifact.name,sha256:createHash('sha256').update(wire).digest('hex'),constructor:surface.functions.find(fn=>fn.name==='constructor'),storageAddressSetup:surface.functions.find(fn=>fn.name==='set_all_storage_addresses')??null,functions:artifact.functions.filter(fn=>surface.functions.some(v=>v.name===fn.name)).map(fn=>({name:fn.name,attributes:fn.custom_attributes,nativeParameterCount:fn.abi.parameters.length,callerParameterCount:callerParameters(fn).length,callerParameterNames:callerParameters(fn).map(parameter=>parameter.name)})),events:surface.events};
});
fs.writeFileSync(new URL('./baseline-api-inventory.json',import.meta.url),JSON.stringify({originalCommit:'00bfa05c18862cce1c5adb362e4ecebe084c329a',artifactDirectory:directory,contracts:rows},null,2));
console.log('Inventoried',rows.length,'original contract interfaces.');

