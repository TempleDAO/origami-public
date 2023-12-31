import { Address, BigDecimal, BigInt, Bytes } from '@graphprotocol/graph-ts'

import { OrigamiInvestmentVault as InvestmentVaultContract } from '../../generated/GmxInvestment/OrigamiInvestmentVault'

import { Investment, InvestmentVault, InvestmentVaultDailySnapshot, InvestmentVaultHourlySnapshot } from '../../generated/schema'
import { BIG_DECIMAL_0, BIG_DECIMAL_1, BIG_DECIMAL_100, BIG_DECIMAL_365, CACHE_INTERVAL } from '../utils/constants'
import { dayFromTimestamp, hourFromTimestamp } from '../utils/dates'
import { ipow, toDecimal } from '../utils/decimals'
import { getOrCreateInvestment, updateInvestment } from './investment'
import { getMetric, updateMetric } from './metric'
import { getOrCreatePricedToken, getPricedToken } from './pricedToken'


const MAX_VALID_APR = BigDecimal.fromString('1000')


function createInvestmentVault(address: Address, timestamp: BigInt): InvestmentVault {
  const investmentVault = new InvestmentVault(address.toHexString())
  investmentVault.timestamp = timestamp

  const investmentVaultContract = InvestmentVaultContract.bind(address)
  investmentVault.name = investmentVaultContract.name()
  investmentVault.symbol = investmentVaultContract.symbol()

  const acceptedInvTokens = investmentVaultContract.acceptedInvestTokens()
  let investTokens = new Array<Bytes>(acceptedInvTokens.length)
  for (let i = 0; i < acceptedInvTokens.length; ++i) {
    investTokens[i] = acceptedInvTokens[i]
  }
  investmentVault.acceptedInvestTokens = investTokens

  const acceptedExTokens = investmentVaultContract.acceptedExitTokens()
  let exitTokens = new Array<Bytes>(acceptedExTokens.length)
  for (let i = 0; i < acceptedExTokens.length; ++i) {
    exitTokens[i] = acceptedExTokens[i]
  }
  investmentVault.acceptedExitTokens = exitTokens

  const tokenPrices = investmentVaultContract.tokenPrices()
  investmentVault.tokenPrices = tokenPrices
  const reserveToken = investmentVaultContract.reserveToken()
  investmentVault.reserveToken = getOrCreatePricedToken(reserveToken, tokenPrices, timestamp).id

  investmentVault.investmentManager = investmentVaultContract.investmentManager()
  investmentVault.investment = getOrCreateInvestment(reserveToken, timestamp).id
  investmentVault.vaultToken = getOrCreatePricedToken(address, tokenPrices, timestamp).id

  const perfFee = investmentVaultContract.performanceFee()
  const numerator = perfFee.value0.toBigDecimal()
  const denominator = perfFee.value1.toBigDecimal()
  investmentVault.performanceFee = numerator.times(BIG_DECIMAL_100).div(denominator)

  investmentVault.tvl = BIG_DECIMAL_0
  investmentVault.tvlUSD = BIG_DECIMAL_0
  investmentVault.volume = BIG_DECIMAL_0
  investmentVault.volumeUSD = BIG_DECIMAL_0
  investmentVault.apr = BIG_DECIMAL_0
  investmentVault.apy = BIG_DECIMAL_0
  investmentVault.totalReserves = BIG_DECIMAL_0
  investmentVault.totalSupply = BIG_DECIMAL_0
  investmentVault.reservesPerShare = BIG_DECIMAL_0
  investmentVault.userCount = 0
  investmentVault.save()

  const metric = getMetric()
  metric.investmentVaultCount += 1

  const investmentVaults = metric.investmentVaults
  investmentVaults.push(investmentVault.id)
  metric.investmentVaults = investmentVaults
  updateMetric(metric, timestamp)

  return investmentVault
}

export function getOrCreateInvestmentVault(address: Address, timestamp: BigInt): InvestmentVault {
  let investmentVault = InvestmentVault.load(address.toHexString())

  if (investmentVault === null) {
    investmentVault = createInvestmentVault(address, timestamp)
    updateInvestmentVault(investmentVault, timestamp)
  } else if (investmentVault.timestamp.plus(CACHE_INTERVAL) < timestamp) {
    updateInvestmentVault(investmentVault, timestamp)
  }

  return investmentVault as InvestmentVault
}

export function getInvestmentVault(address: Address): InvestmentVault | null {
  let investmentVault = InvestmentVault.load(address.toHexString())

  return investmentVault
}

export function updateInvestmentVault(investmentVault: InvestmentVault, timestamp: BigInt): void {
  investmentVault.timestamp = timestamp

  const IVContract = InvestmentVaultContract.bind(Address.fromString(investmentVault.id))
  const apr = getAPR(IVContract)
  investmentVault.apr = apr
  investmentVault.apy = getAPY(apr)

  const totalReserves = toDecimal(IVContract.totalReserves(), 18)
  investmentVault.totalReserves = totalReserves
  const totalSupply = toDecimal(IVContract.totalSupply(), 18)
  investmentVault.totalSupply = totalSupply
  investmentVault.reservesPerShare = investmentVault.totalReserves.div(totalSupply)

  const vaultToken = getPricedToken(investmentVault.id, timestamp)
  investmentVault.tvlUSD = investmentVault.tvl.times(vaultToken.price)

  investmentVault.save()

  updateOrCreateHourData(investmentVault, timestamp)
  updateOrCreateDayData(investmentVault, timestamp)
}

export function updateInvestmentVaults(timestamp: BigInt): void {
  const metric = getMetric()
  let investmentVaultsTvlUSD = BIG_DECIMAL_0
  let investmentsTvlUSD = BIG_DECIMAL_0

  const investmentVaults = metric.investmentVaults
  const investments = metric.investments
  for (let i = 0; i < investmentVaults.length; ++i) {
    const investmentVault = InvestmentVault.load(investmentVaults[i]) as InvestmentVault
    updateInvestmentVault(investmentVault, timestamp)
    investmentVaultsTvlUSD = investmentVaultsTvlUSD.plus(investmentVault.tvlUSD)

    const investment = Investment.load(investments[i]) as Investment
    updateInvestment(investment, timestamp)
    investmentsTvlUSD = investmentsTvlUSD.plus(investment.tvlUSD)
  }

  metric.investmentVaultsTvlUSD = investmentVaultsTvlUSD
  metric.investmentsTvlUSD = investmentsTvlUSD
  updateMetric(metric, timestamp)
}

function getAPR(investmentVaultContract: InvestmentVaultContract): BigDecimal {
  const aprBpsCall = investmentVaultContract.try_apr()
  if (!aprBpsCall.reverted) {
    const apr = aprBpsCall.value.toBigDecimal().div(BIG_DECIMAL_100)
    // 1,000% as an upper bound on APR such that the APY calc doesn't overflow
    if (apr < MAX_VALID_APR) {
      return apr
    }
  }

  return BIG_DECIMAL_0
}

function getAPY(apr: BigDecimal): BigDecimal {
  if (apr > BIG_DECIMAL_0) {
    const lhs = BIG_DECIMAL_1.plus(apr.div(BIG_DECIMAL_100).div(BIG_DECIMAL_365))
    const apy = ipow(lhs, 365).minus(BIG_DECIMAL_1)
    return apy.times(BIG_DECIMAL_100).truncate(2)
  }

  return BIG_DECIMAL_0
}

export function updateOrCreateDayData(investmentVault: InvestmentVault, timestamp: BigInt): void {
  const dayTimestamp = dayFromTimestamp(timestamp)
  const dataID = investmentVault.id + '-' + dayTimestamp

  let dayData = InvestmentVaultDailySnapshot.load(dataID)
  if (dayData === null) {
    dayData = new InvestmentVaultDailySnapshot(dataID)
    dayData.timeframe = BigInt.fromString(dayTimestamp)
  }

  dayData.investmentVault = investmentVault.id
  dayData.timestamp = timestamp
  dayData.name = investmentVault.name
  dayData.symbol = investmentVault.symbol
  dayData.tvl = investmentVault.tvl
  dayData.tvlUSD = investmentVault.tvlUSD
  dayData.volume = investmentVault.volume
  dayData.volumeUSD = investmentVault.volumeUSD
  dayData.apr = investmentVault.apr
  dayData.apy = investmentVault.apy
  dayData.reservesPerShare = investmentVault.reservesPerShare
  dayData.totalReserves = investmentVault.totalReserves
  dayData.totalSupply = investmentVault.totalSupply
  dayData.performanceFee = investmentVault.performanceFee
  dayData.userCount = investmentVault.userCount
  dayData.save()
}

export function updateOrCreateHourData(investmentVault: InvestmentVault, timestamp: BigInt): void {
  const hourTimestamp = hourFromTimestamp(timestamp)
  const dataID = investmentVault.id + '-' + hourTimestamp

  let hourData = InvestmentVaultHourlySnapshot.load(dataID)
  if (hourData === null) {
    hourData = new InvestmentVaultHourlySnapshot(dataID)
    hourData.timeframe = BigInt.fromString(hourTimestamp)
  }

  hourData.investmentVault = investmentVault.id
  hourData.timestamp = timestamp
  hourData.name = investmentVault.name
  hourData.symbol = investmentVault.symbol
  hourData.tvl = investmentVault.tvl
  hourData.tvlUSD = investmentVault.tvlUSD
  hourData.volume = investmentVault.volume
  hourData.volumeUSD = investmentVault.volumeUSD
  hourData.apr = investmentVault.apr
  hourData.apy = investmentVault.apy
  hourData.reservesPerShare = investmentVault.reservesPerShare
  hourData.totalReserves = investmentVault.totalReserves
  hourData.totalSupply = investmentVault.totalSupply
  hourData.performanceFee = investmentVault.performanceFee
  hourData.userCount = investmentVault.userCount
  hourData.save()
}
