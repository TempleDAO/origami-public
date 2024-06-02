pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/borrowAndLend/IOrigamiMorphoBorrowAndLend.sol)

import { IOrigamiBorrowAndLend } from "contracts/interfaces/common/borrowAndLend/IOrigamiBorrowAndLend.sol";
import { IMorpho, Id as MorphoMarketId, MarketParams as MorphoMarketParams } from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";
import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";

/**
 * @notice An Origami abstraction over a borrow/lend money market for
 * a single `supplyToken` and a single `borrowToken`.
 * This is a Morpho specific interface
 */
interface IOrigamiMorphoBorrowAndLend is IOrigamiBorrowAndLend {
    event MaxSafeLtvSet(uint256 _maxSafeLtv);
    event SwapperSet(address indexed swapper);

    /**
     * @notice Set the max LTV we will allow when borrowing or withdrawing collateral.
     * @dev The morpho LTV is the liquidation LTV only, we don't want to allow up to that limit
     */
    function setMaxSafeLtv(uint256 _maxSafeLtv) external;

    /**
     * @notice Set the swapper responsible for `borrowToken` <--> `supplyToken` swaps
     */
    function setSwapper(address _swapper) external;

    /**
     * @notice Increase the leverage of the existing position, by supplying `supplyToken` as collateral
     * and borrowing `borrowToken` and swapping that back to `supplyToken`
     * @dev The totalCollateralSupplied may include any surplus after swapping from the debt to collateral
     */
    function increaseLeverage(
        uint256 supplyCollateralAmount,
        uint256 borrowAmount,
        bytes memory swapData,
        uint256 supplyCollateralSurplusThreshold
    ) external returns (uint256 totalCollateralSupplied);

    /**
     * @notice Decrease the leverage of the existing position, by repaying `borrowToken`
     * and withdrawing `supplyToken` collateral then swapping that back to `borrowToken`
     */
    function decreaseLeverage(
        uint256 repayAmount,
        uint256 withdrawCollateralAmount,
        bytes memory swapData,
        uint256 repaySurplusThreshold
    ) external returns  (
        uint256 debtRepaidAmount, 
        uint256 surplusDebtRepaid
    );

    /**
     * @notice The morpho singleton contract
     */
    function morpho() external view returns (IMorpho);

    /**
     * @notice The Morpho oracle used for the target market
     */
    function morphoMarketOracle() external view returns (address);

    /**
     * @notice The Morpho Interest Rate Model used for the target market
     */
    function morphoMarketIrm() external view returns (address);

    /**
     * @notice The Morpho Liquidation LTV for the target market
     */
    function morphoMarketLltv() external view returns (uint96);

    /**
     * @notice The Morpho market parameters
     */
    function getMarketParams() external view returns (MorphoMarketParams memory);

    /**
     * @notice The derived Morpho market ID given the market parameters
     */
    function marketId() external view returns (MorphoMarketId);

    /**
     * @notice The max LTV we will allow when borrowing or withdrawing collateral.
     * @dev The morpho LTV is the liquidation LTV only, we don't want to allow up to that limit
     */
    function maxSafeLtv() external view returns (uint256);
    
    /**
     * @notice The swapper for `borrowToken` <--> `supplyToken`
     */
    function swapper() external view returns (IOrigamiSwapper);

    /**
     * @notice Returns the curent Morpho position data
     */
    function debtAccountData() external view returns (
        uint256 collateral,
        uint256 collateralPrice,
        uint256 borrowed,
        uint256 maxBorrow,
        uint256 currentLtv,
        uint256 healthFactor
    );
}