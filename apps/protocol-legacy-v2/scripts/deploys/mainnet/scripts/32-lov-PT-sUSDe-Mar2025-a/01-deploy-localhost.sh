#!/bin/bash

set -x
set -e

SCRIPT_DIR=`dirname $0`
DIRECTORY=`basename $SCRIPT_DIR`

npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-oracles/01-pt-susde-mar2025-usde-oracle.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-oracles/02-pt-susde-mar2025-dai-oracle.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-oracles/03-pt-susde-mar2025-discount-to-maturity.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/01-oracles/04-pt-susde-mar2025-dai-with-discount-to-maturity.ts

npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/01-borrow-lend.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/02-vault.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/03-manager.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/04-grant-overlord-access.ts
npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/02-vault/05-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/mainnet/$DIRECTORY/03-access/01-vault.ts
