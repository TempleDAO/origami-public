import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
  addrs.VAULTS.OPAL_PT_SUSDE_B.TOKEN.address = '0x5bCC3154698bBC205ABF09351A52DD2d1A39F608';
  addrs.VAULTS.OPAL_PT_SUSDE_B.MANAGER.address = '0x70c74940097e7c1946263a0D471Bf47AF97a5C5A';
  addrs.VAULTS.OPAL_PT_SUSDE_B.ADAPTER_INSTANCES["AAVE_V3.1: [sUSDe]/[USDT]"] = '0x564aC96B2B6bbFc12B566fc4Bf84Ee6AeFDa09cd';
  addrs.VAULTS.OPAL_PT_SUSDE_B.ADAPTER_INSTANCES["AAVE_V3.1: [PT-sUSDE-7MAY2026]/[USDT]"] = '0xD01ed156a8943959CC33c8C17B66901693606AE4';
  return addrs;
}
