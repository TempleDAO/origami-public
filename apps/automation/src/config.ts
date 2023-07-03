

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
  WALLET_NAME: 'origami_automation_testnet',
}

const HARVEST_GMX_CONFIG : HarvestGmxConfig = {
  ...COMMON_CONFIG,
  GMX_ADDRESS: "0x79264843745dD81127B42Cffe30584A11a08C8F5",
  OGMX_ADDRESS: "0x79Dd3E25E0ED4A8C375AEAE4813baAA145599e61",
  GMX_REWARD_AGGREGATOR_ADDRESS: "0x647Ea2305C51831f5e42A072d0f1757cdd7fAE26",
  ZERO_EX_PROXY_ADDRESS: "0x7B174Bb59b6691fd3b9dfd5147E29a21972bd2E7",

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
  GMX_ADDRESS: "0x79264843745dD81127B42Cffe30584A11a08C8F5",
  OGMX_ADDRESS: "0x79Dd3E25E0ED4A8C375AEAE4813baAA145599e61",
  OGLP_ADDRESS: "0xea5043b2C7cEA4720B9Ec622E96FD79C051B1Ded",
  GLP_REWARD_AGGREGATOR_ADDRESS: "0x32E5b971618f6DC55263Bbcc1593949697B8481b",
  ZERO_EX_PROXY_ADDRESS: "0x7B174Bb59b6691fd3b9dfd5147E29a21972bd2E7",

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
  GLP_MANAGER: "0xf589Ee06C0967Fe36bbF7E9B8DA45B6954Df2AFf",
  MIN_TRANSFER_INTERVAL_SECS: 60*60, // 1 hour
};

const ALERT_PAUSED_STATUS_CONFIG: AlertPausedStatusConfig = {
  CHAIN: MUMBAI,
  GLP_MANAGER: "0xf589Ee06C0967Fe36bbF7E9B8DA45B6954Df2AFf",
  GMX_MANAGER: "0x3b81Fcc218c0b29F28c72c053cBe4f286A7dcf67",
};

export const DISCORD_WEBHOOK_URL_KEY = "origami_discord_webhook_url";
