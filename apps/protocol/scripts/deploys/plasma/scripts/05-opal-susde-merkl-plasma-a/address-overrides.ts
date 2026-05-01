import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
  addrs.VAULTS.OPAL_SUSDE_MERKL_PLASMA_A.OVERLORD_WALLET = addrs.CORE.MULTISIG;
  addrs.VAULTS.OPAL_SUSDE_MERKL_PLASMA_A.TOKEN.address = '0xf32FD934887214ca6E769563456d842fE90Ffd62';
  addrs.VAULTS.OPAL_SUSDE_MERKL_PLASMA_A.MANAGER.address = '0x5d1E1EeF7c2F0BF9978cCf25B711E23448d5EcC4';
  addrs.VAULTS.OPAL_SUSDE_MERKL_PLASMA_A.ADAPTER_INSTANCES["AAVE_V3.1: [sUSDe, USDe]/[USDT0]"] = '0xA30CF1128466Cd0f4661E507a6a3909E979FA914';
  return addrs;
}
