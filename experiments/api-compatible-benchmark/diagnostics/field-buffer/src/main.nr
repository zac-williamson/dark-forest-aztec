use aztec::macros::aztec;
#[aztec]
pub contract BufferGasProbe {
 use aztec::macros::functions::external;
 use buffers::{UnrolledBuffer267,HybridBuffer,FieldBuffer267,FieldBuffer128,FieldBuffer384};
 #[external("public")]
 fn array267(words:[Field;267])->[Field;267] {words}
 #[external("public")]
 fn buffer267(words:FieldBuffer267)->FieldBuffer267 {words}
 #[external("public")]
 fn array128(words:[Field;128])->[Field;128] {words}
 #[external("public")]
 fn buffer128(words:FieldBuffer128)->FieldBuffer128 {words}
 #[external("public")]
 fn array384(words:[Field;384])->[Field;384] {words}
 #[external("public")]
 fn buffer384(words:FieldBuffer384)->FieldBuffer384 {words}
 #[external("public")]
 fn decode_array267(words:[Field;267])->Field {words[0]+words[266]}
 #[external("public")]
 fn decode_buffer267(words:FieldBuffer267)->Field {words.words[0]+words.words[266]}
 #[external("public")]
 fn hybrid267(words:HybridBuffer<267>)->HybridBuffer<267> {words}
 #[external("public")]
 fn decode_hybrid267(words:HybridBuffer<267>)->Field {words.words[0]+words.words[266]}
 #[external("public")]
 fn unrolled267(words:UnrolledBuffer267)->UnrolledBuffer267 {words}
 #[external("public")]
 fn decode_unrolled267(words:UnrolledBuffer267)->Field {words.words[0]+words.words[266]}
}
