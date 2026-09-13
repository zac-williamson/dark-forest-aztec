#!/usr/bin/env python3
"""Bounded source/patch validation; never compiles, follows symlinks or uses a wallet."""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / 'docs/api-compatibility'
SNAPSHOT = DOCS / 'v8-actions-source-snapshot.json'
PATCH = DOCS / 'v8-actions-source.patch'
INVENTORY = DOCS / 'v8-actions-patch-inventory.json'
FILES = [
    'contracts/system/artifact_action/Nargo.toml',
    'contracts/system/artifact_action/src/main.nr',
    'tests/api-compatibility/generate-backend-plans.py',
    'tests/api-compatibility/generated/backend-plan-transform.json',
    'tests/api-compatibility/test_worker_transform.py',
    'tests/api-compatibility/test_prospect_original_private.py',
    'tests/api-compatibility/optimize-artifact-actions-original-private.py',
    'tests/api-compatibility/test_artifact_actions_original_private.py',
    'tests/api-compatibility/snapshots/v8-actions-v7/artifact_action.nr',
    'tests/api-compatibility/snapshots/v8-actions-v7/provenance.json',
    'tests/api-compatibility/validate-actions-source.py',
    'docs/api-compatibility/v8-actions-source-snapshot.json',
    'docs/api-compatibility/v8-actions-private-dependencies.json',
    'docs/api-compatibility/v8-actions-candidate.md',
]
PRODUCTION_CHANGES = set(FILES[:2])
FORBIDDEN = {'.git', 'node_modules', 'target', 'artifacts', '__pycache__', '.state'}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def checked(root, relative):
    name = Path(relative)
    assert not name.is_absolute() and '..' not in name.parts
    assert not FORBIDDEN.intersection(name.parts)
    path = root
    for component in name.parts:
        path /= component
        assert not path.is_symlink(), path
    return path


def validate(write_patch=False):
    snapshot = json.loads(SNAPSHOT.read_text())
    base = Path(snapshot['source'])
    rows, patch = [], []
    for relative in FILES:
        raw = checked(ROOT, relative).read_bytes()
        expected = snapshot['copiedFiles'].get(relative)
        original = checked(base, relative).read_bytes() if expected is not None else None
        if original is not None:
            assert sha(original) == expected, relative
        rows.append({'file': relative, 'baseSha256': expected, 'candidateSha256': sha(raw)})
        patch.append(f'diff --git a/{relative} b/{relative}\n')
        if original is None:
            patch.append('new file mode 100644\n')
        for line in difflib.unified_diff((original or b'').decode().splitlines(keepends=True), raw.decode().splitlines(keepends=True),
                                        fromfile='a/' + relative if original is not None else '/dev/null', tofile='b/' + relative):
            patch.append(line if line.endswith('\n') else line + '\n\\ No newline at end of file\n')
    patch_bytes = ''.join(patch).encode()
    inventory = {'base': str(base), 'scope': 'V8 source-only patch on V7; excludes every build artifact, key, runtime state and dependency tree.',
                 'patchSha256': sha(patch_bytes), 'files': rows}
    if write_patch:
        PATCH.write_bytes(patch_bytes)
        INVENTORY.write_text(json.dumps(inventory, indent=2) + '\n')
    else:
        assert PATCH.read_bytes() == patch_bytes
        assert json.loads(INVENTORY.read_text()) == inventory
    with tempfile.TemporaryDirectory(prefix='df-v8-action-patch-') as temporary:
        fresh = Path(temporary)
        copied_bytes = 0
        for row in rows:
            if row['baseSha256'] is not None:
                raw = checked(base, row['file']).read_bytes()
                target = checked(fresh, row['file'])
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(raw)
                copied_bytes += len(raw)
        subprocess.run(['git', 'apply', '--check', str(PATCH)], cwd=fresh, check=True)
        subprocess.run(['git', 'apply', str(PATCH)], cwd=fresh, check=True)
        for row in rows:
            assert checked(fresh, row['file']).read_bytes() == checked(ROOT, row['file']).read_bytes(), row['file']
    unchanged = 0
    for relative, digest in snapshot['copiedFiles'].items():
        if relative.startswith('contracts/') and Path(relative).suffix in {'.nr', '.toml'} and relative not in PRODUCTION_CHANGES:
            assert sha(checked(ROOT, relative).read_bytes()) == digest, relative
            unchanged += 1
    dependency = json.loads((DOCS / 'v8-actions-private-dependencies.json').read_text())
    for row in dependency['files']:
        assert sha(checked(ROOT, row['current']).read_bytes()) == row['currentSha256'], row['current']
    report = {'passed': True, 'scope': 'Source and exact patch replay only; compiled identity, native admission and Fee Juice remain pending.',
              'patchFiles': len(rows), 'patchSha256': inventory['patchSha256'], 'baseBytesCopied': copied_bytes,
              'unchangedProductionFiles': unchanged, 'originalDependencyFiles': len(dependency['files']),
              'compilerRun': False, 'verificationKeysOrProofsGenerated': False, 'walletOrChainUsed': False}
    (DOCS / 'v8-actions-source-validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write-patch', action='store_true')
    validate(parser.parse_args().write_patch)
