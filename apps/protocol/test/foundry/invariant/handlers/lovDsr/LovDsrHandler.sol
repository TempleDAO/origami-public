pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { TimestampStore } from "test/foundry/invariant/stores/TimestampStore.sol";
import { StateStore } from "test/foundry/invariant/stores/StateStore.sol";
import { BaseHandler } from "test/foundry/invariant/handlers/BaseHandler.sol";

import { ExternalContracts, OUsdcContracts, LovTokenContracts } from "test/foundry/deploys/lovDsr/OrigamiLovTokenTestDeployer.t.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiLovTokenErc4626Manager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenErc4626Manager.sol";
import { OrigamiLovTokenTestConstants as Constants } from "test/foundry/deploys/lovDsr/OrigamiLovTokenTestConstants.t.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { DummyLovTokenSwapper } from "contracts/test/investments/lovToken/DummyLovTokenSwapper.sol";

/// @notice Invariant Handler lovDSR
contract LovDsrHandler is BaseHandler {
    using OrigamiMath for uint256;

    error InvalidRebalanceUpParam();
    error InvalidRebalanceDownParam();

    address public overlord;
    ExternalContracts public externalContracts;
    OUsdcContracts public oUsdcContracts;
    LovTokenContracts public lovTokenContracts;

    uint256 public totalDaiDeposits;
    uint256 public totalDaiExits;

    constructor(
        TimestampStore timestampStore_,
        StateStore stateStore_,
        address _overlord,
        ExternalContracts memory _externalContracts,
        OUsdcContracts memory _oUsdcContracts,
        LovTokenContracts memory _lovTokenContracts
    )
        BaseHandler(timestampStore_, stateStore_)
    {
        overlord = _overlord;
        externalContracts = _externalContracts;
        oUsdcContracts = _oUsdcContracts;
        lovTokenContracts = _lovTokenContracts;
    }

    function investLovDsr_dai(
        uint256 amount, 
        uint256 timeJumpSeed
    ) external 
        instrument
        adjustTimestamp(timeJumpSeed) 
        useSender
    returns (uint256 amountOut) {
        // The min bound needs to be 1 share worth (plus a little for rounding)
        // The max is set so we don't trip borrow circuit breakers when borrower later
        {
            // + 2 to insure it rounds up and adds one
            uint256 minReserves = lovTokenContracts.lovDsrManager.sharesToReserves(1, IOrigamiOracle.PriceType.SPOT_PRICE) + 2;
            uint256 minInvest = externalContracts.sDaiToken.previewMint(minReserves) + 2;
            uint256 maxInvest = min(
                100_000e18,
                lovTokenContracts.lovDsrManager.maxInvest(address(externalContracts.daiToken))
            );

            if (maxInvest < minInvest) {
                stateStore.setFinishedEarly();
                return 0;
            }
            amount = _bound(amount, minInvest, maxInvest);
            if (amount == 0) {
                stateStore.setFinishedEarly();
                return 0;
            }
        }      

        totalDaiDeposits += amount;

        doMint(externalContracts.daiToken, msg.sender, amount);
        externalContracts.daiToken.approve(address(lovTokenContracts.lovDsr), amount);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovTokenContracts.lovDsr.investQuote(
            amount,
            address(externalContracts.daiToken),
            0,
            0
        );

        // Fees gobbled up since they round up
        if (quoteData.expectedInvestmentAmount == 0) {
            stateStore.setFinishedEarly();
            return 0;
        }

        uint256 alRatioBefore = lovTokenContracts.lovDsrManager.assetToLiabilityRatio();

        amountOut = lovTokenContracts.lovDsr.investWithToken(quoteData);
        uint256 alRatioAfter = lovTokenContracts.lovDsrManager.assetToLiabilityRatio();

        assertGe(alRatioAfter, alRatioBefore, "Invariant violation: investLovDsr_dai A/L after invest should be higher");
    }

    function exitLovDsr_dai(
        uint256 amount, 
        uint256 timeJumpSeed
    ) external 
        instrument
        adjustTimestamp(timeJumpSeed) 
        useSender
    returns (uint256 amountOut) {

        uint256 maxAvailableToExit = min(
            lovTokenContracts.lovDsr.balanceOf(msg.sender),
            lovTokenContracts.lovDsr.maxExit(address(externalContracts.daiToken))
        );
        amount = _bound(amount, 0, maxAvailableToExit);
        
        // Very small amounts may run into AL validation issues where the ratioAfter < ratioBefore
        // because of upstream ERC-4626 interest accrual.
        if (amount < 10) {
            stateStore.setFinishedEarly();
            return 0;
        }

        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovDsr.exitQuote(
            amount,
            address(externalContracts.daiToken),
            0,
            0
        );

        amountOut = lovTokenContracts.lovDsr.exitToToken(quoteData, msg.sender);
        totalDaiExits += amountOut;
    }

    function rebalanceDown(
        uint256 targetAL, 
        uint256 timeJumpSeed
    ) external
        instrument
        adjustTimestamp(timeJumpSeed) 
    {
        // Given the time jump, checkpoint the current borrower debt first so we calculate the right rebalance amounts and bounds
        checkpointBorrowers();
        uint256 alRatioBefore = lovTokenContracts.lovDsrManager.assetToLiabilityRatio();

        if (alRatioBefore < Constants.REBALANCE_AL_FLOOR) {
            stateStore.setFinishedEarly();
            return;
        }

        if (alRatioBefore < Constants.REBALANCE_AL_CEILING) {
            targetAL = _bound(targetAL, Constants.REBALANCE_AL_FLOOR, alRatioBefore);
        } else {
            targetAL = _bound(targetAL, Constants.REBALANCE_AL_FLOOR, Constants.REBALANCE_AL_CEILING);
        }

        // Nothing to rebalance if already lower
        if (alRatioBefore <= targetAL) {
            stateStore.setFinishedEarly();
            return;
        }

        (IOrigamiLovTokenErc4626Manager.RebalanceDownParams memory params, bool cappedBorrow) = rebalanceDownParams(targetAL, alRatioBefore, 100);

        // Don't try and rebalance for dust, it leads to rounding diffs which
        // would revert on the A/L checks
        if (params.borrowAmount < 1e6) {
            stateStore.setFinishedEarly();
            return;
        }

        vm.startPrank(overlord);
        uint128 alRatioAfter = lovTokenContracts.lovDsrManager.rebalanceDown(params);
        vm.stopPrank();

        assertLe(
            alRatioAfter, 
            alRatioBefore, 
            "Invariant violation: A/L after rebalanceDown <= A/L before rebalanceDown"
        );

        stateStore.setCappedRebalanceDown(cappedBorrow && alRatioAfter > Constants.REBALANCE_AL_CEILING);
    }

    function rebalanceUp(
        uint256 targetAL, 
        uint256 timeJumpSeed
    ) external
        instrument
        adjustTimestamp(timeJumpSeed) 
    {
        // Given the time jump, checkpoint the current borrower debt first so we calculate the right rebalance amounts and bounds
        checkpointBorrowers();

        uint256 alRatioBefore = lovTokenContracts.lovDsrManager.assetToLiabilityRatio();
        if (alRatioBefore < Constants.REBALANCE_AL_CEILING) {
            targetAL = _bound(targetAL, alRatioBefore, Constants.REBALANCE_AL_CEILING);
        } else {
            targetAL = _bound(targetAL, Constants.REBALANCE_AL_FLOOR, Constants.REBALANCE_AL_CEILING);
        }

        // Nothing to rebalance if already higher
        if (alRatioBefore >= targetAL) {
            stateStore.setFinishedEarly();
            return;
        }

        IOrigamiLovTokenErc4626Manager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, alRatioBefore, 100);

        // Don't try and rebalance for dust, it leads to rounding diffs which
        // would revert on the A/L checks
        if (params.minDebtAmountToRepay < 1e6) {
            stateStore.setFinishedEarly();
            return;
        }

        vm.startPrank(overlord);
        uint128 alRatioAfter = lovTokenContracts.lovDsrManager.rebalanceUp(params);
        vm.stopPrank();

        assertGe(
            alRatioAfter, 
            alRatioBefore, 
            "Invariant violation: A/L after rebalanceUp >= A/L before rebalanceUp"
        );
    }
    
    function solveRebalanceDownAmount(
        uint256 targetAL, uint256 currentAL
    ) internal view returns (
        uint256 reservesAmount,
        uint256 managerAssets,
        uint256 managerLiabilities,
        uint256 managerPrecision
    ) {
        if (targetAL <= 1e18) revert InvalidRebalanceDownParam();
        if (targetAL >= currentAL) revert InvalidRebalanceDownParam();

        /*
          targetAL == (assets+X) / (liabilities+X);
          targetAL*(liabilities+X) == (assets+X)
          targetAL*liabilities + targetAL*X == assets+X
          targetAL*liabilities + targetAL*X - X == assets
          targetAL*X - X == assets - targetAL*liabilities
          X * (targetAL - 1) == assets - targetAL*liabilities
          X == (assets - targetAL*liabilities) / (targetAL - 1)
        */
        managerAssets = lovTokenContracts.lovDsrManager.reservesBalance();
        managerLiabilities = lovTokenContracts.lovDsrManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        managerPrecision = 1e18;

        uint256 _netAssets = managerAssets - targetAL.mulDiv(managerLiabilities, managerPrecision, OrigamiMath.Rounding.ROUND_UP);
        reservesAmount = _netAssets.mulDiv(
            managerPrecision,
            targetAL - managerPrecision,
            OrigamiMath.Rounding.ROUND_UP
        );
    }

    function rebalanceDownParams(
        uint256 targetAL,
        uint256 currentAL,
        uint256 alSlippageBps
    ) internal returns (
        IOrigamiLovTokenErc4626Manager.RebalanceDownParams memory params,
        bool cappedBorrow
    ) {
        (
            uint256 reservesAmount,
            uint256 managerAssets,
            uint256 managerLiabilities,
            uint256 managerPrecision
        ) = solveRebalanceDownAmount(targetAL, currentAL);

        // How much DAI to get that much reserves
        uint256 daiDepositAmount = externalContracts.sDaiToken.previewMint(reservesAmount);

        params.borrowAmount = lovTokenContracts.daiUsdcOracle.convertAmount(
            address(externalContracts.daiToken),
            daiDepositAmount,
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN
        );

        // If it's trying to borrow more than available in oUSDC, then cap
        // and work backwards
        uint256 availableToBorrow = oUsdcContracts.lendingClerk.availableToBorrow(address(lovTokenContracts.lovDsrManager));
        if (availableToBorrow < params.borrowAmount) {
            cappedBorrow = true;
            params.borrowAmount = availableToBorrow;

            daiDepositAmount = lovTokenContracts.daiUsdcOracle.convertAmount(
                address(externalContracts.usdcToken),
                params.borrowAmount, // USDC
                IOrigamiOracle.PriceType.SPOT_PRICE,
                OrigamiMath.Rounding.ROUND_UP
            );

            reservesAmount = externalContracts.sDaiToken.previewDeposit(daiDepositAmount);

            // Recalculate the targetAL based off this capped amount            
            uint256 newLiabilities = managerLiabilities + reservesAmount;
            if (newLiabilities != 0) {
                targetAL = managerPrecision.mulDiv(
                    managerAssets + reservesAmount,
                    managerLiabilities + reservesAmount,
                    OrigamiMath.Rounding.ROUND_DOWN
                );
            }
        }

        // Fund the swapper
        doMint(externalContracts.daiToken, address(lovTokenContracts.swapper), daiDepositAmount);

        params.swapData = abi.encode(
            DummyLovTokenSwapper.SwapData({
                buyTokenAmount: daiDepositAmount // USDC->DAI using the oracle price
            })
        );

        params.minNewAL = uint128(OrigamiMath.subtractBps(targetAL, alSlippageBps, OrigamiMath.Rounding.ROUND_DOWN));
        params.maxNewAL = uint128(OrigamiMath.addBps(targetAL, alSlippageBps, OrigamiMath.Rounding.ROUND_UP));
    }

    /// @dev Since there are large time jumps between calls, the debt needs
    /// to be checkpoint between runs
    function checkpointBorrowers() internal {
        address[] memory _debtors = new address[](2);
        (_debtors[0], _debtors[1]) = (address(oUsdcContracts.idleStrategyManager), address(lovTokenContracts.lovDsrManager));
        oUsdcContracts.iUsdc.checkpointDebtorsInterest(_debtors);
    }

    function solveRebalanceUpAmount(uint256 targetAL, uint256 currentAL) internal view returns (uint256 reservesAmount) {
        if (targetAL <= 1e18) revert InvalidRebalanceUpParam();
        if (targetAL <= currentAL) return 0;

        /*
          targetAL == (assets-X) / (liabilities-X);
          targetAL*(liabilities-X) == (assets-X)
          targetAL*liabilities - targetAL*X == assets-X
          targetAL*X - X == targetAL*liabilities - assets
          X - targetAL*X == targetAL*liabilities - assets
          X * (targetAL - 1) == targetAL*liabilities - assets
          X = (targetAL*liabilities - assets) / (targetAL - 1)
        */
        uint256 _assets = lovTokenContracts.lovDsrManager.reservesBalance();
        uint256 _liabilities = lovTokenContracts.lovDsrManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        uint256 _precision = 1e18;
        
        uint256 _netAssets = targetAL.mulDiv(_liabilities, _precision, OrigamiMath.Rounding.ROUND_UP) - _assets;
        reservesAmount = _netAssets.mulDiv(
            _precision,
            targetAL - _precision,
            OrigamiMath.Rounding.ROUND_UP
        );
    }

    function rebalanceUpParams(
        uint256 targetAL,
        uint256 currentAL,
        uint256 alSlippageBps
    ) internal virtual returns (
        IOrigamiLovTokenErc4626Manager.RebalanceUpParams memory params
    ) {
        // reserves (sDAI) amount
        params.minReserveAssetShares = solveRebalanceUpAmount(targetAL, currentAL);

        // How much DAI to sell for that reserves amount
        params.depositAssetsToWithdraw = externalContracts.sDaiToken.previewRedeem(params.minReserveAssetShares);

        // Use the oracle price (and scale for USDC)
        // Round down so the min repay amount is conservative
        params.minDebtAmountToRepay = params.depositAssetsToWithdraw.mulDiv(
            1e6,
            lovTokenContracts.daiUsdcOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP),
            OrigamiMath.Rounding.ROUND_DOWN
        );

        // Fund the swapper
        doMint(externalContracts.usdcToken, address(lovTokenContracts.swapper), params.minDebtAmountToRepay);

        params.swapData = abi.encode(
            DummyLovTokenSwapper.SwapData({
                buyTokenAmount: params.minDebtAmountToRepay // DAI->USDC using the oracle price
            })
        );

        params.minNewAL = uint128(OrigamiMath.subtractBps(targetAL, alSlippageBps, OrigamiMath.Rounding.ROUND_DOWN));
        params.maxNewAL = uint128(OrigamiMath.addBps(targetAL, alSlippageBps, OrigamiMath.Rounding.ROUND_UP));
    }
}
