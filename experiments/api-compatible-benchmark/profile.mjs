// Real native private-transaction proof timing. This program never sends a transaction.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {performance} from 'node:perf_hooks';
import {createAztecNodeClient} from '@aztec/aztec.js/node';
import {Contract} from '@aztec/aztec.js/contracts';
import {AztecAddress} from '@aztec/aztec.js/addresses';
import {loadContractArtifact} from '@aztec/stdlib/abi';
import {getContractClassFromArtifact} from '@aztec/stdlib/contract';
import {GasFees} from '@aztec/stdlib/gas';
import {EmbeddedWallet} from '@aztec/wallets/embedded';
import {registerInitialLocalNetworkAccountsInWallet} from '@aztec/wallets/testing';
import {files,auxiliaryFiles,findFunction} from './runtime.mjs';
import {json} from './fixtures.mjs';

const methods={initialize_player:'core',reveal_location:'core',upgrade_planet:'core',
  withdraw_silver:'core',refresh_planet:'core',safe_set_owner:'admin',move:'move',
  prospect_planet:'artifact_prospect',find_artifact:'artifact_find',deposit_artifact:'artifact_valut',
  withdraw_artifact:'artifact_valut',give_spaceships:'artifact_valut',
  activate_artifact:'artifact_action',deactivate_artifact:'artifact_action'};
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const positiveInteger=(value,label)=>{const n=Number(value);assert(Number.isSafeInteger(n)&&n>=1,`${label} must be a positive integer`);return n;};

function packageVersion(name,entry){
  let directory=path.dirname(fileURLToPath(import.meta.resolve(entry)));
  while(directory!==path.dirname(directory)){
    const manifest=path.join(directory,'package.json');
    if(fs.existsSync(manifest)){const pkg=JSON.parse(fs.readFileSync(manifest));if(pkg.name===name)return pkg.version;}
    directory=path.dirname(directory);
  }
  throw new Error(`Cannot identify installed version of ${name}`);
}

export function revive(type,value){
  if(type.kind==='field'||type.kind==='integer')return BigInt(value);
  if(type.kind==='boolean'){assert.equal(typeof value,'boolean');return value;}
  if(type.kind==='array'){assert.equal(value.length,type.length);return value.map(v=>revive(type.type,v));}
  if(type.kind==='struct'&&type.path.endsWith('::AztecAddress'))return AztecAddress.fromStringUnsafe(value);
  assert.equal(type.kind,'struct',`Unsupported original ABI type ${type.kind}`);
  return Object.fromEntries(type.fields.map(field=>{assert(Object.hasOwn(value,field.name),`Missing ${field.name}`);return[field.name,revive(field.type,value[field.name])];}));
}

function canonicalType(type){
  if(type.kind==='array')return {kind:type.kind,length:type.length,type:canonicalType(type.type)};
  if(type.kind==='struct')return {kind:type.kind,name:type.path.split('::').at(-1),fields:type.fields.map(f=>({name:f.name,type:canonicalType(f.type)}))};
  return type.kind==='integer'?{kind:type.kind,width:type.width,sign:type.sign}:{kind:type.kind};
}

const median=values=>{const sorted=[...values].sort((a,b)=>a-b),middle=Math.floor(sorted.length/2);return sorted.length%2?sorted[middle]:(sorted[middle-1]+sorted[middle])/2;};
const distribution=values=>values.length?{count:values.length,min:Math.min(...values),max:Math.max(...values),mean:values.reduce((a,b)=>a+b,0)/values.length,median:median(values)}:null;

export function summarize(samples,selected,variants){
  const metrics={provingMs:s=>s.stats.timings.proving,totalMs:s=>s.stats.timings.total,wallMs:s=>s.wallMs};
  return Object.fromEntries(selected.map(method=>{
    const measured=samples.filter(s=>s.method===method&&!s.warmup);
    const summary={measuredRounds:Math.min(...variants.map(v=>measured.filter(s=>s.variant===v).length)),metrics:{}};
    for(const [metric,value] of Object.entries(metrics)){
      const baseline=distribution(measured.filter(s=>s.variant===variants[0]).map(value));
      const candidate=distribution(measured.filter(s=>s.variant===variants[1]).map(value));
      const paired=[];
      for(const round of new Set(measured.map(s=>s.round))){
        const b=measured.find(s=>s.round===round&&s.variant===variants[0]);
        const c=measured.find(s=>s.round===round&&s.variant===variants[1]);
        if(b&&c)paired.push({round,baselineMs:value(b),candidateMs:value(c),changePercent:100*(value(c)/value(b)-1)});
      }
      summary.metrics[metric]={baseline,candidate,paired,
        medianChangePercent:baseline&&candidate?100*(candidate.median/baseline.median-1):null,
        medianPairedChangePercent:paired.length?median(paired.map(p=>p.changePercent)):null};
    }
    return [method,summary];
  }));
}

export async function main(){
  const selected=(process.env.PROFILE_METHODS??Object.keys(methods).join(',')).split(',').map(s=>s.trim()).filter(Boolean);
  assert(selected.length>0&&new Set(selected).size===selected.length,'Select distinct original private methods');
  for(const method of selected)assert(Object.hasOwn(methods,method),`Unknown private method ${method}`);
  const caseOverrides=JSON.parse(process.env.PROFILE_CASES_JSON??'{}');
  assert(caseOverrides&&typeof caseOverrides==='object'&&!Array.isArray(caseOverrides),'PROFILE_CASES_JSON must map method names to saved case labels');
  for(const [method,caseId] of Object.entries(caseOverrides)){
    assert(Object.hasOwn(methods,method),`Unknown fixture method ${method}`);
    assert(typeof caseId==='string'&&/^[a-z0-9_]+$/.test(caseId),`Invalid fixture case for ${method}`);
  }
  const cases=Object.fromEntries(selected.map(method=>[method,caseOverrides[method]??'ordinary']));
  const rounds=positiveInteger(process.env.PROFILE_ROUNDS??2,'PROFILE_ROUNDS');
  const variants=[process.env.PROFILE_BASELINE_VARIANT??'baseline-v2',process.env.PROFILE_CANDIDATE_VARIANT??'candidate-v2'];
  assert(variants[0]!==variants[1]);
  for(const variant of variants)assert(/^[a-z0-9_-]+$/.test(variant),'Invalid fixture variant');
  const directories={
    [variants[0]]:path.resolve(process.env.PROFILE_BASELINE_ARTIFACTS??'/tmp/df-fee-tools/artifacts/baseline'),
    [variants[1]]:path.resolve(process.env.PROFILE_CANDIDATE_ARTIFACTS??'/tmp/df-api-compatible-v2-native'),
  };
  const stateDirectory=path.resolve(process.env.PROFILE_STATE_DIRECTORY??fileURLToPath(new URL('.state/',import.meta.url)));
  const nodeUrl=process.env.AZTEC_NODE_URL??'http://127.0.0.1:8097';
  const output=path.resolve(process.env.PROFILE_OUTPUT??fileURLToPath(new URL('../../docs/api-compatibility/native-proof-profile-v2.json',import.meta.url)));
  assert(!fs.existsSync(output),`Refusing to overwrite existing measurements: ${output}. Use PROFILE_OUTPUT for another run.`);
  const bbPath=process.env.PROFILE_BB_BINARY??'/tmp/df-fee-tools/node_modules/@aztec/bb.js/build/arm64-macos/bb';
  assert(fs.statSync(bbPath).isFile(),'Real native Barretenberg binary is required');
  const sdk={wallets:packageVersion('@aztec/wallets','@aztec/wallets/embedded'),
    aztec:packageVersion('@aztec/aztec.js','@aztec/aztec.js/node'),
    stdlib:packageVersion('@aztec/stdlib','@aztec/stdlib/abi'),
    barretenberg:packageVersion('@aztec/bb.js','@aztec/bb.js')};
  assert(Object.values(sdk).every(version=>version==='5.2.0'),'This comparison is pinned to SDK5.2.0');
  const samples=[],fixtures={},artifacts={},provenance={};
  const report={status:'preparing',passed:false,startedAt:new Date().toISOString(),
    scope:'Real native Aztec5.2 whole private transaction ClientIVC proof generation and cryptographic verification, including account and private kernels. Excludes public execution, transaction inclusion, Fee Juice, browser performance and mobile performance. No transaction is sent.',
    configuration:{methods:selected,variants,caseIds:cases,measuredRounds:rounds,warmupRounds:1,threads:4,
      order:'For each method, baseline/candidate at warmup; reverse their order every subsequent round.',
      timestamp:'One fresh common chain timestamp per pair; every other prepared witness field remains unchanged.',
      artifacts:directories,stateDirectory,nodeUrl,bbPath,nativeBinarySha256:hash(fs.readFileSync(bbPath)),sdk,
      profileMode:'none',skipProofGeneration:false,proverEnabled:true},
    machine:{platform:os.platform(),architecture:os.arch(),cpuModel:os.cpus()[0]?.model,cpuCount:os.cpus().length,totalMemoryBytes:os.totalmem(),nodeVersion:process.version},
    fixtures:{},artifacts:provenance,samples,summary:{}};
  const save=()=>{report.updatedAt=new Date().toISOString();report.summary=summarize(samples,selected,variants);
    const completed=selected.filter(method=>report.summary[method].measuredRounds===rounds);
    report.uxAssessment={scope:'Observed native proof latency only; this does not certify browser/mobile UX or statistical equivalence.',
      completedMethods:completed.length,requiredMethods:selected.length,
      methodsWithHigherCandidateMedian:Object.fromEntries(['provingMs','totalMs','wallMs'].map(metric=>
        [metric,completed.filter(method=>report.summary[method].metrics[metric].medianChangePercent>0)]))};
    fs.mkdirSync(path.dirname(output),{recursive:true});fs.writeFileSync(output+'.tmp',json(report)+'\n');fs.renameSync(output+'.tmp',output);};
  // Validate every artifact and fixture before initializing the expensive prover.
  for(const [variantIndex,variant] of variants.entries()){
    artifacts[variant]={};provenance[variant]={};fixtures[variant]={};report.fixtures[variant]={};
    const expectedFiles=variantIndex===0?files:{...files,...auxiliaryFiles};
    assert.equal(Object.keys(expectedFiles).length,variantIndex===0?17:20);
    for(const [role,file] of Object.entries(expectedFiles)){
      const artifactPath=path.join(directories[variant],file),bytes=fs.readFileSync(artifactPath),raw=JSON.parse(bytes);
      assert.equal(raw.transpiled,true,`${variant}/${role} must be a native-processed artifact`);
      const artifact=loadContractArtifact(raw);
      artifacts[variant][role]={artifact,raw};
      provenance[variant][role]={file:artifactPath,sha256:hash(bytes),noirVersion:raw.noir_version,instances:{}};
    }
    for(const method of selected){
      const fixturePath=path.join(stateDirectory,`${variant}-${method}-${cases[method]}.json`);
      const bytes=fs.readFileSync(fixturePath),fixture=JSON.parse(bytes),system=methods[method];
      assert.equal(fixture.system,system);assert.equal(fixture.method,method);assert.equal(fixture.caseId,cases[method]);
      const {artifact,raw}=artifacts[variant][system],abi=findFunction(artifact,method);
      assert(abi?.functionType==='private',`${method} must be an original private entry`);
      assert(raw.functions.find(fn=>fn.name===method)?.custom_attributes.includes('abi_private'));
      for(const role of Object.keys(expectedFiles))assert(fixture.contracts[role],`${variant}/${method} missing deployed ${role}`);
      const input=Object.fromEntries(abi.parameters.map(p=>{assert(Object.hasOwn(fixture.input,p.name),`Missing ${method}.${p.name}`);return[p.name,revive(p.type,fixture.input[p.name])];}));
      const snark=input.snark_config??input.provided_snark_config;
      if(snark)assert.equal(snark.disable_zk_checks,false,`${method}: coordinate checks must remain enabled`);
      fixtures[variant][method]={fixture,abi,input};
      report.fixtures[variant][method]={file:fixturePath,sha256:hash(bytes),system,caseId:cases[method],
        contract:fixture.contracts[system],admin:fixture.admin,actor:fixture.actor??fixture.admin,preparedTimestamp:fixture.input.timestamp??null,
        privateBytecodeSha256:hash(Buffer.from(raw.functions.find(fn=>fn.name===method).bytecode,'base64')),
        coordinateChecksEnabled:snark?snark.disable_zk_checks===false:null};
    }
  }
  for(const method of selected){
    assert.deepEqual(
      fixtures[variants[0]][method].abi.parameters.map(p=>({name:p.name,type:canonicalType(p.type)})),
      fixtures[variants[1]][method].abi.parameters.map(p=>({name:p.name,type:canonicalType(p.type)})),
      `${method}: original private ABI must be identical`);
    assert.equal(report.fixtures[variants[0]][method].actor,report.fixtures[variants[1]][method].actor,`${method}: paired actor must be identical`);
  }
  save();
  const node=createAztecNodeClient(nodeUrl);
  let wallet;
  try{
    if(selected.includes('find_artifact')){
      const current=BigInt(await node.getBlockNumber());
      const anchors=variants.map(variant=>BigInt(fixtures[variant].find_artifact.input.planet.prospected_block_number));
      assert.equal(anchors[0],anchors[1],'Find proof fixtures must use the same historical seed block');
      for(const anchor of anchors)assert(anchor>0n&&current>=anchor&&current-anchor<256n,'Find proof fixture has expired; measure a fresh matched Find case and select it with PROFILE_CASES_JSON');
      report.findAnchor={number:anchors[0],currentBlock:current,age:current-anchors[0]};
    }
    wallet=await EmbeddedWallet.create(node,{pxe:{dataDirectory:fs.mkdtempSync(path.join(os.tmpdir(),'df-api-native-profile-')),
      proverEnabled:true,proverOrOptions:{bbPath,threads:4}}});
    const accounts=await registerInitialLocalNetworkAccountsInWallet(wallet),admin=accounts[0];
    const options={from:admin,fee:{gasSettings:{maxFeesPerGas:new GasFees(0n,100000000000000n)}}};
    const registered=new Map(),contracts={};
    for(const variant of variants){
      contracts[variant]={};
      for(const [role,{artifact}] of Object.entries(artifacts[variant])){
        const expectedClass=(await getContractClassFromArtifact(artifact)).id;
        provenance[variant][role].classId=expectedClass.toString();
        for(const method of selected){
          const fixture=fixtures[variant][method].fixture;
          assert.equal(fixture.admin,admin.toString(),'Use the exact fixture account');
          assert(accounts.some(account=>account.toString()===(fixture.actor??fixture.admin)),'Selected fixture actor must be registered and funded');
          const address=AztecAddress.fromStringUnsafe(fixture.contracts[role]),key=address.toString();
          if(!registered.has(key)){
            const instance=await node.getContract(address);assert(instance,`${role} must be deployed`);
            assert(instance.currentContractClassId.equals(expectedClass),`${variant}/${role} current class must match the measured artifact`);
            await wallet.registerContract(instance,artifact);registered.set(key,expectedClass.toString());
          }else assert.equal(registered.get(key),expectedClass.toString(),'Address has conflicting artifact classes');
          provenance[variant][role].instances[key]={currentClassId:expectedClass.toString()};
          if(role===methods[method])contracts[variant][method]=await Contract.at(address,artifact,wallet);
        }
      }
    }
    const creator=wallet.pxe.proofCreator;
    assert.equal(creator.constructor.name,'BBPrivateKernelProver');
    assert.equal(creator.options.threads,4);assert.equal(creator.options.bbPath,bbPath);
    const createProof=creator.createChonkProof.bind(creator);
    let observedProofs=[];
    // Observe the genuine native result without replacing any proof generation,
    // witness, circuit, verification, or randomness implementation.
    creator.createChonkProof=async(...args)=>{
      const proof=await createProof(...args);assert.equal(proof.isEmpty(),false);
      const bytes=proof.toBuffer();observedProofs.push({nonempty:true,fieldsWithPublicInputs:proof.fieldsWithPublicInputs.length,
        serializedBytes:bytes.length,sha256:hash(bytes),compressedBytes:proof.compressedProof?.length??null});
      return proof;
    };
    report.status='profiling';report.registeredGameInstances=registered.size;save();
    for(const method of selected){
      for(let round=0;round<=rounds;round++){
        const block=await node.getBlock('latest'),pairTimestamp=BigInt(block.header.globalVariables.timestamp);
        const order=round%2?[...variants].reverse():variants;
        for(const [position,variant] of order.entries()){
          const {abi,fixture}=fixtures[variant][method];
          const input=Object.fromEntries(abi.parameters.map(p=>[p.name,revive(p.type,fixture.input[p.name])]));
          if(Object.hasOwn(input,'timestamp'))input.timestamp=pairTimestamp;
          const call=contracts[variant][method].methods[method](...abi.parameters.map(p=>input[p.name]));
          const actionOptions={...options,from:AztecAddress.fromStringUnsafe(fixture.actor??fixture.admin)};
          observedProofs=[];
          report.inProgress={variant,method,round,warmup:round===0,position,pairTimestamp,startedAt:new Date().toISOString()};save();
          const start=performance.now();
          const profile=await wallet.profileTx(await call.request(actionOptions),{...actionOptions,profileMode:'none',skipProofGeneration:false});
          const wallMs=performance.now()-start;
          assert.equal(observedProofs.length,1,'Exactly one genuine whole-transaction proof is required');
          assert(Number.isFinite(profile.stats.timings.proving)&&profile.stats.timings.proving>0);
          assert(Number.isFinite(profile.stats.timings.total)&&profile.stats.timings.total>0);
          assert(profile.executionSteps.some(step=>step.functionName.endsWith(`:${method}`)),'Original private game method must execute');
          samples.push({variant,system:methods[method],method,caseId:cases[method],round,warmup:round===0,position,
            pairedTimestamp:pairTimestamp,inputTimestamp:input.timestamp??null,
            fixtureSha256:report.fixtures[variant][method].sha256,artifactSha256:provenance[variant][methods[method]].sha256,
            inputSha256:hash(json(input)),proof:observedProofs[0],wallMs,stats:profile.stats,
            executionSteps:profile.executionSteps.map(step=>({functionName:step.functionName,timings:step.timings}))});
          delete report.inProgress;save();
          console.log('PROOF',variant,method,'round',round,'provingMs',profile.stats.timings.proving,'totalMs',profile.stats.timings.total);
        }
      }
    }
    report.status='complete';report.passed=true;report.completedAt=new Date().toISOString();save();
  }catch(error){report.status='failed';report.error={name:error.name,message:String(error.message??error).slice(0,2400)};save();
    throw new Error(`Proof profiling failed; partial evidence is saved in ${output}: ${report.error.message.slice(0,300)}`);}
  finally{if(wallet)await wallet.stop();}
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))await main();
