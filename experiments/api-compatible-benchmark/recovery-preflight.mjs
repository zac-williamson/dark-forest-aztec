// Read-only recovery evidence. No wallet, node startup, LMDB open, or sends.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import http from 'node:http';
import {getInitialTestAccountsData} from '@aztec/accounts/testing';
import {getL1Config} from '@aztec/cli/config';
import {getPublicClient} from '@aztec/ethereum/client';
import {RollupContract} from '@aztec/ethereum/contracts';
import {EthAddress} from '@aztec/foundation/eth-address';
import {getGenesisValues} from '@aztec/world-state/testing';
import {getBananaFPCAddress} from '/tmp/df-fee-tools/node_modules/@aztec/aztec/dest/local-network/banana_fpc.js';
import {getSponsoredFPCAddress} from '/tmp/df-fee-tools/node_modules/@aztec/aztec/dest/local-network/sponsored_fpc.js';

const rpc=(url,method,params=[])=>new Promise((resolve,reject)=>{
  const request=http.request(url,{method:'POST',headers:{'content-type':'application/json'}},response=>{
    let body='';response.on('data',part=>body+=part);response.on('end',()=>{
      try{const result=JSON.parse(body);assert(!result.error,JSON.stringify(result.error));resolve(result.result);}catch(error){reject(error);}
    });
  });
  request.setTimeout(15000,()=>request.destroy(Error(`${method} timeout`)));
  request.on('error',reject);request.end(JSON.stringify({jsonrpc:'2.0',id:1,method,params}));
});
const info=await rpc('http://127.0.0.1:8097','node_getNodeInfo');
console.log('Read owned node metadata');
const env=JSON.parse(fs.readFileSync('/tmp/df-api-compatible-node-restart-env.json'));
assert.equal(info.nodeVersion,'5.2.0');assert.equal(info.l1ChainId,31337);assert.equal(info.realProofs,false);
const {addresses,config}=await getL1Config(EthAddress.fromString(info.l1ContractAddresses.registryAddress),[env.ETHEREUM_HOSTS],31337,info.rollupVersion);
console.log('Read existing L1 configuration');
assert.equal(addresses.rollupAddress.toString(),info.l1ContractAddresses.rollupAddress);
const accounts=await getInitialTestAccountsData(),banana=await getBananaFPCAddress(accounts),sponsored=await getSponsoredFPCAddress();
const {genesisArchiveRoot}=await getGenesisValues([...accounts.map(a=>a.address),banana,sponsored]);
assert.equal(genesisArchiveRoot.toString(),config.genesisArchiveTreeRoot);
const client=getPublicClient({l1RpcUrls:[env.ETHEREUM_HOSTS],l1ChainId:31337});
const rollup=new RollupContract(client,addresses.rollupAddress),tips=await rollup.getTips();
const latestL1=await client.getBlock();
const dbVersions={};
for(const directory of fs.readdirSync(env.DATA_DIRECTORY)){
  const file=`${env.DATA_DIRECTORY}/${directory}/db_version`;if(!fs.existsSync(file))continue;
  const version=JSON.parse(fs.readFileSync(file));
  if(directory!=='l1-tx-utils')assert.equal(version.rollupAddress,info.l1ContractAddresses.rollupAddress);
  dbVersions[directory]=version;
}
const report={checkedAt:new Date().toISOString(),readOnly:true,nodeInfo:info,launchEnvironment:env,
  l1Config:config,genesisArchiveRoot:genesisArchiveRoot.toString(),genesisVerified:true,dbVersions,
  currentL1Block:{number:latestL1.number.toString(),hash:latestL1.hash,timestamp:latestL1.timestamp.toString()},
  l1Tips:tips,lastRecordedL2Block:278};
const json=JSON.stringify(report,(_key,value)=>typeof value==='bigint'?value.toString():value,2)+'\n';
fs.writeFileSync(new URL('./results/recovery-preflight-before-v4.json',import.meta.url),json);
console.log(JSON.stringify({genesisVerified:true,l1Tips:tips,l1Block:report.currentL1Block,
  rollup:addresses.rollupAddress.toString(),dbVersionCount:Object.keys(dbVersions).length}));
