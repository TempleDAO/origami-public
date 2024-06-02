pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol)

import { IOrigamiOTokenManager } from "contracts/interfaces/investments/IOrigamiOTokenManager.sol";
import { IWhitelisted } from "contracts/interfaces/common/access/IWhitelisted.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiLovToken } from "contracts/interfaces/investments/lovToken/IOrigamiLovToken.sol";

/**
 * @title Origami lovToken Manager
 * @notice The delegated logic to handle deposits/exits, and borrow/repay (rebalances) into the underlying reserve token
 */
interface IOrigamiLovTokenManager is IOrigamiOTokenManager, IWhitelisted {
    event FeeConfigSet(uint16 maxExitFeeBps, uint16 minExitFeeBps, uint24 feeLeverageFactor);

    event UserALRangeSet(uint128 floor, uint128 ceiling);
    event RebalanceALRangeSet(uint128 floor, uint128 ceiling);

    event Rebalance(
        /// @dev positive when Origami supplies the `reserveToken` as new collateral, negative when Origami withdraws collateral
        /// Represented in the units of the `reserveToken` of this lovToken
        int256 collateralChange,

        /// @dev positive when Origami borrows new debt, negative when Origami repays debt
        /// Represented in the units of the `debtToken` of this lovToken
        int256 debtChange,

        /// @dev The Assets/Liabilities ratio before the rebalance
        uint256 alRatioBefore,

        /// @dev The Assets/Liabilities ratio after the rebalance
        uint256 alRatioAfter
    );
    
    error ALTooLow(uint128 ratioBefore, uint128 ratioAfter, uint128 minRatio);
    error ALTooHigh(uint128 ratioBefore, uint128 ratioAfter, uint128 maxRatio);
    error NoAvailableReserves();

    /**
     * @notice Set the minimum fee (in basis points) of lovToken's for deposit and exit,
     * and also the nominal leverage factor applied within the fee calculations
     * @dev feeLeverageFactor has 4dp precision
     */
    function setFeeConfig(uint16 _minDepositFeeBps, uint16 _minExitFeeBps, uint24 _feeLeverageFactor) external;

    /**
     * @notice Set the valid lower and upper bounds of A/L when users deposit/exit into lovToken
     */
    function setUserALRange(uint128 floor, uint128 ceiling) external;

    /**
     * @notice Set the valid range for when a rebalance is not required.
     */
    function setRebalanceALRange(uint128 floor, uint128 ceiling) external;

    /**
     * @notice lovToken contract - eg lovDSR
     */
    function lovToken() external view returns (IOrigamiLovToken);

    /**
     * @notice The min deposit/exit fee and feeLeverageFactor configuration
     * @dev feeLeverageFactor has 4dp precision
     */
    function getFeeConfig() external view returns (uint64 minDepositFeeBps, uint64 minExitFeeBps, uint64 feeLeverageFactor);

    /**
     * @notice The current deposit and exit fee based on market conditions.
     * Fees are the equivalent of burning lovToken shares - benefit remaining vault users
     * @dev represented in basis points
     */
    function getDynamicFeesBps() external view returns (uint256 depositFeeBps, uint256 exitFeeBps);

    /**
     * @notice The valid lower and upper bounds of A/L allowed when users deposit/exit into lovToken
     * @dev Transactions will revert if the resulting A/L is outside of this range
     */
    function userALRange() external view returns (uint128 floor, uint128 ceiling);

    /**
     * @notice The valid range for when a rebalance is not required.
     * When a rebalance occurs, the transaction will revert if the resulting A/L is outside of this range.
     */
    function rebalanceALRange() external view returns (uint128 floor, uint128 ceiling);

    /**
     * @notice The common precision used
     */
    function PRECISION() external view returns (uint256);
    
    /**
     * @notice The reserveToken that the lovToken levers up on
     */
    function reserveToken() external view returns (address);

    /**
     * @notice The token which lovToken borrows to increase the A/L ratio
     */
    function debtToken() external view returns (address);
    
    /**
     * @notice The total balance of reserve tokens this lovToken holds, and also if deployed as collateral
     * in other platforms
     */
    function reservesBalance() external view returns (uint256); 

    /**
     * @notice The debt of the lovToken from the borrower, converted into the reserveToken
     * @dev Use the Oracle `debtPriceType` to value any debt in terms of the reserve token
     */
    function liabilities(IOrigamiOracle.PriceType debtPriceType) external view returns (uint256);

    /**
     * @notice The current asset/liability (A/L) of this lovToken
     * to `PRECISION` precision
     * @dev = reserves / liabilities
     */
    function assetToLiabilityRatio() external view returns (uint128);

    /**
     * @notice Retrieve the current assets, liabilities and calculate the ratio
     * @dev Use the Oracle `debtPriceType` to value any debt in terms of the reserve token
     */
    function assetsAndLiabilities(IOrigamiOracle.PriceType debtPriceType) external view returns (
        uint256 assets,
        uint256 liabilities,
        uint256 ratio
    );

    /**
     * @notice The current effective exposure (EE) of this lovToken
     * to `PRECISION` precision
     * @dev = reserves / (reserves - liabilities)
     * Use the Oracle `debtPriceType` to value any debt in terms of the reserve token
     */
    function effectiveExposure(IOrigamiOracle.PriceType debtPriceType) external view returns (uint128);

    /**
     * @notice The amount of reserves that users may redeem their lovTokens as of this block
     * @dev = reserves - liabilities
     * Use the Oracle `debtPriceType` to value any debt in terms of the reserve token
     */
    function userRedeemableReserves(IOrigamiOracle.PriceType debtPriceType) external view returns (uint256);

    /**
     * @notice How many reserve tokens would one get given a number of lovToken shares
     * @dev Use the Oracle `debtPriceType` to value any debt in terms of the reserve token
     */
    function sharesToReserves(uint256 shares, IOrigamiOracle.PriceType debtPriceType) external view returns (uint256);

    /**
     * @notice How many lovToken shares would one get given a number of reserve tokens
     * @dev Use the Oracle `debtPriceType` to value any debt in terms of the reserve token
     */
    function reservesToShares(uint256 reserves, IOrigamiOracle.PriceType debtPriceType) external view returns (uint256);
}
