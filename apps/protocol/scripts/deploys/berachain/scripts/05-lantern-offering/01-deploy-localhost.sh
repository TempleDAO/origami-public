#!/bin/bash

set -x
set -e

npx hardhat run --network localhost scripts/deploys/berachain/05-lantern-offering/01-deploy.ts
npx hardhat run --network localhost scripts/deploys/berachain/05-lantern-offering/03-registrations.ts
npx hardhat run --network localhost scripts/deploys/berachain/05-lantern-offering/04-access.ts
