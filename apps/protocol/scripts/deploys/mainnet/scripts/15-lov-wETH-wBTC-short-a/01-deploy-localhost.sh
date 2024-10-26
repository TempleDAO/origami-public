#!/bin/bash

set -x
set -e

npx hardhat run --network localhost scripts/deploys/mainnet/15-lov-wETH-wBTC-short-a/01-vault/01-borrow-lend.ts
npx hardhat run --network localhost scripts/deploys/mainnet/15-lov-wETH-wBTC-short-a/01-vault/02-vault.ts
npx hardhat run --network localhost scripts/deploys/mainnet/15-lov-wETH-wBTC-short-a/01-vault/03-manager.ts
npx hardhat run --network localhost scripts/deploys/mainnet/15-lov-wETH-wBTC-short-a/01-vault/04-grant-overlord-access.ts
npx hardhat run --network localhost scripts/deploys/mainnet/15-lov-wETH-wBTC-short-a/01-vault/05-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/mainnet/15-lov-wETH-wBTC-short-a/02-access/01-vault.ts
