/** Generate and copy the exact20 checked interfaces using the installed SDK. */
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {loadContractArtifact} from '@aztec/stdlib/abi';
import {generateTypescriptContractInterface} from '@aztec/builder/codegen';
import {adaptCheckedArtifactWrapper} from './wrapper-compatibility.ts';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../../..');
const contracts=path.join(root,'contracts');
const source=path.join(contracts,'target/api-compatible');
const require=createRequire(import.meta.url);
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
function regular(p){assert(fs.lstatSync(p).isFile()&&!fs.lstatSync(p).isSymbolicLink(),`Expected regular file: ${p}`);return fs.readFileSync(p);}
function packageVersion(spec){
  const expected=spec.split('/').slice(0,2).join('/');
  let p=path.dirname(fs.realpathSync(require.resolve(spec)));
  while(true){
    const file=path.join(p,'package.json');
    if(fs.existsSync(file)){const metadata=JSON.parse(regular(file));if(metadata.name===expected)return metadata.version;}
    const parent=path.dirname(p);assert(parent!==p,`Missing package metadata: ${expected}`);p=parent;
  }
}
assert.equal(packageVersion('@aztec/builder/codegen'),'5.0.1');
assert.equal(packageVersion('@aztec/stdlib/abi'),'5.0.1');
const mode=process.argv[2];assert(['codegen','copy'].includes(mode)&&process.argv.length===3,'Use codegen or copy');
const manifest=JSON.parse(regular(path.join(contracts,'target/api-compatible-build-provenance.json')));
assert(manifest.passed&&manifest.artifacts.length===20&&Object.keys(manifest.sourceFiles).length===349,'Missing checked native provenance');
for(const [name,digest] of Object.entries(manifest.sourceFiles))assert.equal(hash(regular(path.join(root,name))),digest,`Source changed: ${name}`);
const files=new Map();
for(const row of manifest.artifacts){
  assert.equal(path.basename(row.file),row.file);assert(!files.has(row.file));
  const bytes=regular(path.join(source,row.file));assert.equal(hash(bytes),row.sha256,`Artifact changed: ${row.file}`);
  const artifact=loadContractArtifact(JSON.parse(bytes));
  const wrapper=Buffer.from(adaptCheckedArtifactWrapper(await generateTypescriptContractInterface(artifact,`./${row.file}`),artifact.name));
  assert(!files.has(`${artifact.name}.ts`));
  files.set(row.file,bytes);files.set(`${artifact.name}.ts`,wrapper);
  if(mode==='copy')assert(regular(path.join(source,`${artifact.name}.ts`)).equals(wrapper),`Stale generated interface: ${artifact.name}`);
}
assert.equal(files.size,40);
assert(fs.readdirSync(source).every(name=>files.has(name)),'Unexpected files in checked artifact directory');
const destination=mode==='codegen'?source:path.join(contracts,'scripts/artifacts');
assert(!fs.existsSync(destination)||!fs.lstatSync(destination).isSymbolicLink(),'Destination must not be a symlink');
fs.mkdirSync(path.dirname(destination),{recursive:true});
const temp=fs.mkdtempSync(path.join(path.dirname(destination),'.checked-artifacts-'));
const staged=path.join(temp,'new');const previous=path.join(temp,'previous');
let moved=false,installed=false;
try{
  fs.mkdirSync(staged);
  for(const [name,bytes] of files){fs.writeFileSync(path.join(staged,name),bytes);assert(regular(path.join(staged,name)).equals(bytes));}
  if(fs.existsSync(destination)){fs.renameSync(destination,previous);moved=true;}
  fs.renameSync(staged,destination);installed=true;
  for(const [name,bytes] of files)assert(regular(path.join(destination,name)).equals(bytes));
}catch(error){
  if(installed)fs.rmSync(destination,{recursive:true});
  if(moved)fs.renameSync(previous,destination);
  throw error;
}finally{fs.rmSync(temp,{recursive:true,force:true});}
console.log(`${mode==='codegen'?'Generated':'Copied'} all20 checked contract interfaces and native artifacts.`);
