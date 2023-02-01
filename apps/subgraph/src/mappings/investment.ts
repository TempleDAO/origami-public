import { Invested, Exited } from '../../generated/GmxInvestment/OrigamiInvestment'
import { getOrCreateInvestment, updateInvestment } from '../entities/investment'

import { getPricedToken } from '../entities/pricedToken'
import { getOrCreateToken } from '../entities/token'
import { toDecimal } from '../utils/decimals'


export function onInvested(event: Invested): void {
    const timestamp = event.block.timestamp

    const investment = getOrCreateInvestment(event.address, timestamp)

    const toToken = getPricedToken(investment.id, timestamp)
    const toTokenAmount = toDecimal(event.params.investmentAmount, toToken.decimals)

    investment.tvl = investment.tvl.plus(toTokenAmount)
    investment.tvlUSD = investment.tvl.times(toToken.price)
    investment.volume = investment.volume.plus(toTokenAmount)
    investment.volumeUSD = investment.volumeUSD.plus(toTokenAmount.times(toToken.price))
    updateInvestment(investment, timestamp)
}

export function onExited(event: Exited): void {
    const timestamp = event.block.timestamp

    const investment = getOrCreateInvestment(event.address, timestamp)

    const fromToken = getPricedToken(investment.id, timestamp)
    const fromTokenAmount = toDecimal(event.params.investmentAmount, fromToken.decimals)

    investment.tvl = investment.tvl.minus(fromTokenAmount)
    investment.tvlUSD = investment.tvl.times(fromToken.price)
    investment.volume = investment.volume.plus(fromTokenAmount)
    investment.volumeUSD = investment.volumeUSD.plus(fromTokenAmount.times(fromToken.price))
    updateInvestment(investment, timestamp)
}
