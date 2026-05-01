# OPAL docs

## What is OPAL and why does it exist?

OPAL (Origami Portfolio of Assets & Liabilities) is a tokenized balance‑sheet vault that issues a single ERC‑20 share representing a managed portfolio of on‑chain positions across multiple venues. Unlike typical vaults that only track assets, OPAL models both assets and liabilities, enabling safe leverage, debt roll‑overs, and cross‑venue rebalances under one token.

At a glance (TL;DR)

- One share token for a portfolio spanning multiple integrations (“adapters”).
- Deterministic join/exit math over combined token sets; users interact with the vault, not individual venues.
- Permissioned, atomic rebalances executed via a Bundler-based manager using approved plugins (e.g., swaps, flashloans).
- Adapters are minimal clones (Solady) with immutable args for gas‑efficient, configurable deployments.

Why OPAL?

- First‑class liabilities: Treat debt as a citizen of the balance sheet to enable safer leverage policies.
- Operational safety: Rebalances are governed, batched, and auditable through a permissioned Bundler; plugins are allow‑listed.
- Predictable UX: Proportional allocation preserves portfolio mix; rounding is explicit and deterministic.
- Modularity: Adapters are pluggable clones (Aave V3, Morpho, spot assets), created/whitelisted via a factory.
- Observability: Vault exposes TBS‑V2 views (tokens, balanceSheet, previews) for off‑chain reasoning and integrations.

Key properties

- Vault: ERC‑20 shares with time‑based performance fees (capped at 1,000 bps/year).
- Manager: Aggregates tokens, computes maxJoin/maxExit, performs join/exit allocation, and runs permissioned multicall bundles.
- Adapters: Bundler plugins restricted to the Manager; immutable args via Solady clones.
- Bounded surface: MAX_ADAPTERS = 10, MAX_TOKENS = 10; join/exit fee cap MAX_FEE_BPS = 330.
- Composability: Works with general plugins (e.g., entry‑point, swap, flashloan, TBS helpers) inside Manager‑owned bundles.

Mental model

- Users deposit/withdraw via the Vault → Vault delegates to the Manager → Manager splits work across Adapters according to current balances and limits.
- Governance/operators perform rebalances via Manager.multicall([...]) using approved plugins; users remain abstracted from underlying venue details.

## Contents

This folder documents the Origami Portfolio of Assets and Liabilities (OPAL).

- [ARCHITECTURE](./docs/ARCHITECTURE.md) — components, inheritance, and high-level flows
- [VAULT](./docs/VAULT.md) — OpalVault behavior (fees, TBS V2 surface, hooks)
- [MANAGER](./docs/MANAGER.md) — OpalManager registry, token mapping, allocations, and limits
- [ADAPTERS](./docs/ADAPTERS.md) — adapter design, Solady clones, immutable args, and types
- [REBALANCES](./docs/REBALANCES.md) — how OPAL vaults are rebalanced and the overlap with Origami Bundler/Plugins
- [ALLOCATION](./docs/ALLOCATION.md) — algorithms and worked examples for join/exit and max
- [SECURITY](./docs/SECURITY.md) — review guide and risk considerations
