# Origami Contracts v0.1

## Getting Started

### Requirements

* node
* yarn

This repository uses `.nvmrc` to dictate the version of node required to compile and run the project. This will allow you to use `nvm` followed by either `nvm use` or `nvm install` to automatically set the right version of node in that terminal session.

This project uses yarn workspaces to share common dependencies between all the applications. Before attempting to run any of the apps, you'll want to run `yarn install` from the root of the project.

### Contracts

#### .env

Copy `env.sample` to `.env` and tweak the `MAINNET_RPC_URL` and `ETHERSCAN_API_KEY` (signup for a free acount on both to generate an API key)

#### Local Deployment

The protocol app uses hardhat for development. The following steps will compile the contracts and deploy to a local hardhat node

```bash
# Compile the contracts
yarn compile

# Generate the typechain.
yarn typechain

The protocol test suite can be run without deploying to a local-node by running

```bash
# Run tests, no deployment neccessary
yarn test
```

#### Local Forks

##### 1. GMX

```bash
# In one terminal window, run a local node forked off mainnet
yarn local-fork:arbitrum

# In another window, run the deploy script
yarn local-fork:deploy:gmx

# Then finally some forked arbi mainnet tests for GMX
yarn local-fork:test:gmx
```

## VSCode Testing

https://hardhat.org/guides/vscode-tests.html

tl;dr;

  1. Install https://marketplace.visualstudio.com/items?itemName=hbenl.vscode-mocha-test-adapter
  2. Set the VSCode config value `"mochaExplorer.files": "test/**/*.{j,t}s"`
  3. Reload VSCode, click the flask icon, see all tests :)

## Slither Static Code Analysis

1. Install `slither-analyzer`:
   1. v0.9.0 cannot handle events emitted from Solidity libraries: https://github.com/crytic/slither/issues/1407
   2. Until the following PR is merged and released, use this patched version: https://github.com/crytic/slither/pull/1419
   3. `pip install git+https://@github.com/crytic/slither.git@c15e88d94443cdfe33d238085453efab6609bf94#egg=slither-analyzer`
2. `yarn slither`
3. For each category + finding, analyse and either:
   1. Fix the issue or
   2. If it's a false positive then ignore the finding by typing the list index number in the triage.
