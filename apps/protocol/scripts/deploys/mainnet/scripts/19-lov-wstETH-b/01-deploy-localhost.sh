#!/bin/bash

set -x
set -e

npx hardhat run --network localhost scripts/deploys/mainnet/19-lov-wstETH-b/01-flashloan-providers/01-aave-v3-flashloan-provider.ts

npx hardhat run --network localhost scripts/deploys/mainnet/19-lov-wstETH-b/02-vault/01-vault.ts
npx hardhat run --network localhost scripts/deploys/mainnet/19-lov-wstETH-b/02-vault/02-borrow-lend.ts
npx hardhat run --network localhost scripts/deploys/mainnet/19-lov-wstETH-b/02-vault/03-manager.ts
npx hardhat run --network localhost scripts/deploys/mainnet/19-lov-wstETH-b/02-vault/04-grant-overlord-access.ts
npx hardhat run --network localhost scripts/deploys/mainnet/19-lov-wstETH-b/02-vault/05-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/mainnet/19-lov-wstETH-b/03-access/01-vault.ts
