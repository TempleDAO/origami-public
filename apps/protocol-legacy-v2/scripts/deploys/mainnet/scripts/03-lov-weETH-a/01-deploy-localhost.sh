#!/bin/bash

set -x
set -e

npx hardhat run --network localhost scripts/deploys/mainnet/03-lov-weETH-a/01-oracles/01-weeth-weth-oracle.ts

npx hardhat run --network localhost scripts/deploys/mainnet/03-lov-weETH-a/02-vault/01-borrow-lend.ts
npx hardhat run --network localhost scripts/deploys/mainnet/03-lov-weETH-a/02-vault/02-vault.ts
npx hardhat run --network localhost scripts/deploys/mainnet/03-lov-weETH-a/02-vault/03-manager.ts
npx hardhat run --network localhost scripts/deploys/mainnet/03-lov-weETH-a/02-vault/04-grant-overlord-access.ts
npx hardhat run --network localhost scripts/deploys/mainnet/03-lov-weETH-a/02-vault/05-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/mainnet/03-lov-weETH-a/03-access/01-oracles.ts
npx hardhat run --network localhost scripts/deploys/mainnet/03-lov-weETH-a/03-access/02-vault.ts
