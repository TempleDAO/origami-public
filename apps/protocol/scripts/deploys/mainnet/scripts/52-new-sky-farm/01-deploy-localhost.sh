#!/bin/bash

set -x
set -e

SCRIPT_DIR=`dirname $0`
DIRECTORY=`basename $SCRIPT_DIR`

npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-vault/01-rewards-harvester.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-vault/02-grant-access.ts
