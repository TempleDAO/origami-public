#!/bin/bash

# When deploying locally as a fork off polygon
# First start local node with:
#    npx hardhat node --fork https://eth-mainnet.g.alchemy.com/v2/XXX --fork-block-number 39751154

set -x
set -e
npx hardhat run --network localhost scripts/deploys/mainnet/governance/01-timelock.ts
npx hardhat run --network localhost scripts/deploys/mainnet/stakedao/01-vesdt.ts
npx hardhat run --network localhost scripts/deploys/mainnet/stakedao/100-transfer-ownership.ts
