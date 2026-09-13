#!/usr/bin/env python3
"""Native processing only; refuse any private circuit without an existing key."""
import base64,gzip,hashlib,json,os,pathlib,sys
BINARY=pathlib.Path('/Users/zac/Documents/ChatGPT/Dark Forest/dark-forest-aztec/node_modules/.pnpm/@aztec+bb.js@5.0.1/node_modules/@aztec/bb.js/build/arm64-macos/bb')
EXPECTED='f9205978aafd888f2c8011456794053a53e4c1e1a7ed4173e54734c456e12553'
def require(condition,message):
    if not condition: raise SystemExit(message)
args=sys.argv[1:]
KNOWN=pathlib.Path('/tmp/df-known-private-keys.json')
require(hashlib.sha256(KNOWN.read_bytes()).hexdigest()=='5a10dd43264601fbb3b946af861446cb07e46a928cc80a8b76eb968b3526beb4', 'Known private-key manifest changed')
known=json.loads(KNOWN.read_text())['keys']
require(len(args)==3 and args[0]=='aztec_process' and args[1]=='-i', 'Only native artifact processing is allowed')
require(hashlib.sha256(BINARY.read_bytes()).hexdigest()==EXPECTED, 'Pinned native processor changed')
require(os.environ.get('HOME')=='/Users/zac', 'Unexpected verification-key cache root')
p=pathlib.Path(args[2]);raw=json.loads(p.read_text());checked=[]
for f in raw['functions']:
    if not f['is_unconstrained']:
        acir=gzip.decompress(base64.b64decode(f['bytecode']))
        digest=hashlib.sha256(acir).hexdigest()
        cache=pathlib.Path('/Users/zac/.bb/5.0.1/vk_cache')/(digest+'.vk')
        require(digest in known, 'Unknown private circuit '+f['name']+'; native processing refused')
        require(cache.is_file() and cache.stat().st_size==known[digest]['keyBytes'], 'Missing cached key for '+f['name']+'; native processing refused')
        require(hashlib.sha256(cache.read_bytes()).hexdigest()==known[digest]['keySha256'], 'Cached key bytes changed; native processing refused')
        checked.append({'function':f['name'],'bytecodeSha256':digest,'cachedKeySha256':hashlib.sha256(cache.read_bytes()).hexdigest()})
print(json.dumps({'cacheOnlyGuard':True,'artifact':str(p),'privateFunctions':checked,'transactionProofs':False}),flush=True)
os.execv(str(BINARY),[str(BINARY),*args])
