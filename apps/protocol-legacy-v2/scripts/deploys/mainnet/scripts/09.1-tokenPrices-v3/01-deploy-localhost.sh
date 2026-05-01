#!/bin/bash

set -x
set -e

npx hardhat run --network localhost scripts/deploys/mainnet/09.1-tokenPrices-v3/01-core/01-token-prices.ts
npx hardhat run --network localhost scripts/deploys/mainnet/09.1-tokenPrices-v3/01-core/02-post-deploy.ts
npx hardhat run --network localhost scripts/deploys/mainnet/09.1-tokenPrices-v3/01-core/03-update-references.ts

npx hardhat run --network localhost scripts/deploys/mainnet/09.1-tokenPrices-v3/02-access/01-core.ts
