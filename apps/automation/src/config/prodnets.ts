


import { HarvestGmxConfig } from "../investments/gmx/gmx-auto-compounder";
import { HarvestGlpConfig } from "../investments/gmx/glp-auto-compounder";
import { TransferStakedGlpConfig } from "../investments/gmx/transfer-staked-glp";
import { AlertPausedStatusConfig } from "../investments/gmx/alert-paused-status";
import { ARBITRUM } from "../chains";

export interface Config {
  harvestGmx: HarvestGmxConfig,
  harvestGlp: HarvestGlpConfig,
  transferStakedGlp: TransferStakedGlpConfig,
  alertPausedStatus: AlertPausedStatusConfig,
}

const COMMON_CONFIG = {
  CHAIN: ARBITRUM,
  WALLET_NAME: 'origami_automation',
}

const HARVEST_GMX_CONFIG : HarvestGmxConfig = {
  ...COMMON_CONFIG,
  GMX_ADDRESS: "0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a",
  OGMX_ADDRESS: "0x784f75C39bD7D3EBC377e64991e99178341c831D",
  GMX_REWARD_AGGREGATOR_ADDRESS: "0xcB6D80Ac3209626D5BC6cB9291eF6c4c321c82bA",
  ZERO_EX_PROXY_ADDRESS: "0xDef1C0ded9bec7F1a1670819833240f027b25EfF",

  // The min frequency that the harvester can actually run
  MIN_HARVEST_INTERVAL_SECS: 15*60, // 15 mins

  // max price impact when swapping $WETH -> $GMX via 0x
  WETH_TO_GMX_PRICE_IMPACT_BPS: 50, // 0.5%

  // max slippage (not including price impact) when swapping $WETH -> $GMX via 0x
  WETH_TO_GMX_SLIPPAGE_BPS: 100, // 1%

  // What percentage of the total oGMX on hand does the aggregator actually add as reserves into ovGMX
  DAILY_ADD_TO_RESERVE_BPS: 10_000, // 100%
};

const HARVEST_GLP_CONFIG: HarvestGlpConfig = {
  ...COMMON_CONFIG,
  GMX_ADDRESS: "0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a",
  OGMX_ADDRESS: "0x784f75C39bD7D3EBC377e64991e99178341c831D",
  OGLP_ADDRESS: "0xb48aC9c5585e5F3c88c63CF9bcbAEdC921F76Df2",
  GLP_REWARD_AGGREGATOR_ADDRESS: "0x643d715a0697c56629A25EC33C9BF5990D08317F",
  ZERO_EX_PROXY_ADDRESS: "0xDef1C0ded9bec7F1a1670819833240f027b25EfF",

  // The min frequency that the harvester can actually run
  MIN_HARVEST_INTERVAL_SECS: 15*60, // 15 mins

  // max price impact when swapping $GMX -> $WETH via 0x
  // likely routed through either:
  // https://info.uniswap.org/#/arbitrum/pools/0x1aeedd3727a6431b8f070c0afaa81cc74f273882
  // https://info.uniswap.org/#/arbitrum/pools/0x80a9ae39310abf666a87c743d6ebbd0e8c42158e
  GMX_TO_WETH_PRICE_IMPACT_BPS: 50, // 0.5%

  // max slippage (not including price impact) when swapping $GMX -> $WETH via 0x
  GMX_TO_WETH_SLIPPAGE_BPS: 100, // 1%

  // max slippage when investing in $oGLP with $WETH
  WETH_TO_OGLP_INVESTMENT_SLIPPAGE_BPS: 100, // 1%

  // What percentage of the total oGLP on hand does the aggregator actually add as reserves into ovGLP
  DAILY_ADD_TO_RESERVE_BPS: 10_000,// 100%
};


const TRANSFER_STAKED_GLP_CONFIG: TransferStakedGlpConfig = {
  ...COMMON_CONFIG,
  GLP_MANAGER: "0x58833508c3d057FE8901A7A2D89CeCcb3449ac24",
  MIN_TRANSFER_INTERVAL_SECS: 60*60, // 1 hour
};

const ALERT_PAUSED_STATUS_CONFIG: AlertPausedStatusConfig = {
  CHAIN: ARBITRUM,
  GLP_MANAGER: "0x58833508c3d057FE8901A7A2D89CeCcb3449ac24",
  GMX_MANAGER: "0xc0F9dd64D247f4Cb50C07632353896918bE79562",
};

export const CONFIG = {
  harvestGmx: HARVEST_GMX_CONFIG,
  harvestGlp: HARVEST_GLP_CONFIG,
  transferStakedGlp: TRANSFER_STAKED_GLP_CONFIG,
  alertPausedStatus: ALERT_PAUSED_STATUS_CONFIG,
}
