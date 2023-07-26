import { Address, BigDecimal, BigInt, Bytes } from '@graphprotocol/graph-ts'

import { ERC20 } from '../../generated/GmxInvestment/ERC20'
import { TokenPrices } from '../../generated/GmxInvestment/TokenPrices'

import { PricedToken, PricedTokenDailySnapshot, PricedTokenHourlySnapshot } from '../../generated/schema'
import { BIG_DECIMAL_0, CACHE_INTERVAL } from '../utils/constants'
import { dayFromTimestamp, hourFromTimestamp } from '../utils/dates'
import { toDecimal } from '../utils/decimals'
import { getMetric, updateMetric } from './metric'


export function createPricedToken(address: Address, tokenPrices: Bytes, timestamp: BigInt): PricedToken {
  const pricedToken = new PricedToken(address.toHexString())
  pricedToken.timestamp = timestamp

  const erc20Token = ERC20.bind(address)
  pricedToken.name = erc20Token.name()
  pricedToken.symbol = erc20Token.symbol()
  pricedToken.decimals = erc20Token.decimals()
  pricedToken.price = BIG_DECIMAL_0
  pricedToken.tokenPrices = tokenPrices
  pricedToken.save()

  const metric = getMetric()
  metric.pricedTokenCount += 1

  const pricedTokens = metric.pricedTokens
  pricedTokens.push(pricedToken.id)
  metric.pricedTokens = pricedTokens
  updateMetric(metric, timestamp)

  return pricedToken
}

export function getOrCreatePricedToken(address: Address, tokenPrices: Bytes, timestamp: BigInt): PricedToken {
  let pricedToken = PricedToken.load(address.toHexString())

  if (pricedToken === null) {
    pricedToken = createPricedToken(address, tokenPrices, timestamp)
    updatePricedToken(pricedToken, timestamp, true)
  } else {
    updatePricedToken(pricedToken, timestamp)
  }

  return pricedToken
}

export function getPricedToken(address: string, timestamp: BigInt): PricedToken {
  let pricedToken = PricedToken.load(address) as PricedToken
  updatePricedToken(pricedToken, timestamp)

  return pricedToken
}

function updatePricedToken(pricedToken: PricedToken, timestamp: BigInt, force: boolean = false): void {
  pricedToken.timestamp = timestamp
  let price = getPricedTokenPrice(pricedToken)
  pricedToken.price = price

  pricedToken.save()

  if (force || pricedToken.timestamp.plus(CACHE_INTERVAL) < timestamp) {
    updateOrCreateHourData(pricedToken, timestamp)
    updateOrCreateDayData(pricedToken, timestamp)
  }
}

export function getPricedTokenPrice(pricedToken: PricedToken): BigDecimal {
  const tokenPrices = TokenPrices.bind(Address.fromBytes(pricedToken.tokenPrices))
  const price = tokenPrices.try_tokenPrice(Address.fromString(pricedToken.id))
  if (price.reverted) {
    return BIG_DECIMAL_0
  }

  // tokenPrices returns prices to 30 decimal places
  const tokenPricesDecimals = 30
  return toDecimal(price.value, tokenPricesDecimals)
}

export function updatePricedTokenPrices(timestamp: BigInt): void {
  const metric = getMetric()
  const pricedTokens = metric.pricedTokens
  for (let i = 0; i < pricedTokens.length; ++i) {
    const pricedToken = PricedToken.load(pricedTokens[i]) as PricedToken
    updatePricedToken(pricedToken, timestamp, true)
  }
}

export function updateOrCreateDayData(pricedToken: PricedToken, timestamp: BigInt): void {
  const dayTimestamp = dayFromTimestamp(timestamp)
  const dataID = pricedToken.id + '-' + dayTimestamp

  let dayData = PricedTokenDailySnapshot.load(dataID)
  if (dayData === null) {
    dayData = new PricedTokenDailySnapshot(dataID)
    dayData.timeframe = BigInt.fromString(dayTimestamp)
  }

  dayData.pricedToken = pricedToken.id
  dayData.timestamp = timestamp
  dayData.name = pricedToken.name
  dayData.symbol = pricedToken.symbol
  dayData.decimals = pricedToken.decimals
  dayData.price = pricedToken.price
  dayData.tokenPrices = pricedToken.tokenPrices
  dayData.save()
}

export function updateOrCreateHourData(pricedToken: PricedToken, timestamp: BigInt): void {
  const hourTimestamp = hourFromTimestamp(timestamp)
  const dataID = pricedToken.id + '-' + hourTimestamp

  let hourData = PricedTokenHourlySnapshot.load(dataID)
  if (hourData === null) {
    hourData = new PricedTokenHourlySnapshot(dataID)
    hourData.timeframe = BigInt.fromString(hourTimestamp)
  }

  hourData.pricedToken = pricedToken.id
  hourData.timestamp = timestamp
  hourData.name = pricedToken.name
  hourData.symbol = pricedToken.symbol
  hourData.decimals = pricedToken.decimals
  hourData.price = pricedToken.price
  hourData.tokenPrices = pricedToken.tokenPrices
  hourData.save()
}
