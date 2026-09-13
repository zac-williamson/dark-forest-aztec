#!/usr/bin/env python3
"""Resolve and freeze a local build plan. Never compiles, proves or opens a wallet."""
from pathlib import Path
import argparse, hashlib, json, os, platform, shutil, subprocess, sys
from dependencies import snapshot

HERE = Path(__file__).resolve().parent
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
def require(ok, message):
    if not ok: raise ValueError(message)
def dump(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + '\n')
def pin(path):
    p = Path(path).expanduser().resolve()
    require(p.is_file(), 'Missing required tool/reference: ' + str(p))
    return {'path':str(p), 'sha256':sha(p)}
def binary(env, default):
    value = os.environ.get(env) or shutil.which(default)
    require(value, f'Set {env} to the installed {default} executable')
    return pin(value)
def find_package(entry, name):
    for directory in Path(entry).parents:
        package=directory/'package.json'
        if package.is_file() and json.loads(package.read_text()).get('name')==name:return package
    raise ValueError('Missing installed package metadata: '+name)
def body_identity(lock):
    return {'packages':{k:{q:v for q,v in row.items() if q!='root'} for k,row in lock['packages'].items()},
            'repositories':{k:{q:v for q,v in row.items() if q!='root'} for k,row in lock['repositories'].items()},
            'fileCount':lock['fileCount']}

def prepare(root, plan_path, output):
    root=root.resolve();plan_path=plan_path.resolve();output=output.resolve()
    require(not plan_path.exists() and not output.exists(), 'Use fresh plan and native output paths')
    paths=json.loads((HERE/'reference/production-paths.json').read_text())
    require(len(paths)==349 and len(set(paths))==349, 'Expected exact349 production input paths')
    source={}
    for n in paths:
        p=root/n;require(p.is_file() and not p.is_symlink(), 'Regular production input required: '+n)
        source[n]=sha(p)
    validator_path=root/'tests/api-compatibility/generated/selected-validator-inputs.json'
    validator=json.loads(validator_path.read_text())
    require(validator['script'] in validator['files'], 'Selected validator must pin itself')
    files=[]
    for n,h in validator['files'].items():
        p=root/n;require(p.is_file() and not p.is_symlink() and sha(p)==h, 'Validator input changed: '+n)
        files.append({'path':str(p), 'sha256':h})
    files.append(pin(validator_path))
    python=binary('DF_PYTHON','python3');node=binary('DF_NODE','node');nargo=binary('DF_NARGO','aztec-nargo')
    version=subprocess.run([nargo['path'],'--version'],check=True,capture_output=True,text=True).stdout
    require('1.0.0-beta.22' in version and 'c57152' in version, 'Expected pinned beta22+c57152 compiler')
    script="""const {createRequire}=require('node:module');const path=require('node:path');const fs=require('node:fs');const r=createRequire(path.join(process.argv[1],'package.json'));const out={};for(const n of ['@aztec/stdlib/abi','@aztec/stdlib/contract','@aztec/constants','@aztec/bb.js','@aztec/builder/codegen'])out[n]=fs.realpathSync(r.resolve(n));console.log(JSON.stringify(out));"""
    entries=json.loads(subprocess.run([node['path'],'-e',script,str(root)],check=True,capture_output=True,text=True).stdout)
    stdlib_package=find_package(entries['@aztec/stdlib/abi'],'@aztec/stdlib');constants_package=find_package(entries['@aztec/constants'],'@aztec/constants');bb_package=find_package(entries['@aztec/bb.js'],'@aztec/bb.js')
    builder_package=find_package(entries['@aztec/builder/codegen'],'@aztec/builder')
    for p in [stdlib_package,constants_package,bb_package,builder_package]: require(json.loads(p.read_text())['version']=='5.0.1','Expected installed Aztec SDK5.0.1: '+str(p))
    machine={'arm64':'arm64','aarch64':'arm64','x86_64':'amd64','AMD64':'amd64'}.get(platform.machine())
    system={'Darwin':'macos','Linux':'linux'}.get(platform.system())
    processor=os.environ.get('DF_NATIVE_PROCESSOR') or os.environ.get('DF_BB')
    if not processor:
        require(machine and system, 'Set DF_NATIVE_PROCESSOR to the installed Aztec5.0.1 native bb executable')
        processor=bb_package.parent/'build'/f'{machine}-{system}'/'bb'
    toolchain={'python':python,'node':node,'nargo':nargo,'guard':pin(HERE/'cached-only.py'),
      'nativeProcessor':pin(processor),'stdlibAbi':pin(entries['@aztec/stdlib/abi']),
      'stdlibContract':pin(entries['@aztec/stdlib/contract']),'constants':pin(entries['@aztec/constants']),
      'stdlibPackageJson':pin(stdlib_package),'constantsPackageJson':pin(constants_package),'bbPackageJson':pin(bb_package),
      'builderCodegen':pin(entries['@aztec/builder/codegen']),'builderPackageJson':pin(builder_package),
      'jsPackageJson':pin(root/'package.json'),'jsDependencyLock':pin(root/'node_modules/.pnpm/lock.yaml'),'projectDependencyLock':pin(root/'pnpm-lock.yaml')}
    require(toolchain['jsDependencyLock']['sha256']==toolchain['projectDependencyLock']['sha256'],'Installed dependency lock differs from project')
    cache=Path(os.environ.get('DF_NARGO_CACHE',str(Path.home()/'nargo'))).expanduser().resolve()
    require(cache==(Path.home()/'nargo').resolve(), 'This pinned compiler uses ~/nargo; a different DF_NARGO_CACHE is not supported')
    lock=snapshot(cache);expected=json.loads((HERE/'reference/dependency-body-lock.json').read_text())
    require(body_identity(lock)==body_identity(expected),'Pinned external Noir dependency bodies changed')
    work=plan_path.parent;source_file=work/(plan_path.stem+'-inputs.json');deps_file=work/(plan_path.stem+'-dependencies.json')
    for p in [source_file,deps_file]:require(not p.exists(),'Plan input already exists: '+str(p))
    dump(source_file,source);dump(deps_file,lock)
    references={}
    for name,row in json.loads((HERE/'reference/private-references.json').read_text()).items():
        p=HERE/row['file'];require(sha(p)==row['sha256'],'Private reference changed: '+name);references[name]=pin(p)
    plan={'sourceRoot':str(root),'sourceManifest':pin(source_file),'toolingManifest':pin(HERE/'tooling-manifest.json'),
      'dependencyLock':pin(deps_file),'output':str(output),'toolchain':toolchain,'jsResolutionRoot':str(root),
      'vkCache':str(Path.home()/'.bb/5.0.1/vk_cache'),
      'validators':[{'name':'selected-semantic-source','script':str(root/validator['script']),'args':['--root',str(root)],'files':files}],
      'privateReferences':references,'provenance':{'policy':'All14 private circuits/verification keys identical to admitted V7 Core / V8 others; public original447 API and actual native binding/cap checks required','proofsGenerated':0,'keysGenerated':0,'noirVersionOutput':version.strip()}}
    dump(plan_path,plan);return {'plan':str(plan_path),'sha256':sha(plan_path),'output':str(output)}

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--root',type=Path,required=True);ap.add_argument('--plan',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);args=ap.parse_args()
    print(json.dumps(prepare(args.root,args.plan,args.output)))
