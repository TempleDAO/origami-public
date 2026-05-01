#!/bin/bash

set -x
set -e

npx hardhat run --network localhost scripts/deploys/mainnet/18-lov-USD0++-a/01-oracles/01-usd0++-usd0-oracle.ts
npx hardhat run --network localhost scripts/deploys/mainnet/18-lov-USD0++-a/01-oracles/02-usd0++-usdc-oracle.ts
npx hardhat run --network localhost scripts/deploys/mainnet/18-lov-USD0++-a/01-oracles/03-usd0-usdc-oracle.ts

npx hardhat run --network localhost scripts/deploys/mainnet/18-lov-USD0++-a/02-vault/01-borrow-lend.ts
npx hardhat run --network localhost scripts/deploys/mainnet/18-lov-USD0++-a/02-vault/02-vault.ts
npx hardhat run --network localhost scripts/deploys/mainnet/18-lov-USD0++-a/02-vault/03-manager.ts
npx hardhat run --network localhost scripts/deploys/mainnet/18-lov-USD0++-a/02-vault/04-grant-overlord-access.ts
npx hardhat run --network localhost scripts/deploys/mainnet/18-lov-USD0++-a/02-vault/05-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/mainnet/18-lov-USD0++-a/03-access/01-oracles.ts
npx hardhat run --network localhost scripts/deploys/mainnet/18-lov-USD0++-a/03-access/02-vault.ts
