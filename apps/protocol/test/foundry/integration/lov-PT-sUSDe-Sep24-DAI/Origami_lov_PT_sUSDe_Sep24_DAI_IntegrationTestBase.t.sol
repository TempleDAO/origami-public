pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IMorpho } from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";

import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiLovTokenMorphoManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenMorphoManager.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { ExternalContracts, LovTokenContracts, Origami_lov_PT_sUSDe_Sep24_DAI_TestDeployer } from "test/foundry/deploys/lov-PT-sUSDe-Sep24-DAI/Origami_lov_PT_sUSDe_Sep24_DAI_TestDeployer.t.sol";
import { DummyLovTokenSwapper } from "contracts/test/investments/lovToken/DummyLovTokenSwapper.sol";

contract Origami_lov_PT_sUSDe_Sep24_DAI_IntegrationTestBase is OrigamiTest {
    using OrigamiMath for uint256;

    error BadSwapParam(uint256 expected, uint256 found);
    error UnknownSwapAmount_BorrowToReserve(uint256 amount);
    error UnknownSwapAmount_ReserveToBorrow(uint256 amount);
    error InvalidRebalanceUpParam();
    error InvalidRebalanceDownParam();

    Origami_lov_PT_sUSDe_Sep24_DAI_TestDeployer internal deployer;
    ExternalContracts public externalContracts;
    LovTokenContracts public lovTokenContracts;

    function setUp() public virtual {
        fork("mainnet", 20308622);
        vm.warp(1721006984);

        deployer = new Origami_lov_PT_sUSDe_Sep24_DAI_TestDeployer(); 
        origamiMultisig = address(deployer);
        (externalContracts, lovTokenContracts) = deployer.deployForked(origamiMultisig, feeCollector, overlord, vm);

        // Bootstrap the morpho pool with some DAI
        supplyIntoMorpho(500_000e18);

        deal(address(externalContracts.ptSUSDeToken), address(lovTokenContracts.swapper), 10_000_000e18, false);
        deal(address(externalContracts.daiToken), address(lovTokenContracts.swapper), 10_000_000e18, false);
    }

    function supplyIntoMorpho(uint256 amount) internal {
        deal(address(externalContracts.daiToken), origamiMultisig, amount, false);
        vm.startPrank(origamiMultisig);
        IMorpho morpho = lovTokenContracts.borrowLend.morpho();
        SafeERC20.forceApprove(externalContracts.daiToken, address(morpho), amount);
        morpho.supply(lovTokenContracts.borrowLend.getMarketParams(), amount, 0, origamiMultisig, "");
        vm.stopPrank();
    }

    function investLovToken(address account, uint256 amount) internal returns (uint256 amountOut) {
        deal(address(externalContracts.ptSUSDeToken), account, amount, false);
        vm.startPrank(account);
        externalContracts.ptSUSDeToken.approve(address(lovTokenContracts.lovToken), amount);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovTokenContracts.lovToken.investQuote(
            amount,
            address(externalContracts.ptSUSDeToken),
            0,
            0
        );

        amountOut = lovTokenContracts.lovToken.investWithToken(quoteData);
    }

    function exitLovToken(address account, uint256 amount, address recipient) internal returns (uint256 amountOut) {
        vm.startPrank(account);

        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = lovTokenContracts.lovToken.exitQuote(
            amount,
            address(externalContracts.ptSUSDeToken),
            0,
            0
        );

        amountOut = lovTokenContracts.lovToken.exitToToken(quoteData, recipient);
    }

    function solveRebalanceDownAmount(uint256 targetLTV, uint256 marketPtToDaiPrice) internal view returns (uint256 reservesAmount) {
        /*
            Solving for the new PT we need to add:
            targetRatio = (currentDebt + (newAssets * morphoPrice)) / ((currentAssets + newAssets) * marketPrice)
            targetRatio * marketPrice * (currentAssets + newAssets) = currentDebt + (newAssets * morphoPrice)
            targetRatio * marketPrice * currentAssets + targetRatio * newAssets = currentDebt + newAssets * morphoPrice
            targetRatio * marketPrice * currentAssets - currentDebt = newAssets * morphoPrice - targetRatio * newAssets
            targetRatio * marketPrice * currentAssets - currentDebt = newAssets * (morphoPrice - targetRatio)
            newAssets[PT] = 
                (targetRatio[] * marketPrice[DAI/PT] * currentAssets[PT] - currentDebt[DAI])
                / (morphoPrice[DAI/PT] - targetRatio[])
        */
        uint256 _currentDebt = lovTokenContracts.borrowLend.debtBalance();
        uint256 _currentAssets = lovTokenContracts.borrowLend.suppliedBalance();

        uint256 marketDaiToPtPrice = 1e18 * 1e18 / marketPtToDaiPrice;
        uint256 numerator = (
            targetLTV 
            * marketDaiToPtPrice / 1e18
            * _currentAssets / 1e18
        ) - _currentDebt;
        uint256 denominator = 1e18 - targetLTV;

        reservesAmount = numerator * 1e18 / denominator;
    }

    function solveRebalanceUpAmount(uint256 targetLTV, uint256 marketPtToDaiPrice) internal view returns (uint256 reservesAmount) {
        /*
            Solving for the new PT we need to add:
            targetRatio = (currentDebt - (newAssets * morphoPrice)) / ((currentAssets - newAssets) * marketPrice)
            targetRatio * marketPrice * (currentAssets - newAssets) = currentDebt - (newAssets * morphoPrice)
            targetRatio * marketPrice * currentAssets - targetRatio * newAssets = currentDebt - newAssets * morphoPrice
            targetRatio * marketPrice * currentAssets - currentDebt = targetRatio * newAssets - newAssets * morphoPrice
            targetRatio * marketPrice * currentAssets - currentDebt = newAssets * (targetRatio - morphoPrice)
            currentDebt - targetRatio * marketPrice * currentAssets = newAssets * (morphoPrice - targetRatio)
            newAssets[PT] = 
                (currentDebt[DAI] - targetRatio[] * marketPrice[DAI/PT] * currentAssets[PT])
                / (targetRatio[] - morphoPrice[DAI/PT])
        */
        uint256 _currentDebt = lovTokenContracts.borrowLend.debtBalance();
        uint256 _currentAssets = lovTokenContracts.borrowLend.suppliedBalance();

        uint256 marketDaiToPtPrice = 1e18 * 1e18 / marketPtToDaiPrice;
        uint256 numerator = _currentDebt - (
            targetLTV 
            * marketDaiToPtPrice / 1e18
            * _currentAssets / 1e18
        );
        uint256 denominator = 1e18 - targetLTV;

        reservesAmount = numerator * 1e18 / denominator;
    }

    function rebalanceDownParams(
        uint256 targetLTV,
        uint256 swapSlippageBps,
        uint256 alSlippageBps
    ) internal virtual view returns (
        IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params,
        uint256 reservesAmount
    ) {
        uint256 marketPtToDaiPrice = lovTokenContracts.ptSUsdeToDaiOracle.latestPrice(
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN
        );

        reservesAmount = params.supplyAmount = solveRebalanceDownAmount(
            targetLTV,
            marketPtToDaiPrice
        );

        // How much DAI do we need to borrow in order to swap to that supplyAmount of PT
        // Use the dex price
        params.borrowAmount = params.supplyAmount * marketPtToDaiPrice / 1e18;

        // Add slippage to the amount we actually borrow so after the swap
        // we ensure we have more collateral than supplyAmount
        params.borrowAmount = params.borrowAmount.inverseSubtractBps(swapSlippageBps, OrigamiMath.Rounding.ROUND_DOWN);

        params.swapData = abi.encode(DummyLovTokenSwapper.SwapData(params.supplyAmount));

        {
            (uint256 existingAssets, uint256 existingLiabilities,) = lovTokenContracts.lovTokenManager.assetsAndLiabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
            uint256 newAssets = existingAssets + params.supplyAmount;
            uint256 newLiabilities = existingLiabilities + (params.borrowAmount * 1e18 / marketPtToDaiPrice);
            uint256 targetAL = newAssets * 1e18 / newLiabilities;

            params.minNewAL = uint128(targetAL.subtractBps(alSlippageBps, OrigamiMath.Rounding.ROUND_DOWN));
            params.minNewAL = convertAL(params.minNewAL, marketPtToDaiPrice);
            params.maxNewAL = uint128(targetAL.addBps(alSlippageBps, OrigamiMath.Rounding.ROUND_UP));
            params.maxNewAL = convertAL(params.maxNewAL, marketPtToDaiPrice);
        }

        // When to sweep surplus balances and supply as collateral
        params.supplyCollateralSurplusThreshold = 0;
    }

    function convertAL(uint128 al, uint256 oraclePrice) internal pure returns (uint128) {
        return uint128(uint256(al).mulDiv(1e18, oraclePrice, OrigamiMath.Rounding.ROUND_UP));
    }

    // Increase liabilities to lower A/L
    function doRebalanceDown(
        uint256 targetLTV, 
        uint256 slippageBps, 
        uint256 alSlippageBps
    ) internal virtual returns (uint256 reservesAmount) {
        IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params;
        (params, reservesAmount) = rebalanceDownParams(targetLTV, slippageBps, alSlippageBps);

        vm.startPrank(origamiMultisig);
        lovTokenContracts.lovTokenManager.rebalanceDown(params);
    }
    
    function rebalanceUpParams(
        uint256 targetLTV,
        uint256 swapSlippageBps,
        uint256 alSlippageBps
    ) internal virtual view returns (
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params
    ) {
        uint256 marketPtToDaiPrice = lovTokenContracts.ptSUsdeToDaiOracle.latestPrice(
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN
        );

        // ideal reserves (USDe) amount to remove
        params.withdrawCollateralAmount = solveRebalanceUpAmount(targetLTV, marketPtToDaiPrice);

        // How much DAI do we need to repay in order to swap to that supplyAmount of PT
        // Use the dex price
        params.repayAmount = params.withdrawCollateralAmount * marketPtToDaiPrice / 1e18;

        params.swapData = abi.encode(DummyLovTokenSwapper.SwapData(params.withdrawCollateralAmount));

        // If there's a fee (currently disabled on Spark) then remove that from what we want to request
        uint256 feeBps = 0;
        params.repayAmount = params.repayAmount.inverseSubtractBps(feeBps, OrigamiMath.Rounding.ROUND_UP);

        // Apply slippage to the amount what's actually flashloaned is the lowest amount which
        // we would get when converting the collateral [USDe] to the flashloan asset [wETH].
        // We need to be sure it can be paid off. Any remaining wETH is repaid on the wETH debt in Spark
        params.repayAmount = params.repayAmount.subtractBps(swapSlippageBps, OrigamiMath.Rounding.ROUND_DOWN);

        // When to sweep surplus balances and repay
        params.repaySurplusThreshold = 1_000_000e18;

        {
            (uint256 existingAssets, uint256 existingLiabilities,) = lovTokenContracts.lovTokenManager.assetsAndLiabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
            uint256 newAssets = existingAssets - params.withdrawCollateralAmount;
            uint256 newLiabilities = existingLiabilities - (params.repayAmount * 1e18 / marketPtToDaiPrice);
            uint256 targetAL = newAssets * 1e18 / newLiabilities;
            params.minNewAL = uint128(targetAL.subtractBps(alSlippageBps, OrigamiMath.Rounding.ROUND_DOWN));
            params.minNewAL = convertAL(params.minNewAL, marketPtToDaiPrice);
            params.maxNewAL = uint128(targetAL.addBps(alSlippageBps, OrigamiMath.Rounding.ROUND_UP));
            params.maxNewAL = convertAL(params.maxNewAL, marketPtToDaiPrice);
        }
    }

    // Decrease liabilities to raise A/L
    function doRebalanceUp(
        uint256 targetLTV, 
        uint256 slippageBps, 
        uint256 alSlippageBps
    ) internal virtual {
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params = rebalanceUpParams(targetLTV, slippageBps, alSlippageBps);
        vm.startPrank(origamiMultisig);

        lovTokenContracts.lovTokenManager.rebalanceUp(params);
    }
}
