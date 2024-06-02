#!/bin/bash

set -x
set -e

npx hardhat run --network localhost scripts/deploys/mainnet/05-lov-wstETH-a/01-oracles/01-steth-weth-oracle.ts
npx hardhat run --network localhost scripts/deploys/mainnet/05-lov-wstETH-a/01-oracles/02-wsteth-weth-oracle.ts

npx hardhat run --network localhost scripts/deploys/mainnet/05-lov-wstETH-a/02-flashloan-providers/01-spark-flashloan-provider.ts

npx hardhat run --network localhost scripts/deploys/mainnet/05-lov-wstETH-a/03-vault/01-vault.ts
npx hardhat run --network localhost scripts/deploys/mainnet/05-lov-wstETH-a/03-vault/02-borrow-lend.ts
npx hardhat run --network localhost scripts/deploys/mainnet/05-lov-wstETH-a/03-vault/03-manager.ts
npx hardhat run --network localhost scripts/deploys/mainnet/05-lov-wstETH-a/03-vault/04-grant-overlord-access.ts
npx hardhat run --network localhost scripts/deploys/mainnet/05-lov-wstETH-a/03-vault/05-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/mainnet/05-lov-wstETH-a/04-access/01-oracles.ts
npx hardhat run --network localhost scripts/deploys/mainnet/05-lov-wstETH-a/04-access/02-vault.ts
