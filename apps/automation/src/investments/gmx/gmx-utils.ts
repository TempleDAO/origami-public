import { AutotaskConnection } from "@/connect";
import { getBlockTimestamp } from "@/ethers";
import { OrigamiGmxRewardsAggregator } from "@/typechain";

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
