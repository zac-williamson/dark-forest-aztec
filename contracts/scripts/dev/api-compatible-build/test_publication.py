"""Offline failure-path coverage: no native tools, RPC, proofs or external writes."""
from pathlib import Path
import base64, gzip, hashlib, importlib.util, json, tempfile, unittest
from unittest.mock import patch
import publish
from build import ENTRIES, BINDINGS, codegen, filename

def sha(data):return hashlib.sha256(data).hexdigest()
def write(path,data):path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
def dump(path,value):write(path,(json.dumps(value,indent=2)+'\n').encode())
spec=importlib.util.spec_from_file_location('cached_only',Path(__file__).parent/'cached-only.py')
guard=importlib.util.module_from_spec(spec);spec.loader.exec_module(guard)

class Publication(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)/'root';self.native=Path(self.temp.name)/'native'
        self.rows=[]
        for i,e in enumerate(ENTRIES):
            name=filename(e);data=json.dumps({'fixture':name}).encode()
            write(self.native/'codegen'/name,data)
            self.rows.append({'file':name,'sha256':sha(data),'classId':hex(i+1),'publicBytes':31,'packedFields':2,'limits':{'publicBytes':96000,'packedFields':3000}})
        bindings=codegen({r['file']:r for r in self.rows})
        inputs={};final={}
        for n in [*BINDINGS,*[f'contracts/fixture-{i}.nr' for i in range(344)]]:
            data=b'fixture original\n';output=bindings[n].encode() if n in bindings else data
            write(self.root/n,data);write(self.native/'build-source'/n,output)
            inputs[n]=sha(data);final[n]=sha(output)
        self.report={'passed':True,'sourceRootUnchanged':True,'proofsGenerated':0,'newKeysGenerated':0,'artifacts':self.rows,'secondIdentityPass':19,'identityChecks':[{'file':r['file'],'classIdStable':True} for r in self.rows[:-1]],'privateMethods':{'fixture':[{}]*14},'inputSourceFiles':inputs,'sourceFiles':final,'artifactDirectory':'codegen','limits':self.rows[0]['limits']}
        self.save()
    def save(self):dump(self.native/'build-provenance.json',self.report)
    def test_success_adopts_only_derived_bindings_and_twenty_artifacts(self):
        result=publish.publish(self.root,self.native);self.assertTrue(result['passed'])
        for n,h in self.report['sourceFiles'].items():self.assertEqual(sha((self.root/n).read_bytes()),h)
        self.assertEqual(len(list((self.root/'contracts/target/api-compatible').iterdir())),20)
    def test_final_source_patch_can_install_and_repeat_without_rebuilding(self):
        for n in BINDINGS:write(self.root/n,(self.native/'build-source'/n).read_bytes())
        self.assertTrue(publish.publish(self.root,self.native)['passed'])
        self.assertTrue(publish.publish(self.root,self.native)['passed'])
    def test_mixed_input_and_final_bindings_are_rejected(self):
        n=BINDINGS[0];write(self.root/n,(self.native/'build-source'/n).read_bytes())
        with self.assertRaisesRegex(ValueError,'complete input or final'):publish.validate(self.root,self.native)
    def test_changed_source_rejected_before_publication(self):
        (self.root/'contracts/fixture-1.nr').write_text('changed')
        with self.assertRaisesRegex(ValueError,'File changed'):publish.publish(self.root,self.native)
        self.assertFalse((self.root/'contracts/target').exists())
    def test_changed_artifact_rejected(self):
        (self.native/'codegen'/self.rows[0]['file']).write_text('changed')
        with self.assertRaisesRegex(ValueError,'File changed'):publish.validate(self.root,self.native)
    def test_unrelated_build_source_change_is_not_a_binding(self):
        n='contracts/fixture-1.nr';(self.native/'build-source'/n).write_text('changed')
        self.report['sourceFiles'][n]=sha(b'changed');self.save()
        with self.assertRaisesRegex(ValueError,'non-derived'):publish.validate(self.root,self.native)
    def test_wrong_derived_class_rejected_even_when_rehashed(self):
        n=BINDINGS[0];(self.native/'build-source'/n).write_text('wrong class')
        self.report['sourceFiles'][n]=sha(b'wrong class');self.save()
        with self.assertRaisesRegex(ValueError,'Derived binding'):publish.validate(self.root,self.native)
    def test_native_limit_disagreement_rejected(self):
        self.rows[1]['limits']={'publicBytes':96001,'packedFields':3000};self.save()
        with self.assertRaisesRegex(ValueError,'public byte limit'):publish.validate(self.root,self.native)
    def test_missing_identity_rejected(self):
        self.report['identityChecks'].pop();self.save()
        with self.assertRaisesRegex(ValueError,'identity pass'):publish.validate(self.root,self.native)
    def test_unlisted_codegen_file_rejected(self):
        (self.native/'codegen/unexpected.json').write_text('{}')
        with self.assertRaisesRegex(ValueError,'Unexpected native output'):publish.validate(self.root,self.native)
    def test_publication_error_restores_existing_source_and_directory(self):
        destination=self.root/'contracts/target/api-compatible';write(destination/'old.ts',b'old interface')
        original={n:(self.root/n).read_bytes() for n in BINDINGS};real=publish.os.replace
        def fail(source,dest):
            if Path(source).name=='artifacts':raise OSError('simulated disk error')
            return real(source,dest)
        with patch.object(publish.os,'replace',side_effect=fail):
            with self.assertRaisesRegex(OSError,'disk error'):publish.publish(self.root,self.native)
        self.assertEqual((destination/'old.ts').read_bytes(),b'old interface')
        for n,data in original.items():self.assertEqual((self.root/n).read_bytes(),data)

class CachedOnly(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.artifact=self.root/'artifact.json';self.cache=self.root/'cache';self.cache.mkdir()
        self.circuit=b'private circuit fixture';self.digest=sha(self.circuit);self.key=b'cached verification key fixture'
        self.known={self.digest:{'keyBytes':len(self.key),'keySha256':sha(self.key)}}
        self.keypath=self.cache/(self.digest+'.vk');self.keypath.write_bytes(self.key)
        dump(self.artifact,{'functions':[{'name':'test','is_unconstrained':False,'bytecode':base64.b64encode(gzip.compress(self.circuit)).decode()}]})
    def test_existing_exact_cache_is_accepted_without_execution(self):
        self.assertEqual(len(guard.verify_cached_functions(self.artifact,self.known,self.cache)),1)
    def test_missing_cache_refused(self):
        self.keypath.unlink()
        with self.assertRaisesRegex(SystemExit,'Missing existing'):guard.verify_cached_functions(self.artifact,self.known,self.cache)
    def test_changed_cache_refused(self):
        self.keypath.write_bytes(b'wrong')
        with self.assertRaisesRegex(SystemExit,'key differs'):guard.verify_cached_functions(self.artifact,self.known,self.cache)
    def test_unknown_circuit_refused(self):
        with self.assertRaisesRegex(SystemExit,'Unknown private'):guard.verify_cached_functions(self.artifact,{},self.cache)
    def test_symlinked_key_refused(self):
        key=self.root/'other';self.keypath.rename(key);self.keypath.symlink_to(key)
        with self.assertRaisesRegex(SystemExit,'Missing existing'):guard.verify_cached_functions(self.artifact,self.known,self.cache)
    def test_prove_force_extra_flags_refused_before_reading_config(self):
        for args in [['prove','-i','x'],['aztec_process','-i','x','--force'],['aztec_process','-i']]:
            with self.assertRaisesRegex(SystemExit,'Only aztec_process'):guard.validate(args,{})

if __name__=='__main__':unittest.main()
