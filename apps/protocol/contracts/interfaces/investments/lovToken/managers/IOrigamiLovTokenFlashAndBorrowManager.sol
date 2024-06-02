pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/lovToken/managers/IOrigamiLovTokenFlashAndBorrowManager.sol)

import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";
import { IOrigamiFlashLoanReceiver } from "contracts/interfaces/common/flashLoan/IOrigamiFlashLoanReceiver.sol";
import { IOrigamiFlashLoanProvider } from "contracts/interfaces/common/flashLoan/IOrigamiFlashLoanProvider.sol";

/**
 * @title Origami lovToken Manager
 * @notice The delegated logic to handle deposits/exits, and borrow/repay (rebalances) into the underlying reserve token
 */
interface IOrigamiLovTokenFlashAndBorrowManager is IOrigamiLovTokenManager, IOrigamiFlashLoanReceiver {
    event SwapperSet(address indexed swapper);
    event FlashLoanProviderSet(address indexed provider);
    event OraclesSet(address indexed debtTokenToReserveTokenOracle, address indexed dynamicFeePriceOracle);
    event BorrowLendSet(address indexed addr);

    /**
     * @notice Set the swapper responsible for `reserveToken` <--> `debtToken` swaps
     */
    function setSwapper(address _swapper) external;

    /**
     * @notice Set the `reserveToken` <--> `debtToken` oracle configuration 
     */
    function setOracles(address _debtTokenToReserveTokenOracle, address _dynamicFeePriceOracle) external;
    
    /**
     * @notice Set the flash loan provider
     */
    function setFlashLoanProvider(address _provider) external;

    /**
     * @notice Set the Origami Borrow/Lend position holder
     */
    function setBorrowLend(address _address) external;

    struct RebalanceUpParams {
        // The amount of `debtToken` to flashloan, used to repay Aave/Spark debt
        uint256 flashLoanAmount;

        // The amount of `reserveToken` collateral to withdraw after debt is repaid
        uint256 collateralToWithdraw;

        // The swap quote data to swap from `reserveToken` -> `debtToken`
        bytes swapData;

        // The min balance threshold for when surplus balance of `debtToken` is repaid to the Spark/Aave position
        uint256 repaySurplusThreshold;

        // The minimum acceptable A/L, will revert if below this
        uint128 minNewAL;

        // The maximum acceptable A/L, will revert if above this
        uint128 maxNewAL;
    }

    /**
     * @notice Increase the A/L by reducing liabilities. Flash loan and repay debt, and withdraw collateral to repay the flash loan
     */
    function rebalanceUp(RebalanceUpParams calldata params) external;

    /**
     * @notice Force a rebalanceUp ignoring A/L ceiling/floor
     * @dev Separate function to above to have stricter control on who can force
     */
    function forceRebalanceUp(RebalanceUpParams calldata params) external;

    struct RebalanceDownParams {
        // The amount of new `debtToken` to flashloan
        uint256 flashLoanAmount;

        // The minimum amount of `reserveToken` expected when swapping from the flashloaned amount
        uint256 minExpectedReserveToken;

        // The swap quote data to swap from `debtToken` -> `reserveToken`
        bytes swapData;

        // The minimum acceptable A/L, will revert if below this
        uint128 minNewAL;

        // The maximum acceptable A/L, will revert if above this
        uint128 maxNewAL;
    }

    /**
     * @notice Decrease the A/L by increasing liabilities. Flash loan `debtToken` swap to `reserveToken`
     * and add as collateral into Aave/Spark. Then borrow `debtToken` to repay the flash loan.
     */
    function rebalanceDown(RebalanceDownParams calldata params) external;

    /**
     * @notice Force a rebalanceDown ignoring A/L ceiling/floor
     * @dev Separate function to above to have stricter control on who can force
     */
    function forceRebalanceDown(RebalanceDownParams calldata params) external;

    /**
     * @notice The flashLoan provider contract, which may be through Aave/Spark/Balancer/etc
     */
    function flashLoanProvider() external view returns (IOrigamiFlashLoanProvider);

    /**
     * @notice The swapper for `debtToken` <--> `reserveToken`
     */
    function swapper() external view returns (IOrigamiSwapper);

    /**
     * @notice The oracle to convert `debtToken` <--> `reserveToken`
     */
    function debtTokenToReserveTokenOracle() external view returns (IOrigamiOracle);

    /**
     * @notice The base asset used when retrieving the prices for dynamic fee calculations.
     */
    function dynamicFeeOracleBaseToken() external view returns (address);

    /**
     * @notice The oracle to use when observing prices which are used for the dynamic fee calculations
     */
    function dynamicFeePriceOracle() external view returns (IOrigamiOracle);
}