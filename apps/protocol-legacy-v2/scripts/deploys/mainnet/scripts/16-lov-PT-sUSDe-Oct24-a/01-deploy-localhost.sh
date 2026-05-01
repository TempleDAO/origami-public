#!/bin/bash

set -x
set -e

npx hardhat run --network localhost scripts/deploys/mainnet/16-lov-PT-sUSDe-Oct24-a/01-oracles/01-pt-susde-oct24-usde-oracle.ts
npx hardhat run --network localhost scripts/deploys/mainnet/16-lov-PT-sUSDe-Oct24-a/01-oracles/02-dai-usd-oracle.ts
npx hardhat run --network localhost scripts/deploys/mainnet/16-lov-PT-sUSDe-Oct24-a/01-oracles/03-pt-susde-oct24-dai-oracle.ts

npx hardhat run --network localhost scripts/deploys/mainnet/16-lov-PT-sUSDe-Oct24-a/02-swappers/01-pendle-swapper.ts

npx hardhat run --network localhost scripts/deploys/mainnet/16-lov-PT-sUSDe-Oct24-a/03-vault/01-borrow-lend.ts
npx hardhat run --network localhost scripts/deploys/mainnet/16-lov-PT-sUSDe-Oct24-a/03-vault/02-vault.ts
npx hardhat run --network localhost scripts/deploys/mainnet/16-lov-PT-sUSDe-Oct24-a/03-vault/03-manager.ts
npx hardhat run --network localhost scripts/deploys/mainnet/16-lov-PT-sUSDe-Oct24-a/03-vault/04-grant-overlord-access.ts
npx hardhat run --network localhost scripts/deploys/mainnet/16-lov-PT-sUSDe-Oct24-a/03-vault/05-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/mainnet/16-lov-PT-sUSDe-Oct24-a/04-access/01-swappers.ts
npx hardhat run --network localhost scripts/deploys/mainnet/16-lov-PT-sUSDe-Oct24-a/04-access/02-vault.ts
