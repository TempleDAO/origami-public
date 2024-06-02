#!/bin/bash

set -x
set -e

npx hardhat run --network localhost scripts/deploys/sepolia/lov-sUSDe-a/01-external/01-dai-token.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lov-sUSDe-a/01-external/02-usde-token.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lov-sUSDe-a/01-external/03-susde-token.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lov-sUSDe-a/01-external/04-usde-usd-oracle.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lov-sUSDe-a/01-external/05-susde-usd-oracle.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lov-sUSDe-a/01-external/06a-morpho.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lov-sUSDe-a/01-external/06b-morpho-irm.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lov-sUSDe-a/01-external/06c-morpho-oracle.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lov-sUSDe-a/01-external/99-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/sepolia/lov-sUSDe-a/02-core/01-token-prices.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lov-sUSDe-a/02-core/02-swapper.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lov-sUSDe-a/02-core/99-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/sepolia/lov-sUSDe-a/03-lov-sUSDe/01a-usde-dai-oracle.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lov-sUSDe-a/03-lov-sUSDe/01b-susde-dai-oracle.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lov-sUSDe-a/03-lov-sUSDe/02-borrow-lend.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lov-sUSDe-a/03-lov-sUSDe/03-lov-sUSDe.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lov-sUSDe-a/03-lov-sUSDe/04-lov-sUSDe-manager.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lov-sUSDe-a/03-lov-sUSDe/99-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/sepolia/lov-sUSDe-a/99-access/01-grant-overlord-access.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lov-sUSDe-a/99-access/99-update-ownership.ts
