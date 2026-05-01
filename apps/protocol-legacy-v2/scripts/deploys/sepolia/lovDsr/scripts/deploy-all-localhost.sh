#!/bin/bash

set -x
set -e

npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/01-external/01-dai-token.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/01-external/02-sdai-token.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/01-external/03-usdc-token.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/01-external/04-dai-usd-oracle.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/01-external/05-usdc-usd-oracle.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/01-external/06-eth-usd-oracle.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/01-external/99-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/02-core/01-circuit-breaker-proxy.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/02-core/02-token-prices.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/02-core/03-swapper.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/02-core/99-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/03-ovUsdc/01-idle-strategy-manager.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/03-ovUsdc/02-iUsdc-debt-token.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/03-ovUsdc/03-oUsdc-token.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/03-ovUsdc/04-ovUsdc-token.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/03-ovUsdc/05-supply-manager.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/03-ovUsdc/06-cb-usdc-borrow.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/03-ovUsdc/07-cb-oUsdc-exit.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/03-ovUsdc/08-global-ir-model.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/03-ovUsdc/09-rewards-minter.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/03-ovUsdc/10-lending-clerk.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/03-ovUsdc/11-aave-v3-idle-strategy.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/03-ovUsdc/99-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/04-lovDsr/01a-dai-usd-oracle.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/04-lovDsr/01b-iusdc-usd-oracle.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/04-lovDsr/01c-dai-iusdc-oracle.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/04-lovDsr/02-lovDsr.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/04-lovDsr/03-lovDsr-manager.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/04-lovDsr/04-lovDsr-ir-model.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/04-lovDsr/99-post-deploy.ts

npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/99-access/01-grant-overlord-access.ts
npx hardhat run --network localhost scripts/deploys/sepolia/lovDsr/99-access/99-update-ownership.ts
