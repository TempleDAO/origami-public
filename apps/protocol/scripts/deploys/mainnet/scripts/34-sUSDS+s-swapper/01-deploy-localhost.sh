#!/bin/bash

set -x
set -e

SCRIPT_DIR=`dirname $0`
DIRECTORY=`basename $SCRIPT_DIR`

npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-oracles/01-sky-mkr-oracle.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-oracles/02-mkr-usds-oracle.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-oracles/03-sky-usds-oracle.ts

npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/01-cow-swapper.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/02-post-deploy.ts