import fs from 'node:fs';
import {AztecAddress} from '@aztec/aztec.js/addresses';
import {revive,zeroValue,json} from './fixtures.mjs';
import {stateDirectory,findFunction} from './runtime.mjs';
export function clone(value){
  if(value instanceof AztecAddress)return value;
  if(Array.isArray(value))return value.map(clone);
  if(value&&typeof value==='object')return Object.fromEntries(Object.entries(value).map(([key,item])=>[key,clone(item)]));
  return value;
}
export const addressOptions={addressFromBigInt:value=>AztecAddress.fromBigIntUnsafe(value)};
export async function makeBase(runtime){
  const old=JSON.parse(fs.readFileSync(new URL('./seed-fixtures/fixture-0-account.json',import.meta.url)));
  const parameters=runtime.artifacts.move.functions.find(fn=>fn.name==='move').parameters;
  const move=Object.fromEntries(parameters.map(parameter=>[parameter.name,revive(parameter.type,old[parameter.name],addressOptions)]));
  const block=await runtime.node.getBlock('latest');
  const timestamp=BigInt(block.header.globalVariables.timestamp)+1n;
  const location=move.target_loc;
  const zeroState=store=>zeroValue(findFunction(runtime.artifacts[store],'set').parameters.at(-1).type,addressOptions);
  const planet=clone(move.target_planet_state??move.target_planet); // Original Move parameter names are retained below.
  if(!planet)throw Error('Original Move target planet fixture missing');
  Object.assign(planet,{owner:runtime.admin,planet_level:2n,planet_type:0n,space_type:0n,perlin:15n,silver:100000n,silver_cap:100000n,population:50000n,population_cap:100000n});
  const planetArtifacts=zeroState('planet_artifacts');planetArtifacts.last_updated=1n;
  const planetEvents=zeroState('planet_events');planetEvents.last_updated=1n;
  const player=zeroState('player');Object.assign(player,{init_timestamp:1n,home_planet_id:location,score:1000n,last_updated:1n});
  const artifact=zeroState('artifact');Object.assign(artifact,{owner:runtime.admin,controller:runtime.admin,discoverer:runtime.admin,artifact_type:1n,rarity:1n,last_updated:1n});
  const artifactLocation=zeroState('artifact_location');artifactLocation.last_updated=1n;
  const b={move,location,x:1n,y:0n,perlin:15n,timestamp,admin:runtime.admin,otherOwner:runtime.accounts[1],planet,planetArtifacts,planetEvents,player,artifact,artifactLocation,world:clone(move.world),zeroState};
  for(const parameter of parameters)if(/config|planet_default_stats|planet_type_weights|planet_level_thresholds/.test(parameter.name))b[parameter.name]=clone(move[parameter.name]);
  b.snark_config.disable_zk_checks=false;b.snark_config.perlin_length_scale=32n;
  Object.assign(b.world_config,{time_factor_hundredths:100n,silver_score_value:100n,admin_can_add_planets:true,planet_transfer_enabled:true});
  Object.assign(b.game_config_core,{max_natural_planet_level:9n,perlin_threshold_1:20n,perlin_threshold_2:24n,perlin_threshold_3:28n,init_perlin_min:0n,init_perlin_max:255n,biome_threshold_1:15n,biome_threshold_2:17n,planet_rarity:1n,max_location_id:(move.source_loc>move.target_loc?move.source_loc:move.target_loc)+1n});
  b.planet_level_thresholds.thresholds=[16777216n,...Array(9).fill(0n)];
  for(let tier=0;tier<4;tier++)b[`planet_type_weights_tier_${tier}`].weights=Array.from({length:10},()=>[1n,0n,0n,0n,0n]);
  Object.assign(b.planet_default_stats,{population_cap:100000n,population_growth:1n,range:1000n,speed:100n,defense:100n,silver_cap:100000n,silver_growth:1n,barbarian_percentage:0n});
  b.artifacts_config.token_mint_end_timestamp=4102444800n;
  b.artifacts_config.artifact_point_values=b.artifacts_config.artifact_point_values.map(()=>100n);
  b.spaceships_config={gear:true,mothership:true,titan:true,crescent:true,whale:true};
  b.upgrade_config={silver_cost_percent:10n,max_total_level_nebula:4n,max_total_level_space:5n,max_total_level_deep_space:6n,max_total_level_dead_space:6n,max_branch_level:4n};
  b.upgrade={pop_cap_multiplier:110n,pop_gro_multiplier:110n,range_multiplier:110n,speed_multiplier:110n,def_multiplier:120n};
  const configKeys=['snark_config','world_config','game_config_core','planet_level_thresholds','space_junk_config','artifacts_config','spaceships_config','upgrade_config','upgrade','planet_default_stats',...Array.from({length:4},(_,tier)=>`planet_type_weights_tier_${tier}`)];
  const configPath=new URL('common-config.json',stateDirectory);
  if(!fs.existsSync(configPath))fs.writeFileSync(configPath,json(Object.fromEntries(configKeys.map(key=>[key,b[key]]))));
  else{
    const saved=JSON.parse(fs.readFileSync(configPath));
    for(const key of configKeys){
      const method=key.startsWith('planet_type_weights_tier_')?'set_planet_type_weights_tier':`set_${key}`;
      const type=findFunction(runtime.artifacts.config,method).parameters.at(-1).type;
      b[key]=revive(type,saved[key],addressOptions);
    }
  }
  const findPair=process.env.BENCH_FIND_PAIR;
  if(findPair&&!/^[a-z0-9_]+$/.test(findPair))throw Error('Find pair label must use lowercase letters, digits or underscore');
  const seedPath=new URL(findPair?`shared-seed-block-${findPair}.json`:'shared-seed-block.json',stateDirectory);
  if(!fs.existsSync(seedPath))fs.writeFileSync(seedPath,json({number:BigInt(block.number),hash:(await block.header.hash()).toBigInt()}));
  const seed=JSON.parse(fs.readFileSync(seedPath));b.seedBlock={number:BigInt(seed.number),hash:BigInt(seed.hash)};
  return b;
}

export async function configure(runtime,base){
  const marker=new URL(`${runtime.variant}-fixture-configured`,stateDirectory);
  if(fs.existsSync(marker))return;
  const c=runtime.contracts.config,calls=[];
  for(const key of ['snark_config','world_config','game_config_core','planet_level_thresholds','space_junk_config','artifacts_config','spaceships_config','upgrade_config'])calls.push(c.methods[`set_${key}`](base[key]));
  await runtime.batch(calls);calls.length=0;
  // Each tier writes50 fields; combining tiers exceeds the protocol write budget.
  for(let tier=0;tier<4;tier++)await c.methods.set_planet_type_weights_tier(tier,base[`planet_type_weights_tier_${tier}`]).send(runtime.opts);
  for(const level of [0n,1n,2n,3n])calls.push(c.methods.set_planet_default_stats(level,base.planet_default_stats));
  for(const branch of [0n,1n,2n])calls.push(c.methods.set_upgrade_by_branch_level(branch,0n,base.upgrade));
  await runtime.batch(calls);console.log('CONFIGURED',runtime.variant,'same19 typed setters');
  fs.writeFileSync(marker,'Original typed fixture configuration initialized.\n');
}
