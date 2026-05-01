import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
  addrs.ORACLES.PT_SUSDE_18JUN2026_USDE = '0x5d1E1EeF7c2F0BF9978cCf25B711E23448d5EcC4';
  addrs.VAULTS.OPAL_PT_SUSDE_PLASMA_A.ADAPTER_INSTANCES["AAVE_V3.1: [PT-sUSDE-18JUN2026]/[USDT0]"] = '0x5597a61428097252F09731C6Bf2358BA030f549D';
  return addrs;
}
