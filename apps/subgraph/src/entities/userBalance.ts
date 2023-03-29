import { BigInt } from '@graphprotocol/graph-ts'

import { InvestmentVault, User, UserBalance, UserBalanceSnapshot } from '../../generated/schema'

import { BIG_DECIMAL_0, BIG_INT_0 } from '../utils/constants'


export function createUserBalance(user: User, investmentVault: InvestmentVault, timestamp: BigInt): UserBalance {
  const ubID = user.id + '-' + investmentVault.id
  const userBalance = new UserBalance(ubID)
  userBalance.timestamp = timestamp

  userBalance.user = user.id
  userBalance.investmentVault = investmentVault.id
  userBalance.enterInvestTimestamp = BIG_INT_0
  userBalance.investAmount = BIG_DECIMAL_0
  userBalance.investAmountUSD = BIG_DECIMAL_0
  userBalance.investVolume = BIG_DECIMAL_0
  userBalance.investCount = 0
  userBalance.exitCount = 0
  userBalance.save()

  return userBalance as UserBalance
}

export function getOrCreateUserBalance(user: User, investmentVault: InvestmentVault, timestamp: BigInt): UserBalance {
  const ubID = user.id + '-' + investmentVault.id
  let userBalance = UserBalance.load(ubID)

  if (userBalance === null) {
    userBalance = createUserBalance(user, investmentVault, timestamp)
  }

  return userBalance
}

export function getUserBalance(user: User, tokenID: string): UserBalance {
  const ubID = user.id + '-' + tokenID
  const userBalance = UserBalance.load(ubID)

  return userBalance as UserBalance
}

export function updateUserBalance(userBalance: UserBalance, timestamp: BigInt): void {
  userBalance.timestamp = timestamp
  userBalance.save()

  updateOrCreateData(userBalance, timestamp)
}

export function updateOrCreateData(userBalance: UserBalance, timestamp: BigInt): void {
  const dataID = userBalance.id + '-' + timestamp.toString()

  let data = UserBalanceSnapshot.load(dataID)
  if (data === null) {
    data = new UserBalanceSnapshot(dataID)
  }

  data.userBalance = userBalance.id
  data.timestamp = timestamp
  data.user = userBalance.user
  data.investmentVault = userBalance.investmentVault
  data.enterInvestTimestamp = userBalance.enterInvestTimestamp
  data.investAmount = userBalance.investAmount
  data.investAmountUSD = userBalance.investAmountUSD
  data.investVolume = userBalance.investVolume
  data.investCount = userBalance.investCount
  data.exitCount = userBalance.exitCount
  data.save()
}
