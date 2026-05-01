#!/bin/bash

set -x
set -e

SCRIPT_DIR=`dirname $0`
DIRECTORY=`basename $SCRIPT_DIR`

# Not required, as this test is using already deployed mainnet contracts

# npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-borrow-lend.ts
# npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-migrator.ts
# npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/03-create-safe-migration.ts
