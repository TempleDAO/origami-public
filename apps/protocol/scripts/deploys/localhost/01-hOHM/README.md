# hOHM Local Fork Setup

(1) Start anvil in one terminal:

```bash
anvil --fork-url $MAINNET_RPC_URL --fork-block-number 22122191 --auto-impersonate --disable-code-size-limit
```

Notes on flags:

1. `--auto-impersonate` is required to impersonate different accounts
2. `--disable-code-size-limit` is required to allow contracts with a larger bytecode size (MonoCooler is large - Olympus turn optimisations down to make the bytecode smaller)

(2) Run the forge script which will update the state on that anvil local fork

```bash
forge script --fork-url http://localhost:8545 scripts/deploys/localhost/01-hOHM/01-deploy.sol --unlocked --code-size-limit 50000 --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --broadcast --gas-estimate-multiplier=200
```

Notes on flags:

1. `--unlocked` is required to impersonate broadcasting as other accounts (eg multisig, olympus etc)
2. `--code-size-limit` MonoCooler has high byte size (they change optimisation runs in their repo)
3. `--sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` is the first account in the anvil local fork -- some account with gas to fund.
4. `--gas-estimate-multiplier=200` The estimation was off for one of the transactions - the default gasLimit is 130 (1.3X) the estimate, this changes it to 2X the estimate.
