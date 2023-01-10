import { Invested, Exited, ReservesAdded, ReservesRemoved } from '../../generated/GmxInvestmentShare/InvestmentShare'

import { createUserInvestment } from '../entities/userInvestment'
import { createUserExit } from '../entities/userExit'
import { getOrCreateInvestmentShare } from '../entities/investmentShare'
import { toDecimal } from '../utils/decimals'


export function onInvestedShare(event: Invested): void {
    createUserInvestment(event)
}

export function onExitedShare(event: Exited): void {
    createUserExit(event)
}

export function onReservesAdded(event: ReservesAdded): void {
    const invShare = getOrCreateInvestmentShare(event.address, event.block.timestamp)
    const amount = toDecimal(event.params.amount, 18)
    invShare.totalReserves = invShare.totalReserves.plus(amount)
    invShare.save()
}

export function onReservesRemoved(event: ReservesRemoved): void {
    const invShare = getOrCreateInvestmentShare(event.address, event.block.timestamp)
    const amount = toDecimal(event.params.amount, 18)
    invShare.totalReserves = invShare.totalReserves.minus(amount)
    invShare.save()
}
