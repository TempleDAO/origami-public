#!/bin/bash

set -x
set -e

SCRIPT_DIR=`dirname $0`
DIRECTORY=`basename $SCRIPT_DIR`

npx hardhat run --network localhost scripts/deploys/berachain/$DIRECTORY/01-swappers/01-direct-dex-swapper.ts

npx hardhat run --network localhost scripts/deploys/berachain/$DIRECTORY/02-oracles/01-ibgt-wbera-oracle.ts
npx hardhat run --network localhost scripts/deploys/berachain/$DIRECTORY/02-oracles/02-oribgt-wbera-oracle.ts

npx hardhat run --network localhost scripts/deploys/berachain/$DIRECTORY/03-vault/01-borrow-lend.ts
npx hardhat run --network localhost scripts/deploys/berachain/$DIRECTORY/03-vault/02-vault.ts
npx hardhat run --network localhost scripts/deploys/berachain/$DIRECTORY/03-vault/03-manager.ts
npx hardhat run --network localhost scripts/deploys/berachain/$DIRECTORY/03-vault/04-grant-overlord-access.ts
npx hardhat run --network localhost scripts/deploys/berachain/$DIRECTORY/03-vault/05-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/berachain/$DIRECTORY/04-access/01-vault.ts

npx hardhat run --network localhost scripts/deploys/berachain/$DIRECTORY/05-seed/01-seed-deposit.ts
