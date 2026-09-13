import assert from 'node:assert/strict';

// Lossless ordered original event decoding. Only explicit current-time and
// current-block output fields are normalized for historical paired comparisons.
function leafPaths(type,prefix='state'){
  if(type.kind==='struct'&&type.path?.endsWith('::AztecAddress'))return [prefix];
  if(type.kind==='struct')return type.fields.flatMap(field=>leafPaths(field.type,`${prefix}.${field.name}`));
  if(type.kind==='array')return Array.from({length:type.length},(_,index)=>leafPaths(type.type,`${prefix}.${index}`)).flat();
  return [prefix];
}
const currentTimeFields=new Set(['last_updated','created_at','init_timestamp','last_reveal_timestamp','minted_at_timestamp','last_activated','last_deactivated','departure_time']);
export function decodeActionEvents(receipt,timestamp,method,{roleByAddress,rawArtifacts}){
  const changes=[],latest=new Map();
  for(const log of receipt.txEffect.publicLogs){
    const role=roleByAddress[log.contractAddress.toString()];
    assert(role,`Unexpected public event emitter ${log.contractAddress}`);
    assert((rawArtifacts[role].outputs.structs.events??[]).length,`Unexpected public event from ${role}`);
    const wire=log.fields.map(value=>BigInt(value.toString()));
    assert.equal(wire[2],BigInt(receipt.blockNumber),'Event block must equal mined receipt');
    const event=rawArtifacts[role].outputs.structs.events[0];
    const stateType=event.fields.find(field=>field.name==='state').type;
    const paths=leafPaths(stateType),fields=wire.slice(3);assert.equal(fields.length,paths.length,'All original event fields must remain present');
    const normalized=fields.map((value,index)=>{
      const name=paths[index].split('.').at(-1);
      if(currentTimeFields.has(name)&&value===timestamp)return '@transaction_time';
      if(role==='arrival'&&name==='arrival_time')return `@arrival_after:${value-timestamp}`;
      if(method==='prospect_planet'&&name==='prospected_block_number'&&value===BigInt(receipt.blockNumber))return '@transaction_block';
      return value.toString();
    });
    changes.push({store:role,tag:wire[0].toString(),id:wire[1].toString(),fields:normalized});
    latest.set(`${role}:${wire[1]}`,{role,id:wire[1],fields});
  }
  assert(changes.length>0,'Complete action must expose its state changes');
  return {changes,latest};
}
