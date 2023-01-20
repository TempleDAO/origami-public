import { AutotaskEvent } from 'defender-autotask-utils';
import { CommonConfig } from '@/config';
import { AutotaskResult, isFailure } from '@/autotask-result';
import { autotaskConnect } from '@/connect';
import { TRANSACTION_NAME, TransferStakedGlpConfig, transferStakedGlp } from './transfer-staked-glp';

const COMMON_CONFIG: CommonConfig = {
    NETWORK: 'arbitrum',
    TRANSACTION_NAME: TRANSACTION_NAME,
    TRANSACTION_VALID_FOR_SECS: 900, // 15 mins
    TRANSACTION_SPEED: 'fast',
    TRANSACTION_IS_PRIVATE: false,
    TRANSACTION_SLIPPAGE_BPS: 0, // N/A
    WAIT_SLEEP_SECS: 5,
    TOTAL_TIMEOUT_SECS: 290, // 4min 50sec
};

const CONFIG: TransferStakedGlpConfig = {
    GLP_MANAGER: '',
    MIN_TRANSFER_INTERVAL_SECS: 60*60, // 1 hour
};

export async function handler(event: AutotaskEvent): Promise<AutotaskResult> {
    const connection = await autotaskConnect(event, COMMON_CONFIG);
    const result = await transferStakedGlp(connection, COMMON_CONFIG, CONFIG);
    if (isFailure(result)) {
        console.log(result);
        throw new Error(TRANSACTION_NAME);
    }
    return result;
}
