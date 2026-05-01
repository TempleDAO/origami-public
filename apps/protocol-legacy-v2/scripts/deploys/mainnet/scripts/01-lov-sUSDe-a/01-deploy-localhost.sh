#!/bin/bash

set -x
set -e

npx hardhat run --network localhost scripts/deploys/mainnet/01-lov-sUSDe-a/01-core/01-token-prices.ts
npx hardhat run --network localhost scripts/deploys/mainnet/01-lov-sUSDe-a/01-core/02-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/mainnet/01-lov-sUSDe-a/02-oracles/01-usde-dai-oracle.ts
npx hardhat run --network localhost scripts/deploys/mainnet/01-lov-sUSDe-a/02-oracles/02-susde-dai-oracle.ts

npx hardhat run --network localhost scripts/deploys/mainnet/01-lov-sUSDe-a/03-swappers/01-erc4626-dex-swapper.ts

npx hardhat run --network localhost scripts/deploys/mainnet/01-lov-sUSDe-a/04-vault/01-borrow-lend.ts
npx hardhat run --network localhost scripts/deploys/mainnet/01-lov-sUSDe-a/04-vault/02-vault.ts
npx hardhat run --network localhost scripts/deploys/mainnet/01-lov-sUSDe-a/04-vault/03-manager.ts
npx hardhat run --network localhost scripts/deploys/mainnet/01-lov-sUSDe-a/04-vault/04-grant-overlord-access.ts
npx hardhat run --network localhost scripts/deploys/mainnet/01-lov-sUSDe-a/04-vault/05-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/mainnet/01-lov-sUSDe-a/05-access/01-core.ts
npx hardhat run --network localhost scripts/deploys/mainnet/01-lov-sUSDe-a/05-access/02-oracles.ts
npx hardhat run --network localhost scripts/deploys/mainnet/01-lov-sUSDe-a/05-access/03-swappers.ts
npx hardhat run --network localhost scripts/deploys/mainnet/01-lov-sUSDe-a/05-access/04-vault.ts
