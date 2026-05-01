# OpalManager

Core responsibilities:

- Registry of adapters (add/remove) with per-adapter token index maps into the combined token lists.
- Maintains combined assetTokens and liabilityTokens across all active adapters.
- Executes proportional allocations for join/exit.
- Computes capacity-aware maxJoin()/maxExit() with group-aware scaling.
- Acts as a permissioned Bundler (Elevated Access only) for rebalances and plugin interactions.

## Combined token sets and maps

- Combined arrays: assetTokens[], liabilityTokens[] (bounded by MAX_TOKENS = 10).
- Each adapter tracks local indices; the manager stores maps (local → combined index) for assets and liabilities.
- On adapter add/remove, the manager resyncs these maps.

## Proportional allocation (join/exit)

Implemented in:

- _allocateAcrossAdapters(...)
- _allocateToAdapter(...)

Algorithm (per token, per adapter):

- Start with combinedAllocations[T] (the aggregate delta) and combinedBalances[T] (aggregate current balance).
- For adapter A holding token T with adapterBalance[T]:
  - If combinedBalance[T] == 0 or adapterBalance[T] == 0 → allocate 0.
  - Else if adapterBalance[T] == combinedBalance[T] → allocate entire remaining combinedAllocations[T] (avoids rounding and ensures last holder absorbs dust).
  - Else allocate floor(combinedAllocations[T] * adapterBalance[T] / combinedBalance[T]).
- After each adapter:
  - Subtract the allocated amount from combinedAllocations[T].
  - Subtract adapterBalance[T] from combinedBalance[T].
- Result: exact sum equality, with “last adapter gets dust” by construction.

## Capacity-aware maxima (groups)

- Some adapters share an underlying market capacity (e.g., same Aave pool or Morpho market). Each adapter exposes groupId.
- Manager computes:
  - Combined totals (all adapters).
  - Per-group totals (summing only adapters with the same groupId).
- For a token T and adapter function f (maxJoin or maxExit):
  - Compute candidate = f(adapter A, T) scaled by combinedTotal[T] / groupTotal[T].
  - The vault-level maximum for T is the minimum of all candidates across adapters holding T.
- Intuition: prevents exceeding shared caps by scaling per-adapter capacity with group totals.
