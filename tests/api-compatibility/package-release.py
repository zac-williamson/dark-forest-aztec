#!/usr/bin/env python3
"""Package this implementation without changing the repository or its Git index.

The patch is applied to a fresh archive of the original commit and every included
file is compared byte-for-byte. Native artifacts must match a successful build's
manifest. This checks packaging integrity, not gameplay or performance.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import stat
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]
REFERENCE = '00bfa05c18862cce1c5adb362e4ecebe084c329a'
SCOPE = [
    'client/src/Session/WalletManager/WalletManager.ts',
    'contracts', 'vendor', 'tests/api-compatibility', 'tests/api-compatible-storage',
    # Retain labeled historical standalone-storage sources and their dependency.
    # Current bound runtime validation is tests/api-compatible-storage.
    'tests/contract-optimization', 'tests/optimization-benchmark', 'tests/gameplay-equivalence',
    'tests/config-commitment', 'tests/artifact-triple',
    'experiments/api-compatible-benchmark', 'experiments/api-compatible-browser',
    'docs/api-compatibility', 'docs/fee-benchmark/common-fee-schedule.json',
    'docs/fee-benchmark/common-fee-schedule-provenance.md',
    'docs/fee-benchmark/common-fee-schedule-provenance.json',
    'docs/fee-benchmark/reference-capture/node_getCurrentMinFees.json',
    'docs/fee-benchmark/reference-capture/node_getNodeInfo.selected.json',
    'docs/fee-benchmark/reference-capture/node_getBlockNumber.json',
    'docs/fee-benchmark/live-receipts.json',
]
PACKAGE_PATHS = [*SCOPE,
    ':(exclude,glob)**/__pycache__/**',
    ':(exclude,glob)**/*.pyc',
    ':(exclude,glob)**/*.pyo',
]


def run(*args, cwd=ROOT):
    return subprocess.check_output(args, cwd=cwd)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def checked_native_directory(native, build):
    relative=Path(build.get('artifactDirectory', 'codegen' if (native/'codegen').is_dir() else '.'))
    assert not relative.is_absolute() and '..' not in relative.parts
    artifacts=native/relative
    assert artifacts.is_dir() and not artifacts.is_symlink()
    rows=build['artifacts']
    assert len(rows)==20 and len({r['file'] for r in rows})==20
    limits=build.get('limits', rows[0].get('limits'))
    assert limits=={'publicBytes':96000,'packedFields':3000}
    for row in rows:
        assert Path(row['file']).name==row['file']
        assert row.get('limits',limits)==limits
        file=artifacts/row['file']
        assert file.is_file() and not file.is_symlink()
        assert sha(file.read_bytes())==row['sha256'],row['file']
        assert 0<row['publicBytes']<=limits['publicBytes']
        assert row['packedFields']==1+(row['publicBytes']+30)//31
        assert row['packedFields']<=limits['packedFields']
    return artifacts,relative


def checked_native_sources(native, build):
    files=build['sourceFiles']
    assert len(files)==349, 'Expected complete349 final build inputs'
    for name,digest in files.items():
        relative=Path(name)
        assert not relative.is_absolute() and '..' not in relative.parts
        file=native/'build-source'/relative
        assert file.is_file() and not file.is_symlink(), f'Missing regular build source: {name}'
        assert sha(file.read_bytes())==digest, f'Build source changed: {name}'
    return files


def write_native_archive(native, build, bundle):
    artifacts,relative=checked_native_directory(native,build)
    files=checked_native_sources(native,build)
    with tarfile.open(bundle, 'w:gz') as tar:
        tar.add(native/'build-provenance.json',arcname='build-provenance.json',recursive=False)
        for row in build['artifacts']:
            tar.add(artifacts/row['file'],arcname=str(relative/row['file']),recursive=False)
        # The checked installer authenticates these against the same manifest.
        # No wallet, cache, environment, or unrelated build output is included.
        for name in sorted(files):
            tar.add(native/'build-source'/name,arcname=str(Path('build-source')/name),recursive=False)


def package(native, destination):
    assert run('git', 'rev-parse', 'HEAD').decode().strip() == REFERENCE
    build = json.loads((native / 'build-provenance.json').read_text())
    assert build['passed'] and len(build['artifacts']) == 20
    assert build.get('sourceFiles'), 'Final build must record source hashes'
    for name, digest in build['sourceFiles'].items():
        assert sha((ROOT / name).read_bytes()) == digest, f'Source changed after native build: {name}'
    artifacts,artifact_relative=checked_native_directory(native,build)
    checked_native_sources(native,build)
    tracked = run('git', 'diff', '--name-only', '-z', REFERENCE, '--', *PACKAGE_PATHS).decode().split('\0')
    added = run('git', 'ls-files', '--others', '--exclude-standard', '-z', '--', *PACKAGE_PATHS).decode().split('\0')
    files = sorted(set(filter(None, tracked + added)))
    assert files and all('\n' not in name and ' ' not in name for name in files)
    assert all(not set(Path(name).parts) & {'.state', 'node_modules', 'target', '.git'} for name in files)
    assert all(Path(name).name != '.env' for name in files)
    # Mutable accumulation avoids copying the complete patch for every added line.
    patch = bytearray(run('git', 'diff', '--no-ext-diff', '--binary', REFERENCE, '--', *PACKAGE_PATHS))
    for name in sorted(filter(None, added)):
        source = ROOT / name
        assert source.is_file() and not source.is_symlink(), name
        data = source.read_bytes()
        data.decode('utf-8')  # Large binaries belong in the artifact archive.
        assert b'\0' not in data, name
        mode = '100755' if source.stat().st_mode & stat.S_IXUSR else '100644'
        blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        patch += f'diff --git a/{name} b/{name}\nnew file mode {mode}\nindex {"0" * 40}..{blob}\n'.encode()
        if data:
            lines = data.splitlines(keepends=True)
            patch += f'--- /dev/null\n+++ b/{name}\n@@ -0,0 +1,{len(lines)} @@\n'.encode()
            for line in lines:
                patch += b'+' + line
                if not line.endswith(b'\n'):
                    patch += b'\n\\ No newline at end of file\n'
    destination.mkdir(parents=True, exist_ok=True)
    patch_path = destination / 'dark-forest-api-compatible-optimizations.patch'
    patch_path.write_bytes(patch)
    with tempfile.TemporaryDirectory(prefix='df-api-release-apply-') as temporary:
        fresh = Path(temporary)
        archive = run('git', 'archive', '--format=tar', REFERENCE)
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(fresh, filter='data')
        run('git', 'apply', '--check', str(patch_path), cwd=fresh)
        run('git', 'apply', str(patch_path), cwd=fresh)
        for name in files:
            if (ROOT / name).exists():
                assert (fresh / name).read_bytes() == (ROOT / name).read_bytes(), name
            else:
                assert not (fresh / name).exists(), name

    bundle = destination / 'dark-forest-api-compatible-native-artifacts.tar.gz'
    write_native_archive(native,build,bundle)
    report = {
        'scope': 'Fresh-archive patch application, byte equality and native build identity; not additional fee or gameplay verification',
        'referenceCommit': REFERENCE, 'freshApplyPassed': True,
        'patch': {'file': patch_path.name, 'bytes': len(patch), 'sha256': sha(patch)},
        'nativeArchive': {'file': bundle.name, 'bytes': bundle.stat().st_size, 'sha256': sha(bundle.read_bytes()), 'contracts': 20, 'authenticatedBuildSources':349},
        'includedFiles': {name: sha((ROOT / name).read_bytes()) if (ROOT / name).exists() else None for name in files},
    }
    (destination / 'dark-forest-api-compatible-release-manifest.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: report[key] for key in ['freshApplyPassed', 'patch', 'nativeArchive']}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('native_directory', type=Path)
    parser.add_argument('--output', type=Path, default=ROOT.parent)
    args = parser.parse_args()
    package(args.native_directory.resolve(), args.output.resolve())
