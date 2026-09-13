import fs from 'node:fs';
import assert from 'node:assert/strict';
import {json} from './fixtures.mjs';
const file=new URL('./results/transactions.json',import.meta.url);
const records=JSON.parse(fs.readFileSync(file));
const candidate=process.argv[2]??'candidate';
const fj=value=>{const n=BigInt(value),negative=n<0n,abs=negative?-n:n;return `${negative?'-':''}${abs/10n**18n}.${(abs%10n**18n).toString().padStart(18,'0')}`;};
const rows=[];
for(const row of records.filter(row=>row.variant===candidate)){
  const original=records.find(other=>other.variant===(row.baselineVariant??'baseline')&&other.method===row.method&&other.caseId===row.caseId&&other.paymentMode===row.paymentMode);
  if(!original)throw Error(`Missing matched original ${row.method}/${row.caseId}/${row.paymentMode}`);
  assert(row.verified&&original.verified,'Both complete receipts need state/root verification');
  assert(row.originalStateEquivalent,'Candidate ordered original event payloads must match baseline');
  const before=BigInt(original.feeAtObservedLivePriceWei),after=BigInt(row.feeAtObservedLivePriceWei),saved=before-after;
  rows.push({system:row.system,method:row.method,caseId:row.caseId,paymentMode:row.paymentMode,baselineFeeJuice:fj(before),candidateFeeJuice:fj(after),savedFeeJuice:fj(saved),percentReduction:Number(saved)*100/Number(before),baselineReceipt:original.receipt.txHash,candidateReceipt:row.receipt.txHash,originalStateEquivalent:true});
}
const report={candidate,feeUnit:'1 Fee Juice = 10^18 base units',scope:'Complete user transaction, including account or SponsoredFPC fee flow and all public execution; preparation transactions excluded',source:new URL('./results/transactions.json',import.meta.url).pathname,comparisons:rows};
fs.writeFileSync(new URL(`./results/comparison-${candidate}.json`,import.meta.url),json(report));
console.log(json(report));
