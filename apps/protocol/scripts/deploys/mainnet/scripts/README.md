# Localhost Deploy Testing

## To Run Tests

Localhost testing uses a local forked anvil node.
After each successful script, it takes a snapshot up to that point
When re-run, it rehydrates that snapshot.

1. In one terminal: `anvil --hardfork cancun --fork-url https://eth-mainnet.g.alchemy.com/v2/XXX --fork-block-number 19579625 --timestamp 1712197600`
   1. Replacing `XXX` for your api key
2. In another terminal: `./scripts/deploys/mainnet/scripts/run-all.sh`

In order to re-run from scratch without the sanpshot, simply remove the `anvil.snapshot` file

## Adding a new test

1. Copy an existing vault directory to a new dir - eg `cp -r 02-lov-USDe-a 07-lov-USDe-b`
2. Remove the `anvil.snapshot`, eg `07-lov-USDe-b/anvil.snapshot`
3. Update the `01-deploy-localhost.sh` deploy script to run the hardhat deploy scripts for that vault.
4. Update the `02-verify-localhost.ts` to do the required tests for that vault.
5. Add the new directory to `./run-all.sh`, eg add a new line: `deploy_and_test scripts/deploys/mainnet/scripts/07-lov-USDe-b`
