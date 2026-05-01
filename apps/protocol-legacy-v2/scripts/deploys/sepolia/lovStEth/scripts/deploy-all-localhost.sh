#!/bin/bash

set -x
set -e

npx hardhat run --network localhost scripts/deploys/sepolia/lovStEth/01-external/01-weth-token.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovStEth/01-external/02-steth-token.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovStEth/01-external/03-wsteth-token.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovStEth/01-external/04-steth-eth-oracle.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovStEth/01-external/05-eth-usd-oracle.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovStEth/01-external/99-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/sepolia/lovStEth/02-core/01-token-prices.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovStEth/02-core/02-swapper.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovStEth/02-core/03-flashloan-provider.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovStEth/02-core/99-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/sepolia/lovStEth/03-lovStEth/01a-steth-eth-oracle.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovStEth/03-lovStEth/01b-wsteth-eth-oracle.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovStEth/03-lovStEth/02-borrow-lend.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovStEth/03-lovStEth/03-lovStEth.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovStEth/03-lovStEth/04-lovStEth-manager.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovStEth/03-lovStEth/99-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/sepolia/lovStEth/99-access/01-grant-overlord-access.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovStEth/99-access/99-update-ownership.ts
