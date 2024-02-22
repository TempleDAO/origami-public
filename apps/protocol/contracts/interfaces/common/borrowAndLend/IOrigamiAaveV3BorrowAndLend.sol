pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/borrowAndLend/IOrigamiAaveV3BorrowAndLend.sol)

import { IPool as IAavePool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { IAToken as IAaveAToken } from "@aave/core-v3/contracts/interfaces/IAToken.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IOrigamiBorrowAndLend } from "contracts/interfaces/common/borrowAndLend/IOrigamiBorrowAndLend.sol";

/**
 * @notice An Origami abstraction over a borrow/lend money market for
 * a single `supplyToken` and a single `borrowToken`.
 * This is an Aave V3 specific interface, borrowing using variable debt only
 */
interface IOrigamiAaveV3BorrowAndLend is IOrigamiBorrowAndLend {
    event ReferralCodeSet(uint16 code);

    /**
     * @notice Set the Aave/Spark referral code
     */
    function setReferralCode(uint16 code) external;

    /**
     * @notice Allow the use of `supplyToken` as collateral within Aave/Spark
     */
    function setUserUseReserveAsCollateral(bool useAsCollateral) external;

    /**
     * @notice Update the e-mode category for the pool
     */
    function setEModeCategory(uint8 categoryId) external;

    /**
     * @notice The Aave/Spark pool contract
     */
    function aavePool() external view returns (IAavePool);

    /**
     * @notice The Aave/Spark rebasing aToken received when supplying `supplyToken`
     */
    function aaveAToken() external view returns (IAaveAToken);

    /**
     * @notice The Aave/Spark rebasing variable debt token received when borrowing `debtToken`
     */
    function aaveDebtToken() external view returns (IERC20Metadata);

    /**
     * @notice The referral code used when supplying/borrowing in Aave/Spark
     */
    function referralCode() external view returns (uint16);

    /**
     * @notice Returns the Aave/Spark account data
     * @return totalCollateralBase The total collateral of the user in the base currency used by the price feed
     * @return totalDebtBase The total debt of the user in the base currency used by the price feed
     * @return availableBorrowsBase The borrowing power left of the user in the base currency used by the price feed
     * @return currentLiquidationThreshold The liquidation threshold of the user
     * @return ltv The loan to value of The user
     * @return healthFactor The current health factor of the user
    */
    function debtAccountData() external view returns (
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    );
    
}