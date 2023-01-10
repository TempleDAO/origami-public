import { AnswerUpdated } from '../../generated/HourlyScheduler/OffchainAggregator'

import { updateInvestmentShares } from '../entities/investmentShare'
import { getMetric, updateMetric } from '../entities/metric'
import { updateRewardTokenPrices } from '../entities/rewardToken'


export function onAnswerUpdated(event: AnswerUpdated): void {
    // Update reward token prices
    updateRewardTokenPrices(event.block.timestamp)

    // Update investments
    updateInvestmentShares(event.block.timestamp)

    // Update metrics
    const metric = getMetric()
    updateMetric(metric, event.block.timestamp)
}
