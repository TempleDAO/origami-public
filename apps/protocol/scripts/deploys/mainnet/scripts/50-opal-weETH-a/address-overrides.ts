import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
  addrs.VAULTS.OPAL_WEETH_A_DEPRECATED.OVERLORD_WALLET = addrs.CORE.MULTISIG;
  addrs.VAULTS.OPAL_WEETH_A_DEPRECATED.TOKEN.address = '0x3CFDf9646dBC385E47DC07869626Ea36BE7bA3a2';
  addrs.VAULTS.OPAL_WEETH_A_DEPRECATED.MANAGER.address = '0x9A213F53334279C128C37DA962E5472eCD90554f';
  addrs.VAULTS.OPAL_WEETH_A_DEPRECATED.ADAPTER_INSTANCES["AAVE_V3.1: [weETH]/[WETH]"] = '0x9c8b333bA797b52637Ad845a7CC2F620923C4155';
  return addrs;
}
