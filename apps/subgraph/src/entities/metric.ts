import { BigInt } from '@graphprotocol/graph-ts'

import { OWNER } from '../utils/constants'
import { dayFromTimestamp } from '../utils/dates'
import { MetricDailySnapshot, Metric } from '../../generated/schema'


export function getMetric(): Metric {
  let metric = Metric.load(OWNER)

  if (metric === null) {
    metric = new Metric(OWNER)
    metric.investments = []
    metric.investmentCount = 0
    metric.investmentVaults = []
    metric.investmentVaultCount = 0
    metric.rewardTokens = []
    metric.rewardTokenCount = 0
    metric.userCount = 0
  }

  return metric as Metric
}

export function updateMetric(metric: Metric, timestamp: BigInt): void {
  metric.timestamp = timestamp
  metric.save()

  updateOrCreateDayData(metric, timestamp)
}

export function updateOrCreateDayData(metric: Metric, timestamp: BigInt): void {
  const dayTimestamp = dayFromTimestamp(timestamp);
  const dataID = metric.id + '-' + dayTimestamp

  let dayData = MetricDailySnapshot.load(dataID)
  if (dayData === null) {
    dayData = new MetricDailySnapshot(dataID)
    dayData.timeframe = BigInt.fromString(dayTimestamp)
  }

  dayData.metric = metric.id
  dayData.timestamp = timestamp
  dayData.investmentCount = metric.investmentCount
  dayData.investmentVaultCount = metric.investmentVaultCount
  dayData.rewardTokenCount = metric.rewardTokenCount
  dayData.userCount = metric.userCount
  dayData.save()
}
