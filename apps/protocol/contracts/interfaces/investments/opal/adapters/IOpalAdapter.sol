pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/opal/adapters/IOpalAdapter.sol)

import { IOrigamiBundlerPlugin } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol";

/// @title Origami Portfolio of Assets and Liabilities (OPAL) Adapter interface
/// @notice Core required functions for adapters to slot into the OPAL Tokenized Balance Sheet vault framework
interface IOpalAdapter is IOrigamiBundlerPlugin {
    error InitializeFailed();
    error LtvOutOfRange(uint256 currentLtv, uint256 minLtv, uint256 maxLtv);
    error UtilizationRatioOutOfRange(uint256 currentUR, uint256 minUR, uint256 maxUR);
    error NoCollateral();

    event Initialized();
    event SetDeprecated(bool indexed value);

    event Join(uint256[] assetAmounts, uint256[] liabilityAmounts);

    event Exit(uint256[] assetAmounts, uint256[] liabilityAmounts);

    /****** ADMIN ******/

    /// @notice Initialize the clone, using implementation specific encoded data (may be empty)
    /// to set non-immutable arguments.
    /// @dev This should also be used for any initialization or checks. Typically it will be called by the bundler
    /// in the same transaction as the clone is created.
    function initialize(bytes calldata data) external;

    /// @notice Set this adapter as deprecated.
    /// @dev Note it can still be operated on and used as normal, however an adapter cannot be
    /// removed from the OPAL manager unless isDeprecated is true.
    function setDeprecated(bool value) external;

    /****** BUNDLER PLUGIN ACTIONS ******/

    /// @notice Grant approval to spender to pull ERC20 tokens.
    /// @dev Uses SafeERC20.forceApprove() to ensure it works with USDC/USDT type tokens
    /// To be used with care and revoke access when not required.
    /// @param token The address of the ERC20 token to approve.
    /// @param spender The address of who can spend on behalf of this plugin.
    /// @param amount The amount of token to approve. Callers are responsible for setting back to zero if required.
    function erc20Approve(address token, address spender, uint256 amount) external;

    /// @notice Claim rewards from the provided Merkl rewards distributor
    /// @dev tokens/amounts/proofs are obtained offchain via the Merkl API
    function merklClaim(
        address merklRewardsDistributor,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs,
        address recipient
    ) external;

    /****** JOIN / EXIT ******/

    /// @notice The OPAL manager calls this for the allocation portion when a user has
    /// joined the vault.
    /// @dev Generally the implementation will pull the required assets. So approval should be granted
    /// for at least these amounts
    /// Liabilities will be sent directly to the recipient
    function join(uint256[] calldata assets, uint256[] calldata liabilities, address recipient) external;

    /// @notice The OPAL manager calls this for the allocation portion when a user has
    /// exited the vault.
    /// @dev Generally the implementation will pull the required liabilities. So approval should be granted
    /// for at least these amounts.
    /// Assets will be sent directly to the recipient
    function exit(uint256[] calldata assets, uint256[] calldata liabilities, address recipient) external;

    /****** IMMUTABLE GETTERS ******/

    /// @notice The vault manager contract
    /// @dev The manager is a 'bundler' and has sole access rights to call plugin steps.
    function manager() external view returns (address);

    /// @notice The adapter implementation type and version as a null terminated short string
    /// @dev Format should be {TYPE_STR}.{VERSION_STARTING_AT_1}
    ///      eg "AAVE_V3.1" to represent the first version of an Aave v3 adapter
    /// If the implementation logic is updated for the same type, a new "AAVE_V3.2" would be
    /// deployed and registered in the factory.
    function implTypeAndVersion() external view returns (string memory);

    /// @notice A small string (as bytes32) description for this clone.
    /// Format is left to the caller to decide, but for consistency could (but not enforced) be structured like:
    /// "[ASSET1.symbol, ASSET2.symbol] / [DEBT1.symbol, DEBT2.symbol]"
    function description() external view returns (string memory);

    /// @notice A collection of keys to identify shared caps on underlying lending/borrowing protocols, so that multiple
    /// adapters with the same tokens in the same protocols can be grouped together and reasoned about with reference to
    /// that shared cap.
    /// For example on Aave this could be the instance pool (Core vs Prime), or Morpho this
    /// would just be the underlying marketId for that morpho market.
    /// For Euler each collateral and debt token uses a separate Euler vault with separate caps. So if multiple adapters
    /// use the same Euler vaults they need to share the same caps
    /// @dev The aggregation of maxJoin and maxExit relies on this, where adapters may share
    /// the same underlying supply/borrow caps.
    /// - MUST be immutable.
    /// - MAY be the same OR different across multiple different implTypeAndVersion() for different adapter
    ///   implementations, depending on how caps operate.
    function groupIds() external view returns (bytes32[] memory assetGroupIds, bytes32[] memory liabilityGroupIds);

    /****** VIEWS ******/

    /// @notice Has this adapter been marked as deprecated.
    /// @dev Note it can still be operated on and used as normal, however an adapter cannot be
    /// removed from the OPAL manager unless isDeprecated is true.
    function isDeprecated() external view returns (bool);

    /// @notice Returns the addresses of the underlying tokens which represent the ASSETS and LIABILITIES in this
    /// adapters balance sheet @dev
    /// - MUST be ERC-20 token contracts.
    /// - MUST NOT revert.
    /// - MUST be immutable.
    function tokens() external view returns (address[] memory assetTokens, address[] memory liabilityTokens);

    /// @notice Returns the total amount of the ASSETS and LIABILITIES managed by this adapter
    /// @dev
    /// - `assets` MUST return a list which is the same size and order as `assetTokens()`
    /// - `liabilities` MUST return a list which is the same size and order as `liabilityTokens()`
    /// - SHOULD include any compounding that occurs from yield.
    /// - MUST NOT revert.
    function balanceSheet() external view returns (uint256[] memory assets, uint256[] memory liabilities);

    /// @notice Returns the total amount of the ASSETS and LIABILITIES this adapter can join with as of this block,
    /// irrespective of the position this adapter currently holds. It should reflect the underlying protocol global caps
    /// or other limits, not the position currently in this adapter (since that can be queried via the balanceSheet)
    /// @dev
    /// - `assets` MUST return a list which is the same size and order as `assetTokens()`
    /// - `liabilities` MUST return a list which is the same size and order as `liabilityTokens()`
    /// - SHOULD return zero if paused or entirely capped
    /// - SHOULD return type(uint256).max if unlimited
    /// - MUST NOT revert.
    function maxJoin() external view returns (uint256[] memory assets, uint256[] memory liabilities);

    /// @notice Returns the total amount of the ASSETS and LIABILITIES this adapter can exit as of this block,
    /// irrespective of the position this adapter currently holds. It should reflect the underlying protocol global caps
    /// or other limits, not the position currently in this adapter (since that can be queried via the balanceSheet)
    /// @dev
    /// - `assets` MUST return a list which is the same size and order as `assetTokens()`
    /// - `liabilities` MUST return a list which is the same size and order as `liabilityTokens()`
    /// - SHOULD return zero if paused or entirely capped
    /// - SHOULD return type(uint256).max if unlimited
    /// - MUST NOT revert.
    function maxExit() external view returns (uint256[] memory assets, uint256[] memory liabilities);

    /// @notice The current Loan-To-Value (LTV) of this adapter.
    /// @dev Implementations should use the upstream money market based LTV
    ///      (ie their oracle and measure of debt/collateral) if available
    /// Represented in WAD (0.9e18 == 90% LTV)
    /// If no debt, will return zero
    /// If some debt but no collateral, will return type(uint256).max
    function currentLtv() external view returns (uint256);

    /// @notice The maximum Loan-To-Value (LTV) that this adapter can safetly borrow up to.
    /// @dev This may be an underlying protocol enforced policy, otherwise set on the origami adapter
    /// Represented in WAD (0.9e18 == 90% LTV)
    function maxSafeLtv() external view returns (uint256);

    /// @notice The Loan-To-Value (LTV) that the underlying protocol may liquidate this adapter position.
    /// Represented in WAD (0.9e18 == 90% LTV)
    function liquidationLtv() external view returns (uint256);

    /// @notice The (estimated) health factor of the position
    /// Represented in WAD (1.123e18 == health factor of 1.123)
    function healthFactor() external view returns (uint256);
}
