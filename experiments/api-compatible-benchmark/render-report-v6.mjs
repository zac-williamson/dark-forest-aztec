import fs from 'node:fs';
import {fileURLToPath} from 'node:url';
const candidateName=process.argv[2]??'candidate-v6';
if(!/^[a-zA-Z0-9_-]+$/.test(candidateName))throw Error('Invalid candidate label');
const out=new URL('./results/',import.meta.url);
const records=JSON.parse(fs.readFileSync(new URL('transactions.json',out)));
const schedule=JSON.parse(fs.readFileSync(new URL('../../docs/fee-benchmark/common-fee-schedule.json',import.meta.url)));
const privateMethods=new Set(['initialize_player','reveal_location','upgrade_planet','withdraw_silver','refresh_planet','safe_set_owner','move','prospect_planet','find_artifact','deposit_artifact','withdraw_artifact','give_spaceships','activate_artifact','deactivate_artifact']);
const names={initialize_player:'Initialize player',reveal_location:'Reveal location',upgrade_planet:'Upgrade planet',withdraw_silver:'Withdraw silver',refresh_planet:'Refresh planet',safe_set_owner:'Transfer ownership',move:'Move',prospect_planet:'Prospect planet',find_artifact:'Find artifact',deposit_artifact:'Deposit artifact',withdraw_artifact:'Withdraw artifact',give_spaceships:'Claim all five spaceships',activate_artifact:'Activate artifact',deactivate_artifact:'Deactivate artifact',pause:'Pause',unpause:'Unpause',admin_set_world_radius:'Set world radius',set_owner:'Set owner',add_score:'Add score',deduct_score:'Deduct score',create_planet:'Create planet',admin_initialize_planet:'Initialize planet as admin',create_artifact:'Create artifact',update_artifact:'Update artifact',admin_give_artifact:'Give artifact as admin',admin_give_spaceship:'Give spaceship as admin'};
const caseLabel=row=>row.caseId==='20'?(row.method==='move'?'20 due arrivals per planet':'20 due arrivals'):row.caseId==='ordinary'?(['move','refresh_planet'].includes(row.method)?'Empty queue':['find_artifact','prospect_planet'].includes(row.method)?'Gear enabled':'Standard fixture'):row.caseId.replaceAll('_',' ');
const fee=(n,precision=6)=>{n=BigInt(n);const negative=n<0n;if(negative)n=-n;const factor=10n**BigInt(18-precision),rounded=(n+factor/2n)/factor;return `${negative?'-':''}${rounded/(10n**BigInt(precision))}.${(rounded%(10n**BigInt(precision))).toString().padStart(precision,'0')}`;};
const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const baselineName=process.env.BENCH_BASELINE_VARIANT??records.find(row=>row.variant===candidateName)?.baselineVariant??'baseline';
const coverageFile=new URL(`coverage-${candidateName}.json`,out);
const coverage=fs.existsSync(coverageFile)?JSON.parse(fs.readFileSync(coverageFile)):undefined;
const identity=row=>JSON.stringify([row.method,row.caseId,row.paymentMode]);
const required=coverage?new Set(coverage.rows.map(identity)):undefined;
if(coverage&&(coverage.candidate!==candidateName||required.size!==coverage.verifiedPairs))throw Error('Coverage does not identify a complete, unique comparison matrix');
const baselines=records.filter(row=>row.variant===baselineName&&row.verified&&(!required||required.has(identity(row))));
if(required&&(baselines.length!==required.size||new Set(baselines.map(identity)).size!==required.size))throw Error('Coverage requires exactly one verified original for every pair');
let matched=0,failures=0,cheaper=0,moreExpensive=0,unchanged=0;
const rows=baselines.map(original=>{
 const candidate=records.find(row=>row.variant===candidateName&&row.method===original.method&&row.caseId===original.caseId&&row.paymentMode===original.paymentMode);
 const verified=!!candidate?.verified&&!!candidate?.originalStateEquivalent;
 if(verified)matched++;else if(candidate)failures++;
 const before=BigInt(original.feeAtObservedLivePriceWei),after=verified?BigInt(candidate.feeAtObservedLivePriceWei):undefined,saved=verified?before-after:undefined;
 if(verified){if(saved>0n)cheaper++;else if(saved<0n)moreExpensive++;else unchanged++;}
 return {group:privateMethods.has(original.method)?'Player actions':'Public admin and vault actions',action:names[original.method]??original.method,method:original.method,case:caseLabel(original),payment:original.paymentMode,before:fee(before),after:verified?fee(after):candidate?'Unverified':'Pending',saved:verified?fee(saved):'—',percent:verified?`${(Number(saved)*100/Number(before)).toFixed(Math.abs(Number(saved)*100/Number(before))<1?4:2)}%`:'—',verified,originalHash:original.receipt.txHash,candidateHash:verified?candidate.receipt.txHash:undefined};
});
const columns=['Action','Case','Payment','Original FJ','Candidate FJ','Saved FJ','Reduction'];
const cells=r=>[r.action,r.case,r.payment,r.before,r.after,r.saved,r.percent];
const status=matched?`${matched} paired transactions verified: ${cheaper} cost less, ${moreExpensive} cost more${unchanged?`, ${unchanged} unchanged`:''}. ${baselines.length-matched} await verified candidate results.`:`${baselines.length} original complete transactions verified. Candidate measurements are pending.`;
const notes=[
 'Fees cover the complete transaction, including the account or sponsored payment flow and all public execution. Fixture setup and deployment are excluded.',
 `Every pair uses the same observed reference price: ${schedule.feePerL2Gas} Fee Juice base units per L2 gas and ${schedule.feePerDaGas} per DA gas. One Fee Juice equals 10^18 base units. Table values are rounded to six decimals; full precision is retained in transactions.json.`,
 'Each mined receipt fee is also reconciled exactly against its actual block prices. Reference-price values are comparisons at one observed price, not a promise of future network fees.',
 'Candidate results require the same original event order, tags, IDs and gameplay state fields after documented current-action timestamp/block normalization. Every deployment’s actual stored roots are independently checked against its entire exact emitted state, including unused fields. Historical and candidate raw roots are not claimed identical when timestamps differ. Failed or incomplete verification never counts as savings.',
 'These fee runs use proverEnabled:false. Transaction proof generation and proving-latency measurements are deferred at the user’s request; the fee comparisons do not establish proving performance.'
];
let md=`# Complete transaction fees\n\n${status}${failures?` ${failures} candidate rows require verification.`:''}\n`;
let tables='';
for(const group of ['Player actions','Public admin and vault actions']){
 const selected=rows.filter(row=>row.group===group);if(!selected.length)continue;
 md+=`\n## ${group}\n\n| ${columns.join(' | ')} |\n| ${columns.map((_,i)=>i>=3?'---:':'---').join(' | ')} |\n${selected.map(row=>`| ${cells(row).join(' | ')} |`).join('\n')}\n`;
 tables+=`<section><h2>${esc(group)}</h2><div class="table-wrap"><table><thead><tr>${columns.map(c=>`<th>${esc(c)}</th>`).join('')}</tr></thead><tbody>${selected.map(row=>`<tr class="${row.verified?'verified':'pending'}">${cells(row).map((v,i)=>`<td class="${i>=3?'numeric':''}">${esc(v)}</td>`).join('')}</tr>`).join('')}</tbody></table></div></section>`;
}
md+=`\n${notes.map(note=>`- ${note}`).join('\n')}\n\nEvidence: [complete mined receipts and state checks](transactions.json), [frozen original artifact hashes](baseline-manifest.json).\n`;
const html=`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Dark Forest — complete transaction fees</title><style>:root{color-scheme:light dark;font-family:system-ui,-apple-system,sans-serif;background:light-dark(#f7f8fa,#11141a);color:light-dark(#202631,#e3e8f1)}body{max-width:1180px;margin:48px auto;padding:0 24px}h1{font-size:30px;letter-spacing:-.6px;margin-bottom:8px}h2{font-size:19px;margin:32px 0 12px}.status{font-size:16px;color:light-dark(#536071,#bac5d5)}.table-wrap{overflow-x:auto;border:1px solid light-dark(#d7dfe8,#3b4350);border-radius:10px}table{border-collapse:collapse;width:100%;font-size:13px;background:light-dark(white,#191e27)}th,td{padding:11px 14px;border-bottom:1px solid light-dark(#e7ebf1,#2b3340);text-align:left;white-space:nowrap}th{font-weight:600;color:light-dark(#526174,#afbdd0);background:light-dark(#eef2f7,#202734)}tr:last-child td{border-bottom:0}.numeric{text-align:right;font-variant-numeric:tabular-nums}.pending td:nth-child(n+5){color:light-dark(#778293,#8793a4)}.notes{max-width:920px;line-height:1.5;font-size:13px;color:light-dark(#536071,#bac5d5);padding-left:20px;margin-top:30px}.notes li{margin:9px 0}a{color:light-dark(#235b9e,#8ebcf5)}footer{font-size:13px;margin:25px 0 50px}</style><main><h1>Complete transaction fees</h1><p class="status">${esc(status)}${failures?` ${failures} candidate rows require verification.`:''}</p>${tables}<ul class="notes">${notes.map(note=>`<li>${esc(note)}</li>`).join('')}</ul><footer>Evidence: <a href="transactions.json">mined receipts and state checks</a> · <a href="baseline-manifest.json">original artifact hashes</a></footer></main></html>`;
fs.writeFileSync(new URL(`fee-report-${candidateName}.md`,out),md);fs.writeFileSync(new URL(`fee-report-${candidateName}.html`,out),html);
console.log(JSON.stringify({matched,pending:baselines.length-matched,failures,markdown:fileURLToPath(new URL(`fee-report-${candidateName}.md`,out)),html:fileURLToPath(new URL(`fee-report-${candidateName}.html`,out))}));
