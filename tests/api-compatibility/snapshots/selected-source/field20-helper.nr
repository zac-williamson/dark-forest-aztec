// Experimental public-dispatch-only specialization. Keep all other Deserialize paths unchanged.
comptime fn unpack_parameter(arg_name: Quoted, param_type: Type) -> Quoted {
    let is_field20 = if param_type.as_array().is_some() {
        let (element_type, array_len) = param_type.as_array().unwrap();
        if element_type.is_field() {
            if array_len.as_constant().is_some() {
                array_len.as_constant().unwrap() == 20
            } else {
                false
            }
        } else {
            false
        }
    } else {
        false
    };
    if is_field20 {
        quote {
            let $arg_name: $param_type = [
                reader.peek_offset(0),
                reader.peek_offset(1),
                reader.peek_offset(2),
                reader.peek_offset(3),
                reader.peek_offset(4),
                reader.peek_offset(5),
                reader.peek_offset(6),
                reader.peek_offset(7),
                reader.peek_offset(8),
                reader.peek_offset(9),
                reader.peek_offset(10),
                reader.peek_offset(11),
                reader.peek_offset(12),
                reader.peek_offset(13),
                reader.peek_offset(14),
                reader.peek_offset(15),
                reader.peek_offset(16),
                reader.peek_offset(17),
                reader.peek_offset(18),
                reader.peek_offset(19),
            ];
            reader.advance_offset(20);
        }
    } else {
        quote {
            let $arg_name: $param_type = aztec::protocol::traits::Deserialize::stream_deserialize(&mut reader);
        }
    }
}

