# Origami v2 Contract Design

- [Origami v2 Contract Design](#origami-v2-contract-design)
  - [ovUSDC and lovDSR](#ovusdc-and-lovdsr)
      - [ovUSDC](#ovusdc)
      - [lovDSR](#lovdsr)
  - [General Design Notes](#general-design-notes)
    - [Origami Elevated Access](#origami-elevated-access)
    - [Circuit Breakers](#circuit-breakers)
      - [Implementation of the 24hr Circuit Breaker](#implementation-of-the-24hr-circuit-breaker)
    - [Origami Oracle](#origami-oracle)
    - [Compounding Interest and Maths Libs](#compounding-interest-and-maths-libs)
    - [ERC-4626 vs custom vault](#erc-4626-vs-custom-vault)

## ovUSDC and lovDSR

lovDSR is a `Leveraged Vault` giving 10x exposure to DAI Savings Rate yield. In order to increase leverage, it needs USDC liquidity, provided by the ovUSDC `Liquidity Provider Vault`.

For more details on these vaults, read the [lovStrategy Introduction](./lovStrategyIntro.md#origami-lovstrategy-background)

Both of these vaults implement the [IOrigamiInvestment.sol](../../apps/protocol/contracts/interfaces/investments/IOrigamiInvestment.sol) interface providing a consistent integration point for the dapp across all Origami vaults without custom subgraph/dapp logic.

The high level interaction between these two vaults can be seen here:

<div style="text-align: center;">
  <img src="lovDSR-HighLevel.png" alt="ovUSDC-lovDSR" style="width:600px;"/>
</div>

At a contract level, the interactions and safeguards are illustrated with these two figures

NB: For a better viewing experiance, see [Figma](https://www.figma.com/file/n1VQ5XYVa0utmeei1Be3zL/lovDSR-%26-ovUSDC-Contract-Architecture?type=whiteboard&node-id=0%3A1&t=RBn0PO3D8yRWEVLt-1)

#### ovUSDC

<div style="text-align: center;">
  <img src="ovUsdc.png" alt="ovUsdc"/>
</div>

#### lovDSR

<div style="text-align: center;">
  <img src="lovDSR.png" alt="lovDSR"/>
</div>

## General Design Notes

### Origami Elevated Access

The Origami Finance multisig (a 2 of 5 Safe) is the designated owner of the contracts.

Each protected function uses the `onlyElevatedAccess` modifier, inherited from [OrigamiElevatedAccess](../../apps/protocol/contracts/common/access/OrigamiElevatedAccessBase.sol)

This allows us to whitelist an address to have access to an individual bytes4 function selector. For example, our automation bot for ovUSDC & lovDSR will be granted explicit access to:

- ovUSDC [OrigamiLendingRewardsMinter::checkpointDebtAndMintRewards()](../../apps/protocol/contracts/investments/lending/OrigamiLendingRewardsMinter.sol)
- ovUSDC [OrigamiLendingClerk::refreshBorrowersInterestRate()](../../apps/protocol/contracts/investments/lending/OrigamiLendingClerk.sol)
- ovUSDC [OrigamiLendingClerk::setIdleStrategyInterestRate()](../../apps/protocol/contracts/investments/lending/OrigamiLendingClerk.sol)
- lovDSR manager [OrigamiLovTokenErc4626Manager::rebalanceUp()](../../apps/protocol/contracts/investments/lovToken/managers/OrigamiLovTokenErc4626Manager.sol)
- lovDSR manager [OrigamiLovTokenErc4626Manager::rebalanceDown()](../../apps/protocol/contracts/investments/lovToken/managers/OrigamiLovTokenErc4626Manager.sol)

### Circuit Breakers

Origami has incorporated a circuit breaker for certain functions to provide limited liability in case of an emergency.

<div style="text-align: center;">
  <img src="circuitBreaker.png" alt="Circuit Breakers" style="width:600px;"/>
</div>

Over time, there may be multiple types of circuit breaker implementations. As of writing, we have just one.

This tracks the total funds requested for a single token over a window of time. If the total amount requested is greater than the cap (for that period) then it reverts the transaction.

#### Implementation of the 24hr Circuit Breaker

tl;dr No more than the cap can be borrowed within a 23-24 hour window (not exactly 24hrs)

For efficiency to avoid looping over large data sets, this employs a bucketing algorithm.

1. The tracking is split up into hourly buckets, so for a 24 hour window, we define 24 hourly buckets.
2. When a new transaction is checked, it will roll forward by the required buckets (when it gets to 23 it will circle back from 0), cleaning up the buckets which are now > 24hrs in the past.
   1. If it's in the same hr as last time, then nothing to clean up
3. Then adds the new volume into the bucket
4. Then sums the buckets up and checks vs the cap, reverting if over.

This means that we only have to sum up 24 items.

The compromise is that the window we check for is going to be somewhere between 23hrs and 24hrs.
eg for a cap of 100:

- at 13:45:00 borrow 75 (OK - utilisation == 75)
  - bucket 13 = 75
- at 23:06:00 borrow 25 (OK - utilisation == 100)
  - bucket 13 = 75
  - bucket 23 = 25
- at 12:59:59 borrow 1  (FAIL - utilisation == 101)
  - bucket 13 = 75
  - bucket 23 = 25
  - bucket 12 = 1  (discarded on the revert)
- at 13:00:00 borrow 1  (OK - utilisation == 26)
  - bucket 23 = 25
  - bucket 13 = 1  (the old value at bucket 13 was removed, now have the new value)

Because the last trade crossed into the new window (on the hour) it was ok.

We can make the number of buckets more granular (configurable) -- eg 48 buckets. But it makes a decent difference to the gas required (more things to loop over).
     24 buckets (hourly): 11k gas
     48 buckets (half hourly): 17.5k gas

### Origami Oracle

In order to provide ongoing flexibility and security controls around oracles, we have our own [IOrigamiOracle interface](../../apps/protocol/contracts/interfaces/common/oracle/IOrigamiOracle.sol)

This allows us to:

- Wrap Chainlink Oracles with sensible controls around staleness and price validation
- Apply rounding as required
- Use two different 'modes' for the OrigamiOracle:
  - HISTORIC_PRICE: An expected historic rate - eg for DAI/USD this is expected to be 1.0 (peg). For volatile paris (in future), this may be a TWAP or other moving average as required.
  - SPOT_PRICE: The current on-chain spot price observed on Chainlink or other.
- The two modes allow us to have dynamically adjusted fees based on the difference between SPOT and HISTORIC, offering safe guards for high volatility periods and/or oracle and market exploits impacting our vaults.

### Compounding Interest and Maths Libs

Continuously compounded interest rates are used throughout, utilising the awesome [prb-math](https://github.com/PaulRBerg/prb-math) library from Paul R. Berg, rather than taking 1 second approximations.

### ERC-4626 vs custom vault

We are fans of the ERC-4626 standard for composability and consistency. However it has some shortcomings which prompted us to use our own implementation of the vault:

- Quote data: With some integrations to 3rd party protocols, custom quote data needs to be provided when actually depositing/exiting. This isn't supported in the ERC-4626 interface
- Multi-asset: ERC-4626 only supports one underlying vault asset.
  - NB: There are proposals for multi-asset vaults (eg [mstable's metavaults](https://github.com/mstable/metavaults))
- Vault: A requirement was to have a single interface which worked for all our vaults, whether they are repricing or not. These vaults needed to be composable such that we can create repricing vault (eg ovUSDC) which wraps a non-repricing vault (oUSDC)

With those constraints, Origami v1 created the [IOrigamiInvestment.sol](../../apps/protocol/contracts/interfaces/investments/IOrigamiInvestment.sol) interface which allowed for getting on-chain quotes (with quote data), and then deposits and exits into the vault providing that quote data.

Origami vaults are not intended for integrations. Utilising the ERC-4626 standard was not a priority.
