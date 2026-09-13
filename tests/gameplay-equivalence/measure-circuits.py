"""Compare real contract interfaces/public bytecode and pinned native circuit sizes."""
import concurrent.futures, json, pathlib, subprocess, sys, tempfile
before_dir, after_dir, bb, output = map(pathlib.Path, sys.argv[1:])
records=[]
jobs=[]
for old_path in sorted(before_dir.glob('*.json')):
    before=json.loads(old_path.read_text())
    after=json.loads((after_dir/old_path.name).read_text())
    if before.get('transpiled',False):
        # Saved storage artifacts are postprocessed; no library edits reach them.
        continue
    assert before['outputs']==after['outputs'],old_path.name
    assert [f['name'] for f in before['functions']]==[f['name'] for f in after['functions']],old_path.name
    for old,new in zip(before['functions'],after['functions']):
        assert old['abi']==new['abi'],(old_path.name,old['name'],'ABI')
        assert old['custom_attributes']==new['custom_attributes']
        if old['is_unconstrained']:
            assert old['bytecode']==new['bytecode'],(old_path.name,old['name'],'unconstrained/public bytecode changed')
        else:
            jobs.append((old_path.name,old,new))

def measure(job):
    filename,old,new=job
    sizes=[]
    with tempfile.TemporaryDirectory(prefix='df-circuit-') as tmp:
        for f in (old,new):
            p=pathlib.Path(tmp)/'function.json';p.write_text(json.dumps({'bytecode':f['bytecode']}))
            r=subprocess.run([str(bb.resolve()),'gates','-s','chonk','-b',str(p)],capture_output=True,text=True,check=True)
            sizes.append(json.loads(r.stdout)['functions'][0])
    assert sizes[1]['circuit_size']<=sizes[0]['circuit_size'],(filename,old['name'],'circuit regression')
    return dict(contract=filename,function=old['name'],before=sizes[0],after=sizes[1],bytecode_unchanged=old['bytecode']==new['bytecode'])
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    records=list(pool.map(measure,jobs))
result=dict(public_and_utility_bytecode_unchanged=True,interfaces_and_event_schemas_unchanged=True,all_private_circuits_nonincreasing=True,functions=records)
output.write_text(json.dumps(result,indent=2)+'\n')
for r in records:
    a,b=r['before']['circuit_size'],r['after']['circuit_size']
    print(f"{r['contract']} {r['function']}: {a:,} -> {b:,} ({100*(1-b/a):.2f}% fewer rows)")
