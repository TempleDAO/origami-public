import { EventConditionSummary, TransactionReceipt, formatBigNumber, one_gwei } from '@/utils';
import {
    BlockTriggerEvent,
    SentinelConditionResponse,
    SentinelConditionMatch,
    SentinelTriggerEvent,
} from 'defender-autotask-utils';
import { BigNumber } from 'ethers';
import { CommonConfig } from '@/config';
import { AutotaskConnection } from '@/connect';
import { popStore } from '@/utils';
import { getLastTxTimeKey } from '@/ethers';

export async function getAlertResponse(
    connection: AutotaskConnection,
    COMMON_CONFIG: CommonConfig,
    events: SentinelTriggerEvent[],
): Promise<SentinelConditionResponse> {
    // Pop the latest transaction time if it exists
    const lastTxTimeStr = await popStore(
        connection.store, 
        getLastTxTimeKey(COMMON_CONFIG.NETWORK, COMMON_CONFIG.TRANSACTION_NAME)
    );
    const lastTxTimeSecs = !lastTxTimeStr ? 0 : parseInt(lastTxTimeStr) / 1000;

    const matches: SentinelConditionMatch[] = [];
    for (const event of events) {
        const blockEvent = event as BlockTriggerEvent;
        const transactionReceipt = blockEvent.transaction as TransactionReceipt;
        
        const effectiveGasPrice = BigNumber.from(transactionReceipt.effectiveGasPrice); // In wei
        const gasUsed = BigNumber.from(transactionReceipt.gasUsed); 
        const totalFee = effectiveGasPrice.mul(gasUsed).div(one_gwei);

        let title: string = " ";
        let receiver: string = " ";
        let amount: string = " ";
        let description: string = " ";

        for (const reason of blockEvent.matchReasons) {
            const eventReason = reason as EventConditionSummary;
            console.log("event signature:", eventReason.signature);
            console.log("event params:", eventReason.params);

            if (eventReason.signature.startsWith("SetGlpInvestmentsPaused")) {
                const paused = eventReason.params.pause as boolean;
                title = `GLP Investments ${paused ? "Paused" : "Unpaused"}`;
                description = `SetGlpInvestmentsPaused(pause=${paused})`;
                break;
            } else {
                title = "Transferred Staked GLP";
                receiver = eventReason.params.receiver as string;
                amount = formatBigNumber(eventReason.params.amount as BigNumber, 18, 4);
                description = `StakedGlpTransferred(receiver=${receiver}, amount=${amount})`;
            }
        }

        const match: SentinelConditionMatch = {
            hash: event.hash,
            metadata: {
                gasPrice: formatBigNumber(effectiveGasPrice, 9, 4), // Display in GWEI
                gasUsed: formatBigNumber(gasUsed, 0, 0),
                totalFee: formatBigNumber(totalFee, 9, 8), // Display in ETH to 8 dp
                minedUnixTimestamp: blockEvent.timestamp.toString(),

                title: title,
                description: description,

                submittedUnixTimestamp: lastTxTimeSecs > 0 ? lastTxTimeSecs.toString() : "UNKNOWN",
                secondsToMine: lastTxTimeSecs > 0 ? (Math.round(1000 * (blockEvent.timestamp - lastTxTimeSecs)) / 1000).toString() : "UNKNOWN",

                source: blockEvent.matchedAddresses[0],
                receiver: receiver,
                amount: amount,
            }
        };
        console.log("Match:", match);
        matches.push(match);
    }

    return {
        matches: matches,
    };
}