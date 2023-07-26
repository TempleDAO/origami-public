import { AnswerUpdated } from '../../generated/HourlyScheduler/OffchainAggregator'

import { updateInvestmentVaults } from '../entities/investmentVault'
import { getMetric, updateMetric } from '../entities/metric'
import { updatePricedTokenPrices } from '../entities/pricedToken'


export function onAnswerUpdated(event: AnswerUpdated): void {
    // Update priced token prices
    updatePricedTokenPrices(event.block.timestamp)

    // Update investments & metrics
    updateInvestmentVaults(event.block.timestamp)
}
