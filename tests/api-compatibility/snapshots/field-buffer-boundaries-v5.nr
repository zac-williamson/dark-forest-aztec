use libs::field_buffer::FieldBuffer;
use aztec::protocol::{traits::{Serialize, Deserialize}, utils::{reader::Reader, writer::Writer}};

#[test]
fn reader_writer_cursor_4() {
 let mut original:[Field;4]=[0;4];
 for i in 0..4 {original[i]=if i%3==0 {0} else if i%3==1 {-1} else {i as Field+0x100000000000000000000000000000000000000000000000000};}
 let mut writer:Writer<6> =Writer::new();writer.write(17);FieldBuffer{words:original}.stream_serialize(&mut writer);writer.write(29);
 let mut reader=Reader::new(writer.finish());assert_eq(reader.read(),17);
 let recovered:FieldBuffer<4> =Deserialize::stream_deserialize(&mut reader);
 assert_eq(recovered.words,original);assert_eq(reader.read(),29);reader.finish();
 assert_eq(FieldBuffer::<4>::deserialize(original).serialize(),original);
}

#[test(should_fail)]
fn insufficient_reader_4() {let mut reader=Reader::new([0;3]);let _p:FieldBuffer<4> =Deserialize::stream_deserialize(&mut reader);}

#[test]
fn reader_writer_cursor_56() {
 let mut original:[Field;56]=[0;56];
 for i in 0..56 {original[i]=if i%3==0 {0} else if i%3==1 {-1} else {i as Field+0x100000000000000000000000000000000000000000000000000};}
 let mut writer:Writer<58> =Writer::new();writer.write(17);FieldBuffer{words:original}.stream_serialize(&mut writer);writer.write(29);
 let mut reader=Reader::new(writer.finish());assert_eq(reader.read(),17);
 let recovered:FieldBuffer<56> =Deserialize::stream_deserialize(&mut reader);
 assert_eq(recovered.words,original);assert_eq(reader.read(),29);reader.finish();
 assert_eq(FieldBuffer::<56>::deserialize(original).serialize(),original);
}

#[test(should_fail)]
fn insufficient_reader_56() {let mut reader=Reader::new([0;55]);let _p:FieldBuffer<56> =Deserialize::stream_deserialize(&mut reader);}

#[test]
fn reader_writer_cursor_60() {
 let mut original:[Field;60]=[0;60];
 for i in 0..60 {original[i]=if i%3==0 {0} else if i%3==1 {-1} else {i as Field+0x100000000000000000000000000000000000000000000000000};}
 let mut writer:Writer<62> =Writer::new();writer.write(17);FieldBuffer{words:original}.stream_serialize(&mut writer);writer.write(29);
 let mut reader=Reader::new(writer.finish());assert_eq(reader.read(),17);
 let recovered:FieldBuffer<60> =Deserialize::stream_deserialize(&mut reader);
 assert_eq(recovered.words,original);assert_eq(reader.read(),29);reader.finish();
 assert_eq(FieldBuffer::<60>::deserialize(original).serialize(),original);
}

#[test(should_fail)]
fn insufficient_reader_60() {let mut reader=Reader::new([0;59]);let _p:FieldBuffer<60> =Deserialize::stream_deserialize(&mut reader);}

#[test]
fn reader_writer_cursor_144() {
 let mut original:[Field;144]=[0;144];
 for i in 0..144 {original[i]=if i%3==0 {0} else if i%3==1 {-1} else {i as Field+0x100000000000000000000000000000000000000000000000000};}
 let mut writer:Writer<146> =Writer::new();writer.write(17);FieldBuffer{words:original}.stream_serialize(&mut writer);writer.write(29);
 let mut reader=Reader::new(writer.finish());assert_eq(reader.read(),17);
 let recovered:FieldBuffer<144> =Deserialize::stream_deserialize(&mut reader);
 assert_eq(recovered.words,original);assert_eq(reader.read(),29);reader.finish();
 assert_eq(FieldBuffer::<144>::deserialize(original).serialize(),original);
}

#[test(should_fail)]
fn insufficient_reader_144() {let mut reader=Reader::new([0;143]);let _p:FieldBuffer<144> =Deserialize::stream_deserialize(&mut reader);}

#[test]
fn reader_writer_cursor_88() {
 let mut original:[Field;88]=[0;88];
 for i in 0..88 {original[i]=if i%3==0 {0} else if i%3==1 {-1} else {i as Field+0x100000000000000000000000000000000000000000000000000};}
 let mut writer:Writer<90> =Writer::new();writer.write(17);FieldBuffer{words:original}.stream_serialize(&mut writer);writer.write(29);
 let mut reader=Reader::new(writer.finish());assert_eq(reader.read(),17);
 let recovered:FieldBuffer<88> =Deserialize::stream_deserialize(&mut reader);
 assert_eq(recovered.words,original);assert_eq(reader.read(),29);reader.finish();
 assert_eq(FieldBuffer::<88>::deserialize(original).serialize(),original);
}

#[test(should_fail)]
fn insufficient_reader_88() {let mut reader=Reader::new([0;87]);let _p:FieldBuffer<88> =Deserialize::stream_deserialize(&mut reader);}

#[test]
fn reader_writer_cursor_337() {
 let mut original:[Field;337]=[0;337];
 for i in 0..337 {original[i]=if i%3==0 {0} else if i%3==1 {-1} else {i as Field+0x100000000000000000000000000000000000000000000000000};}
 let mut writer:Writer<339> =Writer::new();writer.write(17);FieldBuffer{words:original}.stream_serialize(&mut writer);writer.write(29);
 let mut reader=Reader::new(writer.finish());assert_eq(reader.read(),17);
 let recovered:FieldBuffer<337> =Deserialize::stream_deserialize(&mut reader);
 assert_eq(recovered.words,original);assert_eq(reader.read(),29);reader.finish();
 assert_eq(FieldBuffer::<337>::deserialize(original).serialize(),original);
}

#[test(should_fail)]
fn insufficient_reader_337() {let mut reader=Reader::new([0;336]);let _p:FieldBuffer<337> =Deserialize::stream_deserialize(&mut reader);}

#[test]
fn reader_writer_cursor_227() {
 let mut original:[Field;227]=[0;227];
 for i in 0..227 {original[i]=if i%3==0 {0} else if i%3==1 {-1} else {i as Field+0x100000000000000000000000000000000000000000000000000};}
 let mut writer:Writer<229> =Writer::new();writer.write(17);FieldBuffer{words:original}.stream_serialize(&mut writer);writer.write(29);
 let mut reader=Reader::new(writer.finish());assert_eq(reader.read(),17);
 let recovered:FieldBuffer<227> =Deserialize::stream_deserialize(&mut reader);
 assert_eq(recovered.words,original);assert_eq(reader.read(),29);reader.finish();
 assert_eq(FieldBuffer::<227>::deserialize(original).serialize(),original);
}

#[test(should_fail)]
fn insufficient_reader_227() {let mut reader=Reader::new([0;226]);let _p:FieldBuffer<227> =Deserialize::stream_deserialize(&mut reader);}

#[test]
fn reader_writer_cursor_245() {
 let mut original:[Field;245]=[0;245];
 for i in 0..245 {original[i]=if i%3==0 {0} else if i%3==1 {-1} else {i as Field+0x100000000000000000000000000000000000000000000000000};}
 let mut writer:Writer<247> =Writer::new();writer.write(17);FieldBuffer{words:original}.stream_serialize(&mut writer);writer.write(29);
 let mut reader=Reader::new(writer.finish());assert_eq(reader.read(),17);
 let recovered:FieldBuffer<245> =Deserialize::stream_deserialize(&mut reader);
 assert_eq(recovered.words,original);assert_eq(reader.read(),29);reader.finish();
 assert_eq(FieldBuffer::<245>::deserialize(original).serialize(),original);
}

#[test(should_fail)]
fn insufficient_reader_245() {let mut reader=Reader::new([0;244]);let _p:FieldBuffer<245> =Deserialize::stream_deserialize(&mut reader);}

#[test]
fn reader_writer_cursor_539() {
 let mut original:[Field;539]=[0;539];
 for i in 0..539 {original[i]=if i%3==0 {0} else if i%3==1 {-1} else {i as Field+0x100000000000000000000000000000000000000000000000000};}
 let mut writer:Writer<541> =Writer::new();writer.write(17);FieldBuffer{words:original}.stream_serialize(&mut writer);writer.write(29);
 let mut reader=Reader::new(writer.finish());assert_eq(reader.read(),17);
 let recovered:FieldBuffer<539> =Deserialize::stream_deserialize(&mut reader);
 assert_eq(recovered.words,original);assert_eq(reader.read(),29);reader.finish();
 assert_eq(FieldBuffer::<539>::deserialize(original).serialize(),original);
}

#[test(should_fail)]
fn insufficient_reader_539() {let mut reader=Reader::new([0;538]);let _p:FieldBuffer<539> =Deserialize::stream_deserialize(&mut reader);}

#[test]
fn reader_writer_cursor_549() {
 let mut original:[Field;549]=[0;549];
 for i in 0..549 {original[i]=if i%3==0 {0} else if i%3==1 {-1} else {i as Field+0x100000000000000000000000000000000000000000000000000};}
 let mut writer:Writer<551> =Writer::new();writer.write(17);FieldBuffer{words:original}.stream_serialize(&mut writer);writer.write(29);
 let mut reader=Reader::new(writer.finish());assert_eq(reader.read(),17);
 let recovered:FieldBuffer<549> =Deserialize::stream_deserialize(&mut reader);
 assert_eq(recovered.words,original);assert_eq(reader.read(),29);reader.finish();
 assert_eq(FieldBuffer::<549>::deserialize(original).serialize(),original);
}

#[test(should_fail)]
fn insufficient_reader_549() {let mut reader=Reader::new([0;548]);let _p:FieldBuffer<549> =Deserialize::stream_deserialize(&mut reader);}

// Every slot receives zero, maximal Field, and a distinct value above u128.
#[test]
fn reader_writer_cursor_35() {
 for rotation in 0..3 {
  let mut original:[Field;35]=[0;35];
  for i in 0..35 {original[i]=if (i+rotation)%3==0 {0} else if (i+rotation)%3==1 {-1} else {i as Field+0x100000000000000000000000000000000000000000000000000};}
  let mut writer:Writer<37> =Writer::new();writer.write(17);FieldBuffer{words:original}.stream_serialize(&mut writer);writer.write(29);
  let mut reader=Reader::new(writer.finish());assert_eq(reader.read(),17);
  let recovered:FieldBuffer<35> =Deserialize::stream_deserialize(&mut reader);
  assert_eq(recovered.words,original);assert_eq(reader.read(),29);reader.finish();
  assert_eq(FieldBuffer::<35>::deserialize(original).serialize(),original);
 }
}

#[test(should_fail)]
fn insufficient_reader_35() {let mut reader=Reader::new([0;34]);let _p:FieldBuffer<35> =Deserialize::stream_deserialize(&mut reader);}

// Every slot receives zero, maximal Field, and a distinct value above u128.
#[test]
fn reader_writer_cursor_52() {
 for rotation in 0..3 {
  let mut original:[Field;52]=[0;52];
  for i in 0..52 {original[i]=if (i+rotation)%3==0 {0} else if (i+rotation)%3==1 {-1} else {i as Field+0x100000000000000000000000000000000000000000000000000};}
  let mut writer:Writer<54> =Writer::new();writer.write(17);FieldBuffer{words:original}.stream_serialize(&mut writer);writer.write(29);
  let mut reader=Reader::new(writer.finish());assert_eq(reader.read(),17);
  let recovered:FieldBuffer<52> =Deserialize::stream_deserialize(&mut reader);
  assert_eq(recovered.words,original);assert_eq(reader.read(),29);reader.finish();
  assert_eq(FieldBuffer::<52>::deserialize(original).serialize(),original);
 }
}

#[test(should_fail)]
fn insufficient_reader_52() {let mut reader=Reader::new([0;51]);let _p:FieldBuffer<52> =Deserialize::stream_deserialize(&mut reader);}

// Every slot receives zero, maximal Field, and a distinct value above u128.
#[test]
fn reader_writer_cursor_141() {
 for rotation in 0..3 {
  let mut original:[Field;141]=[0;141];
  for i in 0..141 {original[i]=if (i+rotation)%3==0 {0} else if (i+rotation)%3==1 {-1} else {i as Field+0x100000000000000000000000000000000000000000000000000};}
  let mut writer:Writer<143> =Writer::new();writer.write(17);FieldBuffer{words:original}.stream_serialize(&mut writer);writer.write(29);
  let mut reader=Reader::new(writer.finish());assert_eq(reader.read(),17);
  let recovered:FieldBuffer<141> =Deserialize::stream_deserialize(&mut reader);
  assert_eq(recovered.words,original);assert_eq(reader.read(),29);reader.finish();
  assert_eq(FieldBuffer::<141>::deserialize(original).serialize(),original);
 }
}

#[test(should_fail)]
fn insufficient_reader_141() {let mut reader=Reader::new([0;140]);let _p:FieldBuffer<141> =Deserialize::stream_deserialize(&mut reader);}

// Every slot receives zero, maximal Field, and a distinct value above u128.
#[test]
fn reader_writer_cursor_186() {
 for rotation in 0..3 {
  let mut original:[Field;186]=[0;186];
  for i in 0..186 {original[i]=if (i+rotation)%3==0 {0} else if (i+rotation)%3==1 {-1} else {i as Field+0x100000000000000000000000000000000000000000000000000};}
  let mut writer:Writer<188> =Writer::new();writer.write(17);FieldBuffer{words:original}.stream_serialize(&mut writer);writer.write(29);
  let mut reader=Reader::new(writer.finish());assert_eq(reader.read(),17);
  let recovered:FieldBuffer<186> =Deserialize::stream_deserialize(&mut reader);
  assert_eq(recovered.words,original);assert_eq(reader.read(),29);reader.finish();
  assert_eq(FieldBuffer::<186>::deserialize(original).serialize(),original);
 }
}

#[test(should_fail)]
fn insufficient_reader_186() {let mut reader=Reader::new([0;185]);let _p:FieldBuffer<186> =Deserialize::stream_deserialize(&mut reader);}

// Every slot receives zero, maximal Field, and a distinct value above u128.
#[test]
fn reader_writer_cursor_257() {
 for rotation in 0..3 {
  let mut original:[Field;257]=[0;257];
  for i in 0..257 {original[i]=if (i+rotation)%3==0 {0} else if (i+rotation)%3==1 {-1} else {i as Field+0x100000000000000000000000000000000000000000000000000};}
  let mut writer:Writer<259> =Writer::new();writer.write(17);FieldBuffer{words:original}.stream_serialize(&mut writer);writer.write(29);
  let mut reader=Reader::new(writer.finish());assert_eq(reader.read(),17);
  let recovered:FieldBuffer<257> =Deserialize::stream_deserialize(&mut reader);
  assert_eq(recovered.words,original);assert_eq(reader.read(),29);reader.finish();
  assert_eq(FieldBuffer::<257>::deserialize(original).serialize(),original);
 }
}

#[test(should_fail)]
fn insufficient_reader_257() {let mut reader=Reader::new([0;256]);let _p:FieldBuffer<257> =Deserialize::stream_deserialize(&mut reader);}

// Every slot receives zero, maximal Field, and a distinct value above u128.
#[test]
fn reader_writer_cursor_263() {
 for rotation in 0..3 {
  let mut original:[Field;263]=[0;263];
  for i in 0..263 {original[i]=if (i+rotation)%3==0 {0} else if (i+rotation)%3==1 {-1} else {i as Field+0x100000000000000000000000000000000000000000000000000};}
  let mut writer:Writer<265> =Writer::new();writer.write(17);FieldBuffer{words:original}.stream_serialize(&mut writer);writer.write(29);
  let mut reader=Reader::new(writer.finish());assert_eq(reader.read(),17);
  let recovered:FieldBuffer<263> =Deserialize::stream_deserialize(&mut reader);
  assert_eq(recovered.words,original);assert_eq(reader.read(),29);reader.finish();
  assert_eq(FieldBuffer::<263>::deserialize(original).serialize(),original);
 }
}

#[test(should_fail)]
fn insufficient_reader_263() {let mut reader=Reader::new([0;262]);let _p:FieldBuffer<263> =Deserialize::stream_deserialize(&mut reader);}

// Every slot receives zero, maximal Field, and a distinct value above u128.
#[test]
fn reader_writer_cursor_270() {
 for rotation in 0..3 {
  let mut original:[Field;270]=[0;270];
  for i in 0..270 {original[i]=if (i+rotation)%3==0 {0} else if (i+rotation)%3==1 {-1} else {i as Field+0x100000000000000000000000000000000000000000000000000};}
  let mut writer:Writer<272> =Writer::new();writer.write(17);FieldBuffer{words:original}.stream_serialize(&mut writer);writer.write(29);
  let mut reader=Reader::new(writer.finish());assert_eq(reader.read(),17);
  let recovered:FieldBuffer<270> =Deserialize::stream_deserialize(&mut reader);
  assert_eq(recovered.words,original);assert_eq(reader.read(),29);reader.finish();
  assert_eq(FieldBuffer::<270>::deserialize(original).serialize(),original);
 }
}

#[test(should_fail)]
fn insufficient_reader_270() {let mut reader=Reader::new([0;269]);let _p:FieldBuffer<270> =Deserialize::stream_deserialize(&mut reader);}

// Every slot receives zero, maximal Field, and a distinct value above u128.
#[test]
fn reader_writer_cursor_279() {
 for rotation in 0..3 {
  let mut original:[Field;279]=[0;279];
  for i in 0..279 {original[i]=if (i+rotation)%3==0 {0} else if (i+rotation)%3==1 {-1} else {i as Field+0x100000000000000000000000000000000000000000000000000};}
  let mut writer:Writer<281> =Writer::new();writer.write(17);FieldBuffer{words:original}.stream_serialize(&mut writer);writer.write(29);
  let mut reader=Reader::new(writer.finish());assert_eq(reader.read(),17);
  let recovered:FieldBuffer<279> =Deserialize::stream_deserialize(&mut reader);
  assert_eq(recovered.words,original);assert_eq(reader.read(),29);reader.finish();
  assert_eq(FieldBuffer::<279>::deserialize(original).serialize(),original);
 }
}

#[test(should_fail)]
fn insufficient_reader_279() {let mut reader=Reader::new([0;278]);let _p:FieldBuffer<279> =Deserialize::stream_deserialize(&mut reader);}

// Every slot receives zero, maximal Field, and a distinct value above u128.
#[test]
fn reader_writer_cursor_397() {
 for rotation in 0..3 {
  let mut original:[Field;397]=[0;397];
  for i in 0..397 {original[i]=if (i+rotation)%3==0 {0} else if (i+rotation)%3==1 {-1} else {i as Field+0x100000000000000000000000000000000000000000000000000};}
  let mut writer:Writer<399> =Writer::new();writer.write(17);FieldBuffer{words:original}.stream_serialize(&mut writer);writer.write(29);
  let mut reader=Reader::new(writer.finish());assert_eq(reader.read(),17);
  let recovered:FieldBuffer<397> =Deserialize::stream_deserialize(&mut reader);
  assert_eq(recovered.words,original);assert_eq(reader.read(),29);reader.finish();
  assert_eq(FieldBuffer::<397>::deserialize(original).serialize(),original);
 }
}

#[test(should_fail)]
fn insufficient_reader_397() {let mut reader=Reader::new([0;396]);let _p:FieldBuffer<397> =Deserialize::stream_deserialize(&mut reader);}

#[test]
fn constant_expression_width_resolves() {
    let mut reader = Reader::new([1; 56]);
    let value: FieldBuffer<40 + 16> = Deserialize::stream_deserialize(&mut reader);
    assert_eq(value.words, [1; 56]);
    reader.finish();
}
