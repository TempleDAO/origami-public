#!/bin/bash

set -x
set -e

npx hardhat run --network localhost scripts/deploys/berachain/03-infrared-auto-compounder-factory/01-core/01-token-prices.ts

npx hardhat run --network localhost scripts/deploys/berachain/03-infrared-auto-compounder-factory/02-vault/04-post-deploy.ts
npx hardhat run --network localhost scripts/deploys/berachain/03-infrared-auto-compounder-factory/03-update-references.ts
