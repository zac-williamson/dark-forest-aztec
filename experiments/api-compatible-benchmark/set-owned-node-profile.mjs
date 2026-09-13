import assert from 'node:assert/strict';
const expectedPid=Number(process.argv[2]),enabled=process.argv[3]==='on';
assert(Number.isSafeInteger(expectedPid)&&expectedPid>1,'Pass the owned Aztec node PID');
assert(['on','off'].includes(process.argv[3]),'Mode must be on or off');
process.kill(expectedPid,'SIGUSR1');
let targets;
for(let i=0;i<20;i++){
 try{targets=await(await fetch('http://127.0.0.1:9229/json/list')).json();break;}
 catch{await new Promise(resolve=>setTimeout(resolve,100));}
}
assert(targets?.length===1,'Expected exactly one loopback Node inspector target');
const socket=new WebSocket(targets[0].webSocketDebuggerUrl);
await new Promise((resolve,reject)=>{socket.addEventListener('open',resolve,{once:true});socket.addEventListener('error',reject,{once:true});});
let sequence=0;const pending=new Map();
socket.addEventListener('message',event=>{const message=JSON.parse(event.data);if(message.id){const entry=pending.get(message.id);pending.delete(message.id);message.error?entry.reject(Error(message.error.message)):entry.resolve(message.result);}});
const evaluate=expression=>new Promise((resolve,reject)=>{const id=++sequence;pending.set(id,{resolve,reject});socket.send(JSON.stringify({id,method:'Runtime.evaluate',params:{expression,returnByValue:true}}));});
const pid=(await evaluate('process.pid')).result.value;
assert.equal(pid,expectedPid,'Refuse to change any process except the explicitly owned benchmark node');
const expression=enabled?'process.env.DF_AVM_PROFILE_OUTPUT="/tmp/df-api-compatible-avm-calls.jsonl"':'delete process.env.DF_AVM_PROFILE_OUTPUT';
await evaluate(expression);
const actual=(await evaluate('!!process.env.DF_AVM_PROFILE_OUTPUT')).result.value;assert.equal(actual,enabled);
// Close the debugging listener after its acknowledgement; profiling itself needs no inspector.
await evaluate('setTimeout(()=>process.getBuiltinModule("inspector").close(),100); true');
socket.close();
console.log(JSON.stringify({pid,profileEnabled:actual,chainRestarted:false}));
