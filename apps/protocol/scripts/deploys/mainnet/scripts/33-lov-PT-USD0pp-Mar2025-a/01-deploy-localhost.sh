#!/bin/bash

set -x
set -e

SCRIPT_DIR=`dirname $0`
DIRECTORY=`basename $SCRIPT_DIR`

npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-oracles/01-pt-usd0pp-mar2025-usd0pp-oracle.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-oracles/02-pt-usd0pp-mar2025-usdc-oracle.ts

npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/01-borrow-lend.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/02-vault.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/03-manager.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/04-grant-overlord-access.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/05-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/03-access/01-vault.ts

# Can run this to check seeding the vault
#npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/04-seed/01-seed-deposit.ts