#!/bin/bash

# When deploying locally as a fork off arbitrum
# First start local node with:
#    npx hardhat node --fork https://arb-mainnet.g.alchemy.com/v2/XXX --fork-block-number 47930000

set -x
set -e
npx hardhat run --network localhost scripts/deploys/arbitrum/governance/01-timelock.ts
npx hardhat run --network localhost scripts/deploys/arbitrum/gmx/01-token-prices.ts
npx hardhat run --network localhost scripts/deploys/arbitrum/gmx/02a-oGMX.ts
npx hardhat run --network localhost scripts/deploys/arbitrum/gmx/02b-oGLP.ts
npx hardhat run --network localhost scripts/deploys/arbitrum/gmx/03a-ovGMX.ts
npx hardhat run --network localhost scripts/deploys/arbitrum/gmx/03b-ovGLP.ts
npx hardhat run --network localhost scripts/deploys/arbitrum/gmx/04a-gmx-earn-account.ts
npx hardhat run --network localhost scripts/deploys/arbitrum/gmx/04b-glp-primary-earn-account.ts
npx hardhat run --network localhost scripts/deploys/arbitrum/gmx/04c-glp-secondary-earn-account.ts
npx hardhat run --network localhost scripts/deploys/arbitrum/gmx/05a-gmx-manager.ts
npx hardhat run --network localhost scripts/deploys/arbitrum/gmx/05b-glp-manager.ts
npx hardhat run --network localhost scripts/deploys/arbitrum/gmx/06a-gmx-rewards-aggregator.ts
npx hardhat run --network localhost scripts/deploys/arbitrum/gmx/06b-glp-rewards-aggregator.ts
npx hardhat run --network localhost scripts/deploys/arbitrum/gmx/99-post-deployment.ts
npx hardhat run --network localhost scripts/deploys/arbitrum/gmx/100-transfer-ownership.ts
