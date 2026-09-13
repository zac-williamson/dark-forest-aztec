// The caller builds calldata, including its selector, exactly once. This is the
// pinned PublicContext::call_public_function protocol with its redundant
// [selector].concat(args) allocation removed. Never use this in a private circuit.
use aztec::oracle::avm;
use aztec::protocol::{address::AztecAddress,constants::MAX_U32_VALUE};

#[inline_never]
pub unconstrained fn call<let N:u32>(address:AztecAddress, calldata:[Field;N])->[Field] {
    avm::call(MAX_U32_VALUE,MAX_U32_VALUE,address,calldata);
    let success=avm::success_copy();
    let result=avm::returndata_copy(0,avm::returndata_size());
    if !success { avm::revert(result); }
    result
}
