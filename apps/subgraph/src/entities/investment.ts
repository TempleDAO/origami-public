import { Address, BigInt, Bytes } from '@graphprotocol/graph-ts'

import { OrigamiInvestment as InvestmentContract } from '../../generated/GmxInvestment/OrigamiInvestment'
import { Investment } from '../../generated/schema'

import { getMetric, updateMetric } from './metric'
import { BIG_DECIMAL_0, TOKEN_PRICES } from '../utils/constants'
import { getOrCreateRewardToken } from './rewardToken'


function createInvestment(address: Address, timestamp: BigInt): Investment {
  const investment = new Investment(address.toHexString())
  investment.timestamp = timestamp

  const investmentContract = InvestmentContract.bind(address)

  const acceptedInvTokens = investmentContract.acceptedInvestTokens()
  let investTokens = new Array<Bytes>(acceptedInvTokens.length)
  for (let i = 0; i < acceptedInvTokens.length; ++i) {
    investTokens[i] = acceptedInvTokens[i]
  }
  investment.acceptedInvestTokens = investTokens

  const acceptedExTokens = investmentContract.acceptedExitTokens()
  let exitTokens = new Array<Bytes>(acceptedExTokens.length)
  for (let i = 0; i < acceptedExTokens.length; ++i) {
    exitTokens[i] = acceptedExTokens[i]
  }
  investment.acceptedExitTokens = exitTokens

  investment.investmentToken = getOrCreateRewardToken(address, TOKEN_PRICES, timestamp).id

  investment.tvl = BIG_DECIMAL_0
  investment.tvlUSD = BIG_DECIMAL_0
  investment.volume = BIG_DECIMAL_0
  investment.volumeUSD = BIG_DECIMAL_0
  investment.userCount = 0
  investment.save()

  const metric = getMetric()
  metric.investmentCount += 1

  const investments = metric.investments
  investments.push(investment.id)
  metric.investments = investments
  updateMetric(metric, timestamp)

  return investment
}

export function getOrCreateInvestment(address: Address, timestamp: BigInt): Investment {
  let investment = Investment.load(address.toHexString())

  if (investment === null) {
    investment = createInvestment(address, timestamp)
  }

  return investment
}

export function getInvestment(address: Address): Investment {
  let investment = Investment.load(address.toHexString())

  return investment as Investment
}

export function updateInvestment(investment: Investment, timestamp: BigInt): void {
  investment.timestamp = timestamp
  investment.save()
}
