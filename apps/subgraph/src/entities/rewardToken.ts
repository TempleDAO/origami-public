import { Address, BigDecimal, BigInt, Bytes } from '@graphprotocol/graph-ts'

import { ERC20 } from '../../generated/GmxInvestment/ERC20'
import { TokenPrices } from '../../generated/GmxInvestment/TokenPrices'

import { RewardToken, RewardTokenDailySnapshot, RewardTokenHourlySnapshot } from '../../generated/schema'
import { BIG_DECIMAL_0, CACHE_INTERVAL } from '../utils/constants'
import { dayFromTimestamp, hourFromTimestamp } from '../utils/dates'
import { toDecimal } from '../utils/decimals'
import { getMetric, updateMetric } from './metric'


export function createRewardToken(address: Address, tokenPrices: Bytes, timestamp: BigInt): RewardToken {
  const rewardToken = new RewardToken(address.toHexString())
  rewardToken.timestamp = timestamp

  const erc20Token = ERC20.bind(address)
  rewardToken.name = erc20Token.name()
  rewardToken.symbol = erc20Token.symbol()
  rewardToken.decimals = erc20Token.decimals()
  rewardToken.price = BIG_DECIMAL_0
  rewardToken.tokenPrices = tokenPrices
  rewardToken.save()

  const metric = getMetric()
  metric.rewardTokenCount += 1

  const rewardTokens = metric.rewardTokens
  rewardTokens.push(rewardToken.id)
  metric.rewardTokens = rewardTokens
  updateMetric(metric, timestamp)

  updateRewardToken(rewardToken, timestamp)

  return rewardToken
}

export function getOrCreateRewardToken(address: Address, tokenPrices: Bytes, timestamp: BigInt): RewardToken {
  let rewardToken = RewardToken.load(address.toHexString())

  if (rewardToken === null) {
    rewardToken = createRewardToken(address, tokenPrices, timestamp)
  } else if (rewardToken.timestamp.plus(CACHE_INTERVAL) < timestamp) {
    updateRewardToken(rewardToken, timestamp)
  }

  return rewardToken
}

export function getRewardToken(address: string, timestamp: BigInt): RewardToken {
  let rewardToken = RewardToken.load(address) as RewardToken

  if (rewardToken.timestamp.plus(CACHE_INTERVAL) < timestamp) {
    updateRewardToken(rewardToken, timestamp)
  }

  return rewardToken
}

function updateRewardToken(rewardToken: RewardToken, timestamp: BigInt): void {
  rewardToken.timestamp = timestamp
  let price = getRewardTokenPrice(rewardToken)
  rewardToken.price = price

  rewardToken.save()

  updateOrCreateHourData(rewardToken, timestamp)
  updateOrCreateDayData(rewardToken, timestamp)
}

export function getRewardTokenPrice(rewardToken: RewardToken): BigDecimal {
  const tokenPrices = TokenPrices.bind(Address.fromBytes(rewardToken.tokenPrices))
  const price = tokenPrices.tokenPrice(Address.fromString(rewardToken.id))

  return toDecimal(price, rewardToken.decimals)
}

export function updateRewardTokenPrice(address: string, timestamp: BigInt): void {
  let rewardToken = RewardToken.load(address) as RewardToken

  if (rewardToken.timestamp.plus(CACHE_INTERVAL) < timestamp) {
    updateRewardToken(rewardToken, timestamp)
  }
}

export function updateRewardTokenPrices(timestamp: BigInt): void {
  const metric = getMetric()
  const rewardTokens = metric.rewardTokens
  for (let i = 0; i < rewardTokens.length; ++i) {
      updateRewardTokenPrice(rewardTokens[i], timestamp)
  }
}

export function updateOrCreateDayData(rewardToken: RewardToken, timestamp: BigInt): void {
  const dayTimestamp = dayFromTimestamp(timestamp)
  const dataID = rewardToken.id + '-' + dayTimestamp

  let dayData = RewardTokenDailySnapshot.load(dataID)
  if (dayData === null) {
    dayData = new RewardTokenDailySnapshot(dataID)
    dayData.timeframe = BigInt.fromString(dayTimestamp)
  }

  dayData.rewardToken = rewardToken.id
  dayData.timestamp = timestamp
  dayData.name = rewardToken.name
  dayData.symbol = rewardToken.symbol
  dayData.decimals = rewardToken.decimals
  dayData.price = rewardToken.price
  dayData.tokenPrices = rewardToken.tokenPrices
  dayData.save()
}

export function updateOrCreateHourData(rewardToken: RewardToken, timestamp: BigInt): void {
  const hourTimestamp = hourFromTimestamp(timestamp)
  const dataID = rewardToken.id + '-' + hourTimestamp

  let hourData = RewardTokenHourlySnapshot.load(dataID)
  if (hourData === null) {
    hourData = new RewardTokenHourlySnapshot(dataID)
    hourData.timeframe = BigInt.fromString(hourTimestamp)
  }

  hourData.rewardToken = rewardToken.id
  hourData.timestamp = timestamp
  hourData.name = rewardToken.name
  hourData.symbol = rewardToken.symbol
  hourData.decimals = rewardToken.decimals
  hourData.price = rewardToken.price
  hourData.tokenPrices = rewardToken.tokenPrices
  hourData.save()
}
