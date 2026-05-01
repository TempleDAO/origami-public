# Allocation algorithms and worked examples

This document details the proportional allocation used in join/exit and demonstrates a full, step-by-step example (including rounding/dust). It also shows a capacity-aware max example.

Notation:

- Combined vectors are indexed over the vault’s combined token lists.
- Per-adapter vectors are indexed over each adapter’s local token lists and mapped to combined indices via adapterToCombinedIndexMap.

Key implementation references:

- _allocateAcrossAdapters(...)
- _allocateToAdapter(...)
- _balanceSheetPerGroup(...)

## 1) Worked example — proportional join allocation

Tokens (combined order):

- Assets: [A1, A2]
- Liabilities: [L1, L2]

Adapters and their local-to-combined index maps:

- Adapter1
  - assetsLocal: [A1] → combined index 0
  - liabilitiesLocal: [L1] → combined index 0
- Adapter2
  - assetsLocal: [A1] → 0
  - liabilitiesLocal: [L2] → 1
- Adapter3
  - assetsLocal: [A2] → 1
  - liabilitiesLocal: [L1] → 0

Pre-join combined balances:

- Assets: [A1: 1,500; A2: 600]
- Liabilities: [L1: 900; L2: 300]

Per-adapter pre-join balances:

- Adapter1:  assets [A1: 500]; liabilities [L1: 300]
- Adapter2:  assets [A1: 1,000]; liabilities [L2: 300]
- Adapter3:  assets [A2: 600]; liabilities [L1: 600]

User join delta (combinedAllocations at start):

- Assets: [A1: 300; A2: 150]
- Liabilities: [L1: 90; L2: 60]

Proportional allocation (per adapter, per token), using floor rounding and running remainders.

Assets A1 (combinedAllocation=300, combinedBalance=1,500):

1) Adapter1 holds 500:
   alloc1 = floor(300 * 500 / 1,500) = 100
   Update: combinedAllocation:=200; combinedBalance:=1,000
2) Adapter2 holds 1,000 (equals remaining combinedBalance):
   alloc2 = 200 (last holder gets all remaining)
Result for A1: Adapter1 +100, Adapter2 +200

Assets A2 (combinedAllocation=150, combinedBalance=600):

- Adapter3 holds 600 (equals combinedBalance):
  alloc3 = 150
Result for A2: Adapter3 +150

Liabilities L1 (combinedAllocation=90, combinedBalance=900):

1) Adapter1 holds 300:
   alloc1 = floor(90 * 300 / 900) = 30
   Update: combinedAllocation:=60; combinedBalance:=600
2) Adapter3 holds 600 (equals remaining):
   alloc3 = 60
Result for L1: Adapter1 +30, Adapter3 +60

Liabilities L2 (combinedAllocation=60, combinedBalance=300):

- Adapter2 holds 300 (equals remaining):
  alloc2 = 60
Result for L2: Adapter2 +60

Final per-adapter join call vectors:

- Adapter1: assets [A1: 100], liabilities [L1: 30]
- Adapter2: assets [A1: 200], liabilities [L2: 60]
- Adapter3: assets [A2: 150], liabilities [L1: 60]

Sanity checks:

- Sum per token equals user delta.
- Rounding dust (if any) is absorbed by the last adapter for that token automatically (via the “equals remaining” fast-path).

### Dust example (single-token)

Let combined A1 delta be 333 (instead of 300), combined A1 balance still 1,500:

- Adapter1 (500): floor(333*500/1500) = 111; remainder becomes 222
- Adapter2 (1,000 equals remaining balance): takes the remaining 222
Totals 111 + 222 = 333 (no off-by-one).

## 2) Worked example — proportional exit allocation

The exit math is symmetric. Suppose the user requests to exit:

- Assets delta: [A1: 120; A2: 60]
- Liabilities delta: [L1: 45; L2: 30]

Using the same pre-exit balances as above, proportions are identical (just withdraw/repay instead of supply/borrow):

- Adapter1: assets [A1: 40], liabilities [L1: 15]
- Adapter2: assets [A1: 80], liabilities [L2: 30]
- Adapter3: assets [A2: 60], liabilities [L1: 30]

Again, any rounding dust is consumed by the last adapter holding each token.

## 3) Worked example — capacity-aware maxJoin (groups)

Assume one asset token T with three adapters, where Adapter1 and Adapter3 share the same underlying market (same groupId), Adapter2 is a different market:

- Current balances of T:
  - Adapter1: 3,000
  - Adapter2: 7,000
  - Adapter3: 5,000
- Combined total: 15,000
- Group totals:
  - Group A (Adapter1 + Adapter3): 8,000
  - Group B (Adapter2): 7,000

Underlying market capacities (for T):

- Group A cap for T: 100
- Group B cap for T: 250

For each adapter A in token T:

- candidate(A) = adapterFn(A,T) scaled by combinedTotal[T] / groupTotal[group(A),T]
  - For Adapter1 (Group A):
    candidate1 = 100 * 15,000 / 8,000 = 187.5
  - For Adapter3 (Group A):
    candidate3 = 100 * 15,000 / 8,000 = 187.5
  - For Adapter2 (Group B):
    candidate2 = 250 * 15,000 / 7,000 ≈ 535.71

Vault-level maxJoin for T = min(candidate1, candidate3, candidate2) = 187.5

Interpretation:

- Even though Adapter2 alone can accept more, the group-shared cap on Group A constrains the portfolio.
- When applying this limit across multiple tokens, take the per-token minima independently.

Notes:

- The above outlines the scaling idea; the exact per-adapter f(A,T) is read from each adapter’s maxJoin() vector for its local tokens and then mapped to combined indices before taking minima.
