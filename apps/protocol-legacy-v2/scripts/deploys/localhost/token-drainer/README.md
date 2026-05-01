# hOHM Local Fork Setup

(1) Start anvil in one terminal:

```bash
anvil --fork-url $BERACHAIN_RPC_URL --fork-block-number 4986172 --auto-impersonate
```

Notes on flags:

1. `--auto-impersonate` is required to impersonate different accounts

(2) Run the forge script which will update the state on that anvil local fork

```bash
forge script --fork-url http://localhost:8545 scripts/deploys/localhost/token-drainer/01-TokenDrainer.sol --sig "run(address tokenAddress, address existingOwnerAddress, address newOwnerAddress, uint256 amount)" $TOKEN_ADDRESS $OLD_OWNER $NEW_OWNER --unlocked --broadcast --gas-estimate-multiplier=200
```

Notes on flags:

1. `$TOKEN_ADDRESS` is the address of the token you want to pull into your EOA, eg [0x98bdeede9a45c28d229285d9d6e9139e9f505391](https://berascan.com/token/0x98bdeede9a45c28d229285d9d6e9139e9f505391)
2. `$OLD_OWNER` is some address which has those tokens as of the block number.
   1. Check the current holders list, eg https://berascan.com/token/0x98bdeede9a45c28d229285d9d6e9139e9f505391#balances
   2. It's a good idea NOT to use a smart contract for this -- so find the first line item on the  which doesn't have the 📄 emoji on the left of the address. Sometimes unavoidable
3. `$NEW_OWNER` this is likely a test EOA which you have the private key for, that you want to use in metamask or whatever. Don't paste the private key anywhere!
4. `--unlocked` is required to impersonate broadcasting as other accounts (eg the old owner)
5. `--gas-estimate-multiplier=200` The bera gas estimation was off for one of the transactions - the default gasLimit is 130 (1.3X) the estimate, this changes it to 2X the estimate.

NOTE: If you see an error in anvil like:
`Error: Transaction rejected: Insufficient funds for gas * price + value`
Then you will need to run another anvil command first, to (force) deal the old address some ETH (eg it might be a smart contract)

```bash
cast rpc anvil_setBalance 0x781B4c57100738095222bd92D37B07ed034AB696 "100000000000000000"
```

An example:

```bash
anvil --fork-url $BERACHAIN_RPC_URL --fork-block-number 4986172 --auto-impersonate

forge script --fork-url http://localhost:8545 scripts/deploys/localhost/token-drainer/01-TokenDrainer.sol --sig "run(address tokenAddress, address existingOwnerAddress, address newOwnerAddress)" 0x98bdeede9a45c28d229285d9d6e9139e9f505391 0x781B4c57100738095222bd92D37B07ed034AB696 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045 --unlocked --broadcast --gas-estimate-multiplier=200
```

```log
== Logs ==
  Pulling 3937139077092364 KODI OHM-HONEY
  from 0x781B4c57100738095222bd92D37B07ed034AB696 to 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045
  ~-~-~-~-~-~-~-~-~-
  BEFORE
  Existing owner balance: 3937139077092364
  New owner balance: 0
  ~-~-~-~-~-~-~-~-~-
  ~-~-~-~-~-~-~-~-~-
  AFTER
  Existing owner balance: 0
  New owner balance: 3937139077092364
  ~-~-~-~-~-~-~-~-~-

## Setting up 1 EVM.

==========================

Chain 80094

Estimated gas price: 0.000000315 gwei

Estimated total gas used for script: 104326

Estimated amount required: 0.00000000003286269 BERA

==========================

##### berachain
✅  [Success] Hash: 0x00824781d4a72ad9bf61d78fd9751eabe65b4a0d2d00eaeef6c00abe5564203f
Block: 4986173
Paid: 0.00000000001502307 ETH (49095 gas * 0.000000306 gwei)

✅ Sequence #1 on berachain | Total Paid: 0.00000000001502307 ETH (49095 gas * avg 0.000000306 gwei)
```
