import { Exited as ExitedShare } from '../../generated/GmxInvestmentShare/InvestmentShare'
import { UserExit } from '../../generated/schema'

import { getOrCreateUser } from './user'
import { toDecimal } from '../utils/decimals'
import { getOrCreateUserBalance, updateUserBalance } from './userBalance'
import { getRewardToken } from './rewardToken'
import { getOrCreateToken } from './token'
import { getOrCreateInvestmentShare, updateInvestmentShare } from './investmentShare'
import { BIG_DECIMAL_0, BIG_INT_0 } from '../utils/constants'


export function createUserExit(event: ExitedShare): UserExit {
  const timestamp = event.block.timestamp

  const investmentShare = getOrCreateInvestmentShare(event.address, timestamp)
  const user = getOrCreateUser(event.params.user, timestamp)
  const userBalance = getOrCreateUserBalance(user, investmentShare.id, timestamp)

  const fromToken = getRewardToken(investmentShare.id, timestamp)
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
    investmentShare.userCount -= 1
    userBalance.enterInvestTimestamp = BIG_INT_0
  }

  investmentShare.tvl = investmentShare.tvl.minus(fromTokenAmount)
  investmentShare.tvlUSD = investmentShare.tvl.times(fromToken.price)
  investmentShare.volume = investmentShare.volume.plus(fromTokenAmount)
  investmentShare.volumeUSD = investmentShare.volumeUSD.plus(fromTokenAmount.times(fromToken.price))
  updateInvestmentShare(investmentShare, timestamp)

  userBalance.investment = investmentShare.id
  userBalance.investAmount = investAmount
  userBalance.investVolume = userBalance.investVolume.plus(fromTokenAmount)
  userBalance.exitCount += 1
  updateUserBalance(userBalance, timestamp)

  return userExit
}
