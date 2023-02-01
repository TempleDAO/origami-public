import { Address, BigInt } from '@graphprotocol/graph-ts'

import { ERC20 } from '../../generated/GmxInvestment/ERC20'

import { Token } from '../../generated/schema'
import { ZERO_ADDRESS } from '../utils/constants'


export function createToken(address: Address, timestamp: BigInt): Token {
  const token = new Token(address.toHexString())
  token.timestamp = timestamp

  if (address == ZERO_ADDRESS) {
    token.name = 'Ethereum'
    token.symbol = 'ETH'
    token.decimals = 18
  } else {
    const erc20Token = ERC20.bind(address)
    token.name = erc20Token.name()
    token.symbol = erc20Token.symbol()
    token.decimals = erc20Token.decimals()
  }
  token.save()

  return token as Token
}

export function getOrCreateToken(address: Address, timestamp: BigInt): Token {
  let token = Token.load(address.toHexString())

  if (token === null) {
    token = createToken(address, timestamp)
  }

  return token as Token
}

export function getToken(address: string): Token {
  let token = Token.load(address) as Token

  return token
}
