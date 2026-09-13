#!/usr/bin/env python3
"""Read frozen artifacts only; compare private bytecode and cached keys without proving."""
import argparse
import base64
import hashlib
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
sha=lambda raw:hashlib.sha256(raw).hexdigest()

def fingerprints(function):
    return {'bytecodeSha256':sha(base64.b64decode(function['bytecode'],validate=True)),
            'cachedKeySha256':sha(base64.b64decode(function['verification_key'],validate=True))}

def audit(directory):
    directory=Path(directory)
    provenance_path=directory/'build-provenance.json'
    provenance=json.loads(provenance_path.read_text())
    assert provenance['passed'],'Candidate must have a completed native build'
    admitted={row['file']:row for row in provenance['artifacts']}
    reference_path=ROOT/'docs/api-compatibility/private-workload-audit-v5.json'
    reference=json.loads(reference_path.read_text())
    rows=[];artifacts={}
    for filename,versions in reference['artifactProvenance'].items():
        functions={};artifacts[filename]={}
        for version in ['original','v5','candidate']:
            path=directory/filename if version=='candidate' else Path(versions[version]['file'])
            raw=path.read_bytes();expected=admitted[filename]['sha256'] if version=='candidate' else versions[version]['sha256']
            assert sha(raw)==expected,(filename,version,'Artifact changed after its recorded build')
            data=json.loads(raw)
            assert data['noir_version']==versions['original']['noirVersion'],(filename,version,'Compiler version mismatch')
            private={fn['name']:fn for fn in data['functions'] if 'abi_private' in fn.get('custom_attributes',[])}
            functions[version]={name:fingerprints(fn) for name,fn in private.items()}
            artifacts[filename][version]={'file':str(path),'sha256':sha(raw)}
        assert functions['original'].keys()==functions['v5'].keys()==functions['candidate'].keys(),(filename,'Private API changed')
        for name,current in functions['candidate'].items():
            rows.append({'artifact':filename,'method':name,'fingerprints':{v:functions[v][name] for v in functions},
                         'originalBytecodeIdentical':current['bytecodeSha256']==functions['original'][name]['bytecodeSha256'],
                         'originalKeyIdentical':current['cachedKeySha256']==functions['original'][name]['cachedKeySha256'],
                         'v5BytecodeIdentical':current['bytecodeSha256']==functions['v5'][name]['bytecodeSha256'],
                         'v5KeyIdentical':current['cachedKeySha256']==functions['v5'][name]['cachedKeySha256']})
    assert len(rows)==14,('Unexpected private method inventory',len(rows))
    return {'scope':'Read-only compiled private bytecode and cached verification-key identity. No execution or latency measurement.',
            'candidateBuildManifest':str(provenance_path),'candidateBuildManifestSha256':sha(provenance_path.read_bytes()),
            'referenceAuditSha256':sha(reference_path.read_bytes()),'artifacts':artifacts,'methods':rows,
            'identicalOriginalMethods':[row['method'] for row in rows if row['originalBytecodeIdentical'] and row['originalKeyIdentical']],
            'identicalV5Methods':[row['method'] for row in rows if row['v5BytecodeIdentical'] and row['v5KeyIdentical']],
            'transactionProofsGenerated':0,'verificationKeysGenerated':0,'compilerCalls':0,'chainCalls':0,
            'limitation':'Nonidentical artifacts require further analysis; source body identity and circuit buckets do not establish equal proof latency.'}

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('directory',type=Path);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();report=audit(args.directory);args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({key:report[key] for key in ['identicalOriginalMethods','identicalV5Methods','transactionProofsGenerated']},indent=2))
