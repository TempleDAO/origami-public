import { Invested as InvestedVault } from '../../generated/GmxInvestmentVault/OrigamiInvestmentVault'
import { UserInvestment } from '../../generated/schema'

import { getOrCreateUser } from './user'
import { toDecimal } from '../utils/decimals'
import { getOrCreateUserBalance, updateUserBalance } from './userBalance'
import { getOrCreateRewardToken } from './rewardToken'
import { getOrCreateToken } from './token'
import { BIG_DECIMAL_0 } from '../utils/constants'
import { getOrCreateInvestmentVault, updateInvestmentVault } from './investmentVault'


export function createUserInvestment(event: InvestedVault): UserInvestment {
  const timestamp = event.block.timestamp

  const investmentVault = getOrCreateInvestmentVault(event.address, timestamp)
  const user = getOrCreateUser(event.params.user, timestamp)
  const userBalance = getOrCreateUserBalance(user, investmentVault.id, timestamp)

  const fromToken = getOrCreateToken(event.params.fromToken, timestamp)
  const fromTokenAmount = toDecimal(event.params.fromTokenAmount, fromToken.decimals)
  const toToken = getOrCreateRewardToken(event.address, investmentVault.tokenPrices, timestamp)
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
    investmentVault.userCount += 1
    userBalance.enterInvestTimestamp = timestamp
  }

  investmentVault.tvl = investmentVault.tvl.plus(toTokenAmount)
  investmentVault.tvlUSD = investmentVault.tvl.times(toToken.price)
  investmentVault.volume = investmentVault.volume.plus(toTokenAmount)
  investmentVault.volumeUSD = investmentVault.volumeUSD.plus(toTokenAmount.times(toToken.price))
  updateInvestmentVault(investmentVault, timestamp)

  userBalance.investment = investmentVault.id
  userBalance.investAmount = userBalance.investAmount.plus(toTokenAmount)
  userBalance.investVolume = userBalance.investVolume.plus(toTokenAmount)
  userBalance.investCount += 1
  updateUserBalance(userBalance, timestamp)

  return userInvestment
}
