import { Address, BigInt } from '@graphprotocol/graph-ts'

import { User } from '../../generated/schema'

import { getMetric, updateMetric } from './metric'


export function createUser(address: Address, timestamp: BigInt): User {
  const metric = getMetric()
  metric.userCount += 1
  updateMetric(metric, timestamp)

  const user = new User(address.toHexString())
  user.timestamp = timestamp
  user.enterTimestamp = timestamp
  user.save()

  return user as User
}

export function getOrCreateUser(address: Address, timestamp: BigInt): User {
  let user = User.load(address.toHexString())

  if (user === null) {
    user = createUser(address, timestamp)
  }

  return user as User
}

export function updateUser(user: User, timestamp: BigInt): void {
  user.timestamp = timestamp
  user.save()
}
