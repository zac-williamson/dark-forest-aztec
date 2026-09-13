"""Read-only lock/check for the exact pinned Noir SDK dependency closure."""
from pathlib import Path
import hashlib,json,subprocess,tomllib

sha=lambda b:hashlib.sha256(b).hexdigest()
SPECS=[
 ('types','AztecProtocol/aztec-packages','v5.0.1','noir-projects/noir-protocol-circuits/crates/types','72666f8d1d61b98be22126db6e467a0b6046cef9',141),
 ('serde','AztecProtocol/aztec-packages','v5.0.1','noir-projects/noir-protocol-circuits/crates/serde','72666f8d1d61b98be22126db6e467a0b6046cef9',7),
 ('sha256','noir-lang/sha256','v0.3.0','','9442e5b6856f98b2ec029882d7e90199ecff91ba',10),
 ('poseidon','noir-lang/poseidon','v0.3.0','','0880c371e88e583d39515fd3f877538657ac41eb',10),
]
LICENSES={'AztecProtocol/aztec-packages':('LICENSE','a386b8c97533961f4c63b59593fba2a98b150b66706321a969d20ff72a9d892b'),'noir-lang/poseidon':('LICENSE','4458503dd48e88c4e0b945fb252a08b93c40ec757309b8ffa7c594dfa1e35104')}
def require(ok,msg):
 if not ok:raise ValueError(msg)
def git(root,*args):
 return subprocess.run(['git','-C',str(root),*args],check=True,text=True,capture_output=True).stdout.strip()
def snapshot(cache_root):
 cache_root=Path(cache_root);rows={};repositories={}
 for name,repo,tag,directory,commit,count in SPECS:
  repository=cache_root/'github.com'/repo/tag;root=repository/directory
  require(git(repository,'rev-parse','HEAD')==commit,f'{repo}: HEAD changed')
  require(git(repository,'rev-parse',tag+'^{commit}')==commit,f'{repo}: tag changed')
  scoped=[str(Path(directory)/'Nargo.toml'),str(Path(directory)/'src')]
  require(not git(repository,'status','--porcelain','--untracked-files=all','--',*scoped),f'{name}: source differs from authenticated repository commit')
  files=[root/'Nargo.toml',*sorted((root/'src').rglob('*.nr'))]
  require(len(files)==count,f'{name}: unexpected source inventory')
  require(not any(p.is_symlink() for p in files),f'{name}: symlinked dependency source')
  manifest=tomllib.loads((root/'Nargo.toml').read_text());deps=manifest.get('dependencies',{})
  if name=='types':
   require(deps=={'sha256':{'tag':'v0.3.0','git':'https://github.com/noir-lang/sha256'},'poseidon':{'tag':'v0.3.0','git':'https://github.com/noir-lang/poseidon'},'serde':{'path':'../serde'}},'types dependency graph changed')
  else:require(not deps,f'{name}: unreviewed transitive dependencies')
  rows[name]={'root':str(root),'files':{str(p.relative_to(root)):sha(p.read_bytes()) for p in files},'repository':repo}
  repositories[repo]={'root':str(repository),'tag':tag,'commit':commit}
 for repo,(name,h) in LICENSES.items():
  path=Path(repositories[repo]['root'])/name;require(sha(path.read_bytes())==h,f'{repo}: licence changed');repositories[repo]['license']={'path':name,'sha256':h}
 repositories['noir-lang/sha256']['licenseStatus']='No licence/notice file in pinned v0.3.0 package; not covered by Aztec licence. Distribution review remains required.'
 require(not any(p.is_file() and p.name.lower().startswith(('license','licence','notice','copying')) for p in Path(repositories['noir-lang/sha256']['root']).iterdir()),'sha256 licence inventory changed; review required')
 return {'scope':'Exact pinned external Noir package bodies and repository/tag identities, read-only','cacheRoot':str(cache_root),'packages':rows,'repositories':repositories,'fileCount':sum(len(r['files']) for r in rows.values())}
def verify(lock):
 current=snapshot(lock['cacheRoot']);require(current==lock,'External Noir dependency lock drift');return current
if __name__=='__main__':
 import argparse
 p=argparse.ArgumentParser();p.add_argument('--cache-root',type=Path,default=Path.home()/'nargo');p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 a.output.write_text(json.dumps(snapshot(a.cache_root),indent=2)+'\n')
