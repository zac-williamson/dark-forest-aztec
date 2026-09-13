use config::Config;
use aztec::{test::helpers::test_environment::TestEnvironment,protocol::{address::AztecAddress,hash::poseidon2_hash,traits::Serialize}};
use types::config::{world::WorldConfig,snark::SnarkConfig,game::{GameConfigCore,PlanetLevelThresholds,PlanetTypeWeightsTier},artifacts::ArtifactsConfig,space_junk::SpaceJunkConfig,spaceships::SpaceshipsConfig,default_stats::PlanetDefaultStats};

unconstrained fn setup()->(TestEnvironment,AztecAddress,AztecAddress){
 let mut env=TestEnvironment::new();let admin=env.create_light_account();
 let address=env.deploy("artifacts@config/Config").with_public_initializer(admin,Config::interface().constructor(admin));
 (env,admin,address)
}
unconstrained fn check(env:TestEnvironment,address:AztecAddress)->Field{
 let c=Config::at(address);let h=env.execute_utility(c.get_all_config_hashes_unconstrained());
 let hashes=[h[1],h[0],h[2],h[3],h[10],h[4],h[5],h[6],h[7]];
 let root=poseidon2_hash(hashes.concat([h[8]]));
 assert_eq(root,env.execute_utility(c.get_move_configuration_root_unconstrained()));
 let stats=env.execute_utility(c.get_planet_default_stats_hash_unconstrained(0));
 assert(env.view_public(c.verify_move_configuration(root,0,stats)));
 assert(env.view_public(c.verify_config_hashes(0,stats,hashes)));
 assert(env.view_public(c.verify_artifacts_config_hash(h[8])));
 assert(!env.view_public(c.verify_move_configuration(root+1,0,stats)));
 assert(!env.view_public(c.verify_move_configuration(root,0,stats+1)));
 root
}
#[test]
unconstrained fn all_common_setters_and_default_batches_keep_cache_atomic(){
 let(mut env,admin,address)=setup();let c=Config::at(address);check(env,address);
 env.call_public(admin,c.set_world_config(WorldConfig::zero()));check(env,address);
 env.call_public(admin,c.set_snark_config(SnarkConfig::zero()));check(env,address);
 env.call_public(admin,c.set_game_config_core(GameConfigCore::zero()));check(env,address);
 env.call_public(admin,c.set_planet_level_thresholds(PlanetLevelThresholds::zero()));check(env,address);
 env.call_public(admin,c.set_space_junk_config(SpaceJunkConfig::zero()));check(env,address);
 env.call_public(admin,c.set_artifacts_config(ArtifactsConfig::zero()));check(env,address);
 for tier in 0..4 {
  env.call_public(admin,c.set_planet_type_weights_tier(tier as u8,PlanetTypeWeightsTier::zero(tier as u8)));check(env,address);
  env.call_public(admin,c.set_default_game_config_planet_type_weights_tier(tier as u8));check(env,address);
 }
 env.call_public(admin,c.set_default_configs_batch_1());check(env,address);
 env.call_public(admin,c.set_default_configs_batch_2());check(env,address);
 let mut world=WorldConfig::zero();world.world_radius_min=777;
 let old=check(env,address);env.call_public(admin,c.set_world_config(world));
 assert(old!=check(env,address));
 assert_eq(env.view_public(c.get_world_config()).serialize(),world.serialize());
 assert_eq(env.execute_utility(c.get_world_config_unconstrained()).serialize(),world.serialize());
}
#[test]
unconstrained fn unrelated_config_and_default_levels_do_not_invalidate_other_moves(){
 let(mut env,admin,address)=setup();let c=Config::at(address);let root=check(env,address);
 env.call_public(admin,c.set_spaceships_config(SpaceshipsConfig::zero()));assert_eq(check(env,address),root);
 let stats=PlanetDefaultStats{population_cap:1,population_growth:2,range:3,speed:4,defense:5,silver_growth:6,silver_cap:7,barbarian_percentage:8};
 env.call_public(admin,c.set_planet_default_stats(1,stats));assert(env.view_public(c.verify_move_configuration(root,0,0)));
 assert(!env.view_public(c.verify_move_configuration(root,1,0)));
 assert(env.view_public(c.verify_move_configuration(root,1,poseidon2_hash(stats.serialize()))));
 env.call_public(admin,c.set_planet_default_stats_batch([0,2,3,4,5],[stats;5],5));
 assert_eq(check(env,address),root);
 assert(!env.view_public(c.verify_move_configuration(root,0,0)));
 assert(env.view_public(c.verify_move_configuration(root,0,poseidon2_hash(stats.serialize()))));
}
#[test(should_fail_with="Only admin")]
unconstrained fn strangers_cannot_update_config_or_cache(){
 let(mut env,_admin,address)=setup();let stranger=env.create_light_account();
 env.call_public(stranger,Config::at(address).set_world_config(WorldConfig::zero()));
}
