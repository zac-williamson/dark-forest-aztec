import test from 'node:test';
import assert from 'node:assert/strict';
import ts from 'typescript';
import {adaptCheckedArtifactWrapper} from './wrapper-compatibility.ts';
const wrapper = (name) => `import ${name}ContractArtifactJson from './native.json' with { type: 'json' };
export const artifact=loadContractArtifact(${name}ContractArtifactJson as NoirCompiledContract);
export const forPublic=()=>loadContractArtifactForPublic(${name}ContractArtifactJson as NoirCompiledContract);
`;
test('type adapter emits identical executable JavaScript for both SDK loader paths',()=>{
 for(const name of ['Core','ArtifactStorage','ArtifactLocationStorage']){
  const original=wrapper(name),adapted=adaptCheckedArtifactWrapper(original,name);
  const emit=s=>ts.transpileModule(s,{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2020}}).outputText;
  assert.equal(emit(adapted),emit(original));
  assert.equal(adapted.replaceAll(' as unknown as NoirCompiledContract',' as NoirCompiledContract'),original);
 }
});
test('unexpected SDK assertion count or loader shape fails closed',()=>{
 const s=wrapper('Core');
 for(const altered of [s.replace('loadContractArtifactForPublic','otherLoader'),s+s,s.replace('CoreContractArtifactJson as NoirCompiledContract','differentOperand')])assert.throws(()=>adaptCheckedArtifactWrapper(altered,'Core'));
});
test('already adapted and wrong-name wrappers are rejected',()=>{
 const s=wrapper('Core');assert.throws(()=>adaptCheckedArtifactWrapper(s,'Move'));assert.throws(()=>adaptCheckedArtifactWrapper(adaptCheckedArtifactWrapper(s,'Core'),'Core'));
});
