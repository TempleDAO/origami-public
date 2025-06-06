#!/bin/bash

set -x
set -e

SCRIPT_DIR=`dirname $0`
DIRECTORY=`basename $SCRIPT_DIR`

npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-oracles/01-usd0++-usdc-floor-price-oracle.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-oracles/02-usd0++-usdc-market-price-oracle.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-oracles/03-usd0++-usdc-morpho-to-market-conversion.ts

npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/01-borrow-lend.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/02-manager.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/03-grant-overlord-access.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/05-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/03-migration/01-migrator.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/03-migration/02-create-safe-migration.ts

npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/04-access/01-vault.ts