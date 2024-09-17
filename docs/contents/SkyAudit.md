
# Intro to Origami Finance

Origami Finance ([https://origami.finance/](https://origami.finance/)) is a protocol that utilises available sources of liquidity to provide constant leverage for whitelisted liquid-staking strategies through a simple vault UX. The initial Origami v1 vaults launched in 2023 for GMX and GLP that automatically harvested yields to compound back into the underlying asset in the vault. The new v2 vaults will add the power of leverage -- also known as folding -- to the vaults by facilitating collateralized loans to increase effective exposure for the underlying asset and managing the leveraged position automatically. The liquidity will be sourced from external money markets such as Spark Finance as well as other Origami vaults like the oUSDC stablecoin vault.

This competition is for a new Origami ERC-4626 vault and dependencies, which is aiming to be launced ASAP. This will be a yield auto-compounder using Sky's (rebranded MakerDAO) USDS.

Further details can be found in: [/apps/protocol/contracts/investments/sky/README.md](../../apps/protocol/contracts/investments/sky/README.md)

And details on the CowSwapper in: [/apps/protocol/contracts/common/swappers/README.md](../../apps/protocol/contracts/common/swappers/README.md)

## Audit Focus Areas

Origami ERC4626:

- Ensure it follows the standard appropriately (we are using the A16z fuzz/property tests to verify this)
- Ensure the extra functions we added to handle fee collection, max supply, permit functionality are ok
- Share price inflation attack is still prevented by hardcoding to 0 offset
- Share price calculations are still appropriate after hardcoding the vault to 18dp (even with an underlying asset of say USDC with 6dp)

CowSwapper:

- Orders submitted by others on behalf of our contract, which are accepted and executed (ie the `isValidSignature()` is too lenient)
  - Note: CoW Solvers are trusted to find best execution due to the competitive auction, and have stake at risk of slashing.
  - The orders are accepted within bounds set as parameters, since the actual buy/sell amounts may vary slightly between trade being placed and validated
- Griefing attacks
  - Solvers may choose to sensor particular contracts if they continuously fail to execute when they show as valid
  - CowSwap's order book may also drop orders which are deemed to be 'spammy', so care is taken to limit new orders to once every 5 minutes (or if config changes)
- Elevated Access is trusted to set the parameters correctly. There are some validation checks, but checking the combination of parameters is left to the caller setting the config
- We will likely be running our own watch-tower infrastructure using the reference implementation, and tweak it over time to our use case + add extra monitoring, etc.

Origami sUSDS++ Vault:

- Ensure no theft of funds by an attacker - so check that permissionless calls are ok and inputs are validated, reentrancy, etc
- Correct behaviour of vault and that

## Audit Competition Scope

### Files in Scope

Files referenced are in the `/apps/protocol/contracts/` directory. Please read the README's linked in the intro above

| Type | File                                                         | Logic Contracts | Interfaces | Lines | nLines | nSLOC | Comment Lines | Complex. Score | Capabilities |
| :--- | :----------------------------------------------------------- | :-------------- | :--------- | :---- | :----- | :---- | :------------ | :------------- | :----------- |
| 📝  | [contracts/common/OrigamiErc4626.sol](../../apps/protocol/contracts/common/OrigamiErc4626.sol)                          | 1               |            | 510   | 467    | 261   | 121           | 208            | 🧮Σ         |
| 📝  | [contracts/common/swappers/OrigamiCowSwapper.sol](../../apps/protocol/contracts/common/swappers/OrigamiCowSwapper.sol)              | 1               |            | 474   | 442    | 223   | 156           | 193            | 🧮          |
| 📝  | [contracts/investments/sky/OrigamiSuperSavingsUsdsManager.sol](../../apps/protocol/contracts/investments/sky/OrigamiSuperSavingsUsdsManager.sol) | 1               |            | 471   | 435    | 295   | 64            | 243            | Σ            |
| 📝  | [contracts/investments/sky/OrigamiSuperSavingsUsdsVault.sol](../../apps/protocol/contracts/investments/sky/OrigamiSuperSavingsUsdsVault.sol)   | 1               |            | 88    | 85     | 56    | 16            | 40             |              |
| 📝  | Totals                                                       | 4               |            | 1543  | 1429   | 835   | 357           | 684            | 🧮Σ         |

### Not In Scope

- Any findings from previous audits are OOS:
  - Origami v1 - yAudit:
    - [01-2023-TempleDAO-Origami](../../audits/origami-v1/01-2023-TempleDao-Origami-yAcademy-Report.pdf)
    - [02-2023-TempleDAO-Origami-Recheck](../../audits/origami-v1/02-2023-TempleDao-Origami-Recheck-yAcademy-Report.pdf)
  - Origami v2 - Zellic:
    - [Origami Finance - Zellic Audit Report.pdf](../../audits/origami-v2/Origami%20Finance%20-%20Zellic%20Audit%20Report.pdf)
  - Hats Audit Competition:
    - [https://github.com/hats-finance/Origami-0x998f1b716a5022be026ca6b919c0ddf45ca31abd/issues](https://github.com/hats-finance/Origami-0x998f1b716a5022be026ca6b919c0ddf45ca31abd/issues)
- ERC20 Tokens:
  - Only standard 18dp ERC20 Tokens are in scope, plus USDT and USDC
- Any `4naly3er` or `slither` output is considered public and OOS
  - 4naly3er output: [apps/protocol/scripts/gas-report/4naly3er-report.md](../../apps/apps/protocol/scripts/gas-report/4naly3er-report.md)
  - Slither output: [apps/protocol/slither.db.json](../../apps/protocol/slither.db.json)
- Centralization risks are for policy/emergency/operational behaviour, and owned by the Origami multisig. This is acceptable and out of scope as it's required for the protocol to work as intended and protect user funds
- External libraries (prbmath, openzeppelin) are out of scope
- Whitelisting for contracts has known constraints (eg code=0 on construction) and this behaviour is expected.
