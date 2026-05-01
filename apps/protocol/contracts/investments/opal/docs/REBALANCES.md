# OPAL Rebalances

OPAL leverages the general Bundler/Plugin framework:

- OPAL Manager is an Origami Bundler:
  - OpalManager inherits OrigamiBundler but exposes multicall only to Elevated Access.
  - Used for permissioned rebalances and maintenance.
- OPAL Adapters are Origami Bundler Plugins:
  - OpalAdapterBase inherits OrigamiBundlerPluginCore; adapters enforce withApprovedBundler (the manager).
- An OPAL multicall can run both:
  - call adapter plugin actions (supply/withdraw/borrow/repay),
  - call other approved plugins (EntryPoint, KyberSwap, TBS V1/V2, Flashloan),
  - execute complex atomic sequences with controlled reentrancy via callback hash (Bundler3 pattern).

This is the bridge between “OPAL Manager/Adapters” and the general “Bundler/Plugins” ecosystem. See [Bundler README](../../../common/bundler/README.md) for plugin model, reentry, and approval patterns. In OPAL:

- Adapters are Bundler Plugins (via OpalAdapterBase -> OrigamiBundlerPluginCore).
- The Manager is a permissioned Bundler specialized for a single vault.

Reentry and safety:

- Bundler uses an expected callback hash to constrain reentry paths; plugins set reenterHash for nested flows (e.g., flashloans).
- Manager can compose multi-plugin, atomic sequences while preserving least privilege: only approved plugins can be called.

## `Bundler Plugins` vs `OPAL Adapters`

Bundler Plugin deployments:

- Are meant to be shared for different use cases and generic.
- They are stateless.
- So if there are left over tokens at the end, or they need tokens at the start, then the caller (ie a hOHM zap) needs to create a bundle that uses [erc20Transfer](../../../common/bundler/plugins/OrigamiBundlerPluginCore.sol) first (as an example)

OPAL Adapter deployments:

- Are for single purposes. So an opal manager will have multiple adapters (some active/some inactive over time)
- A given adapter deployment will never be used in more than one manager (since it's added via a factory addAdapter on the opal manager)
- So it represents 'a single position', eg a position in a Aave for specific immutable tokens.
- If those tokens need to change, then a new adapter is added, a bundle to migrate, then old adapter is removed.
