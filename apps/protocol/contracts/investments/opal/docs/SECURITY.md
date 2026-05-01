# Security and review guide

Access control

- OpalManager.multicall is Elevated-only; only approved plugins can be targeted.
- Adapters enforce withApprovedBundler (the manager) on all actions.
- Vault.setManager is Elevated-only; fee and price-feed setters are governed.

Immutable args

- Adapters parse immutable args via fixed offsets. Verify encoding/decoding layouts in factories and readers for each implementation.

Reentrancy model

- Bundler permits reentry but constrains it via expected callback hashes; ensure all nested flows set the correct hash.
- Plugins must not expose state-changing functions without withApprovedBundler.

Approvals and residues

- Plugins set max approvals to known protocol contracts (routers/pools). Validate addresses.
- Callers (bundle creators) are responsible for avoiding dust left in plugins at the end of a bundle.

Token set drift and hashes

- TBS V2 vaults expose a tokensHash concept at the plugin layer (e.g., TbsV2 plugin) so callers can assert expected token layouts.
- Manager’s combined token set order may change when adapters are added/removed. Use current tokensHash in integrations and previews.

External protocol considerations

- Aave: variable‑rate only (INTEREST_RATE_MODE = VARIABLE). EMODE/category changes are admin‑guarded.
- Morpho: health relies on oracles (price scale and staleness). Ensure safe maxSafeLtv < liquidation LTV.

Fees and supply caps

- Performance fees mint shares; verify interactions with any totalSupply caps and preview math under edge conditions.
- maxJoin/maxExit functions on the vault should cap the amount allowed to join/exit in the vault conservatively.

Arithmetic/rounding

- Allocation uses floor rounding with dust assigned to the last adapter; verify invariants in tests (sum equality).
