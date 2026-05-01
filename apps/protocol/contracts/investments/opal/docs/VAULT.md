# OpalVault

- Extends OrigamiTokenizedBalanceSheetVault (TBS V2 base) and implements IOpalVault.
- Delegates state to the manager:
  - tokens(), balanceSheet(), maxJoin(), maxExit() reflect the manager’s aggregated view.
  - areJoinsPaused()/areExitsPaused(), joinFeeBps()/exitFeeBps() are read from the manager.
- Hooks:
  - On join: transfers user assets to the manager and calls manager.join(..., bsData).
  - On exit: asks manager to settle liabilities and assets back to receiver via manager.exit(..., bsData).
  - bsData (IOpalManager.BalanceSheetData) includes:
    - aggregatedBalanceSheet: combined assets/liabilities snapshot,
    - perAdapterBS: encoded per-adapter balances (used by the manager to compute proportional splits).
- Performance fee:
  - annualPerformanceFeeBps, capped by MAX_PERFORMANCE_FEE_BPS (= 1,000 → 10%/yr).
  - collectPerformanceFees() mints new shares to feeCollector based on elapsed time and totalSupply.
  