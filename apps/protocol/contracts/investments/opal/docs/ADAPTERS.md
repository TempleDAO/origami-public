# OPAL Adapters

All adapters:

- Inherit OpalAdapterBase (which itself inherits OrigamiBundlerPluginCore) and implement IOpalAdapter (+ protocol-specific interfaces).
- Are deployed as Solady minimal clones with immutable args. Immutable args are read at runtime via ClonesImmutableReader.
- Are Bundler Plugins; withApprovedBundler enforces only the manager can invoke actions.
- Expose:
  - tokens(): per-adapter asset/liability token lists,
  - balanceSheet(): per-adapter balances,
  - maxJoin()/maxExit(): per-adapter capacity estimates,
  - join()/exit(): per-adapter execution (called by manager),
  - risk metrics: currentLtv(), liquidationLtv(), healthFactor().

## Types

- SpotAssets
  - Tracks N asset tokens, no liabilities; simple transfer-in/out behavior.
- Aave V3
  - N collateral tokens, 1 debt token. Admin can set EMODE, referral, collateral usage flags; join/exit supply/borrow or repay/withdraw.
- Morpho
  - Single market (1 collateral, 1 debt) with protocol callbacks; join/exit supply/borrow and repay/withdraw; supports loan utilization and LTV constraints.

## Solady clone and immutable storage

- OpalAdapterFactory.clone(impl, manager, description, immutableArgs):
  - manager and description are encoded into immutable args.
  - Protocol-specific params are also encoded (e.g., Aave pool addresses provider, tokens).
- Immutable args advantages:
  - Gas-efficient deployment, no constructor storage.
  - Instance-specific configuration without persistent writes.

## Access control

- withApprovedBundler restricts all adapter actions (join/exit, supply/withdraw/borrow/repay, etc.) to the manager.
- Elevated-access administration (e.g., setDeprecated, parameter updates) remains under the project’s governance roles.

## Appendix A: Adapter types (high‑level)

- Aave V3 adapter (OpalAdapterAaveV3)
  - Multiple collateral tokens, one debt token.
  - Immutable args include: pool address provider, loan token, dToken, packed collateral/aToken pairs, referral code.
  - Admin: updateAavePool, set EMODE category, set collateral usage flags, set max loan utilization ratio on join.

- Morpho adapter (OpalAdapterMorpho)
  - Single market (1 collateral, 1 debt), immutable args include morpho address, oracle, IRM, marketId, lltv.
  - Admin: setMaxSafeLtv, set max loan utilization ratio on join.
  - Uses Morpho callbacks with bundler reentry for certain flows.

- Spot Assets adapter (OpalAdapterSpotAssets)
  - Tracks N asset tokens, no liabilities.
  - Simple join/exit transfers and balance reporting.
