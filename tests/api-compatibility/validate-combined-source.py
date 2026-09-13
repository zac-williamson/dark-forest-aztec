#!/usr/bin/env python3
"""Authenticate medium + Action source merge and bounded fresh patch replay only."""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / 'docs/api-compatibility'
SNAPSHOT = DOCS / 'v7-combined-medium-input.json'
PATCH = DOCS / 'v7-combined-source.patch'
MANIFEST = DOCS / 'v7-combined-patch-inventory.json'
EXTRA_FILES = [
    'tests/api-compatibility/audit-private-artifacts.py',
    'tests/api-compatibility/validate-combined-source.py',
    'docs/api-compatibility/v7-combined-medium-input.json',
    'docs/api-compatibility/v7-combined-added-audit-provenance.json',
    'docs/api-compatibility/v7-combined-actions-input.patch',
    'docs/api-compatibility/v7-combined-actions-input-inventory.json',
    'docs/api-compatibility/v7-combined-candidate.md',
    'docs/api-compatibility/medium-core-worker-literal-admission.json',
    'docs/api-compatibility/medium-transport-verification.json',
    'docs/api-compatibility/v6-frozen-fee-harness-manifest.json',
    'docs/api-compatibility/v7-combined-v6-fee-evidence-reference.json',
]
PRODUCTION_CHANGES = {'contracts/system/artifact_action/src/main.nr', 'contracts/system/artifact_action/Nargo.toml'}
FORBIDDEN = {'.git', 'node_modules', 'target', 'artifacts', '.state', '__pycache__'}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def checked(root, relative):
    name = Path(relative)
    assert not name.is_absolute() and '..' not in name.parts and not FORBIDDEN.intersection(name.parts)
    path = root
    for part in name.parts:
        path /= part
        assert not path.is_symlink(), path
    return path


def validate(write_patch=False):
    snapshot = json.loads(SNAPSHOT.read_text())
    base = Path(snapshot['source'])
    action = json.loads((DOCS / 'v7-combined-actions-input-inventory.json').read_text())
    assert action['patchSha256'] == '0bde54ae50664fccdbb88cdab4aa698ae6d78989c586b72d3d5155f61bf90ee9'
    assert sha((DOCS / 'v7-combined-actions-input.patch').read_bytes()) == action['patchSha256']
    paths = [row['file'] for row in action['files']] + EXTRA_FILES
    assert len(paths) == len(set(paths))
    rows, patch = [], []
    for relative in paths:
        current = checked(ROOT, relative).read_bytes()
        before = snapshot['copiedFiles'].get(relative, snapshot.get('laterReadOnlyEvidenceInputs', {}).get(relative))
        original = checked(base, relative).read_bytes() if before is not None else None
        if original is not None:
            assert sha(original) == before, relative
        rows.append({'file': relative, 'baseSha256': before, 'candidateSha256': sha(current)})
        if current == original:
            continue
        patch.append(f'diff --git a/{relative} b/{relative}\n')
        if original is None:
            patch.append('new file mode 100644\n')
        for line in difflib.unified_diff((original or b'').decode().splitlines(keepends=True), current.decode().splitlines(keepends=True),
                                        fromfile='a/' + relative if original is not None else '/dev/null', tofile='b/' + relative):
            patch.append(line if line.endswith('\n') else line + '\n\\ No newline at end of file\n')
    patch_bytes = ''.join(patch).encode()
    manifest = {'base': str(base), 'actionPatchSha256': action['patchSha256'], 'patchSha256': sha(patch_bytes), 'files': rows}
    if write_patch:
        PATCH.write_bytes(patch_bytes)
        MANIFEST.write_text(json.dumps(manifest, indent=2) + '\n')
    else:
        assert PATCH.read_bytes() == patch_bytes
        assert json.loads(MANIFEST.read_text()) == manifest
    with tempfile.TemporaryDirectory(prefix='df-v7-combined-replay-') as temporary:
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
    for relative, expected in snapshot['copiedFiles'].items():
        if relative.startswith('contracts/') and Path(relative).suffix in {'.nr', '.toml'} and relative not in PRODUCTION_CHANGES:
            assert sha(checked(ROOT, relative).read_bytes()) == expected, relative
            unchanged += 1
    verification = json.loads((DOCS / 'medium-transport-verification.json').read_text())
    for relative, expected in verification['sourceSha256'].items():
        assert sha(checked(ROOT, relative).read_bytes()) == expected, relative
    admission = json.loads((DOCS / 'medium-core-worker-literal-admission.json').read_text())
    assert admission['passedAdmission'] is True
    assert sha(checked(ROOT, 'contracts/settlement_workers/core/src/main.nr').read_bytes()) == admission['sourceSha256']
    fee_reference = json.loads((DOCS / 'v7-combined-v6-fee-evidence-reference.json').read_text())
    assert sha(checked(ROOT, fee_reference['copiedManifest']).read_bytes()) == fee_reference['v6CaptureManifestSha256']
    for row in json.loads((DOCS / 'v7-combined-added-audit-provenance.json').read_text())['files']:
        assert sha(checked(ROOT, row['file']).read_bytes()) == row['sha256'], row['file']
    metadata = json.loads((ROOT / 'tests/api-compatibility/generated/backend-plan-transform.json').read_text())
    restored = {(row['package'], row['private']) for row in metadata['originalPrivateActions']}
    assert restored == {('admin', 'safe_set_owner'), ('core', 'reveal_location'),
                        ('artifact_prospect', 'prospect_planet'), ('artifact_action', 'activate_artifact'),
                        ('artifact_action', 'deactivate_artifact')}
    report = {'passed': True, 'scope': 'Exact source merge and patch replay; no combined native, runtime, proof or Fee Juice result.',
              'patchFiles': len(rows), 'patchSha256': manifest['patchSha256'], 'baseBytesCopied': copied_bytes,
              'unchangedMediumProductionFiles': unchanged, 'mediumVerifiedSourceHashes': len(verification['sourceSha256']),
              'originalPrivateActions': len(restored), 'compilerCalls': 0, 'keysOrProofsGenerated': 0, 'walletOrChainCalls': 0}
    (DOCS / 'v7-combined-source-validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write-patch', action='store_true')
    validate(parser.parse_args().write_patch)
