import { Invested as InvestedShare } from '../../generated/GmxInvestmentShare/InvestmentShare'
import { UserInvestment } from '../../generated/schema'

import { getOrCreateUser } from './user'
import { toDecimal } from '../utils/decimals'
import { getOrCreateUserBalance, updateUserBalance } from './userBalance'
import { getOrCreateRewardToken } from './rewardToken'
import { getOrCreateToken } from './token'
import { BIG_DECIMAL_0 } from '../utils/constants'
import { getOrCreateInvestmentShare, updateInvestmentShare } from './investmentShare'


export function createUserInvestment(event: InvestedShare): UserInvestment {
  const timestamp = event.block.timestamp

  const investmentShare = getOrCreateInvestmentShare(event.address, timestamp)
  const user = getOrCreateUser(event.params.user, timestamp)
  const userBalance = getOrCreateUserBalance(user, investmentShare.id, timestamp)

  const fromToken = getOrCreateToken(event.params.fromToken, timestamp)
  const fromTokenAmount = toDecimal(event.params.fromTokenAmount, fromToken.decimals)
  const toToken = getOrCreateRewardToken(event.address, investmentShare.tokenPrices, timestamp)
  const toTokenAmount = toDecimal(event.params.investmentAmount, toToken.decimals)

  const userInvID = userBalance.id + '-' + userBalance.investCount.toString()
  const userInvestment = new UserInvestment(userInvID)
  userInvestment.timestamp = timestamp
  userInvestment.transaction = event.transaction.hash
  userInvestment.tokenIn = fromToken.id
  userInvestment.tokenOut = toToken.id
  userInvestment.amountIn = fromTokenAmount
  userInvestment.amountOut = toTokenAmount
  userInvestment.user = user.id
  userInvestment.userBalance = userBalance.id
  userInvestment.save()

  if (userBalance.investAmount == BIG_DECIMAL_0) {
    investmentShare.userCount += 1
    userBalance.enterInvestTimestamp = timestamp
  }

  investmentShare.tvl = investmentShare.tvl.plus(toTokenAmount)
  investmentShare.tvlUSD = investmentShare.tvl.times(toToken.price)
  investmentShare.volume = investmentShare.volume.plus(toTokenAmount)
  investmentShare.volumeUSD = investmentShare.volumeUSD.plus(toTokenAmount.times(toToken.price))
  updateInvestmentShare(investmentShare, timestamp)

  userBalance.investment = investmentShare.id
  userBalance.investAmount = userBalance.investAmount.plus(toTokenAmount)
  userBalance.investVolume = userBalance.investVolume.plus(toTokenAmount)
  userBalance.investCount += 1
  updateUserBalance(userBalance, timestamp)

  return userInvestment
}
