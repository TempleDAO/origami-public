import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
  addrs.CORE.TOKEN_PRICES.V3 = '0x43A3cb2cf5eA2331174c166214302f0C3BbA6A85';
  addrs.FLASHLOAN_PROVIDERS.AAVE_V3_MAINNET_HAS_FEE = '0x6c383Ef7C9Bf496b5c847530eb9c49a3ED6E4C56';
  addrs.LOV_WSTETH_B = {
    OVERLORD_WALLET: addrs.CORE.MULTISIG,
    SPARK_BORROW_LEND: '0x2aA12f98795E7A65072950AfbA9d1E023D398241',
    TOKEN: '0xAAF0F531b7947e8492f21862471d61d5305f7538',
    MANAGER: '0x81f4f47aa3bBd154171C877b4d70F6C9EeCAb216',
  };
  
  return addrs;
}
