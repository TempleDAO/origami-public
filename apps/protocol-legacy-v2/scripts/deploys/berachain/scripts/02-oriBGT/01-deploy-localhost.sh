#!/bin/bash

set -x
set -e

npx hardhat run --network localhost scripts/deploys/berachain/02-oriBGT/01-core/01-token-prices.ts

npx hardhat run --network localhost scripts/deploys/berachain/02-oriBGT/02-vault/01-vault.ts
npx hardhat run --network localhost scripts/deploys/berachain/02-oriBGT/02-vault/02-swapper.ts
npx hardhat run --network localhost scripts/deploys/berachain/02-oriBGT/02-vault/03-manager.ts
npx hardhat run --network localhost scripts/deploys/berachain/02-oriBGT/02-vault/04-grant-overlord-access.ts
npx hardhat run --network localhost scripts/deploys/berachain/02-oriBGT/02-vault/05-post-deploy.ts
npx hardhat run --network localhost scripts/deploys/berachain/02-oriBGT/02-vault/06-seed-vault.ts

npx hardhat run --network localhost scripts/deploys/berachain/02-oriBGT/03-access/01-vault.ts
