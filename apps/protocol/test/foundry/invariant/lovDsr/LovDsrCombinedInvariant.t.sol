pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { ExternalContracts, OUsdcContracts, LovTokenContracts, OrigamiLovTokenTestDeployer } from "test/foundry/deploys/lovDsr/OrigamiLovTokenTestDeployer.t.sol";
import { OvUsdcHandler } from "test/foundry/invariant/handlers/lovDsr/OvUsdcHandler.sol";
import { LovDsrHandler } from "test/foundry/invariant/handlers/lovDsr/LovDsrHandler.sol";
import { BaseInvariantTest } from "test/foundry/invariant/BaseInvariant.t.sol";
import { OrigamiLovTokenTestConstants as Constants } from "test/foundry/deploys/lovDsr/OrigamiLovTokenTestConstants.t.sol";
import { IOrigamiDebtToken } from "contracts/interfaces/investments/lending/IOrigamiDebtToken.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

/// @notice Invariant tests on the combined flows of users investing/exiting ovUSDC and also
/// users investin/exiting lovDSR along with lovDSR rebalances up/down
contract LovDsrCombinedInvariantTest is BaseInvariantTest {
    OvUsdcHandler internal ovUsdcHandler;
    LovDsrHandler internal lovDsrHandler;

    OrigamiLovTokenTestDeployer private deployer;
    ExternalContracts public externalContracts;
    OUsdcContracts public oUsdcContracts;
    LovTokenContracts public lovTokenContracts;

    function setUp() public override {
        BaseInvariantTest.setUp();

        {
            deployer = new OrigamiLovTokenTestDeployer(); 
            (externalContracts, oUsdcContracts, lovTokenContracts) = deployer.deployNonForked(address(deployer), feeCollector, overlord);
            doMint(externalContracts.daiToken, address(externalContracts.sDaiToken), 100_000_000e18);

            // Set the circuit breakers really high since the invariant tests use potentially
            // high values
            vm.startPrank(address(deployer));
            oUsdcContracts.cbUsdcBorrow.updateCap(100_000_000e6);
            oUsdcContracts.cbOUsdcExit.updateCap(100_000_000e18);
            oUsdcContracts.lendingClerk.setBorrowerDebtCeiling(address(lovTokenContracts.lovDsrManager), 200_000_000e18);
            vm.stopPrank();
        }

        ovUsdcHandler = new OvUsdcHandler(timestampStore, stateStore, externalContracts, oUsdcContracts, lovTokenContracts);
        vm.label({ account: address(ovUsdcHandler), newLabel: "OvUsdcHandler" });

        lovDsrHandler = new LovDsrHandler(timestampStore, stateStore, deployer.overlord(), externalContracts, oUsdcContracts, lovTokenContracts);
        vm.label({ account: address(lovDsrHandler), newLabel: "LovDsrHandler" });

        // Target only the specific handlers and their functions for invariant testing
        // NB: Because the BaseHandler inherits from DSTest, it would pull in the failed() public function
        // to fuzz. To workaround, manually specify the functions to fuzz instead.
        targetSelectors(
            address(ovUsdcHandler), 
            mkArray(
                OvUsdcHandler.investOvUsdc_usdc.selector,
                OvUsdcHandler.exitOvUsdc_usdc.selector
            )
        );

        targetSelectors(
            address(lovDsrHandler), 
            mkArray(
                LovDsrHandler.investLovDsr_dai.selector,
                LovDsrHandler.exitLovDsr_dai.selector,
                LovDsrHandler.rebalanceDown.selector,
                LovDsrHandler.rebalanceUp.selector
            )
        );

        targetSender(makeAddr("actor1"));
        targetSender(makeAddr("actor2"));
        targetSender(makeAddr("actor3"));
    }

    /**
     @dev Dump out the number of function calls made
     */
    /*
    function invariant_logCalls() external useCurrentTimestamp {
        console.log("totalCalls: ovUsdcHandler:", ovUsdcHandler.totalCalls(), "lovDsrHandler", lovDsrHandler.totalCalls());
        console.log("\tovUsdcHandler.investOvUsdc_usdc:", ovUsdcHandler.calls(OvUsdcHandler.investOvUsdc_usdc.selector));
        console.log("\tovUsdcHandler.exitOvUsdc_usdc:", ovUsdcHandler.calls(OvUsdcHandler.exitOvUsdc_usdc.selector));
        console.log("\tlovDsrHandler.investLovDsr_dai:", lovDsrHandler.calls(LovDsrHandler.investLovDsr_dai.selector));
        console.log("\tlovDsrHandler.exitLovDsr_dai:", lovDsrHandler.calls(LovDsrHandler.exitLovDsr_dai.selector));
        console.log("\tlovDsrHandler.rebalanceDown:", lovDsrHandler.calls(LovDsrHandler.rebalanceDown.selector));
        console.log("\tlovDsrHandler.rebalanceUp:", lovDsrHandler.calls(LovDsrHandler.rebalanceUp.selector));
    }
    */

    /// @dev The amount of oUSDC in ovUSDC matches the reported vested and pending reserves
    function invariant_ovUsdcReserves() external useCurrentTimestamp {
        uint256 actualReserves = oUsdcContracts.oUsdc.balanceOf(address(oUsdcContracts.ovUsdc));
        uint256 pendingAndVestedReserves = oUsdcContracts.ovUsdc.vestedReserves() + oUsdcContracts.ovUsdc.pendingReserves();

        assertEq(
            actualReserves,
            pendingAndVestedReserves,
            "Invariant violation: ovUSDC actual reserves == pending + vested accounting"
        );
    }

    /// @dev The amount of sDAI in lovDSR manager can pay down the debt + the calculated userRedeemableReserves
    function invariant_lovDsrReserves() external useCurrentTimestamp {
        uint256 totalReserves = externalContracts.sDaiToken.balanceOf(address(lovTokenContracts.lovDsrManager));

        uint256 liabilities = lovTokenContracts.lovDsrManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        uint256 userRedeemableReserves = lovTokenContracts.lovDsrManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE);

        assertGe(
            totalReserves,
            userRedeemableReserves + liabilities,
            "Invariant violation: lovDSR actual reserves >= userRedeemableReserves + liabilities"
        );
    }

    /// @dev The iUSDC totalSupply should always be >= to the net USDC deposited into ovUSDC (because of interest)
    function invariant_iUsdcDebtGeNetUsdcInvested() external useCurrentTimestamp {
        uint256 totalDebt = oUsdcContracts.iUsdc.totalSupply();
        uint256 netUsdcInvested = ovUsdcHandler.totalUsdcDeposits() - ovUsdcHandler.totalUsdcExits();

        assertGe(
            totalDebt, 
            netUsdcInvested,
            unicode"Invariant violation: Σ iUsdc supply >= Σ deposited USDC into oUSDC - Σ exited USDC from oUSDC"
        );
    }

    /// @dev The iUSDC interest rate for idle strategy and lovDSR borrower should always be within the min/max on the curve
    function invariant_iUsdcInterestRatesInBounds() external useCurrentTimestamp {
        uint256 totalPrincipal;
        uint256 totalInterest;
        {
            IOrigamiDebtToken.DebtorPosition memory position = oUsdcContracts.iUsdc.getDebtorPosition(address(oUsdcContracts.idleStrategyManager));
            totalPrincipal += position.principal;
            totalInterest += position.interest;
            assertGe(
                position.rate,
                Constants.GLOBAL_IR_AT_0_UR,
                "Invariant violation: iUSDC: Idle Strategy Manager IR >= GLOBAL_IR_AT_0_UR"
            );
            assertLe(
                position.rate,
                Constants.GLOBAL_IR_AT_100_UR,
                "Invariant violation: iUSDC: Idle Strategy Manager IR <= GLOBAL_IR_AT_100_UR"
            );
        }

        {
            IOrigamiDebtToken.DebtorPosition memory position = oUsdcContracts.iUsdc.getDebtorPosition(address(lovTokenContracts.lovDsrManager));
            totalPrincipal += position.principal;
            totalInterest += position.interest;
            assertGe(
                position.rate,
                Constants.GLOBAL_IR_AT_0_UR,
                "Invariant violation: iUSDC: lovDSR Manager borrow IR >= GLOBAL_IR_AT_0_UR"
            );
            assertLe(
                position.rate,
                Constants.GLOBAL_IR_AT_100_UR,
                "Invariant violation: iUSDC: lovDSR Manager borrow IR <= GLOBAL_IR_AT_100_UR"
            );
        }

        IOrigamiDebtToken.DebtOwed memory totalDebt = oUsdcContracts.iUsdc.currentTotalDebt();
        assertEq(
            totalPrincipal,
            totalDebt.principal,
            unicode"Invariant violation: iUSDC: Σ principal == currentTotalDebt().principal"
        );
        // The interest is an estimation - only updated on a checkpoint
        assertGe(
            totalInterest,
            totalDebt.interest,
            unicode"Invariant violation: iUSDC: Σ interest >= currentTotalDebt().interest"
        );
    }

    /* solhint-disable code-complexity */
    /// @dev The lovDSR A/L should be within acceptable ranges (depending on the action just taken)
    function invariant_ALWithinBounds() external useCurrentTimestamp {
        (
            uint256 assets,
            uint256 liabilities,
            uint256 alRatio
        ) = lovTokenContracts.lovDsrManager.assetsAndLiabilities(IOrigamiOracle.PriceType.SPOT_PRICE);

        (address handler, bytes4 sig, bool finishedEarly) = stateStore.pop();

        // No action was taken, so don't check the A/L
        if (finishedEarly) {
            return;
        }

        if (liabilities == 0) {
            // If no liabilities yet, then A/L is uint128.max
            assertEq(
                alRatio, 
                type(uint128).max,
                "Invariant violation: A/L == uint128.max when there are no liabilities"
            );
        } else if (assets == 0) {
            // No assets, but there are somehow liabilities
            assertEq(
                alRatio, 
                0,
                "Invariant violation: A/L == 0 when there are no assets"
            );
        } else if (handler == address(lovDsrHandler)) {
            if (sig == LovDsrHandler.investLovDsr_dai.selector) {
                // The A/L might be at the floor, and then a small investment
                // is made -- it might not yet be over the USER_AL_CEILING.
                // Further, if there was a period of increasing net debt increase
                // then it may still be under the floor by a little
                // but it's definitely over the REBALANCE_AL_FLOOR
                assertGe(
                    alRatio,
                    Constants.REBALANCE_AL_FLOOR - 0.05e18,
                    "Invariant violation: A/L >= REBALANCE_AL_FLOOR after lovDSR invest"
                );

                // A new deposit can't go over the USER_AL_CEILING
                assertLe(
                    alRatio,
                    Constants.USER_AL_CEILING,
                    "Invariant violation: A/L <= USER_AL_CEILING after lovDSR invest"
                );
            } else if (sig == LovDsrHandler.exitLovDsr_dai.selector) {
                // A new exit can't go under the USER_AL_FLOOR
                assertGe(
                    alRatio,
                    Constants.USER_AL_FLOOR,
                    "Invariant violation: A/L >= USER_AL_FLOOR after lovDSR exit"
                );
                // The A/L might be above the ceiling, and then a small exit
                // is made -- it might not yet be under the USER_AL_CEILING or REBALANCE_AL_CEILING
                assertLe(
                    alRatio,
                    type(uint128).max,
                    "Invariant violation: A/L <= uint128.max after lovDSR exit"
                );
            } else if (sig == LovDsrHandler.rebalanceDown.selector) {
                // A rebalance down can't go under the REBALANCE_AL_FLOOR
                assertGe(
                    alRatio,
                    Constants.REBALANCE_AL_FLOOR,
                    "Invariant violation: A/L >= REBALANCE_AL_FLOOR after lovDSR rebalance down"
                );

                if (stateStore.cappedRebalanceDown()) {
                    // If the rebalance was capped (not enough USDC supply)
                    // then as long as it's below uint128.max
                    assertLe(
                        alRatio,
                        type(uint128).max,
                        "Invariant violation: A/L <= uint128.max after lovDSR capped rebalance down"
                    );
                } else {
                    // A non-capped rebalance down should be below the REBALANCE_AL_CEILING
                    // (plus a small delta since the amount we solved for might not quite bring it under the ceiling)
                    assertLe(
                        alRatio,
                        Constants.REBALANCE_AL_CEILING + 0.0001e18, // The rebalance might not quite bring under the ceiling
                        "Invariant violation: A/L <= REBALANCE_AL_CEILING after lovDSR rebalance down"
                    );
                }
            } else if (sig == LovDsrHandler.rebalanceUp.selector) {
                // A rebalance up can't go below the REBALANCE_AL_FLOOR
                // (minus a small delta since the amount we solved for might not quite bring it over the floor)
                assertGe(
                    alRatio,
                    Constants.REBALANCE_AL_FLOOR - 0.0001e18, 
                    "Invariant violation: A/L >= REBALANCE_AL_FLOOR after lovDSR rebalance up"
                );

                // A rebalance up can't go above the REBALANCE_AL_CEILING
                assertLe(
                    alRatio,
                    Constants.REBALANCE_AL_CEILING,
                    "Invariant violation: A/L <= REBALANCE_AL_CEILING after lovDSR rebalance up"
                );
            } else {
                fail();
            }
        } else if (handler == address(ovUsdcHandler)) {
            // When the lovDSR borrow interest rate is less than the sDAI interest rate,
            // then the A/L should always increase (less debt)
            // However if the lovDSR borrow rate is higher than the sDAI interest rate,
            // then the net debt increases, and the A/L could go under the floor by a little
            assertGe(
                alRatio,
                Constants.REBALANCE_AL_FLOOR - 0.075e18,
                "Invariant violation: A/L >= REBALANCE_AL_FLOOR after oUSDC action"
            );

            if (stateStore.cappedRebalanceDown()) {
                // If after a capped rebalance down, then the A/L might still be above the ceiling
                assertLe(
                    alRatio,
                    type(uint128).max,
                    "Invariant violation: A/L <= uint128.max after capped lovDSR rebalance down then oUSDC action"
                );
            } else {
                // ovUSDC deposit/exits won't affect the immediate lovDSR A/L
                // however sDAI will continue to increase over time vs the increase in debt
                // Meaning the A/L may go a little above the ceiling
                assertLe(
                    alRatio,
                    Constants.REBALANCE_AL_CEILING + 0.075e18,
                    "Invariant violation: A/L <= REBALANCE_AL_CEILING after oUSDC action"
                );
            }
        } else {
            fail();
        }
    }
}
