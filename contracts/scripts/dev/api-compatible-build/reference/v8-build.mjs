/** Build immutable API facades/systems first, then bind their classes into the backend.
 * No network or deployment. Fails before publishing artifacts if class identity or
 * the protocol's real native bytecode limits do not hold.
 */
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {loadContractArtifact} from '@aztec/stdlib/abi';
import {getContractClassFromArtifact} from '@aztec/stdlib/contract';
import {MAX_PACKED_PUBLIC_BYTECODE_SIZE_IN_FIELDS, MAX_PUBLIC_BYTECODE_SIZE_IN_BYTES} from '@aztec/constants';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const repository=path.dirname(root);
const output=path.resolve(process.env.DF_NATIVE_OUTPUT??path.join(root,'target/native'));
const published=path.join(root,'target/api-compatible');
const nargo=process.env.DF_NARGO??'aztec-nargo';
const bb=process.env.DF_BB??path.join(repository,'node_modules/.bin/bb');
const python=process.env.DF_PYTHON??'python3';
const facades=[['world','WorldStorage'],['player','PlayerStorage'],['planet','PlanetStorage'],
  ['planet_revealed_coords','PlanetRevealedCoordsStorage'],['planet_events','PlanetEventsStorage'],
  ['planet_artifacts','PlanetArtifactsStorage'],['arrival','ArrivalStorage'],['artifact','ArtifactStorage'],
  ['artifact_location','ArtifactLocationStorage']];
const systems=[['admin','Admin'],['core','Core'],['move','Move'],['artifact_action','ArtifactAction'],
  ['artifact_find','ArtifactFind'],['artifact_prospect','ArtifactProspect'],['artifact_valut','ArtifactValut']];
const workers=[['core_settlement_worker','CoreSettlementWorker'],['vault_settlement_worker','VaultSettlementWorker']];
const contracts=[['config','Config'],...facades,...systems];
const backend=['game_state_backend','GameStateBackend'];
const filename=([pkg,name])=>`${pkg}-${name}.json`;
const checksum=bytes=>createHash('sha256').update(bytes).digest('hex');
function sourceChecksums(){
  const files={};
  function visit(directory){
    for(const entry of fs.readdirSync(directory,{withFileTypes:true})){
      if(entry.isSymbolicLink()||['node_modules','target','.git'].includes(entry.name))continue;
      const file=path.join(directory,entry.name);
      if(entry.isDirectory())visit(file);
      else if(entry.name.endsWith('.nr')||entry.name==='Nargo.toml')files[path.relative(repository,file)]=checksum(fs.readFileSync(file));
    }
  }
  for(const directory of ['circuits','config','libs','prospect_original_libs','types','storage','system','settlement_workers','state_backend','state_backend_readonly','state_facade_interface'])visit(path.join(root,directory));
  for(const file of ['Nargo.toml','package.json','scripts/dev/build-api-compatible.mjs'])files['contracts/'+file]=checksum(fs.readFileSync(path.join(root,file)));
  return Object.fromEntries(Object.entries(files).sort(([a],[b])=>a.localeCompare(b)));
}
fs.mkdirSync(output,{recursive:true});
const logs=path.join(output,'logs');fs.mkdirSync(logs,{recursive:true});
function run(binary,args,label,cwd=root){
  const log=path.join(logs,label+'.log');const fd=fs.openSync(log,'w');
  const result=spawnSync(binary,args,{cwd,stdio:['ignore',fd,fd],env:process.env});fs.closeSync(fd);
  if(result.error||result.status!==0)throw new Error(`${label} failed: ${result.error??result.status}. See ${log}`);
}
function compile(pkg){run(nargo,['compile','--package',pkg,'--force'],`compile-${pkg}`);}
async function native(entry,phase){
  const file=filename(entry),destination=path.join(output,file);
  fs.copyFileSync(path.join(root,'target',file),destination);
  run(bb,['aztec_process','-i',destination],`${phase}-native-${entry[0]}`);
  const bytes=fs.readFileSync(destination),raw=JSON.parse(bytes);
  const dispatch=raw.functions.find(f=>f.name==='public_dispatch');
  assert(dispatch,`${file} has no native public dispatch`);
  const publicBytes=Buffer.from(dispatch.bytecode,'base64').length;
  const packedFields=1+Math.ceil(publicBytes/31);
  assert(publicBytes<=MAX_PUBLIC_BYTECODE_SIZE_IN_BYTES,`${file}: ${publicBytes} public bytes exceeds protocol limit`);
  assert(packedFields<=MAX_PACKED_PUBLIC_BYTECODE_SIZE_IN_FIELDS,`${file}: ${packedFields} packed fields exceeds protocol limit`);
  const contractClass=await getContractClassFromArtifact(loadContractArtifact(raw));
  return {file,sha256:checksum(bytes),classId:contractClass.id.toString(),publicBytes,packedFields};
}

run(python,[path.join(repository,'tests/api-compatibility/build-backend.py')],'generate-backend');
run(python,[path.join(repository,'tests/api-compatibility/generate-backend-plans.py'),'--check'],'settlement-source-generation',repository);
run(python,['-m','unittest','discover','-s','tests/api-compatibility','-p','test_*.py'],'api-and-trust-regressions',repository);
run(python,[path.join(repository,'tests/api-compatibility/check.py'),'check','--strict'],'source-api-compatibility',repository);
const initial=new Map();
for(const entry of contracts){
  console.log(`Building ${entry[1]}`);compile(entry[0]);
  initial.set(entry[0],await native(entry,'initial'));
  if(entry[0]==='config')fs.writeFileSync(path.join(root,'libs/src/config_class.nr'),
    '// Generated from the native Config artifact before compiling initiating Systems.\n'+
    `pub global CONFIG_CLASS: Field = ${initial.get('config').classId};\n`);
}
for(const [index,slug,pkg] of [[0,'core','core'],[1,'vault','artifact_valut']]){
  fs.writeFileSync(path.join(root,'settlement_workers',slug,'src/system_class.nr'),
    '// Generated immutable initiating System class.\n'+
    `pub global SYSTEM_CLASS: Field = ${initial.get(pkg).classId};\n`);
  const entry=workers[index];compile(entry[0]);initial.set(entry[0],await native(entry,'initial'));
}
const ids=entries=>entries.map(([pkg])=>initial.get(pkg).classId);
fs.writeFileSync(path.join(root,'state_backend/src/trusted_classes.nr'),
  '// Generated from the immutable native artifacts by build-api-compatible.mjs.\n'+
  '// Full public hash validation remains mandatory for every other writer.\n'+
  `pub global CONFIG_CLASS: Field = ${initial.get('config').classId};\n`+
  `pub global WORKER_CLASSES: [Field; 2] = [${ids(workers).join(', ')}];\n`+
  `pub global SYSTEM_CLASSES: [Field; 7] = [${ids(systems).join(', ')}];\n`+
  `pub global FACADE_CLASSES: [Field; 9] = [${ids(facades).join(', ')}];\n`+
  'pub fn contains(id: Field) -> bool {\n    (id != 0) & ('+
  systems.map((_,i)=>`(id == SYSTEM_CLASSES[${i}])`).join(' | ')+')\n}\n');
console.log('Building backend with immutable caller classes');compile(backend[0]);
const backendRow=await native(backend,'final');
const final=[];
for(const entry of [...contracts,...workers]){
  // Imported contract interfaces must not embed the backend implementation.
  compile(entry[0]);const row=await native(entry,'identity');
  assert.equal(row.classId,initial.get(entry[0]).classId,`${entry[1]} class changed when backend constants changed`);
  final.push(row);
}
final.push(backendRow);
run(python,[path.join(repository,'tests/api-compatibility/verify_backend_layout.py'),path.join(output,backendRow.file)],'utility-layout-compatibility',repository);
run(python,[path.join(repository,'tests/api-compatibility/verify_config_layout.py'),path.join(output,'config-Config.json')],'config-layout-compatibility',repository);
run(python,[path.join(repository,'tests/api-compatibility/check.py'),'check','--artifacts',output,'--strict'],'compiled-api-compatibility',repository);
run(process.execPath,['--import',path.join(repository,'node_modules/tsx/dist/loader.mjs'),path.join(repository,'tests/api-compatible-storage/verify-move-transport.mjs'),path.join(output,backendRow.file),path.join(output,'move-Move.json')],'compiled-move-transport',repository);
run(process.execPath,[path.join(repository,'tests/api-compatibility/check-raw-selectors.mjs'),output,output,path.join(output,'raw-selectors.json')],'compiled-settlement-transport',repository);
// Only native, size-checked, identity-checked artifacts enter the codegen directory.
fs.mkdirSync(published,{recursive:true});
for(const row of final){
  fs.copyFileSync(path.join(output,row.file),path.join(root,'target',row.file));
  fs.copyFileSync(path.join(output,row.file),path.join(published,row.file));
}
const report={passed:true,scope:'Native bytecode admission and immutable class binding; no deployment or fee claim',
  sourceFiles:sourceChecksums(),
  limits:{publicBytes:MAX_PUBLIC_BYTECODE_SIZE_IN_BYTES,packedFields:MAX_PACKED_PUBLIC_BYTECODE_SIZE_IN_FIELDS},
  facadeClassIds:ids(facades),systemClassIds:ids(systems),workerClassIds:ids(workers),configClassId:initial.get('config').classId,artifacts:final};
fs.writeFileSync(path.join(output,'build-provenance.json'),JSON.stringify(report,null,2)+'\n');
console.log(`Built ${final.length} deployable contracts; original facade/system classes are stable.`);
