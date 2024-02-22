# Origami Contracts v2

## Getting Started

### Submodules

Some tests are written in forge, which uses [git submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules) for std libs.
Initialise those submodules with:

```bash
git submodule update --init --recursive
```

### Requirements

* node
* yarn
* [Foundry](https://book.getfoundry.sh/getting-started/installation)

This repository uses `.nvmrc` to dictate the version of node required to compile and run the project. This will allow you to use `nvm` followed by either `nvm use` or `nvm install` to automatically set the right version of node in that terminal session.

This project uses yarn workspaces to share common dependencies between all the applications. Before attempting to run any of the apps, you'll want to run `yarn install` from the root of the project.

### Build And Test

Origami mostly uses Foundry for development and testing, with some legacy tests still in Hardhat.

Copy `env.sample` to `.env` and tweak the `MAINNET_RPC_URL` and `ETHERSCAN_API_KEY` (signup for a free acount on both to generate an API key)

#### Foundry

```bash
# Compile the contracts
forge build

# Run tests, no deployment neccessary
forge test
```

For invariant (aka property or stateful fuzz) tests, there are a couple of options:

```bash
# For a single run of pre-defined runs
yarn forge-invariant:lite

# Run over and over until it fails (infinite loop)
yarn forge-invariant:untilfail
```

#### Hardhat

```bash
# Compile the contracts
yarn compile

# Run tests, no deployment neccessary
yarn test
```

## Code Coverage

### Hardhat

```bash
yarn coverage
open coverage/index.html
```

### Foundry

Note: Foundry coverage has bugs where it doesn't report coverage accurately for some cases. The repo strives for 100% coverage (even though the metrics reported may not reflect this)

```bash
yarn forge-coverage-html
open report/index.html
```

1. Install `slither-analyzer`:
   1. `pip3 install -r slither.requirements.txt`
2. `yarn slither`
3. For each category + finding, analyse and either:
   1. Fix the issue or
   2. If it's a false positive then ignore the finding by typing the list index number in the triage.

## Slither Static Code Analysis

1. Install `slither-analyzer`:
   1. `pip3 install -r slither.requirements.txt`
2. `yarn slither`
3. For each category + finding, analyse and either:
   1. Fix the issue or
   2. If it's a false positive then ignore the finding by typing the list index number in the triage.

## VSCode Testing

https://hardhat.org/guides/vscode-tests.html

tl;dr;

  1. Install https://marketplace.visualstudio.com/items?itemName=hbenl.vscode-mocha-test-adapter
  2. Set the VSCode config value `"mochaExplorer.files": "test/**/*.{j,t}s"`
  3. Reload VSCode, click the flask icon, see all tests :)

### Local Forks

#### 1. GMX

```bash
# In one terminal window, run a local node forked off mainnet
yarn local-fork:arbitrum

# In another window, run the deploy script
yarn local-fork:deploy:gmx

# Then finally some forked arbi mainnet tests for GMX
yarn local-fork:test:gmx
```