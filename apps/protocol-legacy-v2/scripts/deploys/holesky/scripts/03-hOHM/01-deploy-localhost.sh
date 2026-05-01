#!/bin/bash

set -x
set -e

SCRIPT_DIR=`dirname $0`
DIRECTORY=`basename $SCRIPT_DIR`

npx hardhat run --network localhost scripts/deploys/holesky/$DIRECTORY/01-core/01-token-prices.ts

npx hardhat run --network localhost scripts/deploys/holesky/$DIRECTORY/02-vault/01-vault.ts
npx hardhat run --network localhost scripts/deploys/holesky/$DIRECTORY/02-vault/02-manager.ts
npx hardhat run --network localhost scripts/deploys/holesky/$DIRECTORY/02-vault/03-sweep-swapper.ts
npx hardhat run --network localhost scripts/deploys/holesky/$DIRECTORY/02-vault/04-dummy-dex-router.ts
npx hardhat run --network localhost scripts/deploys/holesky/$DIRECTORY/02-vault/05-teleporter.ts
npx hardhat run --network localhost scripts/deploys/holesky/$DIRECTORY/02-vault/06-post-deploy.ts
npx hardhat run --network localhost scripts/deploys/holesky/$DIRECTORY/02-vault/07-seed-vault.ts
npx hardhat run --network localhost scripts/deploys/holesky/$DIRECTORY/02-vault/08-join-vault.ts
npx hardhat run --network localhost scripts/deploys/holesky/$DIRECTORY/02-vault/09-sweep.ts
npx hardhat run --network localhost scripts/deploys/holesky/$DIRECTORY/02-vault/10-setup-peers.ts

npx hardhat run --network localhost scripts/deploys/holesky/$DIRECTORY/03-access/01-vault.ts
