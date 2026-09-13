import assert from 'node:assert/strict';

const clone=value=>Array.isArray(value)?value.map(clone):value&&typeof value==='object'&&typeof value.toBigInt!=='function'
 ?Object.fromEntries(Object.entries(value).map(([key,item])=>[key,clone(item)])):value;

// This only supplies adversarial inactive input values and the directly specified
// boundary expectation. Real original/candidate private functions perform all game
// calculations. At count zero both actions retain every location. Core then
// stamps carried-ID slots without a count bound; Move stamps only active slots,
// so every inactive Move timestamp remains exactly as supplied.
export function buildInactiveLocationCase(original,role,tag,timestamp){
 assert(['core','move'].includes(role));
 const input=clone(original),batches=[],seeds=[];
 input.timestamp=timestamp;
 const sides=role==='move'?['source','target']:[''];
 for(const [sideIndex,side]of sides.entries()){
  const key=name=>side?`${side}_${name}`:name;
  const pe=input[key('planet_events_state')],pa=input[key('planet_artifacts_state')];
  assert.equal(pe.count,0n);assert.equal(pa.count,0n);
  pa.ids[19]=(1n<<220n)+BigInt(tag*100+sideIndex);
  pe.events[19].id=(1n<<230n)+BigInt(tag*100+sideIndex+1);
  const arrivals=input[key('arrivals')];
  for(let i=0;i<20;i++)assert.equal(arrivals[i].carried_artifact_id,0n,'Start from a no-artifact witness');
  arrivals[19].id=(1n<<210n)+BigInt(tag*100+sideIndex+2);
  arrivals[19].carried_artifact_id=(1n<<205n)+BigInt(tag*100+sideIndex+3);
  const locations=Array.from({length:20},(_,i)=>({
   planet_id:(1n<<200n)+BigInt(tag*10000+sideIndex*100+i),
   voyage_id:(1n<<215n)+BigInt(tag*10000+sideIndex*100+i+1),
   last_updated:(1n<<63n)+BigInt(tag*10000+sideIndex*100+i+2),
  }));
  input[key('arrival_artifact_locations')]=locations;
  const expected=clone(locations);if(role==='core')expected[19].last_updated=timestamp;
  batches.push({side:side||'planet',ids:Array(20).fill(0n),states:expected,count:0n});
  const location=role==='move'?input[`${side}_loc`]:input.location;
  seeds.push({store:'planet',id:location,state:input[key('planet')]},
   {store:'planet_artifacts',id:location,state:pa},{store:'planet_events',id:location,state:pe});
 }
 if(role==='move'){
  for(const id of ['moved_artifact_id','source_activated_artifact_id','target_activated_artifact_id'])assert.equal(input[id],0n);
  assert.equal(input.snark_config.disable_zk_checks,false,'Original cryptographic game checks stay enabled');
  seeds.push({store:'world',id:0n,state:input.world});
 }
 return {input,batches,seeds};
}

export function locationFields(states){
 assert.equal(states.length,20);
 return states.flatMap(state=>[state.planet_id,state.voyage_id,state.last_updated]);
}
