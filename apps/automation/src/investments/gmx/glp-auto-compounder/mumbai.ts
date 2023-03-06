import { AutotaskEvent } from 'defender-autotask-utils';
import { CommonConfig } from '@/config';
import { AutotaskResult, isFailure } from '@/autotask-result';
import { autotaskConnect } from '@/connect';
import { TRANSACTION_NAME, HarvestGlpConfig, harvestGlpRewards } from './glp-compounder';

const COMMON_CONFIG: CommonConfig = {
    NETWORK: 'mumbai',
    TRANSACTION_NAME: TRANSACTION_NAME,
    TRANSACTION_VALID_FOR_SECS: 300, // 5 mins
    TRANSACTION_SPEED: 'fast',
    TRANSACTION_IS_PRIVATE: false,
    TRANSACTION_SLIPPAGE_BPS: 0, // N/A
    WAIT_SLEEP_SECS: 5,
    TOTAL_TIMEOUT_SECS: 290, // 4min 50sec
};

const CONFIG: HarvestGlpConfig = {
    GMX_ADDRESS: "0x3be80dD1aC2533d91330C82aae89Fe4D2E540146",
    OGMX_ADDRESS: "0x58893971408b4ce2c3cc326A8697Eec4471a5615",
    OGLP_ADDRESS: "0x6444Fa91C18C96eBeDaB94Ef04F735B453aabcad",
    GLP_REWARD_AGGREGATOR_ADDRESS: "0xB940160Ae4eD349D0c67fC1750D5d909d3bb2c0c",
    ZERO_EX_PROXY_ADDRESS: "0xb0Ab9A067EFBbAA8aa9c259131C07AfB8012B58B",

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
    DAILY_ADD_TO_RESERVE_BPS: 1_000, // 10%
};

export async function handler(event: AutotaskEvent): Promise<AutotaskResult> {
    const connection = await autotaskConnect(event, COMMON_CONFIG);
    const result = await harvestGlpRewards(connection, COMMON_CONFIG, CONFIG);
    if (isFailure(result)) {
        console.log(result);
        throw new Error(TRANSACTION_NAME);
    }
    return result;
}
