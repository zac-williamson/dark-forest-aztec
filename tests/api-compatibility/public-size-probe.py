#!/usr/bin/env python3
"""Copy only public/utility entrypoints to /tmp for dispatcher-size experiments.

Never deploy the probe. Once size is acceptable, compile the full original API
and compare the actual production dispatch before deployment.
"""
from pathlib import Path
import argparse, importlib.util,re
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('p',HERE/'prepare-system-writes.py');p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
parser=argparse.ArgumentParser();parser.add_argument('package');args=parser.parse_args()
base=p.ROOT/'contracts/system'/args.package;dest=Path('/tmp')/('df-'+args.package+'-public-probe');(dest/'src').mkdir(parents=True,exist_ok=True)
source=(base/'src/main.nr').read_text();edits=[]
for name,fn in p.functions(source).items():
 if '#[external("private")]' in fn['header']:edits.append((fn['start'],fn['body_end']+1))
for start,end in sorted(edits,reverse=True):source=source[:start]+source[end:]
(dest/'src/main.nr').write_text('// PUBLIC SIZE PROBE ONLY. PRIVATE GAMEPLAY ENTRIES OMITTED. NEVER DEPLOY.\n'+source)
nargo=(base/'Nargo.toml').read_text();nargo=nargo.replace('name = "'+args.package+'"','name = "'+args.package+'_public_probe"')
nargo=re.sub(r'path\s*=\s*"([^"]+)"',lambda m:'path = "'+str((base/m.group(1)).resolve())+'"',nargo)
(dest/'Nargo.toml').write_text(nargo)
print(dest)
