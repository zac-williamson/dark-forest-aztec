import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';

// Diagnostic-only SDK instrumentation. Original bytes are saved before installation.
// C++ remains the authoritative simulator; the SDK's existing TS comparison runner
// asserts identical gas and transaction effects for each profiled execution.
const sdk='/tmp/df-fee-tools/node_modules/@aztec/simulator/dest/public';
const backup='/tmp/df-api-compatible-avm-profile-sdk';fs.mkdirSync(backup,{recursive:true});
const manifest=[];
function patch(relative,transform){
  const file=path.join(sdk,relative),saved=path.join(backup,path.basename(relative));
  const original=fs.existsSync(saved)?fs.readFileSync(saved,'utf8'):fs.readFileSync(file,'utf8');
  if(!fs.existsSync(saved))fs.writeFileSync(saved,original);
  const result=transform(original);fs.writeFileSync(file,result);
  manifest.push({file,backup:saved,originalSha256:createHash('sha256').update(original).digest('hex'),diagnosticSha256:createHash('sha256').update(result).digest('hex')});
}
function replace(source,from,to){assert(source.includes(from),`SDK5.2 anchor missing: ${from}`);return source.replace(from,to);}
patch('public_processor/public_processor.js',source=>{
  source="import { CppVsTsPublicTxSimulator } from '../public_tx_simulator/cpp_vs_ts_public_tx_simulator.js';\n"+source;
  return replace(source,'return new TelemetryCppPublicTxSimulator(merkleTree, contractsDB, globalVariables, this.telemetryClient, config, this.log.getBindings());',`if (process.env.DF_AVM_PROFILE_OUTPUT) return new CppVsTsPublicTxSimulator(merkleTree, contractsDB, globalVariables, config, this.log.getBindings());
        return new TelemetryCppPublicTxSimulator(merkleTree, contractsDB, globalVariables, this.telemetryClient, config, this.log.getBindings());`);
});
patch('avm/avm_simulator.js',source=>{
  source="import { appendFileSync as dfAppendFileSync } from 'node:fs';\nlet dfCallSequence=0;\n"+source;
  source=replace(source,'const timer = new Timer();',`const timer = new Timer();
        const dfProfile=process.env.DF_AVM_PROFILE_OUTPUT;
        const dfCallId=dfProfile?++dfCallSequence:0;
        const dfPcGas=new Map();
        if(dfProfile)this.tallyInstructionFunction=this.tallyInstruction;`);
  source=replace(source,'const instrStartGas = machineState.gasLeft;',`const dfPc=machineState.pc;
                const instrStartGas = machineState.gasLeft;`);
  source=replace(source,'this.tallyInstructionFunction(instruction.constructor.name, gasUsed);',`this.tallyInstructionFunction(instruction.constructor.name, gasUsed);
                if(dfProfile){const previous=dfPcGas.get(dfPc)??[0,0,0];dfPcGas.set(dfPc,[previous[0]+1,previous[1]+gasUsed.l2Gas,previous[2]+gasUsed.daGas]);}`);
  return replace(source,'this.tallyPrintFunction();\n            this.log.debug(`Core AVM simulation took ${timer.ms()}ms`);',`this.tallyPrintFunction();
            if(dfProfile){const env=this.context.environment;dfAppendFileSync(dfProfile,JSON.stringify({callId:dfCallId,address:env.address.toString(),sender:env.sender.toString(),depth:env.contractCallDepth.toString(),selector:env.calldata.read(0).toString(),calldataLength:env.calldata.length,instructions:machineState.instrCounter,inclusiveGas:totalGasUsed,reverted,opcodes:Object.fromEntries(this.opcodeTallies),pcGas:Array.from(dfPcGas,([pc,values])=>[pc,...values])})+'\\n');}
            this.log.debug(\`Core AVM simulation took \${timer.ms()}ms\`);`);
});
fs.writeFileSync(path.join(backup,'manifest.json'),JSON.stringify(manifest,null,2));
console.log(JSON.stringify({installed:manifest.length,backup,requiresOwnedNodeRestart:true}));
