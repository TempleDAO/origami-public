#!/bin/bash

set -x
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
DIRECTORY="$(basename "$SCRIPT_DIR")"

npx hardhat run --network localhost scripts/deploys/plasma/$DIRECTORY/01-vault/01-vault.ts
npx hardhat run --network localhost scripts/deploys/plasma/$DIRECTORY/01-vault/02-manager.ts
npx hardhat run --network localhost scripts/deploys/plasma/$DIRECTORY/01-vault/03-post-deploy.ts
npx hardhat run --network localhost scripts/deploys/plasma/$DIRECTORY/01-vault/04-seed-vault.ts
npx hardhat run --network localhost scripts/deploys/plasma/$DIRECTORY/01-vault/05-grant-overlord-access.ts
npx hardhat run --network localhost scripts/deploys/plasma/$DIRECTORY/02-access/01-access.ts
