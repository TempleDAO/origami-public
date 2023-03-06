import { AutotaskEvent } from 'defender-autotask-utils';
import { CommonConfig } from '@/config';
import { AutotaskResult, isFailure } from '@/autotask-result';
import { autotaskConnect } from '@/connect';
import { TRANSACTION_NAME, TransferStakedGlpConfig, transferStakedGlp } from './transfer-staked-glp';

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

const CONFIG: TransferStakedGlpConfig = {
    GLP_MANAGER: '0xD1b9E7C18551B44A7E54943C8eF187Fe8bd51bF3',
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
