// noirc_abi panics if given an error selector absent from this exact ABI.
// Only decode genuine returned data against a matching known selector.
export function decodeKnownRevert(error,abis,decode){
 const data=error?.revertData??[];if(data.length===0)return undefined;
 const selector=data[0].toBigInt().toString();
 const abi=abis.find(candidate=>candidate&&Object.hasOwn(candidate.errorTypes??{},selector));
 return abi?decode(data,abi):undefined;
}
