import test from 'node:test';
import assert from 'node:assert/strict';
import {decodeKnownRevert} from './known-revert.mjs';
test('unknown System selectors never enter custom-fixture WASM decoder',()=>{
 const error={revertData:[{toBigInt:()=>123n}]},custom={errorTypes:{456:{}}};
 assert.equal(decodeKnownRevert(error,[custom],()=>{throw Error('Unknown selector reached decoder');}),undefined);
 assert.equal(decodeKnownRevert({},[custom],()=>{throw Error('Empty data reached decoder');}),undefined);
});
test('matching selector uses the precise returned payload and matching System ABI',()=>{
 const data=[{toBigInt:()=>123n},99n],custom={errorTypes:{456:{}}},system={errorTypes:{123:{}}};
 const decoded=decodeKnownRevert({revertData:data},[custom,system],(actual,abi)=>{assert.equal(actual,data);assert.equal(abi,system);return 'Actual original assertion';});
 assert.equal(decoded,'Actual original assertion');
});
