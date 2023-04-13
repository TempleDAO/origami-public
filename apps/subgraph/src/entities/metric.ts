import { BigInt } from '@graphprotocol/graph-ts'

import { BIG_DECIMAL_0, OWNER } from '../utils/constants'
import { dayFromTimestamp, hourFromTimestamp } from '../utils/dates'
import { MetricDailySnapshot, Metric, MetricHourlySnapshot } from '../../generated/schema'


export function getMetric(): Metric {
  let metric = Metric.load(OWNER)

  if (metric === null) {
    metric = new Metric(OWNER)
    metric.investments = []
    metric.investmentCount = 0
    metric.investmentsTvlUSD = BIG_DECIMAL_0
    metric.investmentVaults = []
    metric.investmentVaultCount = 0
    metric.investmentVaultsTvlUSD = BIG_DECIMAL_0
    metric.pricedTokens = []
    metric.pricedTokenCount = 0
    metric.userCount = 0
  }

  return metric as Metric
}

export function updateMetric(metric: Metric, timestamp: BigInt): void {
  metric.timestamp = timestamp
  metric.save()

  updateOrCreateHourData(metric, timestamp)
  updateOrCreateDayData(metric, timestamp)
}

export function updateOrCreateDayData(metric: Metric, timestamp: BigInt): void {
  const dayTimestamp = dayFromTimestamp(timestamp)
  const dataID = metric.id + '-' + dayTimestamp

  let dayData = MetricDailySnapshot.load(dataID)
  if (dayData === null) {
    dayData = new MetricDailySnapshot(dataID)
    dayData.timeframe = BigInt.fromString(dayTimestamp)
  }

  dayData.metric = metric.id
  dayData.timestamp = timestamp
  dayData.investmentCount = metric.investmentCount
  dayData.investmentsTvlUSD = metric.investmentsTvlUSD
  dayData.investmentVaultCount = metric.investmentVaultCount
  dayData.investmentVaultsTvlUSD = metric.investmentVaultsTvlUSD
  dayData.pricedTokenCount = metric.pricedTokenCount
  dayData.userCount = metric.userCount
  dayData.save()
}

export function updateOrCreateHourData(metric: Metric, timestamp: BigInt): void {
  const hourTimestamp = hourFromTimestamp(timestamp)
  const dataID = metric.id + '-' + hourTimestamp

  let hourData = MetricHourlySnapshot.load(dataID)
  if (hourData === null) {
    hourData = new MetricHourlySnapshot(dataID)
    hourData.timeframe = BigInt.fromString(hourTimestamp)
  }

  hourData.metric = metric.id
  hourData.timestamp = timestamp
  hourData.investmentCount = metric.investmentCount
  hourData.investmentsTvlUSD = metric.investmentsTvlUSD
  hourData.investmentVaultCount = metric.investmentVaultCount
  hourData.investmentVaultsTvlUSD = metric.investmentVaultsTvlUSD
  hourData.pricedTokenCount = metric.pricedTokenCount
  hourData.userCount = metric.userCount
  hourData.save()
}
