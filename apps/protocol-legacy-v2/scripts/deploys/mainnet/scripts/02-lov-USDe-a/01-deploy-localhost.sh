#!/bin/bash

set -x
set -e

npx hardhat run --network localhost scripts/deploys/mainnet/02-lov-USDe-a/01-swappers/01-direct-dex-swapper.ts

npx hardhat run --network localhost scripts/deploys/mainnet/02-lov-USDe-a/02-vault/01-borrow-lend.ts
npx hardhat run --network localhost scripts/deploys/mainnet/02-lov-USDe-a/02-vault/02-vault.ts
npx hardhat run --network localhost scripts/deploys/mainnet/02-lov-USDe-a/02-vault/03-manager.ts
npx hardhat run --network localhost scripts/deploys/mainnet/02-lov-USDe-a/02-vault/04-grant-overlord-access.ts
npx hardhat run --network localhost scripts/deploys/mainnet/02-lov-USDe-a/02-vault/05-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/mainnet/02-lov-USDe-a/03-access/01-swappers.ts
npx hardhat run --network localhost scripts/deploys/mainnet/02-lov-USDe-a/03-access/02-vault.ts
