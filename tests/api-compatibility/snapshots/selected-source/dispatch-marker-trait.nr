
/// Opts a one-field-array transport into direct decoding as the sole public argument.
///
/// Implementors promise Serialize::N == Deserialize::N == the array width and that direct decoding equals
/// stream decoding on every complete serialized packet, with no additional stream checks or side effects.
/// This affects public dispatch only. Implementing it does not alter private serializers or either decoder.
pub trait SinglePublicArgumentDirectDeserialize {}

// The marker is resolved by actual trait identity, never by a type or field name.
comptime fn use_direct_single_argument(parameters: [(Quoted, Type)]) -> bool {
    if parameters.len() != 1 {
        false
    } else {
        let param_type = parameters[0].1;
        let marker = quote { crate::macros::dispatch::SinglePublicArgumentDirectDeserialize }.as_trait_constraint();
        if !param_type.implements(marker) {
            false
        } else {
            let (definition, generics) = param_type.as_data_type().expect(f"Direct public input must be a struct");
            let fields = definition.fields(generics);
            assert(fields.len() == 1, "Direct public input must have one field");
            let (element, width) = fields[0].1.as_array().expect(f"Direct public input must contain an array");
            assert(element.is_field(), "Direct public input elements must be Field");
            assert(width.as_constant().is_some(), "Direct public input width must be constant");
            true
        }
    }
}
