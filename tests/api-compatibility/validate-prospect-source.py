#!/usr/bin/env python3
"""Bounded V7 source/patch checks: no compiler, dependency tree copies or chain.

Only the patch's original files are copied to a temporary apply directory.
Local Noir dependencies are followed through explicit Nargo.toml path entries;
node_modules, artifacts, target and symlinks are never traversed.
"""
import hashlib
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import tomllib

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / 'docs/api-compatibility'
FORBIDDEN = {'.git', 'node_modules', 'target', 'artifacts'}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def checked_file(root, relative):
    path = Path(relative)
    assert not path.is_absolute() and '..' not in path.parts, relative
    assert not FORBIDDEN.intersection(path.parts), relative
    current = root
    for part in path.parts:
        current /= part
        assert not current.is_symlink(), f'Symlink forbidden: {current}'
    return current


def validate(v6_build_manifest=Path('/tmp/df-api-compatible-v6-native/build-provenance.json')):
    handoff = json.loads((DOCS / 'v7-prospect-handoff.json').read_text())
    snapshot = json.loads((DOCS / 'v7-prospect-source-snapshot.json').read_text())
    base = Path(snapshot['source']).resolve()
    patch = DOCS / 'v7-prospect-source.patch'
    assert sha(patch.read_bytes()) == handoff['sourcePatch']['sha256']
    changes = handoff['changes']
    assert len({row['file'] for row in changes}) == len(changes)
    with tempfile.TemporaryDirectory(prefix='df-v7-prospect-patch-') as temporary:
        fresh = Path(temporary)
        copied_bytes = 0
        for row in changes:
            expected = checked_file(ROOT, row['file']).read_bytes()
            assert sha(expected) == row['candidateSha256'], row['file']
            target = checked_file(fresh, row['file'])
            if row['baseSha256'] is not None:
                # The V6 worktree can receive later test-only fixes. A retained,
                # authenticated base fixture preserves the original V7 snapshot.
                original = checked_file(ROOT, row['baseSource']).read_bytes() if row.get('baseSource') else checked_file(base, row['file']).read_bytes()
                assert row['snapshotBaseSha256'] == snapshot['copiedFiles'][row['file']], row['file']
                assert sha(original) == row['baseSha256'] == row['snapshotBaseSha256'], row['file']
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(original)
                copied_bytes += len(original)
        subprocess.run(['git', 'apply', '--check', str(patch)], cwd=fresh, check=True)
        subprocess.run(['git', 'apply', str(patch)], cwd=fresh, check=True)
        for row in changes:
            assert checked_file(fresh, row['file']).read_bytes() == checked_file(ROOT, row['file']).read_bytes(), row['file']

    # Parent copied four generated constants from the completed V6 build before
    # the Prospect compile. Authenticate that exact transition, not arbitrary
    # changes to generated-looking files. V7 class binding remains pending.
    transition = json.loads((DOCS / 'v7-prospect-final-v6-class-inputs.json').read_text())
    expected_constants = {
        'contracts/libs/src/config_class.nr',
        'contracts/settlement_workers/core/src/system_class.nr',
        'contracts/settlement_workers/vault/src/system_class.nr',
        'contracts/state_backend/src/trusted_classes.nr',
    }
    assert set(transition['files']) == expected_constants
    build_bytes = v6_build_manifest.read_bytes()
    assert sha(build_bytes) == transition['v6BuildManifestSha256']
    build = json.loads(build_bytes)
    assert build['passed'] is True
    for relative, hashes in transition['files'].items():
        assert hashes['previousSha256'] == snapshot['copiedFiles'][relative], relative
        assert hashes['finalV6Sha256'] == build['sourceFiles'][relative], relative
        assert sha(checked_file(ROOT, relative).read_bytes()) == hashes['finalV6Sha256'], relative
    assert checked_file(ROOT, 'contracts/prospect_original_libs/src/config_class.nr').read_bytes() == checked_file(ROOT, 'contracts/libs/src/config_class.nr').read_bytes()

    # Every other pre-existing production source stays V6-snapshot-exact except
    # the explicit Prospect manifest/body delta.
    source_changes = {row['file'] for row in changes if row['file'].startswith('contracts/')}
    unchanged = 0
    for relative, digest in snapshot['copiedFiles'].items():
        if not relative.startswith('contracts/') or Path(relative).suffix not in {'.nr', '.toml'}:
            continue
        if relative in source_changes:
            continue
        if relative in expected_constants:
            continue
        assert sha(checked_file(ROOT, relative).read_bytes()) == digest, relative
        unchanged += 1

    dependency_report = json.loads((DOCS / 'v7-prospect-private-dependencies.json').read_text())
    for row in dependency_report['files']:
        assert sha(checked_file(ROOT, row['current']).read_bytes()) == row['currentSha256'], row['current']

    queue = [ROOT / 'contracts/system/artifact_prospect/Nargo.toml']
    manifests = {}
    while queue:
        manifest = queue.pop()
        relative = manifest.relative_to(ROOT).as_posix()
        if relative in manifests:
            continue
        raw = checked_file(ROOT, relative).read_bytes()
        data = tomllib.loads(raw.decode())
        manifests[relative] = {'package': data['package']['name'], 'sha256': sha(raw)}
        for alias, dependency in data.get('dependencies', {}).items():
            if 'path' in dependency:
                target = (manifest.parent / dependency['path'] / 'Nargo.toml').resolve()
                assert target.is_relative_to(ROOT), (relative, alias, target)
                checked_file(ROOT, target.relative_to(ROOT)).read_bytes()
                queue.append(target)
            elif alias == 'aztec':
                assert dependency.get('git') == 'https://github.com/AztecProtocol/aztec-nr'
                assert dependency.get('tag') == 'v5.0.1'
    names = {}
    for relative, item in manifests.items():
        names.setdefault(item['package'], []).append(relative)
    report = {
        'scope': 'Source-only checks; no compiled, runtime, proof-latency or fee claim',
        'freshPatchApplyPassed': True,
        'patchSha256': handoff['sourcePatch']['sha256'],
        'patchFiles': len(changes),
        'baseBytesCopied': copied_bytes,
        'unchangedProductionFiles': unchanged,
        'finalV6ClassInputFiles': len(expected_constants),
        'finalV6BuildManifestSha256': transition['v6BuildManifestSha256'],
        'v7ClassBindingVerified': False,
        'originalDependencyFiles': len(dependency_report['files']),
        'localManifestCount': len(manifests),
        'manifests': manifests,
        'duplicatePackageNamesRequireCompilerValidation': {name: paths for name, paths in names.items() if len(paths) > 1},
        'compilerRun': False, 'keysOrProofsGenerated': False, 'walletOrChainUsed': False,
    }
    (DOCS / 'v7-prospect-source-validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: value for key, value in report.items() if key != 'manifests'}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--v6-build-manifest', type=Path, default=Path('/tmp/df-api-compatible-v6-native/build-provenance.json'))
    validate(parser.parse_args().v6_build_manifest)
