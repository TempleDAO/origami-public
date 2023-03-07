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

export async function handler(event: AutotaskEvent): Promise<AutotaskResult> {
    const connection = await autotaskConnect(event, COMMON_CONFIG);
    const result = await harvestGmxRewards(connection, COMMON_CONFIG, CONFIG);
    if (isFailure(result)) {
        console.log(result);
        throw new Error(TRANSACTION_NAME);
    }
    return result;
}
