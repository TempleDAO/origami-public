#!/bin/bash

set -x
set -e

npx hardhat run --network localhost scripts/deploys/bepolia/01-hOHM/01-hohm-bep-oft.ts
npx hardhat run --network localhost scripts/deploys/bepolia/01-hOHM/02-set-peers.ts
