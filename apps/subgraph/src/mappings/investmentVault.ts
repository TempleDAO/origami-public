import { Invested, Exited, ReservesAdded, ReservesRemoved, TokenPricesSet, PerformanceFeeSet, InvestmentManagerSet } from '../../generated/GmxInvestmentVault/OrigamiInvestmentVault'
import { OrigamiInvestmentVault as InvestmentVaultContract } from '../../generated/GmxInvestment/OrigamiInvestmentVault'

import { createUserInvestment } from '../entities/userInvestment'
import { createUserExit } from '../entities/userExit'
import { getInvestmentVault, getOrCreateInvestmentVault } from '../entities/investmentVault'
import { toDecimal } from '../utils/decimals'
import { getOrCreatePricedToken } from '../entities/pricedToken'
import { BIG_DECIMAL_100 } from '../utils/constants'


export function onInvestmentManagerSet(event: InvestmentManagerSet): void {
    const investmentVaultContract = InvestmentVaultContract.bind(event.address)
    const reserveToken = investmentVaultContract.reserveToken()
    const tokenPrices = investmentVaultContract.tokenPrices()

    const invVault = getInvestmentVault(event.address)
    if (invVault === null) {
        // Initialize the reserve token
        getOrCreatePricedToken(reserveToken, tokenPrices, event.block.timestamp)
    } else {
        invVault.investmentManager = event.params._investmentManager
        invVault.save()
    }
}

export function onInvestedVault(event: Invested): void {
    createUserInvestment(event)
}

export function onExitedVault(event: Exited): void {
    createUserExit(event)
}

export function onReservesAdded(event: ReservesAdded): void {
    const invVault = getOrCreateInvestmentVault(event.address, event.block.timestamp)
    const amount = toDecimal(event.params.amount, 18)
    invVault.totalReserves = invVault.totalReserves.plus(amount)
    invVault.save()
}

export function onReservesRemoved(event: ReservesRemoved): void {
    const invVault = getOrCreateInvestmentVault(event.address, event.block.timestamp)
    const amount = toDecimal(event.params.amount, 18)
    invVault.totalReserves = invVault.totalReserves.minus(amount)
    invVault.save()
}

export function onTokenPricesSet(event: TokenPricesSet): void {
    const invVault = getOrCreateInvestmentVault(event.address, event.block.timestamp)
    invVault.tokenPrices = event.params._tokenPrices
    invVault.save()
}

export function onPerformanceFeeSet(event: PerformanceFeeSet): void {
    const invVault = getOrCreateInvestmentVault(event.address, event.block.timestamp)
    const numerator = event.params.numerator.toBigDecimal()
    const denominator = event.params.denominator.toBigDecimal()
    invVault.performanceFee = numerator.times(BIG_DECIMAL_100).div(denominator)
    invVault.save()
}
