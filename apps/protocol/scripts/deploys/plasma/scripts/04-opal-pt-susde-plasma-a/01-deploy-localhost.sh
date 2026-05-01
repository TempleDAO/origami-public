#!/bin/bash

set -x
set -e

SCRIPT_DIR=`dirname $0`
DIRECTORY=`basename $SCRIPT_DIR`

npx hardhat run --network localhost scripts/deploys/plasma/$DIRECTORY/01-oracle/01-pt-susde-9APR2026-usde-oracle.ts

npx hardhat run --network localhost scripts/deploys/plasma/$DIRECTORY/02-vault/01-vault.ts
npx hardhat run --network localhost scripts/deploys/plasma/$DIRECTORY/02-vault/02-manager.ts
npx hardhat run --network localhost scripts/deploys/plasma/$DIRECTORY/02-vault/03-post-deploy.ts
npx hardhat run --network localhost scripts/deploys/plasma/$DIRECTORY/02-vault/04-seed-vault.ts
npx hardhat run --network localhost scripts/deploys/plasma/$DIRECTORY/02-vault/05-grant-overlord-access.ts
npx hardhat run --network localhost scripts/deploys/plasma/$DIRECTORY/03-access/01-access.ts
