import { AutotaskConnection } from "@/connect";
import { getBlockTimestamp } from "@/ethers";
import { OrigamiGmxRewardsAggregator } from "@/typechain";
import { utils } from "ethers";

const investQuoteTypes = 'tuple(address fromToken, uint256 fromTokenAmount, uint256 maxSlippageBps, ' +
    'uint256 deadline, uint256 expectedInvestmentAmount, uint256 minInvestmentAmount, bytes underlyingInvestmentQuoteData)';
const exitQuoteTypes = 'tuple(uint256 investmentTokenAmount, address toToken, uint256 maxSlippageBps, ' + 
    'uint256 deadline, uint256 expectedToTokenAmount, uint256 minToTokenAmount, bytes underlyingInvestmentQuoteData)';

export const encodeGlpHarvestParams = (params: OrigamiGmxRewardsAggregator.HarvestGlpParamsStruct): string => {
    const types = `tuple(${exitQuoteTypes} oGmxExitQuoteData, bytes gmxToNativeSwapData, ` +
        `${investQuoteTypes} oGlpInvestQuoteData, uint256 addToReserveAmountPct)`;
    return utils.defaultAbiCoder.encode(
        [types], 
        [params],
    );
}

export const encodeGmxHarvestParams = (params: OrigamiGmxRewardsAggregator.HarvestGmxParamsStruct): string => {
    const types = `tuple(bytes nativeToGmxSwapData, ${investQuoteTypes} oGmxInvestQuoteData, uint256 addToReserveAmountPct)`; 
    return utils.defaultAbiCoder.encode(
        [types], 
        [params],
    );
}

export async function wasHarvestedRecently(
    connection: AutotaskConnection, 
    minHarvestIntervalSecs: number,
    rewardAggregator: OrigamiGmxRewardsAggregator
) {
    const currentBlockTime = await getBlockTimestamp(connection);
    const lastHarvestedAt = await rewardAggregator.lastHarvestedAt();
    const timeSinceLastHarvest = currentBlockTime.sub(lastHarvestedAt);

    // If the harvest ran recently, then nothing to do.
    if (timeSinceLastHarvest.lte(minHarvestIntervalSecs)) {
        console.log(
            `Already harvested recently. currentBlockTime = [${currentBlockTime.toNumber()}] ` +
            `lastHarvestedAt [${lastHarvestedAt.toNumber()}] ` + 
            `MIN_HARVEST_INTERVAL_SECS [${minHarvestIntervalSecs}]. ` +
            `remaining [${minHarvestIntervalSecs - timeSinceLastHarvest.toNumber()}] secs`
        );
        return true;
    }
    return false;
}
