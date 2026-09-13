#!/usr/bin/env python3
"""Generate typed storage facades from the immutable original API snapshot.

Only implementation bodies, imports and storage are replaced. Every original
function header and event schema is copied verbatim. New games bind once to the
canonical backend; this is not an old-state migration tool.
"""
from pathlib import Path
import re
import check
import typed_facade_logs
import artifact_touch

KINDS = {'world':1,'player':2,'planet':3,'planet_revealed_coords':4,'planet_events':5,'planet_artifacts':6,'arrival':7,'artifact':8,'artifact_location':9}
WIDTHS = {'world':4,'player':8,'planet':32,'planet_revealed_coords':4,'planet_events':22,'planet_artifacts':22,'arrival':11,'artifact':13,'artifact_location':3}
BASE=check.BASE/'sources'

def generate(slug,kind,output_root=None):
    output_root=Path(output_root) if output_root else check.ROOT
    path=Path('contracts/storage')/slug/'src/main.nr'
    s=(BASE/path).read_text();parsed=check.parse_source(str(path),s)
    event=parsed['events'][0]['name'];setter=next(f for f in parsed['functions'] if f['name']=='set')
    key_type=setter['parameters'][0]['type'];state_arg=setter['parameters'][1]['name'];state_type=setter['parameters'][1]['type']
    s=s.replace('traits::Serialize','traits::{Serialize, ToField}')
    s=s.replace('    use ::aztec::state_vars::{Map, PublicMutable};','    use ::aztec::state_vars::{Map, PublicMutable};\n    use ::game_state_backend::GameStateBackend;\n    use ::state_backend_readonly;')
    sm=re.search(r'struct Storage<Context> \{',s);se=check.balanced(check.clean(s),sm.end()-1,'{','}')
    s=s[:sm.end()]+'''
        admin: PublicMutable<AztecAddress, Context>,
        state_backend: PublicMutable<AztecAddress, Context>,
        local_roots: Map<Field, PublicMutable<Field, Context>, Context>,
        authorized_map: Map<AztecAddress, PublicMutable<bool, Context>, Context>,
        authorized_index: Map<AztecAddress, PublicMutable<u32, Context>, Context>,
        authorized_list: Map<u32, PublicMutable<AztecAddress, Context>, Context>,
        authorized_count: PublicMutable<u32, Context>,
    '''+s[se:]
    s=s.replace('    use ::state_backend_readonly;', '    use ::state_backend_readonly;\n    use ::aztec::event::event_interface::EventInterface;')
    if slug=='arrival':s=s.replace('    use ::state_backend_readonly;', '    use ::state_backend_readonly;\n    use ::libs::arrival_codec::keyed::{pack_arrival, unpack_arrival};')
    parsed=check.parse_source(str(path),s)
    replacements=[]
    for f in parsed['functions']:
        m=re.search(r'\bfn\s+'+re.escape(f['name'])+r'\s*\(',s);pe=check.balanced(check.clean(s),m.end()-1);bs=s.find('{',pe);be=check.balanced(check.clean(s),bs,'{','}')
        original=s[bs+1:be];name=f['name'];utility=f['kind']=='utility';dispatch='call' if utility else 'view';suffix='_unconstrained' if utility else ''
        common='''        let backend_address = self.storage.state_backend.read();
        let namespace = self.context.this_address();
'''
        require='''        let backend_address = self.storage.state_backend.read();
        assert(!backend_address.is_zero(), "State backend not bound");
        let backend = GameStateBackend::at(backend_address);
'''
        if utility:common=common.replace('        let backend = GameStateBackend::at(backend_address);\n','')
        def read(method,args,fallback):
            fullargs='namespace'+(', '+args if args else '')
            operation = f'state_backend_readonly::{method}(self.context, backend_address, {fullargs})' if utility else f'state_backend_readonly::public_read::{method}(backend_address, {fullargs})'
            return f'if backend_address.is_zero() {{ {fallback} }} else {{ {operation} }}'
        # Permissions and roots are authoritative facade state. Copy original
        # bodies; use Field keys explicitly for the Player address namespace.
        body=original.replace('self.storage.state_roots','self.storage.local_roots')
        if slug=='player':body=body.replace('local_roots.at(id)','local_roots.at(id.to_field())')
        if name=='constructor':
            body=body.replace('self.storage.admin.write(admin);',
                'self.storage.admin.write(admin);\n        self.storage.state_backend.write(AztecAddress::zero());')
            if slug=='arrival':body=body.replace('self.storage.event_id_counter.write(1);',
                '// Backend binding initializes the unchanged counter at 1.')
        elif slug=='arrival':
            if name=='set':
                body=require+f'        self.call(backend.legacy_set_arrival(self.msg_sender(), id, {state_arg}.id, pack_arrival({state_arg})));\n'
                body+=f'''        self.storage.local_roots.at(id).write(poseidon2_hash({state_arg}.serialize()));
        self.emit({event} {{ id: id, block_number: self.context.block_number(), state: {state_arg} }});'''
            elif name=='allocate_event_id':body=require+'        self.call(backend.allocate_event_id(self.msg_sender()))'
            else:
                # Only the compact Arrival payload and late ID counter live in
                # Backend. Public reads see pending state; utility reads anchor.
                before=body
                body=re.sub(r'self\.storage\.stored_arrivals\.at\(([^()]*)\)\.read\(\)',lambda m:'('+read('get_arrival',m[1],'Arrival::zero()')+')',body)
                body=body.replace('self.storage.event_id_counter.read()','('+read('get_event_id_counter','','1')+')')
                if body!=before:body=common+body
        if name=='set' and slug in typed_facade_logs.SPECS:
            body=typed_facade_logs.rewrite_setter(slug,body)
        replacements.append((bs+1,be,'\n'+body.rstrip()+'\n    '))
    for a,b,t in reversed(replacements):s=s[:a]+t+s[b:]
    # Binding and callback APIs are additive; original APIs and event schemas above are unchanged.
    extra=f'''
    // Deployment wiring for a fresh game. Write before the external call; a failed
    // bind reverts both contracts atomically, and reentrant rebinding is rejected.
    #[external("public")]
    fn set_state_backend(backend_address: AztecAddress) {{
        assert(self.storage.state_backend.read().is_zero(), "State backend already bound");
        assert(self.msg_sender() == self.storage.admin.read(), "Only admin");
        assert(!backend_address.is_zero(), "Invalid state backend");
        self.storage.state_backend.write(backend_address);
        self.call(GameStateBackend::at(backend_address).bind_namespace({kind}, self.storage.admin.read()));
    }}

    #[external("public")]
    #[view]
    fn get_state_backend() -> AztecAddress {{ self.storage.state_backend.read() }}

    #[external("utility")]
    unconstrained fn get_state_backend_unconstrained() -> AztecAddress {{ self.storage.state_backend.read() }}

    #[external("public")]
    fn emit_{slug}_update(id: {key_type}, state: {state_type}) {{
        let backend_address = self.storage.state_backend.read();
        assert(!backend_address.is_zero() & (self.msg_sender() == backend_address), "Only state backend");
        self.storage.local_roots.at({'id.to_field()' if slug=='player' else 'id'}).write(poseidon2_hash(state.serialize()));
        self.emit({event} {{ id: id, block_number: self.context.block_number(), state: state }});
    }}
'''
    # These words come only from the bound backend's authenticated typed producers.
    # Emit the exact original event wire format without decoding and re-encoding
    # its fields. The original typed event and setter API remain unchanged above.
    width=WIDTHS[slug]
    fields=', '.join(f'field_{i}' for i in range(width))
    parameters=', '.join(f'field_{i}: Field' for i in range(width))
    extra+=f'''
    #[external("public")]
    fn emit_{slug}_fields(id: Field, root: Field, {parameters}) {{
        let backend_address = self.storage.state_backend.read();
        assert(!backend_address.is_zero() & (self.msg_sender() == backend_address), "Only state backend");
        self.storage.local_roots.at(id).write(root);
        let tag = comptime {{ aztec::protocol::hash::compute_log_tag(
            {event}::get_event_type_id().to_field(), aztec::protocol::constants::DOM_SEP__EVENT_LOG_TAG,
        ) }};
        let log = [tag, id, self.context.block_number() as Field, {fields}];
        // Safety: The VM constrains log emission; the tag/schema/address are identical
        // to self.emit({event}), and the backend supplies canonical state.
        aztec::oracle::avm::emit_public_log(log.as_vector());
    }}
'''
    # Batch boundaries are explicit. The bound Backend has already checked
    # the original System's live grant at that boundary; callbacks only store
    # roots and emit the original records in input order (including duplicates).
    for batch_slug,maximum in [('artifact_location',5),('artifact_location',20),('artifact',5)]:
        if slug!=batch_slug:continue
        emitted=', '.join(f'fields[i][{j}]' for j in range(width))
        extra+=f'''
    #[external("public")]
    fn emit_{slug}_batch_max{maximum}(ids: [Field; {maximum}], fields: [[Field; {width}]; {maximum}], count: u32) {{
        let backend_address = self.storage.state_backend.read();
        assert(!backend_address.is_zero() & (self.msg_sender() == backend_address), "Only state backend");
        assert(count <= {maximum}, "count exceeds batch size");
        let tag = comptime {{ aztec::protocol::hash::compute_log_tag(
            {event}::get_event_type_id().to_field(), aztec::protocol::constants::DOM_SEP__EVENT_LOG_TAG,
        ) }};
        for i in 0..count {{
            if ids[i] != 0 {{
                self.storage.local_roots.at(ids[i]).write(poseidon2_hash(fields[i]));
                let log = [tag, ids[i], self.context.block_number() as Field, {emitted}];
                aztec::oracle::avm::emit_public_log(log.as_vector());
            }}
        }}
    }}
'''
    # Keep this earlier additive read API because current Move fallback callers use it.
    if slug=='artifact':extra+='''
    #[external("public")]
    #[view]
    fn verify_hashes_three(ids: [Field; 3], hashes: [Field; 3]) -> [bool; 3] {
        let first = self.storage.local_roots.at(ids[0]).read();
        let second = if ids[1] == ids[0] { first } else { self.storage.local_roots.at(ids[1]).read() };
        let third = if ids[2] == ids[0] { first } else if ids[2] == ids[1] { second } else { self.storage.local_roots.at(ids[2]).read() };
        [first == hashes[0], second == hashes[1], third == hashes[2]]
    }
'''
    pos=s.rfind('}');s=s[:pos]+extra+s[pos:]
    s=s.replace('// Only admin or authorized contracts can write; anyone can verify state by hash.','// Original typed API and event emitter; roots and permissions are authoritative local state.')
    s='\n'.join(line.rstrip() for line in s.splitlines())+'\n'
    s=artifact_touch.apply_facade(s,slug,artifact_touch.parser())
    (output_root/path).write_text(s)
    manifest=output_root/path.parents[1]/'Nargo.toml';toml=manifest.read_text()
    if 'game_state_backend =' not in toml:manifest.write_text(toml.rstrip()+'\ngame_state_backend = { path = "../../state_backend" }\n')
    toml=manifest.read_text()
    if 'state_backend_readonly =' not in toml:manifest.write_text(toml.rstrip()+'\nstate_backend_readonly = { path = "../../state_backend_readonly" }\n')
    return str(path)

if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path)
    args=parser.parse_args()
    for slug,kind in KINDS.items():print(generate(slug,kind,args.root))
