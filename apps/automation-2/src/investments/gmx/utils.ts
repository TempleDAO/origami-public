import { Logger } from "@mountainpath9/overlord";

import { OrigamiGmxRewardsAggregator } from "@/typechain";
import { getBlockTimestamp } from "@/common/utils";
import { TransactionReceipt, Provider } from "@ethersproject/abstract-provider";
import * as ethers from "ethers";
import { TypedEventFilter, TypedEvent } from '@/typechain/common';

export const encodeGlpHarvestParams = (contract: OrigamiGmxRewardsAggregator, params: OrigamiGmxRewardsAggregator.HarvestGlpParamsStruct): string => {
    return contract.interface._encodeParams(
        contract.interface.getEvent("CompoundOvGlp").inputs,
        [params]
    );
}

export const encodeGmxHarvestParams = (contract: OrigamiGmxRewardsAggregator, params: OrigamiGmxRewardsAggregator.HarvestGmxParamsStruct): string => {
    return contract.interface._encodeParams(
        contract.interface.getEvent("CompoundOvGmx").inputs,
        [params]
    );
}

export async function wasHarvestedRecently(
    logger: Logger,
    minHarvestIntervalSecs: number,
    rewardAggregator: OrigamiGmxRewardsAggregator
) {
    const currentBlockTime = await getBlockTimestamp(rewardAggregator.provider);
    const lastHarvestedAt = await rewardAggregator.lastHarvestedAt();
    const timeSinceLastHarvest = currentBlockTime.sub(lastHarvestedAt);

    // If the harvest ran recently, then nothing to do.
    if (timeSinceLastHarvest.lte(minHarvestIntervalSecs)) {
        logger.info(
            `Already harvested recently. currentBlockTime = [${currentBlockTime.toNumber()}] ` +
            `lastHarvestedAt [${lastHarvestedAt.toNumber()}] ` + 
            `MIN_HARVEST_INTERVAL_SECS [${minHarvestIntervalSecs}]. ` +
            `remaining [${minHarvestIntervalSecs - timeSinceLastHarvest.toNumber()}] secs`
        );
        return true;
    }
    return false;
}


/**
 * Generate markdown for standard tx receipt fields
 */
export async function txReceiptMarkdown(provider: Provider, submittedAt: Date, txReceipt: TransactionReceipt): Promise<string[]> {

    const effectiveGasPrice = ethers.BigNumber.from(txReceipt.effectiveGasPrice); // In wei
    const gasUsed = ethers.BigNumber.from(txReceipt.gasUsed); 
    const totalFee = effectiveGasPrice.mul(gasUsed).div(one_gwei);
    const block = await provider.getBlock(txReceipt.blockNumber);
    const minedAt = new Date(block.timestamp * 1000);

    return [
    `_gas price:_ ${formatBigNumber(effectiveGasPrice, 9, 4)}`,
    `_gas used:_  ${formatBigNumber(gasUsed, 0, 0)}`,
    `_total fee:_ ${formatBigNumber(totalFee, 9, 8)}`,
    `_submitted at:_ ${submittedAt.toISOString()}`,
    `_mined at:_ ${minedAt.toISOString()}`,
    `_seconds to mine:_ ${(minedAt.getTime() - submittedAt.getTime()) / 1000}`,
    ];
}

// String representation of a BigNumber, which is represented with a certain number of decimals
export function formatBigNumber(bn: ethers.BigNumber, dnDecimals: number, displayDecimals: number): string {
  return formatNumber(Number(ethers.utils.formatUnits(bn, dnDecimals)), displayDecimals);
};

// Format numbers with a certain number of decimal places, to locale
export function formatNumber(number: number, displayDecimals: number): string {
const stringified = number.toString();
const decimalPlaces = stringified.includes('.')
    ? stringified.split('.')[1].length
    : 0;

return decimalPlaces >= displayDecimals
    ? number.toLocaleString('en-US', {
        minimumFractionDigits: displayDecimals,
    })
    : number.toLocaleString('en-US');
};

export const one_gwei = ethers.BigNumber.from("1000000000");


/**
 * Apply a filter to an event, and, if it matches, return it's parsed
 * values 
 */
export function matchAndDecodeEvent<TArgsArray extends unknown[], TArgsObject>(
  contract: ethers.BaseContract,
  eventFilter: TypedEventFilter<TypedEvent<TArgsArray, TArgsObject>>, 
  event: ethers.Event): TArgsObject | undefined
{
  if(matchTopics(eventFilter.topics, event.topics)) {
    const args = contract.interface.parseLog(event).args;
    return args as TArgsObject;
  }
  return undefined;
}

/**
 * Finds the events that match the specified address and filter, and
 * returns these parsed and mapped to the appropriate type
 */
export function matchAndDecodeEvents<TArgsArray extends unknown[], TArgsObject>(
 events: ethers.Event[],
 contract: ethers.BaseContract,
 address: string | undefined,
 eventFilter: TypedEventFilter<TypedEvent<TArgsArray, TArgsObject>>
): TypedEvent<TArgsArray, TArgsObject>[] {
 return events
   .filter((ev) => !address || address === ev.address)
   .filter((ev) => matchTopics(eventFilter.topics, ev.topics))
   .map((ev) => {
     const args = contract.interface.parseLog(ev).args;
     const result: TypedEvent<TArgsArray, TArgsObject> = {
       ...ev,
       args: args as TArgsArray & TArgsObject,
     };
     return result;
   });
}


function matchTopics(
 filter: Array<string | Array<string>> | undefined,
 value: Array<string>
): boolean {
 // Implement the logic for topic filtering as described here:
 // https://docs.ethers.io/v5/concepts/events/#events--filters
 if (!filter) {
   return false;
 }
 for (let i = 0; i < filter.length; i++) {
   const f = filter[i];
   const v = value[i];
   if (typeof f == 'string') {
     if (f !== v) {
       return false;
     }
   } else {
     if (f.indexOf(v) === -1) {
       return false;
     }
   }
 }
 return true;
}

export function first<T>(values: T[]): T | undefined {
 return values.length >= 1 ? values[0] : undefined;
}