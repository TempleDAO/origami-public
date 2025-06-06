import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
  addrs.ORACLES.PT_USD0pp_MAR_2025_USD0pp = '0x1D87585dF4D48E52436e26521a3C5856E4553e3F';
  addrs.ORACLES.PT_USD0pp_MAR_2025_USDC_PEGGED = '0x810090f35DFA6B18b5EB59d298e2A2443a2811E2';

  addrs.LOV_PT_USD0pp_MAR_2025_A.OVERLORD_WALLET = addrs.CORE.MULTISIG;
  addrs.LOV_PT_USD0pp_MAR_2025_A.MORPHO_BORROW_LEND = '0x2B8F5e69C35c1Aff4CCc71458CA26c2F313c3ed3';
  addrs.LOV_PT_USD0pp_MAR_2025_A.TOKEN = '0x9A8Ec3B44ee760b629e204900c86d67414a67e8f';
  addrs.LOV_PT_USD0pp_MAR_2025_A.MANAGER = '0xA899118f4BCCb62F8c6A37887a4F450D8a4E92E0';
  return addrs;
}
