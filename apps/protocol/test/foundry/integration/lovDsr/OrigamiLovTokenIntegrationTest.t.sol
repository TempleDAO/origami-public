pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { stdError } from "forge-std/StdError.sol";
import { OrigamiLovTokenIntegrationTestBase } from "test/foundry/integration/lovDsr/OrigamiLovTokenIntegrationTestBase.t.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiLendingBorrower } from "contracts/interfaces/investments/lending/IOrigamiLendingBorrower.sol";
import { IOrigamiLendingClerk } from "contracts/interfaces/investments/lending/IOrigamiLendingClerk.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";
import { IOrigamiLovTokenErc4626Manager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenErc4626Manager.sol";
import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiStableChainlinkOracle } from "contracts/common/oracle/OrigamiStableChainlinkOracle.sol";
import { OrigamiCrossRateOracle } from "contracts/common/oracle/OrigamiCrossRateOracle.sol";
import { OrigamiCircuitBreakerAllUsersPerPeriod } from "contracts/common/circuitBreaker/OrigamiCircuitBreakerAllUsersPerPeriod.sol";
import { OrigamiAaveV3IdleStrategy } from "contracts/investments/lending/idleStrategy/OrigamiAaveV3IdleStrategy.sol";
import { OrigamiIdleStrategyManager } from "contracts/investments/lending/idleStrategy/OrigamiIdleStrategyManager.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiDexAggregatorSwapper } from "contracts/common/swappers/OrigamiDexAggregatorSwapper.sol";
import { OrigamiLovTokenTestConstants as Constants } from "test/foundry/deploys/lovDsr/OrigamiLovTokenTestConstants.t.sol";
import { Range } from "contracts/libraries/Range.sol";

contract OrigamiLovTokenIntegrationTest_Lending is OrigamiLovTokenIntegrationTestBase {
    function test_oUsdc_initialization() public {
        {
            assertEq(address(oUsdcContracts.oUsdc.owner()), origamiMultisig);
            assertEq(address(oUsdcContracts.oUsdc.manager()), address(oUsdcContracts.supplyManager));
        }

        {
            assertEq(address(oUsdcContracts.supplyManager.owner()), origamiMultisig);
            assertEq(address(oUsdcContracts.supplyManager.asset()), address(externalContracts.usdcToken));
            assertEq(address(oUsdcContracts.supplyManager.oToken()), address(oUsdcContracts.oUsdc));
            assertEq(address(oUsdcContracts.supplyManager.circuitBreakerProxy()), address(oUsdcContracts.cbProxy));
            assertEq(address(oUsdcContracts.supplyManager.lendingClerk()), address(oUsdcContracts.lendingClerk));
        }
        
        {
            assertEq(address(oUsdcContracts.lendingClerk.owner()), origamiMultisig);
            assertEq(address(oUsdcContracts.lendingClerk.asset()), address(externalContracts.usdcToken));
            assertEq(address(oUsdcContracts.lendingClerk.oToken()), address(oUsdcContracts.oUsdc));
            assertEq(address(oUsdcContracts.lendingClerk.idleStrategyManager()), address(oUsdcContracts.idleStrategyManager));
            assertEq(address(oUsdcContracts.lendingClerk.debtToken()), address(oUsdcContracts.iUsdc));
            assertEq(address(oUsdcContracts.lendingClerk.circuitBreakerProxy()), address(oUsdcContracts.cbProxy));
            assertEq(address(oUsdcContracts.lendingClerk.supplyManager()), address(oUsdcContracts.supplyManager));
            assertEq(oUsdcContracts.lendingClerk.globalBorrowPaused(), false);
            assertEq(oUsdcContracts.lendingClerk.globalRepayPaused(), false);
            assertEq(address(oUsdcContracts.lendingClerk.globalInterestRateModel()), address(oUsdcContracts.globalInterestRateModel));
        }

        {
            assertEq(address(oUsdcContracts.idleStrategyManager.owner()), origamiMultisig);
            assertEq(oUsdcContracts.idleStrategyManager.version(), "1.0.0");
            assertEq(oUsdcContracts.idleStrategyManager.name(), "IdleStrategyManager");
            assertEq(address(oUsdcContracts.idleStrategyManager.asset()), address(externalContracts.usdcToken));
            assertEq(address(oUsdcContracts.idleStrategyManager.idleStrategy()), address(oUsdcContracts.idleStrategy));
            assertEq(oUsdcContracts.idleStrategyManager.depositsEnabled(), true);
            assertEq(oUsdcContracts.idleStrategyManager.withdrawalBuffer(), 100e6);
            assertEq(oUsdcContracts.idleStrategyManager.depositThreshold(), 100e6);
        }

        {
            assertEq(address(oUsdcContracts.iUsdc.owner()), origamiMultisig);
            assertEq(oUsdcContracts.iUsdc.name(), "Origami iUSDC");
            assertEq(oUsdcContracts.iUsdc.symbol(), "iUSDC");
            assertEq(oUsdcContracts.iUsdc.totalPrincipal(), 0);
            assertEq(oUsdcContracts.iUsdc.estimatedTotalInterest(), 0);
            assertEq(oUsdcContracts.iUsdc.repaidTotalInterest(), 0);
            assertEq(oUsdcContracts.iUsdc.decimals(), 18);
        }

        {
            assertEq(address(oUsdcContracts.rewardsMinter.owner()), origamiMultisig);
            assertEq(address(oUsdcContracts.rewardsMinter.oToken()), address(oUsdcContracts.oUsdc));
            assertEq(address(oUsdcContracts.rewardsMinter.ovToken()), address(oUsdcContracts.ovUsdc));
            assertEq(address(oUsdcContracts.rewardsMinter.debtToken()), address(oUsdcContracts.iUsdc));
            assertEq(oUsdcContracts.rewardsMinter.carryOverRate(), 500);
            assertEq(address(oUsdcContracts.rewardsMinter.feeCollector()), feeCollector);
            assertEq(oUsdcContracts.rewardsMinter.cumulativeInterestCheckpoint(), 0);
        }
        
        {
            assertEq(address(oUsdcContracts.cbProxy.owner()), origamiMultisig);
        }

        {
            assertEq(address(oUsdcContracts.cbUsdcBorrow.owner()), origamiMultisig);
            assertEq(oUsdcContracts.cbUsdcBorrow.periodDuration(), 26 hours);
            assertEq(oUsdcContracts.cbUsdcBorrow.cap(), Constants.CB_DAILY_USDC_BORROW_LIMIT);
            assertEq(oUsdcContracts.cbUsdcBorrow.nBuckets(), 13);
            assertEq(oUsdcContracts.cbUsdcBorrow.secondsPerBucket(), 2 hours);
            assertEq(oUsdcContracts.cbUsdcBorrow.bucketIndex(), 0);
            assertEq(oUsdcContracts.cbUsdcBorrow.MAX_BUCKETS(), 4_000);
        }

        {
            assertEq(address(oUsdcContracts.cbOUsdcExit.owner()), origamiMultisig);
            assertEq(oUsdcContracts.cbOUsdcExit.periodDuration(), 26 hours);
            assertEq(oUsdcContracts.cbOUsdcExit.cap(), Constants.CB_DAILY_OUSDC_EXIT_LIMIT);
            assertEq(oUsdcContracts.cbOUsdcExit.nBuckets(), 13);
            assertEq(oUsdcContracts.cbOUsdcExit.secondsPerBucket(), 2 hours);
            assertEq(oUsdcContracts.cbOUsdcExit.bucketIndex(), 0);
            assertEq(oUsdcContracts.cbOUsdcExit.MAX_BUCKETS(), 4_000);
        }

        {
            assertEq(address(oUsdcContracts.globalInterestRateModel.owner()), origamiMultisig);
            (
                uint80 baseInterestRate,
                uint80 maxInterestRate,
                uint80 kinkInterestRate,
                uint256 kinkUtilizationRatio
            ) = oUsdcContracts.globalInterestRateModel.rateParams();

            assertEq(baseInterestRate, Constants.GLOBAL_IR_AT_0_UR);
            assertEq(maxInterestRate, Constants.GLOBAL_IR_AT_100_UR);
            assertEq(kinkInterestRate, Constants.GLOBAL_IR_AT_KINK);
            assertEq(kinkUtilizationRatio, Constants.UTILIZATION_RATIO_90);
        }

        {
            assertEq(address(lovTokenContracts.borrowerInterestRateModel.owner()), origamiMultisig);
            (
                uint80 baseInterestRate,
                uint80 maxInterestRate,
                uint80 kinkInterestRate,
                uint256 kinkUtilizationRatio
            ) = lovTokenContracts.borrowerInterestRateModel.rateParams();

            assertEq(baseInterestRate, Constants.BORROWER_IR_AT_0_UR);
            assertEq(maxInterestRate, Constants.BORROWER_IR_AT_100_UR);
            assertEq(kinkInterestRate, Constants.BORROWER_IR_AT_KINK);
            assertEq(kinkUtilizationRatio, Constants.UTILIZATION_RATIO_90);
        }
    }

    function test_ovUsdc_invest_single() public {
        uint256 amount = 155e6;
        uint256 amountOut = investOusdc(alice, amount);

        assertEq(amountOut, 155e18);
        assertEq(externalContracts.usdcToken.balanceOf(alice), 0);
        assertEq(oUsdcContracts.ovUsdc.balanceOf(alice), 155e18);
        assertEq(externalContracts.usdcToken.balanceOf(address(oUsdcContracts.idleStrategyManager)), 100e6);
        assertEq(aToken.balanceOf(address(oUsdcContracts.idleStrategy)), 55e6);
    }

    function test_ovUsdc_makeWhole() public {
        // Check that if oUDSC isn't backed 1:1 (eg we over minted, exploit, etc),
        // then we can donate USDC back in.
        uint256 amount = 155e6;
        investOusdc(alice, amount);

        // Drain funds
        {
            vm.startPrank(address(oUsdcContracts.idleStrategyManager));
            externalContracts.usdcToken.transfer(bob, 99e6);
        }

        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = oUsdcContracts.ovUsdc.exitQuote(
            150e18,
            address(externalContracts.usdcToken),
            0,
            0
        );

        // Can't exit it all
        {
            vm.startPrank(alice);
            vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InsufficientBalance.selector, address(externalContracts.usdcToken), 150e6, 56e6));
            oUsdcContracts.ovUsdc.exitToToken(quoteData, alice);
        }

        // Make whole
        {
            doMint(externalContracts.usdcToken, address(oUsdcContracts.idleStrategyManager), 99e6);

            // Alice can now exit
            vm.startPrank(alice);
            oUsdcContracts.ovUsdc.exitToToken(quoteData, alice);
        }
    }

    function test_ovUsdc_invest_multiple() public {
        // Alice invests
        uint256 amount = 155e6;
        uint256 amountOut = investOusdc(alice, amount);
        
        {
            assertEq(amountOut, 155e18);
            assertEq(externalContracts.usdcToken.balanceOf(alice), 0);
            assertEq(oUsdcContracts.ovUsdc.balanceOf(alice), 155e18);
            assertEq(externalContracts.usdcToken.balanceOf(address(oUsdcContracts.idleStrategyManager)), 100e6);
            assertEq(aToken.balanceOf(address(oUsdcContracts.idleStrategy)), 55e6);
            assertEq(oUsdcContracts.iUsdc.balanceOf(address(oUsdcContracts.idleStrategyManager)), 155e18);
        }

        vm.warp(block.timestamp + 365 days);

        {
            address[] memory debtors = new address[](1);
            debtors[0] = address(oUsdcContracts.idleStrategyManager);
            vm.startPrank(origamiMultisig);
            oUsdcContracts.rewardsMinter.checkpointDebtAndMintRewards(debtors);
        }

        uint256 expectedInterest = 7.947019938283726045e18;

        // Got a little interest now
        {           
            assertEq(amountOut, 155e18);
            assertEq(externalContracts.usdcToken.balanceOf(alice), 0);
            assertEq(oUsdcContracts.ovUsdc.balanceOf(alice), 155e18);
            assertEq(externalContracts.usdcToken.balanceOf(address(oUsdcContracts.idleStrategyManager)), 100e6);
            assertEq(aToken.balanceOf(address(oUsdcContracts.idleStrategy)), 58.146876e6);
            assertEq(oUsdcContracts.iUsdc.balanceOf(address(oUsdcContracts.idleStrategyManager)), 155e18 + expectedInterest);
            assertEq(oUsdcContracts.iUsdc.estimatedTotalInterest(), expectedInterest);
        }

        {
            // Price is still 1:1 since the rewards are 'pending'
            assertEq(oUsdcContracts.ovUsdc.reservesPerShare(), 1e18);
            // Interest minus carry over, minus performance fee
            assertEq(oUsdcContracts.ovUsdc.pendingReserves(), 7.398675562542148947e18);
            assertEq(oUsdcContracts.ovUsdc.vestedReserves(), 155e18);

            // NB this is 1 year of accrued rewards distributed over 2 days
            assertEq(oUsdcContracts.ovUsdc.apr(), 87_113);
        }

        // Move forward a day so the ovUSDC price changes
        vm.warp(block.timestamp + 1 days);
        assertEq(oUsdcContracts.ovUsdc.reservesPerShare(), 1.023866695363039190e18);

        // Now Bob invests the same amount
        amountOut = investOusdc(bob, amount);

        {
            assertEq(amountOut, 151.386895092862283411e18);
            assertEq(externalContracts.usdcToken.balanceOf(bob), 0);
            assertEq(oUsdcContracts.ovUsdc.balanceOf(bob), 151.386895092862283411e18);
            assertEq(externalContracts.usdcToken.balanceOf(address(oUsdcContracts.idleStrategyManager)), 100e6);
            // Includes the carry over from the last harvest
            assertEq(aToken.balanceOf(address(oUsdcContracts.idleStrategy)), 213.155499e6);
            assertEq(oUsdcContracts.iUsdc.balanceOf(address(oUsdcContracts.idleStrategyManager)), 317.969342976804645827e18);
        }
    }

    function test_ovUsdc_exit_multiple() public {
        // Alice invests
        uint256 amount = 155e6;
        investOusdc(alice, amount);
        vm.warp(block.timestamp + 365 days);
        uint256 bobOvUsdc = investOusdc(bob, amount);

        assertEq(oUsdcContracts.ovUsdc.maxExit(address(externalContracts.usdcToken)), 155e18 * 2);
        
        {
            address[] memory debtors = new address[](1);
            debtors[0] = address(oUsdcContracts.idleStrategyManager);
            vm.startPrank(origamiMultisig);
            oUsdcContracts.rewardsMinter.checkpointDebtAndMintRewards(debtors);

            vm.warp(block.timestamp + 1 days);
            assertEq(oUsdcContracts.ovUsdc.reservesPerShare(), 1.011933347681519595e18);
        }

        // Total USDC = 311.47, but converted to ovUSDC shares = 307.8
        assertEq(aToken.balanceOf(address(oUsdcContracts.idleStrategy)), 213.197627e6);
        assertEq(oUsdcContracts.ovUsdc.maxExit(address(externalContracts.usdcToken)), 309.504205704436400053e18);

        // Bob exits some
        uint256 amountOut = exitOusdc(bob, 150e18);

        {
            assertEq(amountOut, 151.790002e6);
            assertEq(externalContracts.usdcToken.balanceOf(bob), amountOut);
            assertEq(oUsdcContracts.ovUsdc.balanceOf(bob), bobOvUsdc - 150e18);
            assertEq(externalContracts.usdcToken.balanceOf(address(oUsdcContracts.idleStrategyManager)), 100e6);
            assertEq(aToken.balanceOf(address(oUsdcContracts.idleStrategy)), 61.407624e6);
            assertEq(oUsdcContracts.iUsdc.balanceOf(address(oUsdcContracts.idleStrategyManager)), 166.200575307890007622e18);
        }

        // Bob exists the remainder
        amountOut = exitOusdc(bob, oUsdcContracts.ovUsdc.balanceOf(bob));

        {
            assertEq(amountOut, 5.059666e6);
            assertEq(externalContracts.usdcToken.balanceOf(bob), 156.849668e6);
            assertEq(oUsdcContracts.ovUsdc.balanceOf(bob), 0);
            assertEq(externalContracts.usdcToken.balanceOf(address(oUsdcContracts.idleStrategyManager)), 94.940334e6);
            assertEq(aToken.balanceOf(address(oUsdcContracts.idleStrategy)), 61.407624e6);
            assertEq(oUsdcContracts.iUsdc.balanceOf(address(oUsdcContracts.idleStrategyManager)), 161.140909307890007622e18);
        }

        // Alice can't exit it all immediately - have to wait until the remaining vests
        {
            vm.startPrank(alice);
            (IOrigamiInvestment.ExitQuoteData memory quoteData,) = oUsdcContracts.ovUsdc.exitQuote(
                oUsdcContracts.ovUsdc.balanceOf(alice),
                address(externalContracts.usdcToken),
                0,
                0
            );
            vm.expectRevert(stdError.arithmeticError);
            oUsdcContracts.ovUsdc.exitToToken(quoteData, alice);
        }

        // Can checkpoint and then exit max
        vm.warp(block.timestamp + 2 days);
        oUsdcContracts.ovUsdc.checkpointReserves();
        uint256 maxExit = oUsdcContracts.ovUsdc.maxExit(address(externalContracts.usdcToken));
        assertEq(maxExit, 150.972421800983505347e18);
        amountOut = exitOusdc(alice, maxExit);
        assertEq(amountOut, 156.377240e6);

        // Tiny residual left in the contract, expected because dai->usdc is rounded down
        assertEq(oUsdcContracts.idleStrategyManager.availableToWithdraw(), 1);
    }

    function test_ovUsdc_fail_circuitBreaker() public {
        vm.prank(deployer.owner());
        oUsdcContracts.cbOUsdcExit.updateCap(2_000_000e18);

        uint256 amount = 2_500_000e6;
        investOusdc(alice, amount);

        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = oUsdcContracts.ovUsdc.exitQuote(
            2_000_000e18,
            address(externalContracts.usdcToken),
            0,
            0
        );
        uint256 amountOut = oUsdcContracts.ovUsdc.exitToToken(quoteData, bob);
        assertEq(amountOut, 2_000_000e6);
        assertEq(externalContracts.usdcToken.balanceOf(bob), 2_000_000e6);
        assertEq(externalContracts.usdcToken.balanceOf(alice), 0);

        (quoteData,) = oUsdcContracts.ovUsdc.exitQuote(
            1,
            address(externalContracts.usdcToken),
            0,
            0
        );
        vm.expectRevert(abi.encodeWithSelector(OrigamiCircuitBreakerAllUsersPerPeriod.CapBreached.selector, 2_000_000e18 + 1, 2_000_000e18));
        oUsdcContracts.ovUsdc.exitToToken(quoteData, alice);
    }

    function test_ovUsdc_migrate_idle_strategy() public {
        uint256 amount = 10_000e6;
        investOusdc(alice, amount);

        uint256 idleStrategyBalance = oUsdcContracts.idleStrategy.totalBalance();
        {
            assertEq(externalContracts.usdcToken.balanceOf(address(oUsdcContracts.idleStrategyManager)), 100e6);
            assertEq(idleStrategyBalance, 9_900e6);
            assertEq(oUsdcContracts.idleStrategyManager.availableToWithdraw(), amount);
            IOrigamiLendingBorrower.AssetBalance[] memory assetBalances = oUsdcContracts.idleStrategyManager.latestAssetBalances();
            assertEq(assetBalances.length, 1);
            assertEq(assetBalances[0].asset, address(externalContracts.usdcToken));
            assertEq(assetBalances[0].balance, amount);
        }

        // Disable deposits and withdraw to manager
        vm.startPrank(origamiMultisig);
        oUsdcContracts.idleStrategyManager.setDepositsEnabled(false);
        uint256 amountOut = oUsdcContracts.idleStrategyManager.withdrawToManager(idleStrategyBalance);

        {
            assertEq(amountOut, idleStrategyBalance);
            assertEq(externalContracts.usdcToken.balanceOf(address(oUsdcContracts.idleStrategyManager)), amount);
            assertEq(oUsdcContracts.idleStrategy.totalBalance(), 0);
            assertEq(oUsdcContracts.idleStrategyManager.availableToWithdraw(), amount);
            IOrigamiLendingBorrower.AssetBalance[] memory assetBalances = oUsdcContracts.idleStrategyManager.latestAssetBalances();
            assertEq(assetBalances.length, 1);
            assertEq(assetBalances[0].asset, address(externalContracts.usdcToken));
            assertEq(assetBalances[0].balance, amount);
        }

        investOusdc(alice, amount);

        {
            assertEq(externalContracts.usdcToken.balanceOf(address(oUsdcContracts.idleStrategyManager)), 2*amount);
            assertEq(oUsdcContracts.idleStrategy.totalBalance(), 0);
            assertEq(oUsdcContracts.idleStrategyManager.availableToWithdraw(), 2*amount);
            IOrigamiLendingBorrower.AssetBalance[] memory assetBalances = oUsdcContracts.idleStrategyManager.latestAssetBalances();
            assertEq(assetBalances.length, 1);
            assertEq(assetBalances[0].asset, address(externalContracts.usdcToken));
            assertEq(assetBalances[0].balance, 2*amount);
        }

        // Create and migrate to a new strategy
        OrigamiAaveV3IdleStrategy idleStrategy2;
        {
            vm.startPrank(origamiMultisig);
            idleStrategy2 = new OrigamiAaveV3IdleStrategy(origamiMultisig, address(externalContracts.usdcToken), Constants.AAVE_POOL_ADDRESS_PROVIDER);
            setExplicitAccess(
                idleStrategy2, 
                address(oUsdcContracts.idleStrategyManager), 
                OrigamiIdleStrategyManager.allocate.selector, 
                OrigamiIdleStrategyManager.withdraw.selector, 
                true
            );
            oUsdcContracts.idleStrategyManager.setIdleStrategy(address(idleStrategy2));
            oUsdcContracts.idleStrategyManager.setDepositsEnabled(true);
        }

        investOusdc(alice, amount);

        {
            assertEq(externalContracts.usdcToken.balanceOf(address(oUsdcContracts.idleStrategyManager)), 100e6);
            assertEq(idleStrategy2.totalBalance(), 3*amount - 100e6);
            assertEq(oUsdcContracts.idleStrategyManager.availableToWithdraw(), 3*amount);
            IOrigamiLendingBorrower.AssetBalance[] memory assetBalances = oUsdcContracts.idleStrategyManager.latestAssetBalances();
            assertEq(assetBalances.length, 1);
            assertEq(assetBalances[0].asset, address(externalContracts.usdcToken));
            assertEq(assetBalances[0].balance, 3*amount);
        }
    }
}

contract OrigamiLovTokenIntegrationTest_Borrowing is OrigamiLovTokenIntegrationTestBase {
    using OrigamiMath for uint256;

    function test_lovDsr_initialization() public {
        {
            assertEq(address(lovTokenContracts.lovDsr.owner()), origamiMultisig);
            assertEq(address(lovTokenContracts.lovDsr.manager()), address(lovTokenContracts.lovDsrManager));
            assertEq(lovTokenContracts.lovDsr.performanceFee(), Constants.LOV_DSR_PERFORMANCE_FEE_BPS);
            assertEq(lovTokenContracts.lovDsr.PERFORMANCE_FEE_FREQUENCY(), 7 days);
        }

        {
            assertEq(address(lovTokenContracts.lovDsrManager.owner()), origamiMultisig);
            assertEq(lovTokenContracts.lovDsrManager.name(), "lovDSR");
            assertEq(lovTokenContracts.lovDsrManager.version(), "1.0.0");
            assertEq(address(lovTokenContracts.lovDsrManager.lovToken()), address(lovTokenContracts.lovDsr));
            assertEq(lovTokenContracts.lovDsrManager.reservesBalance(), 0);

            (uint64 minDepositFeeBps, uint64 minExitFeeBps, uint64 feeLeverageFactor) = lovTokenContracts.lovDsrManager.getFeeConfig();
            assertEq(minDepositFeeBps, Constants.LOV_DSR_MIN_DEPOSIT_FEE_BPS);
            assertEq(minExitFeeBps, Constants.LOV_DSR_MIN_EXIT_FEE_BPS);
            assertEq(feeLeverageFactor, Constants.LOV_DSR_FEE_LEVERAGE_FACTOR);

            assertEq(lovTokenContracts.lovDsrManager.redeemableReservesBufferBps(), 10_050);

            (uint128 floor, uint128 ceiling) = lovTokenContracts.lovDsrManager.userALRange();
            assertEq(floor, Constants.USER_AL_FLOOR);
            assertEq(ceiling, Constants.USER_AL_CEILING);
            (floor, ceiling) = lovTokenContracts.lovDsrManager.rebalanceALRange();
            assertEq(floor, Constants.REBALANCE_AL_FLOOR);
            assertEq(ceiling, Constants.REBALANCE_AL_CEILING);

            assertEq(address(lovTokenContracts.lovDsrManager.depositAsset()), address(externalContracts.daiToken));
            assertEq(address(lovTokenContracts.lovDsrManager.debtToken()), address(externalContracts.usdcToken));
            assertEq(address(lovTokenContracts.lovDsrManager.reserveToken()), address(externalContracts.sDaiToken));
            assertEq(address(lovTokenContracts.lovDsrManager.lendingClerk()), address(oUsdcContracts.lendingClerk));
            assertEq(address(lovTokenContracts.lovDsrManager.swapper()), address(lovTokenContracts.swapper));
            assertEq(address(lovTokenContracts.lovDsrManager.debtAssetToDepositAssetOracle()), address(lovTokenContracts.daiIUsdcOracle));
        }
        
        {
            assertEq(address(lovTokenContracts.daiUsdOracle.owner()), origamiMultisig);
            assertEq(lovTokenContracts.daiUsdOracle.description(), "DAI/USD");
            assertEq(lovTokenContracts.daiUsdOracle.decimals(), 18);
            assertEq(lovTokenContracts.daiUsdOracle.precision(), 1e18);

            assertEq(lovTokenContracts.daiUsdOracle.stableHistoricPrice(), Constants.DAI_USD_HISTORIC_STABLE_PRICE);
            assertEq(address(lovTokenContracts.daiUsdOracle.spotPriceOracle()), address(externalContracts.clDaiUsdOracle));
            assertEq(lovTokenContracts.daiUsdOracle.spotPricePrecisionScaleDown(), false);
            assertEq(lovTokenContracts.daiUsdOracle.spotPricePrecisionScalar(), 1e10); // CL oracle is 8dp
            assertEq(lovTokenContracts.daiUsdOracle.spotPriceStalenessThreshold(), Constants.DAI_USD_STALENESS_THRESHOLD);
            (uint128 min, uint128 max) = lovTokenContracts.daiUsdOracle.validSpotPriceRange();
            assertEq(min, Constants.DAI_USD_MIN_THRESHOLD);
            assertEq(max, Constants.DAI_USD_MAX_THRESHOLD);
        }
        
        {
            assertEq(address(lovTokenContracts.usdcUsdOracle.owner()), origamiMultisig);
            assertEq(lovTokenContracts.usdcUsdOracle.description(), "USDC/USD");
            assertEq(lovTokenContracts.usdcUsdOracle.decimals(), 18);
            assertEq(lovTokenContracts.usdcUsdOracle.precision(), 1e18);

            assertEq(lovTokenContracts.usdcUsdOracle.stableHistoricPrice(), Constants.USDC_USD_HISTORIC_STABLE_PRICE);
            assertEq(address(lovTokenContracts.usdcUsdOracle.spotPriceOracle()), address(externalContracts.clUsdcUsdOracle));
            assertEq(lovTokenContracts.usdcUsdOracle.spotPricePrecisionScaleDown(), false);
            assertEq(lovTokenContracts.usdcUsdOracle.spotPricePrecisionScalar(), 1e10); // CL oracle is 8dp
            assertEq(lovTokenContracts.usdcUsdOracle.spotPriceStalenessThreshold(), Constants.USDC_USD_STALENESS_THRESHOLD);
            (uint128 min, uint128 max) = lovTokenContracts.usdcUsdOracle.validSpotPriceRange();
            assertEq(min, Constants.DAI_USD_MIN_THRESHOLD);
            assertEq(max, Constants.DAI_USD_MAX_THRESHOLD);
        }
        
        {
            assertEq(lovTokenContracts.daiUsdcOracle.description(), "DAI/USDC");
            assertEq(lovTokenContracts.daiUsdcOracle.decimals(), 18);
            assertEq(lovTokenContracts.daiUsdcOracle.precision(), 1e18);

            assertEq(address(lovTokenContracts.daiUsdcOracle.baseAssetOracle()), address(lovTokenContracts.daiUsdOracle));
            assertEq(address(lovTokenContracts.daiUsdcOracle.quoteAssetOracle()), address(lovTokenContracts.usdcUsdOracle));
        }

        {
            assertEq(OrigamiDexAggregatorSwapper(address(lovTokenContracts.swapper)).router(), Constants.ONE_INCH_ROUTER);
        }
    }

    function test_lovDsr_invest_success() public {
        uint256 amount = 10_000e18;
        uint256 expectedSDai = externalContracts.sDaiToken.previewDeposit(amount);
        (uint256 depositFee, ) = lovTokenContracts.lovDsr.getDynamicFeesBps();
        uint256 amountOut = investLovDsr(alice, amount);
        assertEq(depositFee, 32);
        assertEq(amountOut, OrigamiMath.subtractBps(expectedSDai, depositFee));

        {
            assertEq(lovTokenContracts.lovDsr.balanceOf(alice), amountOut);
            assertEq(externalContracts.sDaiToken.balanceOf(address(lovTokenContracts.lovDsrManager)), expectedSDai);
            assertEq(lovTokenContracts.lovDsrManager.reservesBalance(), expectedSDai);
            assertEq(lovTokenContracts.lovDsrManager.assetToLiabilityRatio(), type(uint128).max);
            assertEq(lovTokenContracts.lovDsrManager.effectiveExposure(IOrigamiOracle.PriceType.SPOT_PRICE), 1e18);
            assertEq(lovTokenContracts.lovDsrManager.effectiveExposure(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1e18);
            assertEq(oUsdcContracts.lendingClerk.availableToBorrow(address(lovTokenContracts.lovDsrManager)), 0);
        }
    }

    function test_lovDsr_rebalanceDown_success() public {
        uint256 amount = 10_000e18;
        investLovDsr(alice, amount);

        // No USDC supplied - so can't borrow
        uint256 targetAL = 1.11e18;
        uint256 slippage = 20; // 0.2%
        (IOrigamiLovTokenErc4626Manager.RebalanceDownParams memory params,) = rebalanceDownParams(targetAL, slippage, slippage);

        {
            vm.startPrank(origamiMultisig);
            vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InsufficientBalance.selector, address(oUsdcContracts.iUsdc), params.borrowAmount * 1e12, 0));
            lovTokenContracts.lovDsrManager.rebalanceDown(params);
        }

        investOusdc(bob, 100_000e6);
        assertEq(oUsdcContracts.lendingClerk.availableToBorrow(address(lovTokenContracts.lovDsrManager)), 100_000e6);
        {
            vm.startPrank(origamiMultisig);
            lovTokenContracts.lovDsrManager.rebalanceDown(params);
        }
        
        {
            // Pretty close to the target - swap prices and fx are slightly different to actual
            assertEq(lovTokenContracts.lovDsrManager.assetToLiabilityRatio(), 1.109680071471767688e18);
            assertEq(lovTokenContracts.lovDsrManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 86_913.308830494366005899e18);
            assertEq(lovTokenContracts.lovDsrManager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 86_894.875386824506455812e18);
            assertEq(lovTokenContracts.lovDsrManager.reservesBalance(), 96_445.966754870805870910e18);
            assertEq(externalContracts.sDaiToken.balanceOf(address(lovTokenContracts.lovDsrManager)), 96_445.966754870805870910e18);
            assertEq(lovTokenContracts.lovDsrManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 9_098.091380223968034981e18);
            assertEq(lovTokenContracts.lovDsrManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 9_116.616991112176882818e18);

            // If those balances are redeemed, what's the new AL - should match the 0.05% buffer
            uint256 newAl = uint256(96_445.966754870805870910e18 - 9_098.091380223968034981e18) * 1e18 / 86_913.308830494366005899e18;
            assertEq(newAl, 1.005e18);
        }

        // Set the buffer to zero and check again
        {
            lovTokenContracts.lovDsrManager.setRedeemableReservesBufferBps(0);
            assertEq(lovTokenContracts.lovDsrManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 86_913.308830494366005899e18);
            assertEq(lovTokenContracts.lovDsrManager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 86_894.875386824506455812e18);
            assertEq(lovTokenContracts.lovDsrManager.reservesBalance(), 96_445.966754870805870910e18);
            assertEq(lovTokenContracts.lovDsrManager.assetToLiabilityRatio(), 1.109680071471767688e18);
            assertEq(lovTokenContracts.lovDsrManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 9_532.657924376439865011e18);
            assertEq(lovTokenContracts.lovDsrManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 9_551.091368046299415098e18);
        }

        investLovDsr(alice, 1_000e18);
    }
    
    function test_lovDsr_rebalanceUp_success() public {
        uint256 amount = 10_000e18;
        uint256 slippage = 20; // 0.2%
        investLovDsr(alice, amount);
        investOusdc(bob, 100_000e6);
        doRebalanceDown(1.11e18, slippage, slippage);

        {
            assertEq(lovTokenContracts.lovDsrManager.assetToLiabilityRatio(), 1.109680071471767688e18);
            assertEq(oUsdcContracts.iUsdc.totalSupply(), 100_000e18);
            assertEq(oUsdcContracts.iUsdc.balanceOf(address(lovTokenContracts.lovDsrManager)), 90_889.809999e18);
            assertEq(oUsdcContracts.iUsdc.balanceOf(address(oUsdcContracts.idleStrategyManager)), 9_110.190001e18);
        }

        doRebalanceUp(1.13e18, slippage, slippage);

        {
            // Pretty close to the target - swap prices and fx are slightly different to actual
            assertEq(lovTokenContracts.lovDsrManager.assetToLiabilityRatio(), 1.130025151324035258e18);
            assertEq(lovTokenContracts.lovDsrManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 73_326.505792466945519693e18);
            assertEq(lovTokenContracts.lovDsrManager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 73_310.953973853421205217e18);
            assertEq(lovTokenContracts.lovDsrManager.reservesBalance(), 82_860.795804195208057402e18);
            assertEq(externalContracts.sDaiToken.balanceOf(address(lovTokenContracts.lovDsrManager)), 82_860.795804195208057402e18);
            assertEq(lovTokenContracts.lovDsrManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 9_167.657482765927810110e18);
            assertEq(lovTokenContracts.lovDsrManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 9_183.287060472519746158e18);

            // If those balances are redeemed, what's the new AL - should match the 0.05% buffer
            uint256 newAl = uint256(82_860.795804195208057402e18 - 9_167.657482765927810110e18) * 1e18 / 73_326.505792466945519693e18;
            assertEq(newAl, 1.005e18);
        }

        {
            assertEq(oUsdcContracts.iUsdc.totalSupply(), 100_000e18);
            assertEq(oUsdcContracts.iUsdc.balanceOf(address(lovTokenContracts.lovDsrManager)), 76_681.376754e18);
            assertEq(oUsdcContracts.iUsdc.balanceOf(address(oUsdcContracts.idleStrategyManager)), 23_318.623246e18);
        }
    }

    function test_lovDsr_rebalanceDown_circuitBreaker() public {
        vm.startPrank(origamiMultisig);
        oUsdcContracts.cbUsdcBorrow.updateCap(90_000e6);

        uint256 amount = 10_000e18;
        uint256 slippage = 20; // 0.2%
        investLovDsr(alice, amount);
        investOusdc(bob, 100_000e6);

        vm.startPrank(origamiMultisig);
        uint256 targetAL = 1.11e18;
        (IOrigamiLovTokenErc4626Manager.RebalanceDownParams memory params,) = rebalanceDownParams(targetAL, slippage, slippage);
        vm.expectRevert(abi.encodeWithSelector(OrigamiCircuitBreakerAllUsersPerPeriod.CapBreached.selector, 90_889.809999e6, 90_000e6));
        lovTokenContracts.lovDsrManager.rebalanceDown(params);
    }

    function test_lovDsr_fail_exit_staleOracle() public {
        investOusdc(bob, 1_000_000e6);

        uint256 amount = 5_000e18;
        investLovDsr(alice, amount);
        investLovDsr(bob, amount);
        
        doRebalanceDown(1.11e18, 20, 20);
        vm.warp(block.timestamp + 30 days);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.StalePrice.selector, address(externalContracts.clDaiUsdOracle), 1701907679, 99978791));        
        lovTokenContracts.lovDsr.exitQuote(
            amount / 2,
            address(externalContracts.usdcToken),
            0,
            0
        );
    }

    function test_lovDsr_success_exit() public {
        vm.prank(origamiMultisig);
        lovTokenContracts.lovDsrManager.setUserALRange(1.05e18, 1.13e18);

        investOusdc(bob, 1_000_000e6);

        uint256 amount = 5_000e18;
        uint256 aliceBalance = investLovDsr(alice, amount);
        uint256 bobBalance = investLovDsr(bob, amount);
        
        // Slightly higher because of deposit fees
        assertEq(lovTokenContracts.lovDsr.reservesPerShare(), 1.004817981643824340e18);

        // The rebalance down introduces a debt.
        // We also hold a buffer % back (0.05%), so the reservesPerShare drops
        // In practice this will be very low.
        doRebalanceDown(1.11e18, 20, 20);
        assertEq(lovTokenContracts.lovDsr.reservesPerShare(), 0.958169050348988436e18);
        assertEq(lovTokenContracts.lovDsrManager.sharesToReserves(1e18, IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.958169050348988436e18);
        assertEq(lovTokenContracts.lovDsrManager.sharesToReserves(1e18, IOrigamiOracle.PriceType.SPOT_PRICE), 0.956221983031232832e18);

        {
            assertEq(lovTokenContracts.lovDsrManager.assetToLiabilityRatio(), 1.109680071471767688e18);
            assertEq(lovTokenContracts.lovDsrManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 86_913.308830494366005899e18);
            assertEq(lovTokenContracts.lovDsrManager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 86_894.875386824506455812e18);
            assertEq(lovTokenContracts.lovDsrManager.reservesBalance(), 96_445.966754870805870909e18);
            assertEq(externalContracts.sDaiToken.balanceOf(address(lovTokenContracts.lovDsrManager)), 96_445.966754870805870909e18);
            assertEq(lovTokenContracts.lovDsrManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 9_098.091380223968034980e18);
            assertEq(lovTokenContracts.lovDsrManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 9_116.616991112176882817e18);
        }

        vm.warp(block.timestamp + 30 days);
    
        // Push out a new oracle to have a higher staleness threshold
        {
            vm.startPrank(origamiMultisig);
            lovTokenContracts.daiUsdOracle = new OrigamiStableChainlinkOracle(
                origamiMultisig,
                "DAI/USD",
                address(externalContracts.daiToken),
                Constants.DAI_DECIMALS,
                Constants.INTERNAL_USD_ADDRESS,
                Constants.USD_DECIMALS,
                Constants.DAI_USD_HISTORIC_STABLE_PRICE,
                address(externalContracts.clDaiUsdOracle),
                1_000 days,
                Range.Data(Constants.DAI_USD_MIN_THRESHOLD, Constants.DAI_USD_MAX_THRESHOLD)
            );
            lovTokenContracts.iUsdcUsdOracle = new OrigamiStableChainlinkOracle(
                origamiMultisig,
                "IUSDC/USD",
                address(externalContracts.usdcToken),
                Constants.IUSDC_DECIMALS,
                Constants.INTERNAL_USD_ADDRESS,
                Constants.USD_DECIMALS,
                Constants.USDC_USD_HISTORIC_STABLE_PRICE,
                address(externalContracts.clUsdcUsdOracle),
                1_000 days,
                Range.Data(Constants.USDC_USD_MIN_THRESHOLD, Constants.USDC_USD_MAX_THRESHOLD)
            );
            lovTokenContracts.daiIUsdcOracle = new OrigamiCrossRateOracle(
                "DAI/IUSDC",
                address(externalContracts.daiToken),
                address(lovTokenContracts.daiUsdOracle),
                Constants.DAI_DECIMALS,
                address(externalContracts.usdcToken),
                address(lovTokenContracts.iUsdcUsdOracle),
                Constants.IUSDC_DECIMALS
            );
            lovTokenContracts.lovDsrManager.setOracle(address(lovTokenContracts.daiIUsdcOracle));
        }

        address recipient = makeAddr("recipient");
        vm.startPrank(alice);
        
        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovDsr.exitQuote(
            aliceBalance,
            address(externalContracts.daiToken),
            0,
            0
        );

        uint256 expectedDai = 4_807.129732213021114492e18;
        uint256 amountOut = lovTokenContracts.lovDsr.exitToToken(quoteData, recipient);
        assertEq(amountOut, expectedDai);
        {
            assertEq(lovTokenContracts.lovDsr.balanceOf(alice), 0);
            assertEq(lovTokenContracts.lovDsr.balanceOf(bob), bobBalance);

            assertEq(externalContracts.daiToken.balanceOf(alice), 0);
            assertEq(externalContracts.daiToken.balanceOf(bob), 0);
            assertEq(externalContracts.daiToken.balanceOf(recipient), amountOut);

            assertEq(externalContracts.sDaiToken.balanceOf(address(lovTokenContracts.lovDsrManager)), 91_868.520795788536414078e18);
            assertEq(lovTokenContracts.lovDsrManager.reservesBalance(), 91_868.520795788536414078e18);
            assertEq(lovTokenContracts.lovDsrManager.assetToLiabilityRatio(), 1.058080262477360285e18);
            assertEq(lovTokenContracts.lovDsrManager.effectiveExposure(IOrigamiOracle.PriceType.SPOT_PRICE), 18.217553043769395495e18);
            assertEq(lovTokenContracts.lovDsrManager.effectiveExposure(IOrigamiOracle.PriceType.HISTORIC_PRICE), 18.151270578560024040e18);
            assertEq(oUsdcContracts.lendingClerk.availableToBorrow(address(lovTokenContracts.lovDsrManager)), 909_110.190001e6);
        }
    }

    function test_lovDsr_exit_fail_al_limit() public {
        vm.prank(origamiMultisig);
        lovTokenContracts.lovDsrManager.setUserALRange(1.05e18, 1.13e18);

        investOusdc(bob, 1_000_000e6);

        uint256 amount = 5_000e18;
        uint256 aliceBalance = investLovDsr(alice, amount);
        investLovDsr(bob, amount);
        
        // The rebalance down introduces a debt.
        // We also hold a buffer % back (0.05%), so the reservesPerShare drops
        // In practice this will be very low.
        doRebalanceDown(1.11e18, 20, 20);
        assertEq(lovTokenContracts.lovDsrManager.assetToLiabilityRatio(), 1.109680071471767688e18);

        {
            vm.startPrank(alice);       
            (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovDsr.exitQuote(
                aliceBalance,
                address(externalContracts.daiToken),
                0,
                0
            );

            lovTokenContracts.lovDsr.exitToToken(quoteData, alice);
            assertEq(lovTokenContracts.lovDsrManager.assetToLiabilityRatio(), 1.057518277043478000e18);
        }

        vm.startPrank(origamiMultisig);
        lovTokenContracts.lovDsrManager.setUserALRange(1.05e18, 1.15e18);

        {
            vm.startPrank(bob);
            (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovDsr.exitQuote(
                1_000e18,
                address(externalContracts.sDaiToken),
                0,
                0
            );

            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, 1.057518277043478000e18, 1.046516356137777911e18, 1.05e18));
            lovTokenContracts.lovDsr.exitToToken(quoteData, alice);
        }
    }

    function test_lovDsr_shutdown() public {
        investOusdc(bob, 1_000_000e6);

        uint256 amount = 5_000e18;
        uint256 aliceBalance = investLovDsr(alice, amount);
        investLovDsr(bob, amount);

        uint256 targetAL = 1.11e18;
        uint256 slippage = 20;
        doRebalanceDown(targetAL, slippage, slippage);

        // Repay the full balance that was borrowed
        uint256 reservesAmount = lovTokenContracts.lovDsrManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        assertEq(reservesAmount, 86_913.308830494366005899e18);
        assertEq(lovTokenContracts.lovDsrManager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 86_894.875386824506455812e18);

        // How much DAI to sell for that reserves amount
        uint256 depositAssetsToWithdraw = externalContracts.sDaiToken.previewRedeem(reservesAmount+30e18);
        (uint256 minDebtAmountToRepay, bytes memory swapData) = swapDaiToUsdcQuote(depositAssetsToWithdraw);

        vm.startPrank(origamiMultisig);
        lovTokenContracts.lovDsrManager.forceRebalanceUp(
            IOrigamiLovTokenErc4626Manager.RebalanceUpParams(
                depositAssetsToWithdraw, 
                reservesAmount, 
                swapData, 
                OrigamiMath.subtractBps(minDebtAmountToRepay, slippage),
                0,
                type(uint128).max
            )
        );

        // It tried to pay off slightly more than it needed to, so has a USDC balance left over
        assertEq(externalContracts.usdcToken.balanceOf(address(lovTokenContracts.lovDsrManager)), 42.281008e6);
        assertEq(lovTokenContracts.lovDsrManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(lovTokenContracts.lovDsrManager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);

        // But we can recover that
        lovTokenContracts.lovDsrManager.recoverToken(address(externalContracts.usdcToken), origamiMultisig, 42.281008e6);

        (IOrigamiLendingBorrower.AssetBalance[] memory assetBalances, uint256 debtTokenBalance) = oUsdcContracts.lendingClerk.borrowerBalanceSheet(address(lovTokenContracts.lovDsrManager));
        assertEq(assetBalances[0].balance, 9_502.657924376439865010e18);
        assertEq(debtTokenBalance, 0);

        // Can no longer borrow
        oUsdcContracts.lendingClerk.shutdownBorrower(address(lovTokenContracts.lovDsrManager));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLendingClerk.BorrowerNotEnabled.selector));      
        lovTokenContracts.lovDsrManager.forceRebalanceDown(
            IOrigamiLovTokenErc4626Manager.RebalanceDownParams(
                1e6, 
                swapData, 
                1e18, 
                0,
                type(uint128).max
            )
        );

        // Users can still withdraw
        vm.startPrank(alice);
        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovDsr.exitQuote(
            aliceBalance,
            address(externalContracts.daiToken),
            0,
            0
        );

        uint256 expectedDai = 4_952.843888331166801321e18;
        uint256 amountOut = lovTokenContracts.lovDsr.exitToToken(quoteData, alice);
        assertEq(amountOut, expectedDai);
        assertEq(externalContracts.daiToken.balanceOf(alice), amountOut);
    }

}

contract OrigamiLovTokenIntegrationTest_PegControls is OrigamiLovTokenIntegrationTestBase {

    function test_lovDsr_rebalanceDown_fail_peg_controls() public {
        investOusdc(bob, 1_000_000e6);

        uint256 amount = 5_000e18;
        investLovDsr(alice, amount);
        investLovDsr(bob, amount);
        
        uint256 slippage = 20;
        uint256 targetAL = 1.11e18;
        (IOrigamiLovTokenErc4626Manager.RebalanceDownParams memory params,) = rebalanceDownParams(targetAL, slippage, slippage);
        vm.startPrank(origamiMultisig);

        vm.mockCall(
            address(externalContracts.clDaiUsdOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(5876, 0.95e8-1, 1701907679, 1701907679, 5876)
        );

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.BelowMinValidRange.selector, address(externalContracts.clDaiUsdOracle), 0.94999999e18, Constants.DAI_USD_MIN_THRESHOLD));
        lovTokenContracts.lovDsrManager.rebalanceDown(params);
    }

    function test_lovDsr_invest_fail_peg_controls() public {
        investOusdc(bob, 1_000_000e6);

        uint256 amount = 5_000e18;
        investLovDsr(alice, amount);
        investLovDsr(bob, amount);
        
        doRebalanceDown(1.11e18, 20, 20);

        doMint(externalContracts.daiToken, bob, amount);
        vm.startPrank(bob);
        externalContracts.daiToken.approve(address(lovTokenContracts.lovDsr), amount);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovTokenContracts.lovDsr.investQuote(
            amount,
            address(externalContracts.daiToken),
            0,
            0
        );

        vm.mockCall(
            address(externalContracts.clDaiUsdOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(5876, 0.95e8-1, 1701907679, 1701907679, 5876)
        );
        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.BelowMinValidRange.selector, address(externalContracts.clDaiUsdOracle), 0.94999999e18, Constants.DAI_USD_MIN_THRESHOLD));
        lovTokenContracts.lovDsr.investWithToken(quoteData);
    }

    function test_lovDsr_exit_fail_peg_controls() public {
        investOusdc(bob, 1_000_000e6);

        uint256 amount = 5_000e18;
        uint256 aliceBalance = investLovDsr(alice, amount);
        investLovDsr(bob, amount);
        
        doRebalanceDown(1.11e18, 20, 20);

        vm.startPrank(alice);       
        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovDsr.exitQuote(
            aliceBalance,
            address(externalContracts.daiToken),
            0,
            0
        );

        vm.mockCall(
            address(externalContracts.clDaiUsdOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(5876, 1.05e8+1, 1701907679, 1701907679, 5876)
        );

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.AboveMaxValidRange.selector, address(externalContracts.clDaiUsdOracle), 1.05000001e18, Constants.DAI_USD_MAX_THRESHOLD));
        lovTokenContracts.lovDsr.exitToToken(quoteData, alice);
    }
}
