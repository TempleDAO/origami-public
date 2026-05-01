#!/bin/bash

set -x
set -e

SCRIPT_DIR=`dirname $0`
DIRECTORY=`basename $SCRIPT_DIR`

npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-oracles/01-aave-usdc-oracle.ts

npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/01-vault.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/02-borrow-lend.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/03-manager.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/04-grant-overlord-access.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/05-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/03-access/01-vault.ts
