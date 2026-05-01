pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/olympus/OrigamiCoolerMigrator.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IUniswapV3QuoterV2 } from "contracts/interfaces/external/uniswap/IUniswapV3QuoterV2.sol";
import { IUniswapV3SwapRouter } from "contracts/interfaces/external/uniswap/IUniswapV3SwapRouter.sol";
import { IOlympusStaking } from "contracts/interfaces/external/olympus/IOlympusStaking.sol";
import { IGOHM } from "contracts/interfaces/external/olympus/IGOHM.sol";
import { IOrigamiTokenizedBalanceSheetVault } from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";
import { IOrigamiHOhmArbBot } from "contracts/interfaces/external/olympus/IOrigamiHOhmArbBot.sol";

import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { SafeCast } from "contracts/libraries/SafeCast.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

import { IMorpho } from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";
import { IMorphoFlashLoanCallback } from "@morpho-org/morpho-blue/src/interfaces/IMorphoCallbacks.sol";

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
contract OrigamiHOhmArbBot is IOrigamiHOhmArbBot, IMorphoFlashLoanCallback, OrigamiElevatedAccess {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC4626;
    using SafeCast for uint256;

    /// @inheritdoc IOrigamiHOhmArbBot
    IOrigamiTokenizedBalanceSheetVault public immutable override hOHM;
    
    /// @inheritdoc IOrigamiHOhmArbBot
    IGOHM public immutable override gOHM;

    /// @inheritdoc IOrigamiHOhmArbBot
    IERC20 public immutable override OHM;

    /// @inheritdoc IOrigamiHOhmArbBot
    IOlympusStaking public immutable override olympusStaking;

    /// @inheritdoc IOrigamiHOhmArbBot
    IERC20 public immutable override USDS;

    /// @inheritdoc IOrigamiHOhmArbBot
    IERC4626 public immutable override sUSDS;

    /// @inheritdoc IOrigamiHOhmArbBot
    IUniswapV3SwapRouter public immutable override uniV3Router;

    /// @inheritdoc IOrigamiHOhmArbBot
    IUniswapV3QuoterV2 public immutable override uniV3Quoter;

    /// @inheritdoc IOrigamiHOhmArbBot
    IMorpho public immutable override MORPHO;

    // @dev Internally used for flashloan callbacks
    struct _FlashloanData {
        _Route route;
        uint256 sUsdsSold;
        uint24 susdsHohmPoolFee;
        uint24 ohmSusdsPoolFee;
        uint256 deadline;
    }

    enum _Route {
        ONE,
        TWO
    }

    constructor(
        address initialOwner_,
        address hOHM_,
        address olympusStaking_,
        address sUsds_,
        address uniV3Router_,
        address uniV3Quoter_,
        address morpho_
    ) OrigamiElevatedAccess(initialOwner_) {
        olympusStaking = IOlympusStaking(olympusStaking_);
        gOHM = IGOHM(olympusStaking.gOHM());
        OHM = IERC20(olympusStaking.OHM());
        hOHM = IOrigamiTokenizedBalanceSheetVault(hOHM_);
        sUSDS = IERC4626(sUsds_);
        USDS = IERC20(sUSDS.asset());
        uniV3Router = IUniswapV3SwapRouter(uniV3Router_);
        uniV3Quoter = IUniswapV3QuoterV2(uniV3Quoter_);
        MORPHO = IMorpho(morpho_);
    }

    /// @inheritdoc IOrigamiHOhmArbBot
    function multicall(bytes[] calldata data) external override returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            results[i] = Address.functionDelegateCall(address(this), data[i]);
        }
    }

    /// @inheritdoc IOrigamiHOhmArbBot
    function approveToken(
        IERC20 token,
        address spender,
        uint256 amount
    ) external override onlyElevatedAccess {
        token.forceApprove(spender, amount);
    }
     
    /// @inheritdoc IOrigamiHOhmArbBot
    function recoverToken(IERC20 token, address to, uint256 amount) external override onlyElevatedAccess {
        // The asset token is sent straight to the manager on deposit/withdraw - so it's acceptable to recover from here.
        emit CommonEventsAndErrors.TokenRecovered(to, address(token), amount);
        token.safeTransfer(to, amount);
    }

    /// @inheritdoc IOrigamiHOhmArbBot
    function quoteRoute1(
        uint256 sUsdsSold,
        uint24 susdsHohmPoolFee,
        uint24 ohmSusdsPoolFee
    ) external override returns (Route1Quote memory quoteData) {
        // Sell sUSDS to buy hOHM on uniswap
        uint256 hohmBought = _uniV3Quote(
            sUSDS,
            sUsdsSold,
            hOHM,
            susdsHohmPoolFee
        );

        // Exit hOHM, receiving gOHM, paying in USDS
        uint256 gOhmFromHohmExit;
        (gOhmFromHohmExit, quoteData.usdsToExitHohm) = _exitHohmQuote(hohmBought);

        // Withdraw USDS from sUSDS to cover hOHM exit
        uint256 sUsdsToExitHohm = sUSDS.previewWithdraw(quoteData.usdsToExitHohm);

        // Swap unstaked gOHM to buy sUSDS
        quoteData.ohmSold = gOHM.balanceFrom(gOhmFromHohmExit);
        uint256 sUsdsRevenue = _uniV3Quote(
            OHM,
            quoteData.ohmSold,
            sUSDS,
            ohmSusdsPoolFee
        );

        quoteData.profit = sUsdsRevenue.encodeInt256() - (sUsdsToExitHohm + sUsdsSold).encodeInt256();
    }

    /// @inheritdoc IOrigamiHOhmArbBot
    function executeRoute1(
        uint256 sUsdsSold,
        uint256 sUsdsFlashAmount,
        int256 minProfit,
        uint24 susdsHohmPoolFee,
        uint24 ohmSusdsPoolFee,
        uint256 deadline
    ) external override onlyElevatedAccess returns (int256 profit) {
        uint256 sUsdsBalanceStart = sUSDS.balanceOf(address(this));

        bytes memory flashloanData = abi.encode(_FlashloanData({
            route: _Route.ONE,
            sUsdsSold: sUsdsSold,
            susdsHohmPoolFee: susdsHohmPoolFee,
            ohmSusdsPoolFee: ohmSusdsPoolFee,
            deadline: deadline
        }));

        MORPHO.flashLoan(address(sUSDS), sUsdsFlashAmount, flashloanData);

        // Calc profit and check vs slippage
        profit = sUSDS.balanceOf(address(this)).encodeInt256() - sUsdsBalanceStart.encodeInt256();
        if (profit < minProfit) revert MinProfitNotMet(minProfit, profit);
    }

    function onMorphoFlashLoan(uint256 /*flashLoanAmount*/, bytes calldata params) external override {
        // Can only be called by the Morpho pool, and the FL can only ever be initiated by this contract.
        if (msg.sender != address(MORPHO)) revert CommonEventsAndErrors.InvalidAccess();

        _FlashloanData memory data = abi.decode(params, (_FlashloanData));

        if (data.route == _Route.ONE) {
            _handleRoute1Flashloan(data);
        } else {
            _handleRoute2Flashloan(data);
        }
    }

    function _handleRoute1Flashloan(_FlashloanData memory data) private {
        // Sell sUSDS to buy hOHM on uniswap
        uint256 hohmBought = _uniV3Swap(
            sUSDS,
            data.sUsdsSold,
            hOHM,
            data.susdsHohmPoolFee,
            data.deadline
        );

        // Withdraw any remaining into USDS in order to exit hOHM
        sUSDS.redeem(sUSDS.balanceOf(address(this)), address(this), address(this));

        // Exit hOHM, receiving gOHM, paying in USDS
        (uint256 gOhmFromHohmExit, ) = _exitHohm(hohmBought);

        // Deposit any remaining USDS back into sUSDS
        uint256 usdsBalance = USDS.balanceOf(address(this));
        if (usdsBalance > 0) {
            sUSDS.deposit(usdsBalance, address(this));
        }

        // Swap unstaked gOHM to buy sUSDS
        uint256 ohmFromHohmExit = olympusStaking.unstake(address(this), gOhmFromHohmExit, false, false);
        _uniV3Swap(
            OHM,
            ohmFromHohmExit,
            sUSDS,
            data.ohmSusdsPoolFee, 
            data.deadline
        );
    }

    /// @inheritdoc IOrigamiHOhmArbBot
    function quoteRoute2(
        uint256 sUsdsSold,
        uint24 susdsHohmPoolFee,
        uint24 ohmSusdsPoolFee
    ) external override returns (Route2Quote memory quoteData) {
        // Sell sUSDS to buy OHM on uniswap
        quoteData.ohmBought = _uniV3Quote(
            sUSDS,
            sUsdsSold,
            OHM,
            ohmSusdsPoolFee
        );

        quoteData.gOhmReceived = gOHM.balanceTo(quoteData.ohmBought);

        // Mint hOHM with the gOHM, also receiving USDS liabilities
        (
            quoteData.hOhmMinted,
            quoteData.usdsReceived
        ) = _mintHohmQuote(quoteData.gOhmReceived);

        // Mint sUSDS with the USDS
        uint256 sUsdsReceived = sUSDS.previewDeposit(quoteData.usdsReceived);

        // Sell hOHM for sUSDS
        uint256 sUsdsBought = _uniV3Quote(
            hOHM,
            quoteData.hOhmMinted,
            sUSDS,
            susdsHohmPoolFee
        );

        quoteData.profit = (sUsdsReceived + sUsdsBought).encodeInt256() - sUsdsSold.encodeInt256();
    }

    /// @inheritdoc IOrigamiHOhmArbBot
    function executeRoute2(
        uint256 sUsdsSold,
        int256 minProfit,
        uint24 susdsHohmPoolFee,
        uint24 ohmSusdsPoolFee,
        uint256 deadline
    ) external override onlyElevatedAccess returns (int256 profit) {
        uint256 sUsdsBalanceStart = sUSDS.balanceOf(address(this));

        bytes memory flashloanData = abi.encode(_FlashloanData({
            route: _Route.TWO,
            sUsdsSold: sUsdsSold,
            susdsHohmPoolFee: susdsHohmPoolFee,
            ohmSusdsPoolFee: ohmSusdsPoolFee,
            deadline: deadline
        }));

        MORPHO.flashLoan(address(sUSDS), sUsdsSold, flashloanData);

        // Calc profit and check vs slippage
        profit = sUSDS.balanceOf(address(this)).encodeInt256() - sUsdsBalanceStart.encodeInt256();
        if (profit < minProfit) revert MinProfitNotMet(minProfit, profit);
    }

    function _handleRoute2Flashloan(_FlashloanData memory data) private {
        // Sell sUSDS to buy OHM on uniswap
        uint256 ohmBought = _uniV3Swap(
            sUSDS,
            data.sUsdsSold,
            OHM,
            data.ohmSusdsPoolFee,
            data.deadline
        );

        // Mint hOHM with the gOHM, also receiving USDS liabilities
        uint256 gohmBought = olympusStaking.stake(address(this), ohmBought, false, true);
        (
            uint256 hohmMinted,
            uint256 usdsReceived
        ) = _mintHohm(gohmBought);

        // Mint sUSDS with the USDS
        sUSDS.deposit(usdsReceived, address(this));

        // Sell hOHM for sUSDS
        _uniV3Swap(
            hOHM,
            hohmMinted,
            sUSDS,
            data.susdsHohmPoolFee,
            data.deadline
        );
    }

    /// @inheritdoc IOrigamiHOhmArbBot
    function uniV3Quote(
        IERC20 tokenIn,
        uint256 amountIn,
        IERC20 tokenOut,
        uint24 fee
    ) external override returns (uint256 amountOut) {
        // Wrapped rather than public for small gas savings during execution
        return _uniV3Quote(tokenIn, amountIn, tokenOut, fee);
    }

    function _mintHohmQuote(uint256 gOhmAmountIn) internal view returns (
        uint256 hOhmSharesOut,
        uint256 usdsAmountOut
    ) {
        uint256[] memory liabilities;
        (
            hOhmSharesOut,
            /*assets*/,
            liabilities
        ) = hOHM.previewJoinWithToken(address(gOHM), gOhmAmountIn);
        usdsAmountOut = liabilities[0];
    }

    function _mintHohm(uint256 gOhmAmountIn) internal returns (
        uint256 hOhmSharesOut,
        uint256 usdsAmountOut
    ) {
        uint256[] memory liabilities;
        (
            hOhmSharesOut,
            /*assets*/,
            liabilities
        ) = hOHM.joinWithToken(address(gOHM), gOhmAmountIn, address(this));
        usdsAmountOut = liabilities[0];
    }

    function _exitHohmQuote(uint256 hOhmAmountIn) internal view returns (
        uint256 gOhmAmountOut,
        uint256 usdsAmountIn
    ) {
        (
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = hOHM.previewExitWithShares(hOhmAmountIn);
        gOhmAmountOut = assets[0];
        usdsAmountIn = liabilities[0];
    }

    function _exitHohm(uint256 hohmAmountOut) internal returns (
        uint256 gOhmAmountOut,
        uint256 usdsAmountIn
    ) {
        (
            uint256[] memory assets,
            uint256[] memory liabilities
        ) = hOHM.exitWithShares(hohmAmountOut, address(this), address(this));
        gOhmAmountOut = assets[0];
        usdsAmountIn = liabilities[0];
    }
    
    function _uniV3Quote(IERC20 tokenIn, uint256 amountIn, IERC20 tokenOut, uint24 fee) private returns (uint256 amountOut) {
        IUniswapV3QuoterV2.QuoteExactInputSingleParams memory quoteParams = IUniswapV3QuoterV2.QuoteExactInputSingleParams({
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            amountIn: amountIn,
            fee: fee,
            sqrtPriceLimitX96: 0 // Not required for quote
        });

        (
            amountOut,
            /*uint160 sqrtPriceX96After*/,
            /*uint32 initializedTicksCrossed*/,
            /*uint256 gasEstimate*/
        ) = uniV3Quoter.quoteExactInputSingle(quoteParams);
    }

    function _uniV3Swap(
        IERC20 tokenIn,
        uint256 amountIn,
        IERC20 tokenOut,
        uint24 fee,
        uint256 deadline
    ) internal returns (uint256 amountOut) {
        return uniV3Router.exactInputSingle(IUniswapV3SwapRouter.ExactInputSingleParams({
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            fee: fee,
            recipient: address(this),
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        }));
    }
}
