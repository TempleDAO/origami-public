#!/bin/bash

set -x
set -e

SCRIPT_DIR=`dirname $0`
DIRECTORY=`basename $SCRIPT_DIR`

npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-core/01-token-prices.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-core/03-map-existing-tokens.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-core/04-update-references.ts

npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/01-vault.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/02-manager.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/03-sweep-swapper.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/04-teleporter.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/05-post-deploy.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/06-grant-overlord-access.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/06b-temp-cooler-setup.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/07-setup-peers.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/08-seed-vault.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/09-migrator.ts

npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/03-access/01-core.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/03-access/02-vault.ts
