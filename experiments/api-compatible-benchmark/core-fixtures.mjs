import {poseidon2Hash} from '@aztec/foundation/crypto/poseidon';
import {Fr} from '@aztec/aztec.js/fields';
import {clone} from './base-fixture.mjs';
export async function buildCoreCase({runtime,method,caseId='ordinary',base,input}){
  const b=base,seed=(store,id,state)=>({store,id,state});
  const normalSeeds=()=>[seed('planet',b.location,input.planet_state??input.planet??b.planet),seed('planet_artifacts',b.location,input.planet_artifacts_state??b.planetArtifacts),seed('planet_events',b.location,input.planet_events_state??b.planetEvents),seed('player',b.admin,input.player_state??b.player),seed('world',0n,b.world)];
  for(const name of Object.keys(input))if(Object.hasOwn(b,name))input[name]=clone(b[name]);
  for(const [key,value] of Object.entries({location:b.location,location_id:b.location,provided_snark_config:b.snark_config,planet_state:b.planet,planet:b.planet,planet_artifacts_state:b.planetArtifacts,planet_events_state:b.planetEvents,player_state:b.player,world_state:b.world}))if(Object.hasOwn(input,key))input[key]=clone(value);
  if(method==='move'){
    input=clone(b.move);
    for(const key of Object.keys(input))if(/config|planet_default_stats|planet_type_weights|planet_level_thresholds/.test(key)&&Object.hasOwn(b,key))input[key]=clone(b[key]);
    input.timestamp=b.timestamp;input.source_planet.owner=b.admin;input.target_planet.owner=b.admin;
    const seeds=[seed('world',0n,input.world)];
    for(const side of ['source','target']){
      seeds.push(seed('planet',input[`${side}_loc`],input[`${side}_planet`]),seed('planet_artifacts',input[`${side}_loc`],input[`${side}_planet_artifacts_state`]),seed('planet_events',input[`${side}_loc`],input[`${side}_planet_events_state`]));
    }
    return {input,seeds};
  }
  if(method==='initialize_player'){
    input.x=128n;input.y=0n;input.radius=129n;input.perlin=16n;input.location_id=(await poseidon2Hash([new Fr(b.snark_config.planethash_key),new Fr(input.x),new Fr(input.y)])).toBigInt();input.level=0n;input.player_state=b.zeroState('player');input.planet_state=b.zeroState('planet');input.planet_artifacts_state=b.zeroState('planet_artifacts');input.planet_events_state=b.zeroState('planet_events');
    if(['init_unused_padding','init_existing_planet'].includes(caseId)){
      // Grid intersections at all three Perlin scales retain value16 and satisfy
      // the original98%-to100% spawn annulus with radius=x+1.
      input.x=caseId==='init_unused_padding'?256n:384n;
      do{input.location_id=(await poseidon2Hash([new Fr(b.snark_config.planethash_key),new Fr(input.x),new Fr(0n)])).toBigInt();if(input.location_id>=b.game_config_core.max_location_id)input.x+=256n;else break;}while(input.x<9000n);
      if(input.location_id>=b.game_config_core.max_location_id)throw Error('No admissible grid spawn found for initialization fixture');
      input.radius=input.x+1n;
    }
    if(caseId==='init_unused_padding'){
      input.planet_artifacts_state.ids[19]=(1n<<200n)+923n;
      input.planet_events_state.events[19].id=(1n<<220n)+117n;
      const unchangedSeeds=[seed('planet_artifacts',input.location_id,input.planet_artifacts_state),seed('planet_events',input.location_id,input.planet_events_state)];
      return {input,actor:runtime.accounts[1],seeds:[seed('world',0n,b.world),...unchangedSeeds],unchangedSeeds,requiresAbsent:['player'],extra:{newPlanetBranch:true,unusedNonzeroPadding:true}};
    }
    if(caseId==='init_existing_planet'){
      input.planet_state=clone(b.planet);input.planet_state.owner=b.zeroState('planet').owner;
      input.planet_state.planet_level=0n;input.planet_state.perlin=16n;
      input.planet_artifacts_state=clone(b.planetArtifacts);input.planet_events_state=clone(b.planetEvents);
      return {input,actor:runtime.accounts[2],seeds:[seed('world',0n,b.world),seed('planet',input.location_id,input.planet_state),seed('planet_artifacts',input.location_id,input.planet_artifacts_state),seed('planet_events',input.location_id,input.planet_events_state)],requiresAbsent:['player'],extra:{newPlanetBranch:false,unclaimedExistingPlanet:true}};
    }
    if(caseId!=='ordinary')throw Error(`Unknown initialization fixture ${caseId}`);
    return {input,seeds:[seed('world',0n,b.world)],requiresAbsent:['player','planet']};
  }
  if(method==='reveal_location'){
    input.level=0n;input.planet_state.planet_level=0n;input.is_admin=false;
    return {input,seeds:normalSeeds(),requiresAbsent:['planet_revealed_coords']};
  }
  if(method==='upgrade_planet')input.branch=0n;
  if(method==='withdraw_silver'){
    input.silver_to_withdraw=10000n;input.planet_state.planet_type=3n;
  }
  if(method==='safe_set_owner'){
    input.new_owner=b.otherOwner;input.level=0n;input.planet_state.planet_level=0n;
    return {input,seeds:[seed('planet',b.location,input.planet_state),seed('world',0n,b.world)]};
  }
  return {input,seeds:normalSeeds()};
}
