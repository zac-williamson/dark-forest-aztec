use serde::{reader::Reader,writer::Writer,serialization::{Serialize,Deserialize}};
pub struct FieldBuffer267 {pub words:[Field;267]}
impl Serialize for FieldBuffer267 {
 let N:u32=267;
 fn serialize(self)->[Field;267] {self.words}
 fn stream_serialize<let K:u32>(self,writer:&mut Writer<K>) {writer.write_array(self.words);}
}
impl Deserialize for FieldBuffer267 {
 let N:u32=267;
 fn deserialize(fields:[Field;267])->Self {Self{words:fields}}
 fn stream_deserialize<let K:u32>(reader:&mut Reader<K>)->Self {Self{words:reader.read_array()}}
}
pub struct FieldBuffer128 {pub words:[Field;128]}
impl Serialize for FieldBuffer128 {
 let N:u32=128;
 fn serialize(self)->[Field;128] {self.words}
 fn stream_serialize<let K:u32>(self,writer:&mut Writer<K>) {writer.write_array(self.words);}
}
impl Deserialize for FieldBuffer128 {
 let N:u32=128;
 fn deserialize(fields:[Field;128])->Self {Self{words:fields}}
 fn stream_deserialize<let K:u32>(reader:&mut Reader<K>)->Self {Self{words:reader.read_array()}}
}
pub struct FieldBuffer384 {pub words:[Field;384]}
impl Serialize for FieldBuffer384 {
 let N:u32=384;
 fn serialize(self)->[Field;384] {self.words}
 fn stream_serialize<let K:u32>(self,writer:&mut Writer<K>) {writer.write_array(self.words);}
}
impl Deserialize for FieldBuffer384 {
 let N:u32=384;
 fn deserialize(fields:[Field;384])->Self {Self{words:fields}}
 fn stream_deserialize<let K:u32>(reader:&mut Reader<K>)->Self {Self{words:reader.read_array()}}
}

pub struct HybridBuffer<let WIDTH:u32> {pub words:[Field;WIDTH]}
impl<let WIDTH:u32> Serialize for HybridBuffer<WIDTH> {
 let N:u32=WIDTH;
 fn serialize(self)->[Field;WIDTH] {self.words}
 fn stream_serialize<let K:u32>(self,writer:&mut Writer<K>) {writer.write_array(self.words);}
}
impl<let WIDTH:u32> Deserialize for HybridBuffer<WIDTH> {
 let N:u32=WIDTH;
 fn deserialize(fields:[Field;WIDTH])->Self {Self{words:fields}}
 fn stream_deserialize<let K:u32>(reader:&mut Reader<K>)->Self {Self{words:<[Field;WIDTH] as Deserialize>::stream_deserialize(reader)}}
}

pub struct UnrolledBuffer267 {pub words:[Field;267]}
impl Serialize for UnrolledBuffer267 {
 let N:u32=267;
 fn serialize(self)->[Field;267] {self.words}
 fn stream_serialize<let K:u32>(self,writer:&mut Writer<K>) {writer.write_array(self.words);}
}
impl Deserialize for UnrolledBuffer267 {
 let N:u32=267;
 fn deserialize(fields:[Field;267])->Self {Self{words:fields}}
 fn stream_deserialize<let K:u32>(reader:&mut Reader<K>)->Self {Self{words:[reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read(), reader.read()]}}
}
