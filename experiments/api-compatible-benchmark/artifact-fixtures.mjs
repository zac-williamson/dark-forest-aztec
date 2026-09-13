import assert from 'node:assert/strict';
import {AztecAddress} from '@aztec/aztec.js/addresses';

const METHODS = ['prospect_planet', 'find_artifact', 'deposit_artifact', 'withdraw_artifact',
  'give_spaceships', 'activate_artifact', 'deactivate_artifact'];
const TYPES = {monolith:1n, wormhole:5n, shield:6n, photoid:7n, bloom:8n,
  black_domain:9n, crescent:11n, gear:13n};

// SDK addresses are immutable values; preserve their prototype while cloning
// every mutable array and record that a fixture can change.
function clone(value) {
  if (value === null || typeof value !== 'object') return value;
  if (typeof value.toBigInt === 'function') return value;
  if (Array.isArray(value)) return value.map(clone);
  return Object.fromEntries(Object.entries(value).map(([key,item]) => [key,clone(item)]));
}

const aliases = {
  location_id:'location', planet_artifacts_state:'planetArtifacts', planet_events_state:'planetEvents',
  provided_snark_config:'snark_config', artifact_location:'artifactLocation',
};

function seed(store,id,state) { return {store,id,state:clone(state)}; }

function makeArtifact(base,type,{active=false,owner=base.admin}={}) {
  const artifact = clone(base.artifact);
  assert(artifact && typeof artifact === 'object','base.artifact must be a complete original ABI record');
  return Object.assign(artifact, {
    planet_discovered_on:BigInt(base.location), rarity:1n, planet_biome:1n,
    minted_at_timestamp:1n, discoverer:base.admin, artifact_type:type,
    activations:active?1n:0n, last_activated:active?1n:0n, last_deactivated:0n,
    wormhole_to:active&&type===TYPES.wormhole?BigInt(base.location)+1n:0n,
    owner,controller:base.admin,last_updated:1n,
  });
}

function makeLocation(base,planet=BigInt(base.location)) {
  assert(base.artifactLocation,'base.artifactLocation must be a complete original ABI record');
  return {...clone(base.artifactLocation),planet_id:planet,voyage_id:0n,last_updated:1n};
}

/**
 * Pure fixture preparation: no wallet, node reads or transactions.
 *
 * The runner supplies a fresh zero ABI `input`, a complete shared `base`, and
 * applies returned seeds/config updates equally to baseline and candidate.
 * Find requires a fixed already-mined seed block, never a per-variant block.
 */
export function buildArtifactCase({runtime,method,caseId='normal',base,input}) {
  assert(METHODS.includes(method),`Unknown artifact action ${method}`);
  assert(base && input,'base and original ABI input are required');
  assert(base.admin ?? runtime?.admin,'A transaction sender is required');
  const sender=base.admin ?? runtime.admin;
  const state=clone(input);
  for(const key of Object.keys(state)) {
    const name=Object.hasOwn(base,key)?key:aliases[key];
    if(name && Object.hasOwn(base,name)) state[key]=clone(base[name]);
  }
  const location=BigInt(base.location),timestamp=BigInt(base.timestamp);
  state.location_id=location;state.timestamp=timestamp;
  state.planet=clone(base.planet);
  Object.assign(state.planet,{owner:sender,is_initialized:true,destroyed:false,last_updated:1n});
  state.planet_artifacts_state=clone(base.planetArtifacts);
  state.planet_events_state=clone(base.planetEvents);
  assert(state.planet_artifacts_state.ids.length===20 && state.planet_events_state.events.length===20);
  state.planet_artifacts_state.ids.fill(0n);state.planet_artifacts_state.count=0n;state.planet_artifacts_state.last_updated=1n;
  state.planet_events_state.events=state.planet_events_state.events.map(event=>({...event,id:0n}));
  state.planet_events_state.count=0n;state.planet_events_state.last_updated=1n;
  if(Object.hasOwn(state,'world')) {
    state.world=clone(base.world);state.world.paused=false;
  }
  if(Object.hasOwn(state,'player')) {
    state.player=clone(base.player);
    Object.assign(state.player,{init_timestamp:1n,home_planet_id:location,last_updated:1n});
  }

  const selectedType=Object.hasOwn(TYPES,caseId)?TYPES[caseId]:TYPES.monolith;
  const artifactId=BigInt(base.artifactId ?? (9_700_000n+BigInt(METHODS.indexOf(method))*100n+selectedType));
  const extra={method,caseId,queueCount:0,ownedGear:false,originalChecksEnabled:true};
  const additionalSeeds=[];
  const configUpdates=[];

  if(method==='prospect_planet' || method==='find_artifact') {
    assert(base.spaceships_config,'Preserve supplied spaceship settings rather than silently disabling Gear');
    state.spaceships_config=clone(base.spaceships_config);
    state.planet.planet_type=2n; // Ruins
    state.planet.has_tried_finding_artifact=false;
    if(method==='prospect_planet') {
      state.planet.prospected_block_number=0n;
      extra.publicBlockNumberField='PlanetUpdate.state.prospected_block_number';
    } else {
      assert(base.seedBlock && BigInt(base.seedBlock.number)>0n,'Find needs one fixed historical seed block');
      state.planet.prospected_block_number=BigInt(base.seedBlock.number);
      state.x=BigInt(base.x);state.y=BigInt(base.y);
      state.biomebase=BigInt(base.biomebase ?? base.perlin);
      state.provided_snark_config=clone(base.snark_config);
      assert(state.provided_snark_config.disable_zk_checks===false,'Find fixture must keep location/biome proof checks enabled');
      state.game_config_core=clone(base.game_config_core);
      state.world_config=clone(base.world_config);
      state.artifacts_config=clone(base.artifacts_config);
      extra.fixedSeedBlock=clone(base.seedBlock);
      extra.generatedArtifactIdRule='Poseidon2(location_id, fixed historical block-header hash); no ID normalization';
    }
    if(state.spaceships_config.gear) {
      const gearId=artifactId+50n,gear=makeArtifact({...base,admin:sender},TYPES.gear,{owner:AztecAddress.ZERO});
      const gearLocation=makeLocation(base);
      state.planet_artifacts_state.ids[0]=gearId;state.planet_artifacts_state.count=1n;
      state.owned_artifacts[0]=clone(gear);state.owned_artifact_locations[0]=clone(gearLocation);
      additionalSeeds.push(seed('artifact',gearId,gear),seed('artifact_location',gearId,gearLocation));
      extra.ownedGear=true;
    }
  } else if(method==='give_spaceships') {
    assert(base.spaceships_config,'GiveSpaceships needs explicit supplied spaceship settings');
    state.spaceships_config=clone(base.spaceships_config);
    state.planet.is_home_planet=true;
    state.player.claimed_ships=false;
    extra.enabledShips=['mothership','crescent','whale','gear','titan'].filter(name=>state.spaceships_config[name]);
    assert(extra.enabledShips.length>0,'A successful full-function fixture must create at least one ship');
    extra.generatedArtifactIdRule='Original create_and_place_spaceship(location, sender, type, nonce); no ID normalization';
  } else {
    state.artifact_id=artifactId;
    const active=method==='deactivate_artifact';
    state.artifact=makeArtifact({...base,admin:sender},selectedType,{active});
    state.artifact_location=makeLocation(base);
    if(method==='deposit_artifact' || method==='withdraw_artifact') {
      assert(selectedType<TYPES.crescent && selectedType!==10n,'Vault fixtures cannot deposit/withdraw ships');
      state.planet.planet_type=3n; // TradingPost
      state.planet.planet_level=2n;state.artifact.rarity=1n;
      if(method==='deposit_artifact') {
        state.artifact.owner=sender;
        state.artifact_location=makeLocation(base,0n);
      } else {
        state.artifact.owner=AztecAddress.ZERO;
        state.planet_artifacts_state.ids[0]=artifactId;state.planet_artifacts_state.count=1n;
      }
    } else {
      state.planet_artifacts_state.ids[0]=artifactId;state.planet_artifacts_state.count=1n;
      if(method==='activate_artifact') {
        state.world_config=clone(base.world_config);
        state.planet_default_stats=clone(base.planet_default_stats);
        state.wormhole_to=selectedType===TYPES.wormhole?location+1n:0n;
        const cooldownHours=selectedType<10n?[24n,0n,0n,0n,0n,4n,4n,24n,24n,24n][Number(selectedType)]:0n;
        assert(timestamp>cooldownHours*3600n,'Action time must satisfy the original activation cooldown');
        if(selectedType===TYPES.crescent) {
          state.planet.owner=AztecAddress.ZERO;state.planet.planet_type=0n;
          state.planet.planet_level=2n;state.planet.silver=0n;
        }
      }
    }
    additionalSeeds.push(seed('artifact',artifactId,state.artifact),seed('artifact_location',artifactId,state.artifact_location));
  }

  // Retain nonzero inactive values when explicitly testing their preservation.
  if(caseId==='nonzero_padding') {
    state.planet_artifacts_state.ids[19]=991991n;
    state.planet_events_state.events[19].id=992992n;
    extra.inactivePadding=true;
  }
  const configMethods={provided_snark_config:'set_snark_config',world_config:'set_world_config',
    game_config_core:'set_game_config_core',artifacts_config:'set_artifacts_config',spaceships_config:'set_spaceships_config'};
  for(const [name,setter] of Object.entries(configMethods)) {
    if(Object.hasOwn(state,name)) configUpdates.push({method:setter,args:[clone(state[name])]});
  }
  if(Object.hasOwn(state,'planet_default_stats')) {
    configUpdates.push({method:'set_planet_default_stats',args:[state.planet.planet_level,clone(state.planet_default_stats)]});
  }
  const seeds=[seed('planet',location,state.planet),seed('planet_artifacts',location,state.planet_artifacts_state),
    seed('planet_events',location,state.planet_events_state),...additionalSeeds];
  if(Object.hasOwn(state,'world')) seeds.push(seed('world',0n,state.world));
  if(Object.hasOwn(state,'player')) seeds.push(seed('player',sender,state.player));
  return {input:state,seeds,configUpdates,extra};
}

export const artifactMethods=Object.freeze([...METHODS]);
