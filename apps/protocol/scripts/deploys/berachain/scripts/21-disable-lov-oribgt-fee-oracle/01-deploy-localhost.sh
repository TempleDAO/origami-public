#!/bin/bash

set -x
set -e

SCRIPT_DIR=`dirname $0`
DIRECTORY=`basename $SCRIPT_DIR`

npx hardhat run --network localhost scripts/deploys/berachain/$DIRECTORY/01-ibgt-wbera-oracle.ts
npx hardhat run --network localhost scripts/deploys/berachain/$DIRECTORY/02-update-lov-oribgt.ts
