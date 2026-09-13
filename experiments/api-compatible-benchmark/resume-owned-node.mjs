// Resume the existing owned Aztec5.2 dev chain; deliberately never call
// createLocalNetwork, deployContractsToL1, or any account/FPC setup function.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {getInitialTestAccountsData} from '@aztec/accounts/testing';
import {createAztecNodeService,registerAztecNodeRpcHandlers} from '@aztec/aztec-node';
import {getConfigEnvVars} from '@aztec/aztec-node/config';
import {createBlobClient} from '@aztec/blob-client/client';
import {getL1Config} from '@aztec/cli/config';
import {getPublicClient} from '@aztec/ethereum/client';
import {RollupContract} from '@aztec/ethereum/contracts';
import {SecretValue} from '@aztec/foundation/config';
import {EthAddress} from '@aztec/foundation/eth-address';
import {createNamespacedSafeJsonRpcServer,getApiKeyAuthMiddleware,startHttpRpcServer} from '@aztec/foundation/json-rpc/server';
import {createLogger} from '@aztec/foundation/log';
import {TestDateProvider} from '@aztec/foundation/timer';
import {getVersioningMiddleware} from '@aztec/stdlib/versioning';
import {getConfigEnvVars as getTelemetryConfig,initTelemetryClient} from '@aztec/telemetry-client';
import {getGenesisValues} from '@aztec/world-state/testing';
import {mnemonicToAccount,privateKeyToAddress} from 'viem/accounts';
import {getBananaFPCAddress} from '/tmp/df-fee-tools/node_modules/@aztec/aztec/dest/local-network/banana_fpc.js';
import {getSponsoredFPCAddress} from '/tmp/df-fee-tools/node_modules/@aztec/aztec/dest/local-network/sponsored_fpc.js';
import {DefaultMnemonic} from '/tmp/df-fee-tools/node_modules/@aztec/aztec/dest/mnemonic.js';
import {getTokenAllowedSetupFunctions} from '/tmp/df-fee-tools/node_modules/@aztec/aztec/dest/testing/token_allowed_setup.js';
import {getVersions} from '/tmp/df-fee-tools/node_modules/@aztec/aztec/dest/cli/versioning.js';
import {BarretenbergSync} from '@aztec/bb.js';

const report=JSON.parse(fs.readFileSync(new URL('./results/recovery-preflight-before-v4.json',import.meta.url)));
const originalDirectory=report.launchEnvironment.DATA_DIRECTORY;
const directory=process.env.BENCH_RECOVERY_DATA_DIRECTORY??originalDirectory;
const starting=process.argv[2]==='--start';
assert(process.argv.length===2||starting,'Only --start is accepted; the default is read-only validation');
for(const [key,value] of Object.entries(report.launchEnvironment))process.env[key]=value;
process.env.DATA_DIRECTORY=directory;
delete process.env.DF_AVM_PROFILE_OUTPUT;
assert.equal(report.nodeInfo.nodeVersion,'5.2.0');
assert.equal(report.nodeInfo.realProofs,false);
const registry=EthAddress.fromString(report.nodeInfo.l1ContractAddresses.registryAddress);
const {addresses,config:l1Config}=await getL1Config(registry,[report.launchEnvironment.ETHEREUM_HOSTS],31337,report.nodeInfo.rollupVersion);
assert.equal(addresses.rollupAddress.toString(),report.nodeInfo.l1ContractAddresses.rollupAddress,'Refuse a different rollup');
for(const [name,expected] of Object.entries(report.dbVersions)){
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(directory,name,'db_version'))),expected,`Refuse schema/rollup reset for ${name}`);
}
const accounts=await getInitialTestAccountsData();
const banana=await getBananaFPCAddress(accounts),sponsored=await getSponsoredFPCAddress();
const {genesisArchiveRoot,genesis}=await getGenesisValues([...accounts.map(account=>account.address),banana,sponsored]);
assert.equal(genesisArchiveRoot.toString(),l1Config.genesisArchiveTreeRoot,'Refuse mismatched genesis');
const client=getPublicClient({l1RpcUrls:[report.launchEnvironment.ETHEREUM_HOSTS],l1ChainId:31337});
const rollup=new RollupContract(client,addresses.rollupAddress),tips=await rollup.getTips();
assert.equal(Number(tips.pending),278);assert.equal(Number(tips.proven),278);
const l1Block=await client.getBlock();
assert.equal(l1Block.hash,report.currentL1Block.hash,'L1 changed since read-only recovery snapshot');
console.log(JSON.stringify({mode:starting?'resume':'read-only-check',noL1Deployment:true,noAccountSetup:true,realProofs:false,
  directory,rollup:addresses.rollupAddress.toString(),genesis:genesisArchiveRoot.toString(),l1Tips:tips}));
if(!starting)process.exit(0);

// Do not allow two native LMDB owners. No process is killed by this launcher.
let oldRunning=false;try{process.kill(26340,0);oldRunning=true;}catch(error){assert.equal(error.code,'ESRCH');}
assert(!oldRunning,'The original owned node must be stopped before resumption');
const backup=process.env.BENCH_RECOVERY_BACKUP;
assert(backup&&fs.existsSync(path.join(backup,'anvil-state.json')),'Require preserved Anvil snapshot before startup');
assert(fs.existsSync(path.join(backup,'network-before-stop.log')),'Require preserved original log before startup');
assert.notEqual(directory,originalDirectory,'Use a byte-for-byte copy; preserve original DB directory untouched');
const envConfig=getConfigEnvVars(),tokenAllowList=await getTokenAllowedSetupFunctions();
const devAccount=mnemonicToAccount(DefaultMnemonic);
const privateKey=`0x${Buffer.from(devAccount.getHdKey().privateKey).toString('hex')}`;
const nodeConfig={...envConfig,...addresses,...l1Config,
  rollupVersion:report.nodeInfo.rollupVersion,dataDirectory:directory,
  skipOrphanProposedBlockPruning:true,allowEphemeralSigningProtection:true,
  txPublicSetupAllowListExtend:[...tokenAllowList,...envConfig.txPublicSetupAllowListExtend??[]],
  useAutomineSequencer:true,automineEnableProveEpoch:true,realProofs:false,
  sequencerPublisherPrivateKeys:[new SecretValue(privateKey)],validatorPrivateKeys:new SecretValue([privateKey]),
  coinbase:EthAddress.fromString(privateKeyToAddress(privateKey))};
const dateProvider=new TestDateProvider();dateProvider.setTime(Number(l1Block.timestamp)*1000);
const telemetry=await initTelemetryClient(getTelemetryConfig());
const node=await createAztecNodeService(nodeConfig,{telemetry,blobClient:createBlobClient(),dateProvider},{genesis});
const services={},adminServices={};registerAztecNodeRpcHandlers(node,services,adminServices,{debug:true});
await BarretenbergSync.initSingleton();
const log=createLogger('owned-node-recovery'),versions=getVersions(nodeConfig);
const versioning=getVersioningMiddleware(versions,{packageVersion:'5.2.0'});
const rpc=createNamespacedSafeJsonRpcServer(services,{http200OnError:false,log,middlewares:[versioning],corsAllowedOrigins:['*']});
const server=await startHttpRpcServer(rpc,{host:'127.0.0.1',port:Number(report.launchEnvironment.AZTEC_PORT)});
const hash=fs.readFileSync(path.join(directory,'admin/api_key_hash'),'utf8').trim();
assert(/^[0-9a-f]{64}$/.test(hash),'Existing admin authentication hash must be valid');
const admin=createNamespacedSafeJsonRpcServer(adminServices,{http200OnError:false,log,middlewares:[getApiKeyAuthMiddleware(Buffer.from(hash,'hex')),versioning]});
const adminServer=await startHttpRpcServer(admin,{host:'127.0.0.1',port:Number(report.launchEnvironment.AZTEC_ADMIN_PORT)});
console.log(JSON.stringify({resumed:true,pid:process.pid,rpcPort:server.port,adminPort:adminServer.port,realProofs:false}));
let stopping=false;async function stop(){if(stopping)return;stopping=true;server.close();adminServer.close();await node.stop();process.exit(0);}
process.on('SIGTERM',()=>void stop());process.on('SIGINT',()=>void stop());
