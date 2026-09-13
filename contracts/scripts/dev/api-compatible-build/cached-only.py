#!/usr/bin/env python3
"""Process a native artifact only when every private verification key is cached."""
import base64, gzip, hashlib, json, os
from pathlib import Path
import sys

def require(ok, message):
    if not ok:
        raise SystemExit(message)

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def pinned(row):
    path = Path(row['path'])
    require(path.is_file() and not path.is_symlink(), 'Pinned regular file required')
    require(digest(path) == row['sha256'], 'Pinned file changed: ' + str(path))
    return path

def verify_cached_functions(artifact, known, cache):
    require(artifact.is_file() and not artifact.is_symlink(), 'Regular artifact required')
    checks = []
    for fn in json.loads(artifact.read_text())['functions']:
        if not fn['is_unconstrained']:
            circuit = gzip.decompress(base64.b64decode(fn['bytecode'], validate=True))
            circuit_hash = hashlib.sha256(circuit).hexdigest()
            require(circuit_hash in known, 'Unknown private circuit; processing refused: ' + fn['name'])
            expected = known[circuit_hash]; key = cache / (circuit_hash + '.vk')
            require(key.is_file() and not key.is_symlink(), 'Missing existing verification key: ' + fn['name'])
            require(key.stat().st_size == expected['keyBytes'] and digest(key) == expected['keySha256'], 'Verification key differs: ' + fn['name'])
            checks.append({'method':fn['name'], 'circuitSHA256':circuit_hash, 'cachedVerificationKeySHA256':expected['keySha256']})
    return checks

def validate(args, config):
    require(len(args) == 3 and args[:2] == ['aztec_process', '-i'], 'Only aztec_process -i ARTIFACT is allowed')
    binary = pinned(config['nativeProcessor'])
    known_path = pinned(config['knownKeys'])
    known = json.loads(known_path.read_text())['keys']
    home = Path(os.environ['HOME']).resolve()
    cache = Path(config['vkCache']).resolve()
    require(cache == home / '.bb' / '5.0.1' / 'vk_cache', 'Cache must be the native processor existing HOME cache')
    return binary, verify_cached_functions(Path(args[2]), known, cache)

if __name__ == '__main__':
    config_path = Path(os.environ['DF_CACHED_ONLY_CONFIG'])
    require(config_path.is_file() and not config_path.is_symlink(), 'Regular guard configuration required')
    require(digest(config_path) == os.environ['DF_CACHED_ONLY_CONFIG_SHA256'], 'Guard configuration changed')
    config = json.loads(config_path.read_text())
    binary, checks = validate(sys.argv[1:], config)
    print(json.dumps({'cacheOnlyGuard':True, 'privateFunctions':checks, 'transactionProofs':False}), flush=True)
    os.execv(str(binary), [str(binary), *sys.argv[1:]])
