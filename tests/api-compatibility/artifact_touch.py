"""Reviewed, fail-closed event-only update over two distinct genuine facades.

Only additive touch methods and the final two update_artifact dispatches change.
The reversed additive argument order avoids creating a fourth identical public
signature and thereby changing the original methods' SDK unpack strategy.
Native admission, genuine new class bindings and runtime fees remain separate.
"""
from pathlib import Path
import functools,hashlib,importlib.util,json

HERE=Path(__file__).resolve().parent
REF=HERE/'snapshots/artifact-touch'
BASE=HERE/'snapshots/selected-source/v8'
VAULT='contracts/system/artifact_valut/src/main.nr'
SPECS={'artifact':'Artifact','artifact_location':'ArtifactLocation'}
ORIGINAL_SETS='''        self.call(artifact_storage.set(id, artifact));
        self.call(artifact_location_storage.set(id, location));'''
COMMENT='    // Additive authorized event-only path: independently verify the current root.'
sha=lambda b:hashlib.sha256(b).hexdigest()

@functools.lru_cache(maxsize=1)
def parser():
    spec=importlib.util.spec_from_file_location('touch_parser',HERE/'prepare-system-writes.py')
    result=importlib.util.module_from_spec(spec);spec.loader.exec_module(result);return result

def provenance():return json.loads((REF/'provenance.json').read_text())

def baseline(path):
    raw=(BASE/path).read_bytes()
    assert sha(raw)==provenance()['v8References'][path],(path,'Unauthenticated touch baseline')
    return raw.decode()

def dispatch():
    raw=(REF/'dispatch.nr').read_bytes()
    assert sha(raw)==provenance()['dispatchSHA256'],'Touch dispatch reference changed'
    return raw.decode().rstrip('\n')

def vault_function(p):
    old=p.functions(baseline(VAULT))['update_artifact'];assert old['body'].count(ORIGINAL_SETS)==1
    assert old['body'].rstrip().endswith(ORIGINAL_SETS)
    result=dict(old);result['body']=old['body'].replace(ORIGINAL_SETS,dispatch(),1)
    result['full']=result['header']+'{'+result['body']+'}'
    return result

def restore_vault(source,p):
    """Restore only an exactly validated public update, including all guards."""
    fn=p.functions(source)['update_artifact'];old=p.functions(baseline(VAULT))['update_artifact'];new=vault_function(p)
    assert fn['full'] in (old['full'],new['full']),'Unexpected update_artifact implementation'
    return source[:fn['start']]+old['full']+source[fn['body_end']+1:]

def apply_vault(source,p):
    source=restore_vault(source,p);fn=p.functions(source)['update_artifact']
    return source[:fn['start']]+vault_function(p)['full']+source[fn['body_end']+1:]

def validate_vault(source,p):
    assert p.functions(source)['update_artifact']['full']==vault_function(p)['full'],'Touch update dispatch changed'
    return True

def touch_block(slug,p):
    typ=SPECS[slug];old=baseline(f'contracts/storage/{slug}/src/main.nr');setter=p.functions(old)['set']
    write='self.storage.local_roots.at(id).write(root);'
    assert setter['body'].count(write)==1
    body=setter['body'].replace(write,'assert(self.storage.local_roots.at(id).read() == root, "State changed after verification");',1)
    assert body.lstrip().startswith('self.internal.assert_authorized();')
    return '\n\n'+COMMENT+f'\n    #[external("public")]\n    fn touch(state: {typ}, id: Field) '+'{'+body+'}'

def apply_facade(source,slug,p):
    if slug not in SPECS:return source
    old=baseline(f'contracts/storage/{slug}/src/main.nr');setter=p.functions(old)['set']
    expected=old[:setter['body_end']+1]+touch_block(slug,p)+old[setter['body_end']+1:]
    assert source in (old,expected),(slug,'Unexpected facade implementation')
    return expected

def validate_facade(source,slug,p):
    assert apply_facade(source,slug,p)==source,(slug,'Missing or altered touch')
    return True
