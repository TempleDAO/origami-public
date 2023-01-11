import { Invested, Exited, ReservesAdded, ReservesRemoved } from '../../generated/GmxInvestmentVault/OrigamiInvestmentVault'

import { createUserInvestment } from '../entities/userInvestment'
import { createUserExit } from '../entities/userExit'
import { getOrCreateInvestmentVault } from '../entities/investmentVault'
import { toDecimal } from '../utils/decimals'


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
