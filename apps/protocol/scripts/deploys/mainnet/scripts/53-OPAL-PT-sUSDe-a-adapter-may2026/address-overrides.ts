import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
  addrs.ORACLES.PT_SUSDE_7MAY2026_USDE = '0x2a75a9AfF7d909002fc458b765CB92F47350464B';
  addrs.VAULTS.OPAL_PT_SUSDE_A_DEPRECATED.ADAPTER_INSTANCES["AAVE_V3.1: [PT-sUSDE-7MAY2026]/[USDC]"] = '0x564aC96B2B6bbFc12B566fc4Bf84Ee6AeFDa09cd';
  return addrs;
}
