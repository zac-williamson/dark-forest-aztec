import assert from 'node:assert/strict';
const roles=new Set(['config','arrival','artifact','artifact_location','planet','planet_artifacts','planet_events','planet_revealed_coords','player','world']);
export function storageRoleFromParameter(name){
 const role=name.replace(/(?:_storage_address|_addr)$/,'').replace(/^arrivals$/,'arrival');
 assert(roles.has(role),`Unrecognized original storage address parameter: ${name}`);return role;
}
export function validateBatchResume(previous,{configuration,provenance,fixtures}){
 assert.equal(previous.proverEnabled,false);assert.equal(previous.gameplayTransactionsSubmitted,0);
 assert.equal(previous.status,'failed');
 assert.equal(previous.error,"Cannot read properties of undefined (reading 'address')",'Only the known pre-Give wiring failure is resumable');
 assert.deepEqual(previous.artifactProvenance,provenance);assert.deepEqual(previous.fixtures,fixtures);
 for(const key of ['variant','artifacts','deployment','nodeUrl'])assert.deepEqual(previous.configuration[key],configuration[key],`Resume ${key} changed`);
 assert.equal(previous.checks.length,76);assert(previous.checks.every(check=>check.passed===true));
 assert.equal(new Set(previous.checks.map(check=>check.label)).size,76);
 assert.equal(previous.checks.filter(check=>/^fixture observes (ids|hashes)\[\d+\] at count0$/.test(check.label)).length,40);
 assert.equal(previous.checks.filter(check=>/^(original|candidate) refresh_planet\/empty\//.test(check.label)).length,36);
 assert.equal(previous.receipts.length,61);assert.equal(previous.receipts.at(-1).label,'give_spaceships/empty exact isolated seeds 0');
 assert.equal(Object.keys(previous.isolated).length,17,'Resume all eight stores, Config, six Systems and two custom verifiers');
 return previous;
}
