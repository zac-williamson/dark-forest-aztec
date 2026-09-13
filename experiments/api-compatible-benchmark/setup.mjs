import fs from 'node:fs';
import {openRuntime,stateDirectory,findFunction} from './runtime.mjs';
const runtime=await openRuntime(process.argv[2]??'baseline',process.argv[3]??'/tmp/df-fee-tools/artifacts/baseline');
await runtime.deployAll();
const marker=new URL(`${runtime.variant}-addresses-authorized-v2`,stateDirectory);
if(!fs.existsSync(marker)){
  const c=runtime.contracts,calls=[];
  for(const [name,artifact] of Object.entries(runtime.artifacts)){
    const method=findFunction(artifact,'set_all_storage_addresses');
    if(!method)continue;
    const args=method.parameters.map(parameter=>{
      const role=parameter.name.replace(/_storage_address$|_addr$/,'').replace(/^arrivals$/,'arrival');
      if(!c[role])throw Error(`Unknown original storage role ${parameter.name}`);
      return c[role].address;
    });
    calls.push(c[name].methods.set_all_storage_addresses(...args));
  }
  // Union of actual writer dependencies; per-action conditional revocation is tested separately.
  const writers={admin:['world','planet','player'],core:['planet','planet_artifacts','planet_events','artifact_location','player','planet_revealed_coords'],move:['planet','planet_artifacts','planet_events','arrival','artifact','artifact_location'],artifact_prospect:['planet','planet_artifacts','planet_events','artifact_location'],artifact_find:['planet','planet_artifacts','planet_events','artifact','artifact_location','player'],artifact_valut:['planet','planet_artifacts','planet_events','artifact','artifact_location','player'],artifact_action:['planet','planet_artifacts','planet_events','artifact','artifact_location']};
  await runtime.batch(calls);
  const grants=[];for(const [system,stores] of Object.entries(writers))for(const store of stores){const existing=(await c[store].methods.is_authorized_unconstrained(c[system].address).simulate(runtime.opts)).result;if(!existing)grants.push(c[store].methods.add_authorized_contract(c[system].address));}
  await runtime.batch(grants);fs.writeFileSync(marker,'Configured original address APIs and writer grants.\n');
}
console.log('READY',runtime.variant,'all 17 original contracts');await runtime.close();
