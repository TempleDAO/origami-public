import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
  addrs.ORACLES.USD0pp_USD0 = '0x6c383Ef7C9Bf496b5c847530eb9c49a3ED6E4C56';
  addrs.ORACLES.USD0pp_USDC = '0xAAF0F531b7947e8492f21862471d61d5305f7538';
  addrs.ORACLES.USD0_USDC = '0x2aA12f98795E7A65072950AfbA9d1E023D398241';
  addrs.LOV_USD0pp_A = {
    OVERLORD_WALLET: addrs.CORE.MULTISIG,
    MORPHO_BORROW_LEND: '0x81f4f47aa3bBd154171C877b4d70F6C9EeCAb216',
    TOKEN: '0x2ce1F0e20C1f69E9d9AEA83b25F0cEB69e2AA2b5',
    MANAGER: '0xE5b6F5e695BA6E4aeD92B68c4CC8Df1160D69A81',
  };
  
  return addrs;
}
