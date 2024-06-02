#!/bin/bash

set -x
set -e

npx hardhat run --network localhost scripts/deploys/sepolia/lov-USDe-a/01-external/06c-morpho-oracle.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lov-USDe-a/01-external/99-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/sepolia/lov-USDe-a/02-core/99-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/sepolia/lov-USDe-a/03-lov-USDe/01-borrow-lend.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lov-USDe-a/03-lov-USDe/03-lov-USDe.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lov-USDe-a/03-lov-USDe/04-lov-USDe-manager.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lov-USDe-a/03-lov-USDe/99-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/sepolia/lov-USDe-a/99-access/01-grant-overlord-access.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lov-USDe-a/99-access/99-update-ownership.ts
