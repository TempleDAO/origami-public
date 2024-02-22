#!/bin/bash

# When deploying locally as a fork off polygon
# First start local node with:
#    npx hardhat node --fork https://eth-mainnet.g.alchemy.com/v2/XXX --fork-block-number 39751154

set -x
set -e
npx hardhat run --network localhost scripts/deploys/polygon/governance/01-timelock.ts
npx hardhat run --network localhost scripts/deploys/polygon/tetu/01-vetetu.ts
npx hardhat run --network localhost scripts/deploys/polygon/tetu/100-transfer-ownership.ts
