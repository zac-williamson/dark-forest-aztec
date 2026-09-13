import {openRuntime} from './runtime.mjs';
import {makeBase,configure} from './base-fixture.mjs';
const runtime=await openRuntime(process.argv[2]??'baseline',process.argv[3]??'/tmp/df-fee-tools/artifacts/baseline');
const base=await makeBase(runtime);console.log('BASE',base.location.toString(),'historical block',base.seedBlock.number.toString());
await configure(runtime,base);console.log('CONFIGURED',runtime.variant);await runtime.close();
