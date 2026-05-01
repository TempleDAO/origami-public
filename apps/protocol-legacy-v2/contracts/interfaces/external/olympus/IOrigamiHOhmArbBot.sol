pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV3SwapRouter } from "contracts/interfaces/external/uniswap/IUniswapV3SwapRouter.sol";
import { IUniswapV3QuoterV2 } from "contracts/interfaces/external/uniswap/IUniswapV3QuoterV2.sol";
import { IOlympusStaking } from "contracts/interfaces/external/olympus/IOlympusStaking.sol";
import { IGOHM } from "contracts/interfaces/external/olympus/IGOHM.sol";
import { IOrigamiTokenizedBalanceSheetVault } from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";
import { IMorpho } from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";

/**
 * @title Origami hOHM arbitrage bot
 * @notice Close the arbitrage for known/fixed routes between hOHM and the underlying
 * gOHM collateral and USDS liabilities
 * 
 * The contract does not need a starting sUSDS balance, unless it expects to operate at a loss.
 * A bot will monitor and will execute either route 1 or route 2 when appropriate.
 * 
 * ROUTE 1 - when hOHM is trading at a discount:
 *  1. Flashloan sUSDS via MORPHO
 *  2. Sell sUSDS (from this contract balance) to buy hOHM via uniswap
 *  3. Redeem sUSDS for USDS - Enough to cover hOHM liabilities for exit in step 4
 *  4. Redeem hOHM: pay USDS (from 3), receive gOHM
 *  5. Unstake gOHM (from 4) for OHM
 *  6. Sell OHM (from 5) for sUSDS via uniswap
 *  7. Repay sUSDS flashloan
 *  8. Ensure min profit is met. 
 *      Profit = (6) - (2) - (3)
 *
 * ROUTE 2 - when hOHM is trading at a premium:
 *  1. Flashloan sUSDS via MORPHO
 *  2. Sell sUSDS (from this contract balance) to buy OHM via uniswap
 *  3. Stake OHM (from 2) for gOHM
 *  4. Mint hOHM: pay gOHM (from 3), receive USDS
 *  5. Use USDS (from 4) to mint sUSDS
 *  6. Sell hOHM (from 4) for sUSDS via uniswap
 *  7. Repay sUSDS flashloan
 *  8. Ensure min profit is met. 
 *      Profit = (6) + (7) - (2)
 */
interface IOrigamiHOhmArbBot {

    struct Route1Quote {
        /// @dev The expected profit (positive) or loss (negative) from this route
        int256 profit;

        /// @dev The amount of USDS to pay when redeeming hOHM
        uint256 usdsToExitHohm;

        /// @dev The amount of OHM sold into the OHM/sUSDS pool
        uint256 ohmSold;
    }

    struct Route2Quote {
        /// @dev The expected profit (positive) or loss (negative) from this route
        int256 profit;

        /// @dev The amount of OHM bought from the OHM/sUSDS pool
        uint256 ohmBought;

        /// @dev The amount of gOHM received from staking `ohmBought`
        uint256 gOhmReceived;

        /// @dev The amount of hOHM minted from the `gOhmReceived`
        uint256 hOhmMinted;

        /// @dev The amount of USDS received when minting hOHM from the `gOhmReceived`
        uint256 usdsReceived;
    }

    error MinProfitNotMet(int256 minProfitExpected, int256 profit);

    /// @notice Origami hOHM Tokenized Balance Sheet Vault
    function hOHM() external view returns (IOrigamiTokenizedBalanceSheetVault);

    /// @notice Olympus' governance OHM token
    function gOHM() external view returns (IGOHM);

    /// @notice Olympus' OHM token
    function OHM() external view returns (IERC20);

    /// @notice Olympus OHM <--> gOHM staking contract
    function olympusStaking() external view returns (IOlympusStaking);

    /// @notice SKY USDS stablecoin
    function USDS() external view returns (IERC20);

    /// @notice SKY sUSDS savings vault for USDS
    function sUSDS() external view returns (IERC4626);

    /// @notice The Uniswap V3 swap router
    function uniV3Router() external view returns (IUniswapV3SwapRouter);

    /// @notice The Uniswap V3 quoter peripheral contract
    function uniV3Quoter() external view returns (IUniswapV3QuoterV2);

    /// @notice Morpho singleton for flashloans
    function MORPHO() external view returns (IMorpho);

    /// @notice Executes a batch of function calls on this contract.
    function multicall(bytes[] calldata data) external returns (bytes[] memory results);

    /// @notice The owner can pre-approve token spend to particular contracts
    function approveToken(IERC20 token, address spender, uint256 amount) external;

    /// @notice The owner can recover tokens
    function recoverToken(IERC20 token, address to, uint256 amount) external;

    /**
     * @notice Get the quote details for Route 1
     * @dev Should be called via callStatic() to emulate a view 
     * (uniswap quoter doesn't allow the function to be a view)
     */
    function quoteRoute1(
        uint256 sUsdsSold,
        uint24 susdsHohmPoolFee,
        uint24 ohmSusdsPoolFee
    ) external returns (Route1Quote memory);

    /**
     * @notice Execute the arbitrage for Route 1
     * @dev Will revert if the actual profit is less than `minProfit`
     */
    function executeRoute1(
        uint256 sUsdsSold,
        uint256 sUsdsFlashAmount,
        int256 minProfit,
        uint24 susdsHohmPoolFee,
        uint24 ohmSusdsPoolFee,
        uint256 deadline
    ) external returns (int256 profit);

    /**
     * @notice Get the quote details for Route 2
     * @dev Should be called via callStatic() to emulate a view 
     * (uniswap quoter doesn't allow the function to be a view)
     */
    function quoteRoute2(
        uint256 sUsdsSold,
        uint24 susdsHohmPoolFee,
        uint24 ohmSusdsPoolFee
    ) external returns (Route2Quote memory quoteData);

    /**
     * @notice Execute the arbitrage for Route 2
     * @dev Will revert if the actual profit is less than `minProfit`
     */
    function executeRoute2(
        uint256 sUsdsSold,
        int256 minProfit,
        uint24 susdsHohmPoolFee,
        uint24 ohmSusdsPoolFee,
        uint256 deadline
    ) external returns (int256 profit);

    /**
     * @notice Get a quote to swap `amountIn` of `tokenIn` to `tokenOut` for a given
     * pool fee
     */
    function uniV3Quote(
        IERC20 tokenIn,
        uint256 amountIn,
        IERC20 tokenOut,
        uint24 fee
    ) external returns (uint256 amountOut);
}
