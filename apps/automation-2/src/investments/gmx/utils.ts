import { Logger } from "@mountainpath9/overlord";

import { OrigamiGmxRewardsAggregator } from "@/typechain";
import { getBlockTimestamp } from "@/common/utils";

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
