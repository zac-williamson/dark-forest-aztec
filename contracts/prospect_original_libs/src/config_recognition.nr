// Only this immutable Config class is independent of the calling contract.
// Arbitrary configured Config implementations keep the original System caller.
use aztec::protocol::{address::AztecAddress, traits::ToField};

#[inline_never]
pub unconstrained fn supports_config(address: AztecAddress) -> bool {
    let current = aztec::oracle::get_contract_instance::get_contract_instance_current_class_id_avm(address);
    if current.is_some() {
        (super::config_class::CONFIG_CLASS != 0)
            & (current.unwrap().to_field() == super::config_class::CONFIG_CLASS)
    } else {
        false
    }
}
