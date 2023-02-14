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
    GMX_ADDRESS: "0xcDF6d6bDD433781205c37968125d2e7Bf2d74C37",
    OGMX_ADDRESS: "0x56561230c92e9bDD97b33Cc6cA76F30b32F54a8A",
    OGLP_ADDRESS: "0xe8A3f2005fc81773D5CAA647722478bDc94E8296",
    GLP_REWARD_AGGREGATOR_ADDRESS: "0x9b36e525220194D2C4471A1c40310c04F4f438E1",
    ZERO_EX_PROXY_ADDRESS: "0x839629d10b6DA5A33480cF632D072bbC314D8b60",

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
