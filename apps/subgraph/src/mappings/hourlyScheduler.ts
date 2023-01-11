import { AnswerUpdated } from '../../generated/HourlyScheduler/OffchainAggregator'

import { updateInvestmentVaults } from '../entities/investmentVault'
import { getMetric, updateMetric } from '../entities/metric'
import { updateRewardTokenPrices } from '../entities/rewardToken'


export function onAnswerUpdated(event: AnswerUpdated): void {
    // Update reward token prices
    updateRewardTokenPrices(event.block.timestamp)

    // Update investments
    updateInvestmentVaults(event.block.timestamp)

    // Update metrics
    const metric = getMetric()
    updateMetric(metric, event.block.timestamp)
}
