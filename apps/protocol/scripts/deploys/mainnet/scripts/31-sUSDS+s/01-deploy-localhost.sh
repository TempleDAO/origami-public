#!/bin/bash

set -x
set -e

SCRIPT_DIR=`dirname $0`
DIRECTORY=`basename $SCRIPT_DIR`

npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-vault/01-cow-swapper.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-vault/02-vault.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-vault/03-manager.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-vault/04-grant-overlord-access.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-vault/05-post-deploy.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-vault/06-seed-vault.ts

npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-access/01-vault.ts
