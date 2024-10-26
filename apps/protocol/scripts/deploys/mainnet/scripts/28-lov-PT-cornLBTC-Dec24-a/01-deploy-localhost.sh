#!/bin/bash

set -x
set -e

SCRIPT_DIR=`dirname $0`
DIRECTORY=`basename $SCRIPT_DIR`

# Required since it's not deployed in mainnet yet
npx hardhat run --network localhost scripts/deploys/mainnet/27-lov-pt-eBTC-dec24-a/02-flashloan-providers/01-zerolend-flashloan-provider.ts

npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-oracles/01-pt-cornLBTC-dec24-LBTC-oracle.ts

npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/01-vault.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/02-borrow-lend.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/03-manager.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/04-grant-overlord-access.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/05-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/03-access/01-vault.ts
