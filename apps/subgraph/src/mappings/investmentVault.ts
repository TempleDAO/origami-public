import { Invested, Exited, PendingReservesAdded, TokenPricesSet, PerformanceFeeSet, InvestmentManagerSet } from '../../generated/GmxInvestmentVault/OrigamiInvestmentVault'
import { OrigamiInvestmentVault as InvestmentVaultContract } from '../../generated/GmxInvestment/OrigamiInvestmentVault'

import { createUserInvestment } from '../entities/userInvestment'
import { createUserExit } from '../entities/userExit'
import { getInvestmentVault, getOrCreateInvestmentVault } from '../entities/investmentVault'
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

export function onPendingReservesAdded(event: PendingReservesAdded): void {
    getOrCreateInvestmentVault(event.address, event.block.timestamp)
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
