import { AutotaskEvent } from 'defender-autotask-utils';
import { CommonConfig } from '@/config';
import { AutotaskResult, isFailure } from '@/autotask-result';
import { autotaskConnect } from '@/connect';
import { TRANSACTION_NAME, HarvestGmxConfig, harvestGmxRewards } from './gmx-compounder';

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

const CONFIG: HarvestGmxConfig = {
    GMX_ADDRESS: "0x3be80dD1aC2533d91330C82aae89Fe4D2E540146",
    OGMX_ADDRESS: "0x58893971408b4ce2c3cc326A8697Eec4471a5615",
    GMX_REWARD_AGGREGATOR_ADDRESS: "0xD642e164563Bd4ba8c1bB433CAfC8d4916A2A390",
    ZERO_EX_PROXY_ADDRESS: "0xb0Ab9A067EFBbAA8aa9c259131C07AfB8012B58B",

    // The min frequency that the harvester can actually run
    MIN_HARVEST_INTERVAL_SECS: 15*60, // 15 mins

    // max price impact when swapping $WETH -> $GMX via 0x
    WETH_TO_GMX_PRICE_IMPACT_BPS: 50, // 0.5%

    // max slippage (not including price impact) when swapping $WETH -> $GMX via 0x
    WETH_TO_GMX_SLIPPAGE_BPS: 100, // 1%

    // What percentage of the total oGMX on hand does the aggregator actually add as reserves into ovGMX
    DAILY_ADD_TO_RESERVE_BPS: 1_000, // 10%
};

export async function handler(event: AutotaskEvent): Promise<AutotaskResult> {
    const connection = await autotaskConnect(event, COMMON_CONFIG);
    const result = await harvestGmxRewards(connection, COMMON_CONFIG, CONFIG);
    if (isFailure(result)) {
        console.log(result);
        throw new Error(TRANSACTION_NAME);
    }
    return result;
}
