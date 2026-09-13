#!/usr/bin/env python3
"""Generate exact concrete FieldBuffer decoders into an explicitly selected file.

No production file is written by default. Generic Serialize and the existing
FieldBuffer wire type are unchanged. Each selected decoder makes the same ordered
Reader.read calls as the original array decoder, without its intermediate loop.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'contracts/libs/src/field_buffer.nr'
PREFIX = '''// Fixed-width, canonical Field transport for additive prepared continuations.
// Its wire representation is exactly the contained array. Direct serialization
// avoids allocating and filling a second Writer for fields already serialized.
use aztec::protocol::{traits::{Serialize, Deserialize}, utils::{reader::Reader, writer::Writer}};

pub struct FieldBuffer<let WIDTH: u32> { pub words: [Field; WIDTH] }

// Explicit public-dispatch opt-in; all Serialize/Deserialize bodies remain unchanged.
impl<let WIDTH: u32> aztec::macros::dispatch::SinglePublicArgumentDirectDeserialize for FieldBuffer<WIDTH> {}


impl<let WIDTH: u32> Serialize for FieldBuffer<WIDTH> {
    let N: u32 = WIDTH;
    fn serialize(self) -> [Field; WIDTH] { self.words }
    fn stream_serialize<let K: u32>(self, writer: &mut Writer<K>) {
        writer.write_array(self.words);
    }
}
'''


def used_widths(contracts=ROOT/'contracts'):
    result={4}  # Existing reader/writer round-trip test.
    for file in contracts.rglob('*.nr'):
        relative=file.relative_to(contracts)
        if 'target' not in relative.parts and relative.as_posix()!='libs/src/field_buffer.nr':
            result.update(map(int,re.findall(r'FieldBuffer\s*(?:::)?\s*<\s*(\d+)\s*>',file.read_text())))
    return result


def metadata(widths, selected, source):
    return {'wireType':'FieldBuffer<WIDTH> { words: [Field; WIDTH] }',
        'widths':sorted(widths),'unrolled':sorted(selected),'genericSerializeUnchanged':True,
        'sourceSha256':hashlib.sha256(source.encode()).hexdigest(), 'publicDirectMarker':True}


def render(widths,selected):
    assert selected<=widths, 'Every selected width must have an implementation'
    assert all(isinstance(width,int) and width>0 for width in widths)
    result=PREFIX+'\n// Generated concrete implementations; regenerate when an additive transport width changes.\n'
    result+='// Unselected widths retain the original array decoder. Reader bounds and\n// cursor advancement are identical; selected paths use only ordered read().\n'
    for width in sorted(widths):
        decoder=('['+', '.join(['reader.read()']*width)+']' if width in selected
                 else f'<[Field; {width}] as Deserialize>::stream_deserialize(reader)')
        result+=f'''\nimpl Deserialize for FieldBuffer<{width}> {{
    let N: u32 = {width};
    fn deserialize(fields: [Field; {width}]) -> Self {{ Self {{ words: fields }} }}
    fn stream_deserialize<let K: u32>(reader: &mut Reader<K>) -> Self {{
        Self {{ words: {decoder} }}
    }}
}}
'''
    result+='''
#[test]
fn field_buffer_preserves_all_fields_and_reader_writer_offsets() {
    let words = [0, 1, -1, 0x100000000000000000000000000000000];
    let buffer = FieldBuffer { words };
    assert(buffer.serialize() == words);
    assert(FieldBuffer::<4>::deserialize(words).words == words);
    let mut writer: Writer<6> = Writer::new();
    writer.write(17);
    buffer.stream_serialize(&mut writer);
    writer.write(29);
    let mut reader = Reader::new(writer.finish());
    assert(reader.read() == 17);
    let recovered: FieldBuffer<4> = Deserialize::stream_deserialize(&mut reader);
    assert(recovered.words == words);
    assert(reader.read() == 29);
    reader.finish();
}
'''
    return result


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--contracts',type=Path,default=ROOT/'contracts')
    parser.add_argument('--unroll',required=True,help='Comma-separated measured literal widths; empty keeps every array decoder')
    parser.add_argument('--manifest',type=Path)
    parser.add_argument('--widths',help='Explicit comma-separated library inventory; required for a restored private dependency closure')
    parser.add_argument('--check',action='store_true',help='Verify selected output and manifest without writing')
    args=parser.parse_args()
    selected={int(value)for value in args.unroll.split(',')if value}
    widths={int(v) for v in args.widths.split(',')} if args.widths else used_widths(args.contracts)
    missing=selected-widths
    assert not missing, f'Selected widths absent from current source: {sorted(missing)}'
    source=render(widths,selected)
    manifest=metadata(widths,selected,source)
    if args.check:
        assert args.output.read_text()==source, 'FieldBuffer source differs from measured decoder selection'
        if args.manifest:
            assert json.loads(args.manifest.read_text())==manifest, 'FieldBuffer selection manifest differs'
    else:
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(source)
        if args.manifest:
            args.manifest.write_text(json.dumps(manifest,indent=2)+'\n')
    print(f'{"Verified" if args.check else "Generated"} {len(widths)} exact-width decoders; {len(selected)} selected unrolls -> {args.output}')
