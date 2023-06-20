

import { HarvestGmxConfig } from "./investments/gmx/gmx-auto-compounder";
import { HarvestGlpConfig } from "./investments/gmx/glp-auto-compounder";
import { TransferStakedGlpConfig } from "./investments/gmx/transfer-staked-glp";
import { AlertPausedStatusConfig } from "./investments/gmx/alert-paused-status";
import { MUMBAI } from "./chains";

export interface Config {
  harvestGmx: HarvestGmxConfig,
  harvestGlp: HarvestGlpConfig,
  transferStakedGlp: TransferStakedGlpConfig,
  alertPausedStatus: AlertPausedStatusConfig,
}



export function getConfig() : Config {
  return {
    harvestGmx: HARVEST_GMX_CONFIG,
    harvestGlp: HARVEST_GLP_CONFIG,
    transferStakedGlp: TRANSFER_STAKED_GLP_CONFIG,
    alertPausedStatus: ALERT_PAUSED_STATUS_CONFIG,
  }
}

const COMMON_CONFIG = {
  CHAIN: MUMBAI,
  WALLET_NAME: 'origami_automation',
}

const HARVEST_GMX_CONFIG : HarvestGmxConfig = {
  ...COMMON_CONFIG,
  GMX_ADDRESS: "0xd4E25f2BA9FaDd6FFCc094116264C49f4C62B948",
  OGMX_ADDRESS: "0xA30B312fDd4D5b9Ea11208239de7943E59cf2e45",
  GMX_REWARD_AGGREGATOR_ADDRESS: "0x48165A1Ba49584eDF7038497d6D65A4756e43e55",
  ZERO_EX_PROXY_ADDRESS: "0x5923eD1131Bf82C7e89716fd797687fE9174a86b",

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
  GMX_ADDRESS: "0xd4E25f2BA9FaDd6FFCc094116264C49f4C62B948",
  OGMX_ADDRESS: "0xA30B312fDd4D5b9Ea11208239de7943E59cf2e45",
  OGLP_ADDRESS: "0xacfee3A66337067F75151637D0DefEd09E880914",
  GLP_REWARD_AGGREGATOR_ADDRESS: "0x4276a5D4AAB00702Ac4b28ff8A0228e0e76E46d6",
  ZERO_EX_PROXY_ADDRESS: "0x5923eD1131Bf82C7e89716fd797687fE9174a86b",

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
  GLP_MANAGER: "0x1d8000368122bD16a1251B9b0fe2367C1cd247d1",
  MIN_TRANSFER_INTERVAL_SECS: 60*60, // 1 hour
};

const ALERT_PAUSED_STATUS_CONFIG: AlertPausedStatusConfig = {
  CHAIN: MUMBAI,
  GLP_MANAGER: "0x1d8000368122bD16a1251B9b0fe2367C1cd247d1",
  GMX_MANAGER: "0x35696286529EBB88c5c53ADe87a4BdCF30b3c8d9",
};

export const DISCORD_WEBHOOK_URL_KEY = "origami_discord_webhook_url";