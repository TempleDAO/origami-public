import { Address, BigDecimal, BigInt, Bytes } from '@graphprotocol/graph-ts'

import { InvestmentShare as InvestmentShareContract } from '../../generated/GmxInvestment/InvestmentShare'

import { InvestmentShare, InvestmentShareDailySnapshot, InvestmentShareHourlySnapshot } from '../../generated/schema'
import { BIG_DECIMAL_0, BIG_DECIMAL_1, BIG_DECIMAL_100, BIG_DECIMAL_365, CACHE_INTERVAL } from '../utils/constants'
import { dayFromTimestamp, hourFromTimestamp } from '../utils/dates'
import { ipow, toDecimal } from '../utils/decimals'
import { getOrCreateInvestment } from './investment'
import { getMetric, updateMetric } from './metric'
import { getOrCreateRewardToken } from './rewardToken'


function createInvestmentShare(address: Address, timestamp: BigInt): InvestmentShare {
  const investmentShare = new InvestmentShare(address.toHexString())
  investmentShare.timestamp = timestamp

  const investmentShareContract = InvestmentShareContract.bind(address)

  const acceptedInvTokens = investmentShareContract.acceptedInvestTokens()
  let investTokens = new Array<Bytes>(acceptedInvTokens.length)
  for (let i = 0; i < acceptedInvTokens.length; ++i) {
    investTokens[i] = acceptedInvTokens[i]
  }
  investmentShare.acceptedInvestTokens = investTokens

  const acceptedExTokens = investmentShareContract.acceptedExitTokens()
  let exitTokens = new Array<Bytes>(acceptedExTokens.length)
  for (let i = 0; i < acceptedExTokens.length; ++i) {
    exitTokens[i] = acceptedExTokens[i]
  }
  investmentShare.acceptedExitTokens = exitTokens

  const tokenPrices = investmentShareContract.tokenPrices()
  investmentShare.tokenPrices = tokenPrices

  investmentShare.reserveToken = getOrCreateRewardToken(address, tokenPrices, timestamp).id

  const investmentAddress = investmentShareContract.reserveToken()
  investmentShare.investment = getOrCreateInvestment(investmentAddress, timestamp).id

  investmentShare.tvl = BIG_DECIMAL_0
  investmentShare.tvlUSD = BIG_DECIMAL_0
  investmentShare.volume = BIG_DECIMAL_0
  investmentShare.volumeUSD = BIG_DECIMAL_0
  investmentShare.apr = BIG_DECIMAL_0
  investmentShare.apy = BIG_DECIMAL_0
  investmentShare.totalReserves = BIG_DECIMAL_0
  investmentShare.totalSupply = BIG_DECIMAL_0
  investmentShare.reservesPerShare = BIG_DECIMAL_0
  investmentShare.userCount = 0
  investmentShare.save()

  const metric = getMetric()
  metric.investmentShareCount += 1

  const investmentShares = metric.investmentShares
  investmentShares.push(investmentShare.id)
  metric.investmentShares = investmentShares
  updateMetric(metric, timestamp)

  return investmentShare
}

export function getOrCreateInvestmentShare(address: Address, timestamp: BigInt): InvestmentShare {
  let investmentShareShare = InvestmentShare.load(address.toHexString())

  if (investmentShareShare === null) {
    investmentShareShare = createInvestmentShare(address, timestamp)
  } else if (investmentShareShare.timestamp.plus(CACHE_INTERVAL) < timestamp) {
    updateInvestmentShare(investmentShareShare, timestamp)
  }

  return investmentShareShare as InvestmentShare
}

export function getInvestmentShare(address: Address): InvestmentShare {
  let investmentShare = InvestmentShare.load(address.toHexString())

  return investmentShare as InvestmentShare
}

export function updateInvestmentShare(investmentShare: InvestmentShare, timestamp: BigInt): void {
  investmentShare.timestamp = timestamp

  const ISContract = InvestmentShareContract.bind(Address.fromString(investmentShare.id))
  const apr = getAPR(ISContract)
  investmentShare.apr = apr
  investmentShare.apy = getAPY(apr)

  const totalSupply = toDecimal(ISContract.totalSupply(), 18)
  investmentShare.totalSupply = totalSupply
  investmentShare.reservesPerShare = investmentShare.totalReserves.div(totalSupply)

  investmentShare.save()

  updateOrCreateHourData(investmentShare, timestamp)
  updateOrCreateDayData(investmentShare, timestamp)
}

export function updateInvestmentShares(timestamp: BigInt): void {
  const investmentShares = getMetric().investmentShares
  for (let i = 0; i < investmentShares.length; ++i) {
    const investmentShare = InvestmentShare.load(investmentShares[i]) as InvestmentShare
    updateInvestmentShare(investmentShare, timestamp)
  }
}

function getAPR(investmentShareContract: InvestmentShareContract): BigDecimal {
  const aprBpsCall = investmentShareContract.try_apr()
  if (!aprBpsCall.reverted) {
    return aprBpsCall.value.toBigDecimal().div(BIG_DECIMAL_100)
  }

  return BIG_DECIMAL_0
}

function getAPY(apr: BigDecimal): BigDecimal {
  if (apr > BIG_DECIMAL_0) {
    const lhs = BIG_DECIMAL_1.plus(apr.div(BIG_DECIMAL_100).div(BIG_DECIMAL_365))
    const apy = ipow(lhs, 365).minus(BIG_DECIMAL_1)
    return apy.times(BIG_DECIMAL_100)
  }

  return BIG_DECIMAL_0
}

export function updateOrCreateDayData(investmentShare: InvestmentShare, timestamp: BigInt): void {
  const dayTimestamp = dayFromTimestamp(timestamp)
  const dataID = investmentShare.id + '-' + dayTimestamp

  let dayData = InvestmentShareDailySnapshot.load(dataID)
  if (dayData === null) {
    dayData = new InvestmentShareDailySnapshot(dataID)
    dayData.timeframe = BigInt.fromString(dayTimestamp)
  }

  dayData.investmentShare = investmentShare.id
  dayData.timestamp = timestamp
  dayData.tvl = investmentShare.tvl
  dayData.tvlUSD = investmentShare.tvlUSD
  dayData.volume = investmentShare.volume
  dayData.volumeUSD = investmentShare.volumeUSD
  dayData.apr = investmentShare.apr
  dayData.apy = investmentShare.apy
  dayData.reservesPerShare = investmentShare.reservesPerShare
  dayData.totalReserves = investmentShare.totalReserves
  dayData.totalSupply = investmentShare.totalSupply
  dayData.userCount = investmentShare.userCount
  dayData.save()
}

export function updateOrCreateHourData(investmentShare: InvestmentShare, timestamp: BigInt): void {
  const hourTimestamp = hourFromTimestamp(timestamp)
  const dataID = investmentShare.id + '-' + hourTimestamp

  let hourData = InvestmentShareHourlySnapshot.load(dataID)
  if (hourData === null) {
    hourData = new InvestmentShareHourlySnapshot(dataID)
    hourData.timeframe = BigInt.fromString(hourTimestamp)
  }

  hourData.investmentShare = investmentShare.id
  hourData.timestamp = timestamp
  hourData.tvl = investmentShare.tvl
  hourData.tvlUSD = investmentShare.tvlUSD
  hourData.volume = investmentShare.volume
  hourData.volumeUSD = investmentShare.volumeUSD
  hourData.apr = investmentShare.apr
  hourData.apy = investmentShare.apy
  hourData.reservesPerShare = investmentShare.reservesPerShare
  hourData.totalReserves = investmentShare.totalReserves
  hourData.totalSupply = investmentShare.totalSupply
  hourData.userCount = investmentShare.userCount
  hourData.save()
}
