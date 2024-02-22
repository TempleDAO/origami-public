
# Intro to Origami Finance

Origami Finance ([https://origami.finance/](https://origami.finance/)) is a protocol that utilises available sources of liquidity to provide constant leverage for whitelisted liquid-staking strategies through a simple vault UX. The initial Origami v1 vaults launched in 2023 for GMX and GLP that automatically harvested yields to compound back into the underlying asset in the vault. The new v2 vaults will add the power of leverage -- also known as folding -- to the vaults by facilitating collateralized loans to increase effective exposure for the underlying asset and managing the leveraged position automatically. The liquidity will be sourced from external money markets such as Spark Finance as well as other Origami vaults like the oUSDC stablecoin vault.

## About the competition

This competition is for the new Origami vaults that will be launched as part of the v2 upgrade. The flagship product is the Leveraged Origami Token Vault (lovToken), which will connect users who wish to lever up on a liquid staking yield strategy to liquidity providers who will earn real yield for lending to one or more lovToken vaults. The Origami v2 framework is designed to maximize capital efficiency and minimize risk of liquidation and bad debt.

On Ethereum mainnet, two lovToken Strategy vaults will be ready for launch:

- **lovDSR** (MakerDAO Dai Savings Rate)
  - This levers up on sDAI by borrowing USDC from the oUSDC vault
- **lovSTETH** (Lido wrapped staked ETH)\
  - This levers up on wstETH by borrowing WETH from Aave v3/Spark Finance

## How Constant Leverage Works

Origami lovToken vaults will provide constant leverage to its depositors by usings its reserves as collateral to increase its reserve balance. By keeping its collateralization ratio within a target range, the vault can achieve leveraged or N-folded exposure to the underlying where N is the leverage factor e.g. 10X.

When new deposits move the collateralization ratio out of its target range, the lovToken vault will automatically borrow more money to increase effective exposure and lower the collateralization ratio. Conversely, the vault will deleverage when that same ratio deteriorates due to withdrawals, rising borrow interest, or when the price of the reserve token is falling.

The prevailing APR for each lovToken vault is dynamic and will fluctuate depending on yield for the underlying liquid staking token (LST) strategy less the borrow interest rate from the liquidity provider. Ignoring fees, the formula to calculate the lovToken APY is:

> `(1 x LST APY) + Leverage Factor x (LST APY - Borrow APY)`

## Origami's New v2 Vaults

### oUSDC "Liquidity Provider" Vault

- oUSDC is the primary internal liquidity provider and lending vault. The oUSDC vault share token is called ovUSDC.
- Users may deposit/exit with USDC. Depositors will receive a continuously compounding yield denominated in USDC. This yield reflects the variable interest earned from lending the USDC to one or more lovToken vaults e.g. lovDSR or the idle strategy (see below).
- As lovToken vaults rebalance to increase leverage, they will borrow the USDC and be issued a continuously compounding internal debt token (iUSDC) that reflects the current debt owed to the oUSDC vault. The iUSDC interest rate is variable and is determined by the utilization of the debt ceiling capacity for that lovToken vault.
- The debt ceiling for each lovToken vault borrower is set by policy. As each vault borrower uses more of its allowance, the iUSDC interest rate for that borrower will rise. This is known as the Specific Interest Rate.
- The total debt ceiling for the oUSDC is the global capacity. As lovToken vaults borrow more of the available global capacity, the alternate calculation for iUSDC interest rate will rise. This is known as the Global Interest Rate. To closely track the true cost of capital, the prevailing iUSDC rate for each lovToken borrower will be set to `max(specific_int_rate, global_int_rate)`.
- Any USDC reserves that is not utilised by a lovToken vault borrower is still earning yield as the USDC will be supplied into Aave as collateral (supply only, no borrows). This "idle strategy" is also issued iUSDC tokens like any other borrower. The interest rate for the idle strategy is updated weekly and set to an average historic rate that will closely track the actual yield from the external protocol.
- To ensure capital efficiency, the USDC will only be lent out if the borrow APR paid by the lovToken vault exceeds the supply APY for the designated USDC idle strategy.

### lovDSR "Leveraged" Vault

- lovDSR is a leveraged Liquid Staking Strategy vault.
- Users can deposit/exit with DAI or sDAI
- This vault levers up on sDAI by borrowing USDC from the oUSDC vault and swapping into sDAI to increase both the Assets (sDAI) and Liabilities (USDC)
- The vault has a target A/L (==1/LTV) range, and a bot operator will call `rebalanceUp()` or `rebalanceDown()` on the lovDSR vault when below or above that nominal range.
- Vault rebalancing transactions have randomisation applied and will be implemented using Flashbots.

### lovSTETH "Leveraged" Vault

- lovSTETH is a leveraged Liquid Staking Strategy vault.
- Users can deposit/exit with wstETH, which will be used to collateralise a debt position on Spark Finance.
- This vault levers up on wstETH by depositing wstETH into Spark Finance as collateral and flash loaning WETH and swapping into more wstETH. This wstETH is added as new collateral to borrow WETH and repay the original flashloan.
- Again the automated bot applies randomisation for when and how much to rebalance, and uses Flashbots.

## High Level Design

## Design Notes

### Oracles

- Chainlink oracles are used to value lovToken liabilities e.g. USDC in terms of the vault's assets e.g. DAI in the case of lovDSR.
- lovDSR uses `[DAI/USD] / [USDC/USD]` to value USDC debt in terms of sDAI assets.
- lovETH uses `wstETH ratio * [stETH/ETH]` to value wETH debt in terms of wstETH assets.

### Defense in Depth

- oUSDC Daily Withdrawal Circuit Breakers
  - A maximum daily cap on ovUSDC exits by users
  - A maximum daily cap on USDC borrows from lovDSR
- lovToken A/L checks:
  - Deposits revert if the A/L will go above a policy set ceiling (under leveraged). Users will need to wait for a rebalance
  - Exits revert if the A/L will go below a policy set ceiling (over leveraged). Users will need to wait for a rebalance
- Oracle Checks:
  - The `DAI/USD`, `USDC/USD`, `stETH/ETH` oracle price lookups will revert if outside of an acceptable policy set range close to 1:1 peg
- lovToken Dynamic Fees:
  - Economic guards are in place to dissuade leeching value from existing vault users when the Chainlink Oracle value varies from the expected historic 1:1 peg for `DAI/USDC` and `stETH/ETH`
  - When the underlying is trading below peg it charges a multiple of the difference between the oracle price and 1 for withdrawals and assumes the underlying is trading at peg for deposits.
  - When the underlying is trading above peg it charges a multiple of the difference between the oracle price and 1 for deposits and assumes the underlying is trading at peg for withdrawals
  - These vault fees are deflationary - lovToken shares are burned to benefit remaining users in the vault.
  - Example scenarios showing the impact of dynamic fees can be found [here](https://docs.google.com/spreadsheets/d/1EUcZFJP5UeCfA8XY2mMWEWO1_oXJU5DWRFBzeDc27nY/edit?usp=sharing)

## Hats Audit

### Audit Focus Areas

- Unexpected or incorrect vault share issuance
- Vault share price manipulation to redeem more than expected reserve tokens
- Vault entry or redemptions that impacts user share price in unexpected ways
- Ways to exit or enter the vault even when the A/L ratio should prohibit the action
- Ways for vaults to bypass system circuit breakers to borrow more than allowed
- Ways to exit the lovToken vault in such a way as to create bad debt in the system balance sheet either for lovToken users or for the liquidity provider
- Front-running behaviour to directly profit off of or avoid loss stemming from pending rebalance events either within the vault or outside of the vault
- Price oracle manipulation such that the system is fooled into a rebalance when it is unnecessary or unprofitable to do so.
- Interest rate manipulation or malicious behaviour such that one vault unfairly benefits at the expense of another vault.
- Attacker actions that can trigger rebalance cascades from the bot

## Audit Competition Scope

### Files in Scope

See here for [in-scope-files.txt](./in-scope-files.txt)

| #   | File                                                                             | nSLOC | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| :-- | :------------------------------------------------------------------------------- | :---- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | contracts/common/access/OrigamiElevatedAccess.sol                                | 7     | (abstract) Inherit to add Owner roles for DAO elevated access.                                                                                                                                                                                                                                                                                                                                                                                                              |
| 2   | contracts/common/access/OrigamiElevatedAccessBase.sol                            | 44    | (abstract) Inherit to add Owner roles for DAO elevated access.                                                                                                                                                                                                                                                                                                                                                                                                              |
| 3   | contracts/common/access/Whitelisted.sol                                          | 23    | (abstract) Functionality to deny non-EOA addresses unless whitelisted.                                                                                                                                                                                                                                                                                                                                                                                                      |
| 4   | contracts/common/borrowAndLend/OrigamiAaveV3BorrowAndLend.sol                    | 155   | An wrapper over an Aave/Spark money market. This is the supplier of one collateral asset, and borrower of another collateral asset                                                                                                                                                                                                                                                                                                                                          |
| 5   | contracts/common/circuitBreaker/OrigamiCircuitBreakerAllUsersPerPeriod.sol       | 102   | Circuit Breaker implementation which tracks total volumes (across all users) in a rolling period window, and reverts if over a cap                                                                                                                                                                                                                                                                                                                                          |
| 6   | contracts/common/circuitBreaker/OrigamiCircuitBreakerProxy.sol                   | 37    | Client contract issues circuit breaker requests to this proxy, which maps  queries to the pre-mapped underlying implementation.                                                                                                                                                                                                                                                                                                                                             |
| 7   | contracts/common/flashLoan/OrigamiAaveV3FlashLoanProvider.sol                    | 52    | A flashloan wrapper over an Aave/Spark flashloan pool                                                                                                                                                                                                                                                                                                                                                                                                                       |
| 8   | contracts/common/interestRate/BaseInterestRateModel.sol                          | 15    | An abstract base contract to calculate the interest rate derived from the current utilization ratio (UR) of debt.                                                                                                                                                                                                                                                                                                                                                           |
| 9   | contracts/common/interestRate/LinearWithKinkInterestRateModel.sol                | 81    | An interest rate curve derived from the current utilization ratio (UR) of debt. This is represented as two separate linear slopes, joined at a 'kink' - a particular UR.                                                                                                                                                                                                                                                                                                    |
| 10  | contracts/common/MintableToken.sol                                               | 44    | (abstract) An ERC20 token which can be minted/burnt by approved accounts                                                                                                                                                                                                                                                                                                                                                                                                    |
| 11  | contracts/common/oracle/OrigamiCrossRateOracle.sol                               | 41    | A derived cross rate oracle price, by dividing baseOracle / quotedOracle                                                                                                                                                                                                                                                                                                                                                                                                    |
| 12  | contracts/common/oracle/OrigamiOracleBase.sol                                    | 54    | (abstract) Common base logic for Origami Oracle's                                                                                                                                                                                                                                                                                                                                                                                                                           |
| 13  | contracts/common/oracle/OrigamiStableChainlinkOracle.sol                         | 66    | An Origami oracle wrapping a spot price lookup from Chainlink, and a fixed expected historic price (eg 1 for DAI/USD)                                                                                                                                                                                                                                                                                                                                                       |
| 14  | contracts/common/oracle/OrigamiWstEthToEthOracle.sol                             | 38    | The Lido wstETH/ETH oracle price, derived from the wstETH/stETH * stETH/ETH                                                                                                                                                                                                                                                                                                                                                                                                 |
| 15  | contracts/common/RepricingToken.sol                                              | 141   | (abstract) A re-pricing token which implements the ERC20 interface.                                                                                                                                                                                                                                                                                                                                                                                                         |
| 16  | contracts/common/swappers/OrigamiDexAggregatorSwapper.sol                        | 57    | An on chain swapper contract to integrate with the 1Inch router || 0x proxy                                                                                                                                                                                                                                                                                                                                                                                                 |
| 17  | contracts/investments/lending/idleStrategy/OrigamiAaveV3IdleStrategy.sol         | 47    | Assets are supplied into aave v3 for yield                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| 18  | contracts/investments/lending/idleStrategy/OrigamiAbstractIdleStrategy.sol       | 16    | (abstract) The common logic for an Idle Strategy, which can allocate and withdraw funds in 3rd party protocols for yield and capital efficiency.                                                                                                                                                                                                                                                                                                                            |
| 19  | contracts/investments/lending/idleStrategy/OrigamiIdleStrategyManager.sol        | 110   | Manage the allocation of idle capital, allocating to an underlying protocol specific strategy.                                                                                                                                                                                                                                                                                                                                                                              |
| 20  | contracts/investments/lending/OrigamiDebtToken.sol                               | 242   | A rebasing ERC20 representing debt accruing at continuously compounding interest rate.                                                                                                                                                                                                                                                                                                                                                                                      |
| 21  | contracts/investments/lending/OrigamiLendingClerk.sol                            | 355   | Manage the supply/withdraw || borrow/repay of a single asset                                                                                                                                                                                                                                                                                                                                                                                                                |
| 22  | contracts/investments/lending/OrigamiLendingRewardsMinter.sol                    | 74    | Periodically mint new oToken rewards for the Origami lending vault based on the cummulatively accrued debtToken interest.                                                                                                                                                                                                                                                                                                                                                   |
| 23  | contracts/investments/lending/OrigamiLendingSupplyManager.sol                    | 135   | Manages the deposits/exits into an Origami oToken vault for lending purposes, eg oUSDC. The supplied assets are forwarded onto a 'lending clerk' which manages the collateral and debt                                                                                                                                                                                                                                                                                      |
| 24  | contracts/investments/lovToken/managers/OrigamiAbstractLovTokenManager.sol       | 291   | (abstract) The delegated logic to handle deposits/exits, and borrow/repay (rebalances) into the underlying reserve token                                                                                                                                                                                                                                                                                                                                                    |
| 25  | contracts/investments/lovToken/managers/OrigamiLovTokenErc4626Manager.sol        | 286   | A lovToken manager which has reserves as ERC-4626 tokens. This will rebalance by borrowing funds from the Origami Lending Clerk, and swapping to the origami deposit tokens using a DEX Aggregator.                                                                                                                                                                                                                                                                         |
| 26  | contracts/investments/lovToken/managers/OrigamiLovTokenFlashAndBorrowManager.sol | 341   | A lovToken manager which supplies reserve's into a money market (in this case Spark/Aave) and uses flashloan's to loop to increase exposure                                                                                                                                                                                                                                                                                                                                 |
| 27  | contracts/investments/lovToken/OrigamiLovToken.sol                               | 156   | Users deposit with an accepted token and are minted lovTokens. Origami will rebalance to lever up on the underlying reserve token, targeting a specific A/L (assets / liabilities) range                                                                                                                                                                                                                                                                                    |
| 28  | contracts/investments/OrigamiInvestment.sol                                      | 16    | (abstract) A non-repricing Origami Vault base contract.                                                                                                                                                                                                                                                                                                                                                                                                                     |
| 29  | contracts/investments/OrigamiInvestmentVault.sol                                 | 221   | A repricing ERC20 Origami Vault which wraps an underlying non-repricing Origami Vault. When users deposit they are allocated shares. Origami will apply the supplied token into the underlying protocol in the most optimal way. The reservesPerShare() will increase over time as upstream rewards are harvested by the protocol and new underlying reserves are added (spread over time to avoid frontrunning). This makes the Origami Investment Vault auto-compounding. |
| 30  | contracts/investments/OrigamiOToken.sol                                          | 96    | Users deposit with an accepted token and are minted oTokens. Generally speaking this oToken will represent the underlying protocol it is wrapping, 1:1. Origami will apply the accepted investment token into the underlying strategy in the most optimal way. Users won’t ordinarily interact with this vault directly, as it will be wrapped by a repricing OrigamiInvestmentVault. This design does allow for future AMO integration on this token.                      |
| 31  | contracts/investments/util/OrigamiManagerPausable.sol                            | 20    | (abstract) A mixin to add pause/unpause for Origami manager contracts                                                                                                                                                                                                                                                                                                                                                                                                       |
| 32  | contracts/libraries/Chainlink.sol                                                | 36    | (library) A helper library to safely query prices from Chainlink oracles and scale them                                                                                                                                                                                                                                                                                                                                                                                     |
| 33  | contracts/libraries/CommonEventsAndErrors.sol                                    | 14    | A collection of common events and errors thrown within the Origami contracts                                                                                                                                                                                                                                                                                                                                                                                                |
| 34  | contracts/libraries/CompoundedInterest.sol                                       | 11    | A maths library to calculate compounded interest                                                                                                                                                                                                                                                                                                                                                                                                                            |
| 35  | contracts/libraries/DynamicFees.sol                                              | 53    | A helper to calculate dynamic entry and exit fees based off the difference between an oracle historic vs spot price                                                                                                                                                                                                                                                                                                                                                         |
| 36  | contracts/libraries/OrigamiMath.sol                                              | 73    | Utilities to operate on fixed point math multiplication and division taking rounding into consideration                                                                                                                                                                                                                                                                                                                                                                     |
| 37  | contracts/libraries/Range.sol                                                    | 15    | A helper library to track a valid range from floor <= x <= ceiling                                                                                                                                                                                                                                                                                                                                                                                                          |
| 38  | contracts/libraries/SafeCast.sol                                                 | 10    | A helper library for safe uint downcasting                                                                                                                                                                                                                                                                                                                                                                                                                                  |
|     |                                                                                  | 3575  |                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |

### Not In Scope

- Any findings from previous audits are OOS:
  - Origami v1 - yAudit:
    - [01-2023-TempleDAO-Origami](../audits/origami-v1/01-2023-TempleDao-Origami-yAcademy-Report.pdf)
    - [02-2023-TempleDAO-Origami-Recheck](../audits/origami-v1/02-2023-TempleDao-Origami-Recheck-yAcademy-Report.pdf)
  - Origami v2 - Zellic:
    - Will be published when competition opens
- ERC20 Tokens:
  - Non standard 18dp ERC20 Tokens (eg USDT, other fee taking ERC20s), other than USDC are OOS for the ovUSDC contract flow (OrigamiLendingSupplyManager, OrigamiLendingClerk)
  - Tokens other than DAI/sDAI are OOS for the lovDSR flow (OrigamiLovTokenErc4626Manager)
  - Tokens other than wstETH/wETH are OOS for the lovStEth flow (OrigamiLovTokenDirectAaveManager)
- Any `4naly3er` or `slither` output is considered public and OOS
  - 4naly3er output: [apps/protocol/scripts/gas-report/4naly3er-report.md](../../apps/apps/protocol/scripts/gas-report/4naly3er-report.md)
  - Slither output: [apps/protocol/slither.db.json](../../apps/protocol/slither.db.json)
- Centralization risks are for policy/emergency/operational behaviour, and owned by the Origami multisig. This is acceptable and out of scope as it's required for the protocol to work as intended and protect user funds
- External libraries (prbmath, openzeppelin) are out of scope
- Whitelisting for contracts has known constraints (eg code=0 on construction) and this behaviour is expected.

### Files Not In Scope

- contracts/investments/gmx/\*\*/\*.sol (this was the v1 vaults)
- contracts/common/access/OrigamiElevatedAccessUpgradeable.sol (this was the v1 vaults)
- contracts/common/TokenPrices.sol (only used off-chain)
- contracts/test/\*\*/\*.sol (mocks, testnet only contracts)
