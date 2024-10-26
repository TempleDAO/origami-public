import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
  // Not required, as this test is using already deployed mainnet contracts
  // addrs.LOV_SDAI_A.MORPHO_BORROW_LEND = '0xd2983525E903Ef198d5dD0777712EB66680463bc';
  return addrs;
}
