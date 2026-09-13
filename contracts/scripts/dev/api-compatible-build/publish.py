#!/usr/bin/env python3
"""Publish only a successful native build, preserving the normal codegen path.

No compiler, key generation, proof, RPC, wallet or deployment is performed here.
The five derived class bindings and artifact directory are installed together;
an ordinary filesystem failure restores the prior files.
"""
from pathlib import Path
import argparse, hashlib, json, os, shutil, tempfile
from build import BINDINGS, ENTRIES, codegen, filename, require

sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

def checked_file(path, expected):
    require(path.is_file() and not path.is_symlink(), 'Regular file required: '+str(path))
    require(sha(path)==expected, 'File changed: '+str(path))

def validate(root, native):
    provenance=native/'build-provenance.json'
    build=json.loads(provenance.read_text())
    require(build.get('passed') is True and build.get('sourceRootUnchanged') is True, 'Native build did not pass')
    require(build.get('proofsGenerated')==0 and build.get('newKeysGenerated')==0, 'Cached-only build required')
    expected={filename(e) for e in ENTRIES}
    rows=build['artifacts'];names=[r['file'] for r in rows]
    require(len(names)==20 and set(names)==expected, 'Expected exact20 native artifacts')
    require(build.get('secondIdentityPass')==19 and len(build.get('identityChecks',[]))==19, 'Missing second identity pass')
    identities=build['identityChecks']
    require({r['file'] for r in identities}==expected-{'game_state_backend-GameStateBackend.json'}, 'Incomplete class identity inventory')
    require(all(r['classIdStable'] is True for r in identities), 'Native class changed')
    require(sum(len(v) for v in build['privateMethods'].values())==14, 'Incomplete private identity audit')
    inputs=build['inputSourceFiles'];final=build['sourceFiles']
    require(len(inputs)==349 and set(inputs)==set(final), 'Incomplete compile closure')
    require(set(BINDINGS)<=set(inputs), 'Missing class binding inputs')
    require(all(inputs[n]==final[n] for n in inputs if n not in BINDINGS), 'Build changed non-derived source')
    # A build starts from its input bindings; a distributed source patch already
    # contains the final bindings. Accept either complete snapshot, never a mix.
    current={}
    for n in inputs:
        path=root/n
        require(path.is_file() and not path.is_symlink(), 'Regular file required: '+str(path))
        current[n]=sha(path)
    require(current==inputs or current==final, 'File changed: repository must match the complete input or final source snapshot')
    for n,h in final.items(): checked_file(native/'build-source'/n,h)
    limits=build.get('limits',rows[0]['limits'])
    require(limits=={'publicBytes':96000,'packedFields':3000}, 'Unexpected protocol admission limits')
    directory=build.get('artifactDirectory','codegen')
    require(directory=='codegen', 'Native publication must use checked codegen directory')
    artifacts=native/directory
    require(not artifacts.is_symlink() and set(p.name for p in artifacts.iterdir())==expected, 'Unexpected native output files')
    for row in rows:
        require(row['limits']==limits and 0<row['publicBytes']<=limits['publicBytes'], 'Native public byte limit')
        require(row['packedFields']==1+(row['publicBytes']+30)//31 and row['packedFields']<=limits['packedFields'], 'Native packed field limit')
        checked_file(artifacts/row['file'],row['sha256'])
    by_name={r['file']:r for r in rows}
    bindings=codegen(by_name)
    for n,text in bindings.items():
        require((native/'build-source'/n).read_text()==text, 'Derived binding does not match actual native class: '+n)
    return build,bindings,artifacts,sha(provenance)

def publish(root,native):
    root=root.resolve();native=native.resolve()
    build,bindings,artifacts,provenance_sha=validate(root,native)
    target=root/'contracts/target';require(not target.is_symlink(), 'Target must not be a symlink')
    target.mkdir(parents=True,exist_ok=True)
    destination=target/'api-compatible';manifest=target/'api-compatible-build-provenance.json'
    require(not destination.is_symlink() and not manifest.is_symlink(), 'Publication destination must not be symlinked')
    with tempfile.TemporaryDirectory(prefix='.api-compatible-publish-',dir=target) as temporary:
        temp=Path(temporary);staged=temp/'artifacts';staged.mkdir()
        for row in build['artifacts']:
            shutil.copyfile(artifacts/row['file'],staged/row['file']);checked_file(staged/row['file'],row['sha256'])
        backups={n:(root/n).read_bytes() for n in bindings}
        old_manifest=manifest.read_bytes() if manifest.exists() else None
        old=temp/'previous';moved=False;installed=False
        # Recheck all inputs after staging before changing any live source.
        validate(root,native)
        try:
            for n,text in bindings.items():
                replacement=temp/('binding-'+str(BINDINGS.index(n)));replacement.write_text(text)
                os.replace(replacement,root/n)
            if destination.exists(): os.replace(destination,old);moved=True
            os.replace(staged,destination);installed=True
            report=temp/'build-provenance.json';report.write_bytes((native/'build-provenance.json').read_bytes())
            os.replace(report,manifest)
            for n,h in build['sourceFiles'].items():checked_file(root/n,h)
            for row in build['artifacts']:checked_file(destination/row['file'],row['sha256'])
        except BaseException:
            for n,data in backups.items(): (root/n).write_bytes(data)
            if installed:shutil.rmtree(destination)
            if moved:os.replace(old,destination)
            if old_manifest is None:manifest.unlink(missing_ok=True)
            else:manifest.write_bytes(old_manifest)
            raise
    return {'passed':True,'artifacts':20,'bindings':5,'buildProvenanceSHA256':provenance_sha,'codegenDirectory':str(destination),'proofsGenerated':0}

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--root',type=Path,required=True);ap.add_argument('--native',type=Path,required=True);ap.add_argument('--check',action='store_true');a=ap.parse_args()
    if a.check:
        validate(a.root.resolve(),a.native.resolve());print(json.dumps({'passed':True,'published':False}))
    else:print(json.dumps(publish(a.root,a.native)))
