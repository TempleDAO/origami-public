import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
  addrs.VAULTS.SUSDSpS = {
    OVERLORD_WALLET: addrs.CORE.MULTISIG,
    COW_SWAPPER: '0xf09e7Af8b380cD01BD0d009F83a6b668A47742ec',
    TOKEN: '0x492844c46CEf2d751433739fc3409B7A4a5ba9A7',
    MANAGER: '0x50cf1849e32E6A17bBFF6B1Aa8b1F7B479Ad6C12',
  };
  
  return addrs;
}
