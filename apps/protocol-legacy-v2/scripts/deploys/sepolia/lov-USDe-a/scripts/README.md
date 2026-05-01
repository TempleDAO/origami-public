# Localhost Deploy Testing

1. Follow the instructions in `scripts/deploys/sepolia/lov-sUSDe-a/scripts/README.md` first
2. In another terminal, run: `scripts/deploys/sepolia/lov-USDe-a/scripts/deploy-all-localhost.sh`
3. Then run: `npx hardhat run --network localhost scripts/deploys/sepolia/lov-USDe-a/scripts/verify-deploy-localhost.ts`
