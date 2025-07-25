import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
  addrs.VAULTS.OAC_USDS_IMF_MOR = {
    OVERLORD_WALLET: addrs.CORE.MULTISIG,
    COW_SWAPPER: '0x2e590d65Dd357a7565EfB5ffB329F8465F18c494',
    TOKEN: '0x8fF6E100EB12Ec17Bf1D0ac53431715ebB845E5D',
    MANAGER: '0x1848875EBafcB36662A674b58b2474874BD823d2',
  };
  
  return addrs;
}
