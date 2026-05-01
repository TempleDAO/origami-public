# Origami Bundler

## Acknowledgements

The Origami Bundler is a fork of the Morpho Bundler3:

* [Overview](https://morpho.org/blog/introducing-bundler3/)
* [Audits](https://github.com/morpho-org/bundler3/tree/main/audits)
* [Github](https://github.com/morpho-org/bundler3)

The key differences in the `OrigamiBundler`:

1. Multiple `Bundler` instances:
   1. A single general use `OrigamiBundler` instance will be used for zaps (eg max buy hOHM by paying USDC) and other dapp/integration purposes
   1. Each [OPAL Vault Manager](../../investments/opal/README.md) is an instance of a Bundler (via inheritance) - used for specific vault rebalances and other operations on that vault.
1. Renamed Morpho 'Adapters' to be `Plugins`
1. A `Plugin` can be used by multiple (whitelisted) `Bundler` instances
1. A different set of `Plugin` functions. There are some overlaps (eg ERC20 transfer) but also some new integrations (eg OHM staking, Origami's Tokenized Balance Sheet Vault).

## Components

The **BUNDLER** is the entry point contract for an EOA (or contract) to call `multicall()` on with a list of declarative call steps.

The general use `OrigamiBundler`, `multicall()` is not permissioned. However other instances (including the `OPAL Vault Manager`) can override to make it permissioned.

The multicall takes a list of `Call` steps, which can execute any target contract with calldata. In general these `Call` steps will be to call a `Bundler Action` on one of Origami's `Plugin` deployments, eg:

* Transfer a pre-approved ERC20 token from the user to the `EntryPoint` plugin
* Stake OHM into gOHM via the `OhmStaking` plugin
* Swap a token via a Dex Aggregator (eg KyberSwap, 1")
* etc

However they can be on other contracts too - eg call `Permit2::permit()` so a user can allow (via a signature) the `EntryPoint` contract to pull tokens without an extra transaction for the user to execute before the multicall.

Each of the call steps will use `CALL` (not `DELEGATECALL`) on the requested `plugin` contract using the provided calldata.

## Trust Assumptions

It is assumed that the caller (bundle creator - eg the Origami dapp) crafts the calldata correctly and only calls trusted contracts through the Bundler. The caller signs this transaction.

There are extra precautions:

* Bundler instances may whitelist Plugins (or external contracts) that can be used by implementing `isApprovedPlugin()`
* Origami Plugins need to approve which Bundler instances can be used (via the `withApprovedBundler` modifier).
  * Within a given `multicall()`, only a single Bundler instance can be used
* Reentrancy is allowed, but controlled by the caller by specifying a hash for any reentered (ie nested) calls. This follows the same methodology as Morpho's Bundler3

It is the responsibility of the bundle creator to ensure no tokens/ETH are left in the plugins at the end of the multicall. For example if dust is left over, then it would be possible for another actor to create another multicall.

It is also the responsibility of the caller to check for slippage. The `EntryPoint` plugin actions have variants which transfer the entire balance and check for minimum amounts. This slippage check can be used at the very end of the bundle to ensure expected min amount of tokens after a series of complex actions.

## Plugins

All plugins inherit `OrigamiBundlerPluginCore` which:

1. Has logic to reenter the bundler for nested calls (eg flash loan callbacks)
1. Provides the `withApprovedBundler` modifier (see below)
1. Some builtin plugin functions which all plugins can use (eg `erc20Transfer()`)

All plugin operations MUST have the `withApprovedBundler` modifier which:

1. Ensures the `msg.sender` is an approved bundler only. A plugin may allow one or more approved bundlers (see `OrigamiBundlerPluginMultiAccess`)
2. Sets the bundler in use for the scope of that call for use when reentering. So in the flashloan example, when `_reenterBundle()` is called by the plugin, it will call bundler.reenter() where the bundler is transiently set for the scope of that flashloan.

Regardless of whether the above two features are required, `withApprovedBundler` should be used as it simplifies the security model (easy to spot 'plugin' functions), and prevents accidental issues (eg balances left over in the plugin and able to be captured directly)

It is technically possible for one of the multicall steps to NOT inherit `OrigamiBundlerPluginCore` and still be utilized. However again that's up to the caller to correctly construct the bundle.

## Reentry

A plugin is allowed to reenter the bundler for nested calls - such as a flash loan callback.

As an extra precaution, in order to ensure only expected reentrancy (eg if the callee is compromised), the caller provides a hash of any expected reentry multicall steps upfront.

## OPAL Manager is a BUNDLER

The [OpalManager](../../investments/opal/OpalManager.sol) contract is also an instance of a `Bundler`. It allows overlord to construct a multicall bundle (permissioned to Elevated Access only) in order to rebalance positions across adapters. In this case each of the [OPAL Adapters](../../investments/opal/adapters/OpalAdapterBase.sol) is a type of `Bundler Plugin`.

Example bundles would include:

1. An intra-rebalance -- eg increase/decrease the leverage within one `OPAL Adapter`
1. An inter-rebalance -- eg migrate some position from `OPAL Adapter A` to `OPAL Adapter B`

Bundles for OPAL can also include other (approved) plugin contract calls. These could be write operations, or could just be views, which revert if conditions aren't met.

For example checking that the adapter LTV is in a 'safe' can be added to the bundle (if not done in the underlying protocol). It could also check external contract state or vault state.

One check could be to verify the actual Balance Sheet amounts in the vault after the operation. The plugin can then atomically revert the entire bundle if the balance of a token is not within the expected range. Overlord would calculate the expected range offchain and provide that as the plugin input -- just like slippage.

## Plugin Action Catalog

* [Core](./plugins/OrigamiBundlerPluginCore.sol)
  * Base logic for all plugins
  * `erc20Transfer()`: Transfers a fixed amount of ERC20 tokens held by the plugin contract to a receiver
  * `erc20TransferBalance()`: Transfers the current balance of ERC20 tokens held by the plugin contract to a receiver.
* [MultiAccess](./plugins/OrigamiBundlerPluginMultiAccess.sol)
  * Allow plugins to be used by zero or more whitelisted Bundler instances
  * All general purpose plugins ([./plugins/*.sol](./plugins/)) will inherit this
* [EntryPoint](./plugins//OrigamiBundlerPluginEntryPoint.sol)
  * Intended as the single contract for end users to have to approve to pull tokens. Either by pre-approval or via Permit2
  * Native ETH is exclusively handled here, and intended to be wrapped to WETH before using in any other plugins
  * Each action has a `use balance` equivalent to use the amount of tokens currently held by the contract at execution time rather than having to know the exact amount in advance
* [OhmStaking](./plugins/OrigamiBundlerPluginOhmStaking.sol)
  * Swap `OHM` <=> `gOHM` using Olympus conversion contract
  * This is at a set rate, currently `269.238508004 OHM per gOHM`
* [TbsV1](./plugins/OrigamiBundlerPluginTbsV1.sol)
  * Join/Exit a V1 of Origami Tokenized Balance Sheet Vault
  * The only V1 instance deployed is [hOHM](https://origami.finance/collections/olympus-collection/1-0x1DB1591540d7A6062Be0837ca3C808aDd28844F6/info)
  * Known TBS vaults are whitelisted on the plugin contract for extra precaution.
* [TbsV2](./plugins/OrigamiBundlerPluginTbsV2.sol)
  * Join/Exit a V2 Origami Tokenized Balance Sheet (TBS) Vault
  * OPAL vaults and any others going forward are V2
  * The only difference is that V2 TBS have a `bytes32 tokensHash` representing the expected balance sheet tokens of the vault. These tokens can change over time so it's important to verify at runtime.
  * Known TBS vaults are whitelisted on the plugin contract for extra precaution.
* [KyberSwap](./plugins/OrigamiBundlerPluginKyberSwap.sol)
  * Execute a swap on the KyberSwap router V5.
  * `swap()` will execute that calldata directly on the router as is. The calldata is obtained offchain via the Kyber API first, and contains the recipient and the fixed amounts/tokens/etc.
  * `swapBalance()` will first scale the amounts in the calldata blob, using the [Kyber Scaling Helper](https://docs.kyberswap.com/kyberswap-solutions/kyberswap-aggregator/developer-guides/scaling-swap-calldata-with-scalehelper)
  * This can't deviate too much from the original quote, but allows amounts not exactly known until transaction runtime (due to previous bundle step slippage for example)
* [AaveV3Flash](./plugins/OrigamiBundlerPluginAaveV3Flash.sol)
  * Request a flashloan from one of the Aave v3 (or fork such as Spark) instances
  * The callback data contains the nested reentrancy, which must be abi encoded steps for `Bundler::reenter(Call[] calldata bundle)`
  * When using this flashloan action, the reenter hash must be provided on the multicall Step

## An Example Bundle

To show the power of this, we can enumerate the steps in order to zap `USDC` into the `hOHM` Tokenized Balance Sheet Vault.

Ordinarily to join() into hOHM, you provide gOHM collateral and receive USDS debt as well as the shares. This zap allows you to maximise the amount of shares you get, given the input token (eg USDC) and without receiving the USDS debt.

A foundry test of this example can be found in [OrigamiHOhmZap.t.sol](../../../test/foundry/unit/investments/olympus/OrigamiHOhmZap.t.sol)

* `1: [EntryPoint]`: Pull USDC zap amount in from the user into the `KyberSwap` plugin
  * Assumes here that the user has given allowance for EntryPoint to pull USDC - could be pre-approved or could use Permit2 in the bundle.
* `2: [KyberSwap]`: Swap USDC for OHM and send to the `OhmStaking` plugin
* `3: [AaveV3Flash]`: Flash an amount of WETH
  * This amount can be solved for, including slippage tolerance - the logic of that isn't included here
  * `3.1: [AaveV3Flash]`: Send the flashed WETH to the `KyberSwap` plugin
  * `3.2: [KyberSwap]`: Swap WETH for OHM and send to the `OhmStaking` plugin
  * `3.3: [OhmStaking]`: Stake all OHM (from `2` and `3.3`) into gOHM and send to the `TbsV1` plugin
  * `3.4: [TbsV1]`: Join hOHM and send hOHM shares + USDS to the `KyberSwap` plugin
    * Joining: plugin provides gOHM (collateral), receives minted hOHM shares and USDS (debt)
  * `3.5: [KyberSwap]`: Swap USDS to WETH and send to `AaveV3Flash`
  * Flashloan is now repaid - end of the `reenter()` callback
* `4: [AaveV3Flash]`: There may be some leftover WETH (slippage surplus)
  * So refund / take as service provider fee
* `5: [AaveV3Flash]`: Send all the hOHM shares to the user via `erc20TransferBalance()`
  * This can also check for an expected minimum amount (slippage)
