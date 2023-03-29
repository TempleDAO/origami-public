import { Exited as ExitedVault } from '../../generated/GmxInvestmentVault/OrigamiInvestmentVault'
import { UserExit } from '../../generated/schema'

import { getOrCreateUser } from './user'
import { toDecimal } from '../utils/decimals'
import { getOrCreateUserBalance, updateUserBalance } from './userBalance'
import { getPricedToken } from './pricedToken'
import { getOrCreateToken } from './token'
import { getOrCreateInvestmentVault, updateInvestmentVault } from './investmentVault'
import { BIG_DECIMAL_0, BIG_INT_0 } from '../utils/constants'


export function createUserExit(event: ExitedVault): UserExit {
  const timestamp = event.block.timestamp

  const investmentVault = getOrCreateInvestmentVault(event.address, timestamp)
  const user = getOrCreateUser(event.params.user, timestamp)
  const userBalance = getOrCreateUserBalance(user, investmentVault, timestamp)

  const fromToken = getPricedToken(investmentVault.id, timestamp)
  const fromTokenAmount = toDecimal(event.params.investmentAmount, fromToken.decimals)
  const toToken = getOrCreateToken(event.params.toToken, timestamp)
  const toTokenAmount = toDecimal(event.params.toTokenAmount, toToken.decimals)

  const userExitID = userBalance.id + '-' + userBalance.exitCount.toString()
  const userExit = new UserExit(userExitID)
  userExit.timestamp = timestamp
  userExit.transaction = event.transaction.hash
  userExit.tokenIn = fromToken.id
  userExit.tokenOut = toToken.id
  userExit.amountIn = fromTokenAmount
  userExit.amountOut = toTokenAmount
  userExit.recipient = event.params.recipient
  userExit.user = user.id
  userExit.userBalance = userBalance.id
  userExit.save()

  const investAmount = userBalance.investAmount.minus(fromTokenAmount)
  if (investAmount <= BIG_DECIMAL_0) {
    investmentVault.userCount -= 1
    userBalance.enterInvestTimestamp = BIG_INT_0
    userBalance.investAmountUSD = BIG_DECIMAL_0
  }

  investmentVault.tvl = investmentVault.tvl.minus(fromTokenAmount)
  investmentVault.tvlUSD = investmentVault.tvl.times(fromToken.price)
  investmentVault.volume = investmentVault.volume.plus(fromTokenAmount)
  investmentVault.volumeUSD = investmentVault.volumeUSD.plus(fromTokenAmount.times(fromToken.price))
  updateInvestmentVault(investmentVault, timestamp)

  userBalance.investAmount = investAmount
  userBalance.investAmountUSD = investAmount.times(fromToken.price)
  userBalance.investVolume = userBalance.investVolume.plus(fromTokenAmount)
  userBalance.exitCount += 1
  updateUserBalance(userBalance, timestamp)

  return userExit
}
