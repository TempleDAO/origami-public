#!/bin/bash

set -x
set -e

SCRIPT_DIR=`dirname $0`
DIRECTORY=`basename $SCRIPT_DIR`

npx hardhat run --network localhost scripts/deploys/plasma/$DIRECTORY/01-oracle/01-pt-oracle.ts

npx hardhat run --network localhost scripts/deploys/plasma/$DIRECTORY/02-vault/01-add-adapter.ts
npx hardhat run --network localhost scripts/deploys/plasma/$DIRECTORY/02-vault/02-remove-adapter.ts

