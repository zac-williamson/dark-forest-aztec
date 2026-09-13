#!/usr/bin/env python3
"""Generate additive proof-bound continuations, or check the recorded transform.

Run --apply once on the unprepared system sources. Run --check after edits.
The manifest records every original function: public/utility/internal functions
must remain token-identical, while private functions may change only their final
enqueue to add hashes of the exact existing arguments. New public continuations
must restore to the old body when their guarded prepared writes are removed.
This is a source-equivalence check, not a substitute for execution/proof tests.
"""

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = Path(__file__).with_name("prepared-system-transform.json")
PACKAGES = ["core", "artifact_action", "artifact_find", "artifact_prospect", "artifact_valut", "admin"]
COMMENT_OR_STRING = re.compile(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/')


def mask(source, strings=False):
    def replace(match):
        text = match.group()
        if text.startswith('"') and not strings:
            return text
        return ''.join('\n' if c == '\n' else ' ' for c in text)
    return COMMENT_OR_STRING.sub(replace, source)


def digest(source):
    tokens = re.findall(r'"(?:\\.|[^"\\])*"|[A-Za-z_][A-Za-z_0-9]*|\d+|[^\s]', mask(source))
    return hashlib.sha256(json.dumps(tokens, separators=(',', ':')).encode()).hexdigest()


def closing(source, start, left, right):
    cleaned = mask(source, strings=True)
    assert cleaned[start] == left
    depth = 1
    for i in range(start + 1, len(cleaned)):
        depth += (cleaned[i] == left) - (cleaned[i] == right)
        if depth == 0:
            return i
    raise AssertionError(f"Unclosed {left}")


def split_arguments(source):
    cleaned = mask(source, strings=True)
    depth = 0
    start = 0
    result = []
    for i, char in enumerate(cleaned):
        if char in '([{':
            depth += 1
        elif char in ')]}':
            depth -= 1
        elif char == ',' and depth == 0:
            value = mask(source[start:i]).strip()
            if value:
                result.append(value)
            start = i + 1
    value = mask(source[start:]).strip()
    if value:
        result.append(value)
    return result


def functions(source):
    result = {}
    for match in re.finditer(r'(?m)^    (?:unconstrained )?fn (\w+)\s*\(', mask(source, strings=True)):
        name = match.group(1)
        paren = source.index('(', match.start())
        end_paren = closing(source, paren, '(', ')')
        body_start = source.index('{', end_paren)
        body_end = closing(source, body_start, '{', '}')
        attr_start = match.start()
        while attr_start:
            previous_start = source.rfind('\n', 0, attr_start - 1) + 1
            previous = source[previous_start:attr_start].strip()
            if previous.startswith('#[') or not previous:
                attr_start = previous_start
            else:
                break
        result[name] = dict(name=name, start=attr_start, fn_start=match.start(), paren=paren,
                            end_paren=end_paren, body_start=body_start, body_end=body_end,
                            params=split_arguments(source[paren + 1:end_paren]),
                            header=source[attr_start:body_start], body=source[body_start + 1:body_end],
                            full=source[attr_start:body_end + 1])
    return result


def prepared_name(name):
    return name + '_prepared'


def root_name(state):
    return 'prepared_' + state + '_root'


def store_declaration(store):
    return r'let\s+' + re.escape(store) + r'\s*=\s*\w+::at\(\s*self\s*\.\s*storage\s*\.\s*(\w+)\s*\.\s*read\(\)\s*,?\s*\);'


def guarded_write(original, store, key, state, address):
    return (
        f'if supports_prepared_{store} {{\n'
        f'            self.call({store}.set_prepared({key}, {state}, {root_name(state)}));\n'
        f'        }} else {{\n'
        f'            {original}\n'
        f'        }}'
    )


def enqueue(source, name):
    match = re.search(r'self\.enqueue_self\.' + re.escape(name) + r'\s*\(', mask(source, strings=True))
    assert match, name
    paren = source.index('(', match.start())
    end = closing(source, paren, '(', ')')
    assert source[end + 1] == ';'
    return match.start(), end + 2, split_arguments(source[paren + 1:end])


def apply():
    assert not MANIFEST.exists(), 'Manifest exists; use --check instead of applying twice'
    manifest = {'scope': 'Additive continuations for six system contracts, excluding Move; source checks only.', 'packages': {}}
    outputs = {}
    for package in PACKAGES:
        path = ROOT / f'contracts/system/{package}/src/main.nr'
        source = path.read_text()
        original_functions = functions(source)
        assert not any(name.endswith('_prepared') for name in original_functions)
        records = {'originalFunctions': {}, 'continuations': []}
        for name, fn in original_functions.items():
            records['originalFunctions'][name] = {'signatureHash': digest(fn['header']), 'functionHash': digest(fn['full'])}
        edits = []
        additions = []
        for private_name, private in original_functions.items():
            if '#[external("private")]' not in private['header']:
                continue
            calls = re.findall(r'self\.enqueue_self\.(\w+)\s*\(', private['body'])
            assert len(calls) == 1, (package, private_name, calls)
            old_name = calls[0]
            public = original_functions[old_name]
            assert '#[only_self]' in public['header']
            params = [re.match(r'(?:mut\s+)?(\w+)\s*:', p).group(1) for p in public['params']]
            assignments = set(re.findall(r'(?m)^\s*(\w+)(?:\.[\w]+|\[[^\]]+\])*\s*(?:=(?!=)|\+=|-=)', mask(public['body'])))
            public_body = public['body']
            replacements = []
            declarations = []
            states = []
            skipped = []
            pattern = r'self\.call\((\w+)\.set\(\s*(\w+)\s*,\s*(\w+)\s*\)\);'
            for match in re.finditer(pattern, public['body']):
                store, key, state = match.groups()
                if state not in params or state in assignments:
                    skipped.append({'store': store, 'state': state, 'reason': 'Public-created or mutated output'})
                    continue
                address_match = re.search(store_declaration(store), public['body'])
                assert address_match, (package, old_name, store)
                address = address_match.group(1)
                original = match.group()
                replacement = guarded_write(original, store, key, state, address)
                replacements.append({'original': original, 'replacement': replacement, 'store': store, 'key': key, 'state': state, 'address': address})
                if state not in states:
                    states.append(state)
            assert states, (package, old_name)
            # Replace by exact spans from the end to preserve conditional order.
            eligible = [m for m in re.finditer(pattern, public_body) if m.group(3) in states]
            assert len(eligible) == len(replacements)
            for match, replacement in reversed(list(zip(eligible, replacements))):
                public_body = public_body[:match.start()] + replacement['replacement'] + public_body[match.end():]
            # Read each target class once. Interface target_contract is the
            # already-resolved address, so this introduces no extra SLOAD.
            for store in dict.fromkeys(item['store'] for item in replacements):
                declaration = re.search(store_declaration(store), public_body).group()
                addition = f'\n        let supports_prepared_{store} = ::libs::prepared_storage::supports_prepared({store}.target_contract);'
                public_body = public_body.replace(declaration, declaration + addition, 1)
                declarations.append(addition)
            extra_params = ''.join(f'        {root_name(state)}: Field,\n' for state in states)
            header = public['header']
            relative_end = public['end_paren'] - public['start']
            before = header[:relative_end].rstrip()
            header = before + '\n' + extra_params + '    ' + header[relative_end:]
            header = re.sub(r'\bfn ' + re.escape(old_name) + r'\b', 'fn ' + prepared_name(old_name), header, count=1)
            additions.append('\n\n    // Additional hashes are bound by the existing private gameplay proof.\n' + header.lstrip('\n') + '{' + public_body + '}')
            start, end, arguments = enqueue(private['body'], old_name)
            assert len(arguments) == len(params), (package, old_name)
            roots = [f'poseidon2_hash(({arguments[params.index(state)]}).serialize())' for state in states]
            old_enqueue = private['body'][start:end]
            new_enqueue = 'self.enqueue_self.' + prepared_name(old_name) + '(\n' + ''.join('            ' + arg + ',\n' for arg in arguments + roots) + '        );'
            edits.append((private['body_start'] + 1 + start, private['body_start'] + 1 + end, new_enqueue))
            records['continuations'].append({'private': private_name, 'original': old_name, 'prepared': prepared_name(old_name),
                                            'states': states, 'replacements': replacements, 'skipped': skipped,
                                            'classDeclarations': declarations,
                                            'originalEnqueue': old_enqueue, 'preparedEnqueue': new_enqueue,
                                            'privateOriginalHash': digest(private['full'])})
        contract = re.search(r'\bcontract\s+\w+\s*\{', mask(source, strings=True))
        contract_end = closing(source, source.index('{', contract.start()), '{', '}')
        edits.append((contract_end, contract_end, ''.join(additions) + '\n'))
        for start, end, replacement in sorted(edits, reverse=True):
            source = source[:start] + replacement + source[end:]
        if package == 'admin':
            source = source.replace('        protocol::address::AztecAddress,', '        protocol::{address::AztecAddress, hash::poseidon2_hash, traits::Serialize},', 1)
        outputs[path] = source
        manifest['packages'][package] = records
    for path, source in outputs.items():
        path.write_text(source)
    MANIFEST.write_text(json.dumps(manifest, indent=2) + '\n')
    check()


def check(snapshot=False):
    manifest = json.loads(MANIFEST.read_text())
    total = 0
    writes = 0
    for package, records in manifest['packages'].items():
        source_path = (MANIFEST.parent / 'snapshots' / 'prepared-original-stores' / package / 'src/main.nr') if snapshot else (ROOT / f'contracts/system/{package}/src/main.nr')
        source = source_path.read_text()
        current = functions(source)
        changed_private = {c['private']: c for c in records['continuations']}
        for name, original in records['originalFunctions'].items():
            fn = current[name]
            assert digest(fn['header']) == original['signatureHash'], (package, name, 'signature/attributes changed')
            restored = fn['full']
            if name in changed_private:
                record = changed_private[name]
                assert restored.count(record['preparedEnqueue']) == 1, (package, name, 'enqueue changed')
                restored = restored.replace(record['preparedEnqueue'], record['originalEnqueue'], 1)
            assert digest(restored) == original['functionHash'], (package, name, 'original function changed')
        for record in records['continuations']:
            prepared = current[record['prepared']]
            original = current[record['original']]
            assert '#[external("public")]' in prepared['header'] and '#[only_self]' in prepared['header']
            expected_params = original['params'] + [root_name(state) + ': Field' for state in record['states']]
            assert [digest(p) for p in prepared['params']] == [digest(p) for p in expected_params]
            body = prepared['body']
            for declaration in record['classDeclarations']:
                assert body.count(declaration) == 1
                body = body.replace(declaration, '', 1)
            for replacement in record['replacements']:
                assert replacement['replacement'] in body, (package, record['prepared'], 'guarded write changed')
                body = body.replace(replacement['replacement'], replacement['original'], 1)
            assert digest(body) == digest(original['body']), (package, record['prepared'], 'other public behavior changed')
            total += 1
            writes += len(record['replacements'])
        print(f'{package}: preserved {len(records["originalFunctions"])} original functions, checked {len(records["continuations"])} prepared continuations')
    print(f'PASS: {total} continuations, {writes} guarded scalar write sites; all original function signatures and computations preserved')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--apply', action='store_true')
    group.add_argument('--check', action='store_true')
    group.add_argument('--check-snapshot', action='store_true', help='Check the preserved original-store experiment')
    args = parser.parse_args()
    if args.apply:
        apply()
    elif args.check_snapshot:
        check(snapshot=True)
    elif (MANIFEST.parent / 'generated' / 'backend-system-transform.json').exists():
        subprocess.run([sys.executable, str(MANIFEST.with_name('generate-backend-settlements.py')), '--check'], check=True)
    else:
        check()
