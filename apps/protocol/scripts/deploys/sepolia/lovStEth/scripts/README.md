# Localhost Deploy Testing

1. Start `anvil` in a terminal
2. In another terminal, run: `scripts/deploys/sepolia/lovStEth/scripts/deploy-all-localhost.sh`
3. Then run: `npx hardhat run --network localhost scripts/deploys/sepolia/lovStEth/scripts/verify-deploy-localhost.ts`
