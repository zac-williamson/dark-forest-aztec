import {clone} from './base-fixture.mjs';
export const publicSpecs=[...['pause','unpause','admin_set_world_radius','set_owner','add_score','deduct_score','create_planet','admin_initialize_planet'].map(method=>['admin',method]),...['create_artifact','update_artifact','admin_give_artifact','admin_give_spaceship'].map(method=>['artifact_valut',method])];
export function buildPublicCase({method,base:b,input}){
  const seeds=[],seed=(store,id,state)=>seeds.push({store,id,state});
  const index=publicSpecs.findIndex(([,name])=>name===method);
  const unique=98000000n+BigInt(index);
  const values={world:clone(b.world),planet_state:clone(b.planet),planet:clone(b.planet),planet_artifacts_state:clone(b.planetArtifacts),player_state:clone(b.player),planet_id:b.location,location_id:unique,player_address:b.admin,new_owner:b.otherOwner,amount:100n,new_radius:10001n,perlin:15n,level:0n,id:unique,artifact:clone(b.artifact),location:clone(b.artifactLocation)};
  for(const name of Object.keys(input))if(Object.hasOwn(values,name))input[name]=values[name];
  if(['pause','unpause','admin_set_world_radius'].includes(method)){
    input.world.paused=method==='unpause';seed('world',0n,input.world);
  }
  if(method==='set_owner')seed('planet',b.location,input.planet_state);
  if(['add_score','deduct_score'].includes(method))seed('player',b.admin,input.player_state);
  if(method==='create_planet')Object.assign(input.args,{location:unique,perlin:15n,level:0n,planet_type:0n,require_valid_location_id:true});
  if(['create_planet','admin_initialize_planet'].includes(method)){
    // Original verify(Planet::zero()) requires explicit H(zero), unlike is_initialized().
    seed('planet',unique,b.zeroState('planet'));
  }
  if(method==='update_artifact'){
    seed('artifact',input.id,input.artifact);seed('artifact_location',input.id,input.location);
  }
  if(['create_artifact','admin_give_artifact','admin_give_spaceship'].includes(method)){
    Object.assign(input.args,{id:unique,planet_id:b.location,rarity:1n,biome:1n,discoverer:b.admin,controller:b.admin,artifact_type:method==='admin_give_spaceship'?13n:1n});
    if(method!=='create_artifact')seed('planet_artifacts',b.location,input.planet_artifacts_state);
    if(method==='admin_give_spaceship')seed('planet',b.location,input.planet);
  }
  return {input,seeds};
}
