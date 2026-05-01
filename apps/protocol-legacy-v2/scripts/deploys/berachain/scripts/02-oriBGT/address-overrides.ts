import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
  addrs.CORE.TOKEN_PRICES.V4 = '0x9A9f2CCfdE556A7E9Ff0848998Aa4a0CFD8863AE';

  addrs.VAULTS.ORIBGT = {
    OVERLORD_WALLET: addrs.CORE.MULTISIG,
    TOKEN: "0x9A9f2CCfdE556A7E9Ff0848998Aa4a0CFD8863AE",
    SWAPPER: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
    MANAGER: "0x3Aa5ebB10DC797CAC828524e59A333d0A371443c",
  };

  return addrs;
}
