import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
  addrs.VAULTS.OPAL_WEETH_A.TOKEN.address = '0x5bCC3154698bBC205ABF09351A52DD2d1A39F608';
  addrs.VAULTS.OPAL_WEETH_A.MANAGER.address = '0x70c74940097e7c1946263a0D471Bf47AF97a5C5A';
  addrs.VAULTS.OPAL_WEETH_A.ADAPTER_INSTANCES["AAVE_V3.1: [weETH]/[WETH]"] = '0x9c8b333bA797b52637Ad845a7CC2F620923C4155';
  return addrs;
}
