import { ContractAddresses } from "../../contract-addresses/types";

export function applyOverrides(addrs: ContractAddresses): ContractAddresses {
  addrs.ORACLES.USD0pp_USDC_FLOOR_PRICE = '0x8C08821f5f94b519c853486eB131667AA528A460';
  addrs.ORACLES.USD0pp_USDC_MARKET_PRICE = '0xdcaa80371BDF9ff638851713f145Df074428Db19';
  addrs.ORACLES.USD0pp_MORPHO_TO_MARKET_CONVERSION = '0xcf23CE2ffa1DDd9Cc2b445aE6778c4DBD605a1A0';
  addrs.LOV_USD0pp_A.MORPHO_BORROW_LEND = '0xcf23CE2ffa1DDd9Cc2b445aE6778c4DBD605a1A0';
  addrs.LOV_USD0pp_A.MANAGER = '0x427EE58a6c574032085AEB90Dd05dEea6F054930';
  return addrs;
}
