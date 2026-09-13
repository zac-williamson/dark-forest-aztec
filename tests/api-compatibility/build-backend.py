from pathlib import Path
import argparse
parser=argparse.ArgumentParser()
parser.add_argument('--settlements',choices=['all','move','none'],default='all')
parser.add_argument('--root',type=Path,help='Isolated output tree; defaults to the repository')
options=parser.parse_args()
root=options.root.resolve() if options.root else Path(__file__).resolve().parents[2]
tables=[('world','World','Field',1),('player','Player','AztecAddress',2),('planet','Planet','Field',3),('planet_revealed_coords','PlanetRevealedCoords','Field',4),('planet_events','PlanetEvents','Field',5),('planet_artifacts','PlanetArtifacts','Field',6),('arrival','Arrival','Field',7),('artifact','Artifact','Field',8),('artifact_location','ArtifactLocation','Field',9)]
widths={'world':4,'player':8,'planet':32,'planet_revealed_coords':4,'planet_events':22,'planet_artifacts':22,'arrival':11,'artifact':13,'artifact_location':3}
imports='''    use aztec::protocol::{address::AztecAddress, hash::poseidon2_hash, traits::{Serialize,ToField,FromField}};
    use types::storage::{world::World, player::Player, planet::{Planet,PlanetArtifacts,PlanetEvents,PlanetEventMetadata,PlanetRevealedCoords}, arrival::Arrival, artifact::{Artifact,ArtifactLocation}};
'''
manifest='''[package]
name = "NAME"
type = "contract"
authors = [""]
[dependencies]
aztec = { path = "../../vendor/aztec" }
types = { path="../types" }
'''
(root/'contracts/state_facade_interface/Nargo.toml').write_text(manifest.replace('NAME','state_facade_interface'))
interface='''// Call signatures only. This contract is never deployed.
use aztec::macros::aztec;
#[aztec]
pub contract StateFacadeInterface {
    use aztec::macros::functions::{external,view};
'''+imports
for name,typ,key,kind in tables:
 interface+=f'    #[external("public")]\n    fn emit_{name}_update(_id: {key}, _state: {typ}) {{ assert(false, "Interface only"); }}\n'
 parameters=', '.join(f'_field_{i}: Field' for i in range(widths[name]))
 interface+=f'    #[external("public")]\n    fn emit_{name}_fields(_id: Field, _root: Field, {parameters}) {{ assert(false, "Interface only"); }}\n'
for name,n in [('artifact_location',5),('artifact_location',20),('artifact',5)]:
 interface+=f'    #[external("public")]\n    fn emit_{name}_batch_max{n}(_ids:[Field;{n}], _fields:[[Field;{widths[name]}];{n}], _count:u32) {{ assert(false,"Interface only"); }}\n'
interface+='}\n'
(root/'contracts/state_facade_interface/src/main.nr').write_text(interface)
(root/'contracts/state_backend/Nargo.toml').write_text(manifest.replace('NAME','game_state_backend')+'libs = { path="../libs" }\nconfig = { path="../config" }\nstate_facade_interface = { path="../state_facade_interface" }\n')
trusted=root/'contracts/state_backend/src/trusted_classes.nr'
if not trusted.exists():trusted.write_text('''// Filled from the seven audited immutable system classes after compilation.
// Unknown classes receive full public hash verification. No admin can change this list.
pub global SYSTEM_CLASSES: [Field; 7] = [0; 7];
pub global FACADE_CLASSES: [Field; 9] = [0; 9];
pub global WORKER_CLASSES: [Field; 2] = [0; 2];
pub global CONFIG_CLASS: Field = 0;
pub fn contains(id: Field) -> bool {
    (id != 0) & ((id == SYSTEM_CLASSES[0]) | (id == SYSTEM_CLASSES[1])
        | (id == SYSTEM_CLASSES[2]) | (id == SYSTEM_CLASSES[3])
        | (id == SYSTEM_CLASSES[4]) | (id == SYSTEM_CLASSES[5]) | (id == SYSTEM_CLASSES[6]))
}
''')
source='''// Shared game settlement and compact Arrival payloads.
// Each immutable facade owns its authoritative root map and original event emitter.
mod trusted_classes;
use aztec::macros::aztec;
#[aztec]
pub contract GameStateBackend {
    use aztec::macros::{functions::{external,initializer,internal,view},storage::storage};
    use aztec::state_vars::{Map,PublicMutable,StateVariable};
    use aztec::protocol::traits::Deserialize;
    use aztec::oracle::get_contract_instance::get_contract_instance_current_class_id_avm;
    use state_facade_interface::StateFacadeInterface;
    use config::Config;
    use libs::arrival_codec::keyed::pack_arrival;
    use libs::batch_utils::assert_public_timestamp;
    use types::storage::artifact::ArtifactType;
'''+imports+'''
    #[storage]
    struct Storage<Context> {
        kinds: Map<AztecAddress,PublicMutable<u8,Context>,Context>,
        arrivals: Map<AztecAddress,Map<Field,PublicMutable<[Field;7],Context>,Context>,Context>,
        counters: Map<AztecAddress,PublicMutable<Field,Context>,Context>,
    }
    #[external("public")] #[initializer]
    fn constructor() {}

    // The namespace is the authenticated caller, never a caller-supplied address.
    #[external("public")]
    fn bind_namespace(kind: u8, initial_admin: AztecAddress) {
        let ns = self.msg_sender();
        assert(kind >= 1 & kind <= 9, "Unknown namespace kind");
        assert(self.storage.kinds.at(ns).read() == 0, "Namespace already bound");
        let caller_class = get_contract_instance_current_class_id_avm(ns);
        assert(caller_class.is_some(), "Unrecognized facade");
        let expected_class = super::trusted_classes::FACADE_CLASSES[(kind - 1) as u32];
        assert(expected_class != 0, "Facade classes not configured");
        assert(caller_class.unwrap().to_field() == expected_class, "Unrecognized facade");
        self.storage.kinds.at(ns).write(kind);
        // Retain the additive binding ABI; the facade owns its current admin.
        let _ = initial_admin;
        if kind == 7 { self.storage.counters.at(ns).write(1); }
    }
    #[internal("public")]
    fn _expect_kind(ns: AztecAddress, kind: u8) {
        assert(self.storage.kinds.at(ns).read() == kind, "Wrong namespace kind");
    }
    #[internal("public")]
    fn _assert_authorized(ns: AztecAddress, actor: AztecAddress) {
        let slot=aztec::protocol::storage::map::derive_storage_slot_in_map(4,actor);
        let explicitly_granted=aztec::oracle::avm::storage_read(slot,ns.to_field());
        if explicitly_granted == 0 {
            let admin=AztecAddress::from_field(aztec::oracle::avm::storage_read(1,ns.to_field()));
            assert(actor==admin,"Not authorized");
        }
    }
    #[internal("public")]
    fn _is_prepared_writer(actor: AztecAddress) -> bool {
        let current = get_contract_instance_current_class_id_avm(actor);
        if current.is_some() { super::trusted_classes::contains(current.unwrap().to_field()) }
        else { false }
    }
    #[internal("public")]
    fn _can_settle(addresses: [AztecAddress;10], required_mask: u16) -> bool {
        let mut valid = true;
        for i in 1..10 {
            if (required_mask & (1u16 << i)) != 0 {
                if self.storage.kinds.at(addresses[i as u32]).read() != (i as u8) { valid = false; }
            }
        }
        valid
    }
    #[internal("public")]
    fn _verify_hash(ns: AztecAddress, key: Field, hash: Field) -> bool {
        aztec::oracle::avm::storage_read(aztec::protocol::storage::map::derive_storage_slot_in_map(3,key),ns.to_field()) == hash
    }
    #[internal("public")]
    fn _is_initialized(ns: AztecAddress, key: Field) -> bool {
        aztec::oracle::avm::storage_read(aztec::protocol::storage::map::derive_storage_slot_in_map(3,key),ns.to_field()) != 0
    }
    #[internal("public")]
    fn _verify_hashes_batch(ns: AztecAddress, ids:[Field;20], hashes:[Field;20], count:u32) -> bool {
        assert(count <= 20, "count exceeds batch size");
        let mut result = true;
        for i in 0..count {
            if result & (ids[i] != 0) {
                if aztec::oracle::avm::storage_read(aztec::protocol::storage::map::derive_storage_slot_in_map(3,ids[i]),ns.to_field()) != hashes[i] { result = false; }
            }
        }
        result
    }
    #[internal("public")]
    fn _verify_hashes_three(ns:AztecAddress, ids:[Field;3], hashes:[Field;3])->[bool;3] {
        let first = aztec::oracle::avm::storage_read(aztec::protocol::storage::map::derive_storage_slot_in_map(3,ids[0]),ns.to_field());
        let second = if ids[1] == ids[0] { first }
            else { aztec::oracle::avm::storage_read(aztec::protocol::storage::map::derive_storage_slot_in_map(3,ids[1]),ns.to_field()) };
        let third = if ids[2] == ids[0] { first }
            else if ids[2] == ids[1] { second }
            else { aztec::oracle::avm::storage_read(aztec::protocol::storage::map::derive_storage_slot_in_map(3,ids[2]),ns.to_field()) };
        [first == hashes[0], second == hashes[1], third == hashes[2]]
    }
'''
# Original getters remain on all nine facades and read these slots through the
# constrained VM / utility library. Redundant experimental backend getter APIs
# are omitted so native bytecode space remains available for game settlement.
source+='''    #[internal("public")]
    fn _store_arrival_payload(ns:AztecAddress, id:Field, packed:[Field;7]) {
        let slot=self.storage.arrivals.at(ns).at(id).get_storage_slot();
        for i in 0..7 {
            // Unwritten words already read as zero. On an overwrite, explicitly
            // clear any old nonzero word, so compact/full transitions are exact.
            if packed[i] != 0 {
                self.context.raw_storage_write(slot+i as Field,[packed[i]]);
            } else {
                let old:[Field;1]=self.context.raw_storage_read(slot+i as Field);
                if old[0] != 0 { self.context.raw_storage_write(slot+i as Field,[0]); }
            }
        }
    }
    #[internal("public")]
    fn _allocate_event_id(ns:AztecAddress, actor:AztecAddress)->Field {
        self.internal._assert_authorized(ns,actor);
        let next=self.storage.counters.at(ns).read()+1;
        self.storage.counters.at(ns).write(next); next
    }
    #[external("public")]
    fn allocate_event_id(actor:AztecAddress)->Field {
        let ns=self.msg_sender(); self.internal._expect_kind(ns,7);
        self.internal._allocate_event_id(ns,actor)
    }
'''
for name,typ,key,kind in tables:
 keyfield='id.to_field()' if key=='AztecAddress' else 'id'
 emitted='AztecAddress::from_field(id)' if key=='AztecAddress' else 'id'
 special='assert(id == state.id, "id mismatch");' if kind==7 else ''
 packed='self.internal._store_arrival_payload(ns,id,pack_arrival(state));' if kind==7 else ''
 emitted_fields=', '.join(f'fields[{i}]' for i in range(widths[name]))
 source+=f'''    #[internal("public")]
    fn _write_{name}(ns:AztecAddress, actor:AztecAddress, id:Field, state:{typ}, new_root:Field, prepared:bool) -> Field {{
        self.internal._assert_authorized(ns,actor);
        {special}
        // Every game settlement authenticates its immutable System caller once
        // before reaching this helper. Original arbitrary writers use the
        // class-authenticated typed facade setters, which hash their own state.
        let root = if prepared {{ new_root }} else {{ poseidon2_hash(state.serialize()) }};
        {packed}
        root
    }}
    #[internal("public")]
    fn _set_{name}(ns:AztecAddress, actor:AztecAddress, id:Field, state:{typ}, new_root:Field, prepared:bool) {{
        let root = self.internal._write_{name}(ns,actor,id,state,new_root,prepared);
        let fields=state.serialize();
        self.call(StateFacadeInterface::at(ns).emit_{name}_fields(id,root,{emitted_fields}));
    }}
'''
 if kind!=7:
  source+=f'''    #[internal("public")]
    fn _set_{name}_fields(ns:AztecAddress, actor:AztecAddress, id:Field, fields:[Field;{widths[name]}], new_root:Field, prepared:bool) {{
        self.internal._assert_authorized(ns,actor);
        // Only immutable, class-authenticated typed producers can reach this
        // internal primitive. Original arbitrary writers use typed facade APIs.
        let root = if prepared {{ new_root }} else {{ poseidon2_hash(fields) }};
        self.call(StateFacadeInterface::at(ns).emit_{name}_fields(id,root,{emitted_fields}));
    }}
'''
source+='''    // The immutable Arrival facade authenticates its actual caller here.
    // No external callback occurs between payload storage and its local root write.
    #[external("public")]
    fn legacy_set_arrival(actor:AztecAddress,id:Field,state_id:Field,packed:[Field;7]) {
        let ns=self.msg_sender();self.internal._expect_kind(ns,7);
        self.internal._assert_authorized(ns,actor);
        assert(id == state_id, "id mismatch");
        self.internal._store_arrival_payload(ns,id,packed);
    }
'''
# Emit zero/singleton batches without fixed maximum-size calldata. Larger
# batches cross into their original emitting facade once, preserving boundaries.
for name,n in [('artifact_location',5),('artifact',5),('artifact_location',20)]:
 width=widths[name]
 source+=f'''    #[internal("public")]
    fn _emit_{name}_batch_max{n}(ns:AztecAddress,ids:[Field;{n}],fields:[[Field;{width}];{n}],count:u32) {{
'''
 if n==20:
  source+='''        if count <= 5 {
            let small_ids=[ids[0],ids[1],ids[2],ids[3],ids[4]];
            let small_fields=[fields[0],fields[1],fields[2],fields[3],fields[4]];
            self.internal._emit_artifact_location_batch_max5(ns,small_ids,small_fields,count);
        } else {
            self.call(StateFacadeInterface::at(ns).emit_artifact_location_batch_max20(ids,fields,count));
        }
'''
 else:
  emitted=', '.join(f'fields[0][{i}]' for i in range(width))
  source+=f'''        if count == 1 {{
            self.call(StateFacadeInterface::at(ns).emit_{name}_fields(ids[0],poseidon2_hash(fields[0]),{emitted}));
        }} else if count > 1 {{
            self.call(StateFacadeInterface::at(ns).emit_{name}_batch_max{n}(ids,fields,count));
        }}
'''
 source+='    }\n'
for method,name,typ,n,kind in [('set_arrival_locations_max20','artifact_location','ArtifactLocation',20,9),('set_spaceship_locations_max5','artifact_location','ArtifactLocation',5,9),('set_spaceships_max5','artifact','Artifact',5,8)]:
 source+=f'''    #[internal("public")]
    fn _{method}(ns:AztecAddress,actor:AztecAddress,ids:[Field;{n}],states:[{typ};{n}],count:u32) {{
        self.internal._assert_authorized(ns,actor);
        assert(count<={n},"count exceeds batch size");
        let mut active_ids=[0;{n}];
        let mut fields=[[0;{widths[name]}];{n}];
        let mut active=0;
        for i in 0..count {{
            if ids[i]!=0 {{
                active_ids[active]=ids[i];
                fields[active]=states[i].serialize();
                active+=1;
            }}
        }}
        self.internal._emit_{name}_batch_max{n}(ns,active_ids,fields,active);
    }}
'''
for f in ['backend-plans.nr','backend-move.nr']:
 if options.settlements=='none' or (options.settlements=='move' and f!='backend-move.nr'):continue
 p=root/'tests/api-compatibility/generated'/f
 if p.exists():source+='\n'+p.read_text().replace('    use aztec::protocol::traits::Deserialize;\n','')+'\n'
source+='}\n'
(root/'contracts/state_backend/src/main.nr').write_text('\n'.join(line.rstrip() for line in source.splitlines())+'\n')
for name in ['lib.nr','public_read.nr']:
 template=Path(__file__).with_name('templates')/'state_backend_readonly'/name
 (root/'contracts/state_backend_readonly/src'/name).write_text(template.read_text())
p=root/'contracts/Nargo.toml';s=p.read_text()
for member in ['state_backend','state_facade_interface','settlement_workers/core','settlement_workers/vault']:
 if f'"{member}"' not in s:s=s.replace('members = [',f'members = [\n    "{member}",')
p.write_text(s)
print('Generated canonical backend primitives and typed facade interface')
