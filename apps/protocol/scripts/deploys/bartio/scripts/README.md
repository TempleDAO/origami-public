# Localhost Deploy Testing

## NEW FROM 18-lov-USD0++ onwards

### To Run Tests

Each test deployment and script runs in isolation, and uses a local fork from a recent block on that chain.

It uses the [mainnet](../contract-addresses/mainnet.ts) addresses as a base, and then any NEW deployment addresses are expected to be added into the [address-overrides.ts](./18-lov-USD0++-a/address-overrides.ts) for that given test.

1. First run `./scripts/deploys/mainnet/scripts/$DEPLOY_SCRIPT_DIR/run.sh`
   1. eg: `./scripts/deploys/mainnet/scripts/18-lov-USD0++-a/run.sh`
   2. This will give the `anvil` command to run to reproduce the deploy and test, including the forked block
2. In one terminal, run that anvil command. eg for the `18-lov-USD0++-a` example, this is:
   1. `anvil --hardfork cancun --fork-url $MAINNET_RPC_URL --fork-block-number 20409660`
3. In another terminal, run step (1) again. This will:
   1. Deploy the contracts on the local forked anvil
   2. Run a test which invests/rebalances down/exits

### Adding a new test

1. Copy an existing vault scripts directory to a new dir - eg `cp -r ./scripts/deploys/mainnet/scripts/18-lov-USD0++-a ./scripts/deploys/mainnet/scripts/XX-lov-XXXX-a`
2. Update the `01-deploy-localhost.sh` deploy script to run the hardhat deploy scripts for that vault.
   1. Deploy each one of these one by one and update `address-overrides.ts` for that address
3. Update the `02-verify-localhost.ts` to do the required tests for that vault.
4. Update the `run.sh` to set the expected block number and any other required anvil parameters.

Finally verify it all works as expected as if you were running the test from scratch.

## DEPRECATED before 18-lov-USD0++

### To Run Tests

Localhost testing uses a local forked anvil node.
After each successful script, it takes a snapshot up to that point
When re-run, it rehydrates that snapshot.

1. In one terminal: `anvil --hardfork cancun --fork-url $MAINNET_RPC_URL --fork-block-number 20071530 --timestamp 1718144505 --no-request-size-limit`
   1. Replacing `XXX` for your api key
2. In another terminal: `./scripts/deploys/mainnet/scripts/run-all.sh`

In order to re-run from scratch without the sanpshot, simply remove the `anvil.snapshot` file

### Adding a new test

1. Copy an existing vault directory to a new dir - eg `cp -r 02-lov-USDe-a 07-lov-USDe-b`
2. Remove the `anvil.snapshot`, eg `07-lov-USDe-b/anvil.snapshot`
3. Update the `01-deploy-localhost.sh` deploy script to run the hardhat deploy scripts for that vault.
4. Update the `02-verify-localhost.ts` to do the required tests for that vault.
5. Add the new directory to `./run-all.sh`, eg add a new line: `deploy_and_test scripts/deploys/mainnet/scripts/07-lov-USDe-b`
