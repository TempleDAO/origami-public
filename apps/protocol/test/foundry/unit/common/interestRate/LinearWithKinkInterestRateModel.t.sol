pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { LinearWithKinkInterestRateModel } from "contracts/common/interestRate/LinearWithKinkInterestRateModel.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

contract LinearWithKinkInterestRateModelTestBase is OrigamiTest {
    LinearWithKinkInterestRateModel public interestRateModelKinkNinety;
    LinearWithKinkInterestRateModel public interestRateModelFlat;
    uint256 public UTILIZATION_RATIO_90 = 0.9e18; // 90%

    uint80 public IR_AT_0_UR = 0.05e18; // 5%
    uint80 public IR_AT_100_UR = 0.2e18; // 20%
    uint80 public IR_AT_KINK_90 = 0.1e18; // 10%
    uint80 public FLAT_IR_12 = 0.12e18; // 12%

    uint96 internal constant MAX_ALLOWED_INTEREST_RATE = 5e18; // 500% APR

    function setUp() public {
        interestRateModelKinkNinety = new LinearWithKinkInterestRateModel(
            origamiMultisig,
            IR_AT_0_UR, // 5% interest rate (rate% at 0% UR)
            IR_AT_100_UR, // 20% percent interest rate (rate% at 100% UR)
            UTILIZATION_RATIO_90, // 90% utilization (UR for when the kink starts)
            IR_AT_KINK_90 // 10% percent interest rate (rate% at kink% UR)
        );

        // check we didn't forget to set any param
        assertNewRateParams(
            interestRateModelKinkNinety,
            uint80(IR_AT_0_UR),
            uint80(IR_AT_100_UR),
            UTILIZATION_RATIO_90,
            uint80(IR_AT_KINK_90)
        );

        interestRateModelFlat = new LinearWithKinkInterestRateModel(
            origamiMultisig,
            FLAT_IR_12, // 12% interest rate (rate% at 0% UR)
            FLAT_IR_12, // 12% percent interest rate (rate% at 100% UR)
            UTILIZATION_RATIO_90, // 90% utilization (UR for when the kink starts)
            FLAT_IR_12 // 12% percent interest rate (rate% at kink% UR)
        );
    }

    function assertNewRateParams(
        LinearWithKinkInterestRateModel baseModel,
        uint80 newBaseInterestRate,
        uint80 newMaxInterestRate,
        uint256 newKinkUtilizationRatio,
        uint80 newKinkInterestRate
    ) internal view {
        // get initial params
        (
            uint80 baseInterestRate,
            uint80 maxInterestRate,
            uint80 kinkInterestRate,
            uint256 kinkUtilizationRatio
        ) = baseModel.rateParams();

        assertEq(baseInterestRate, newBaseInterestRate);
        assertEq(maxInterestRate, newMaxInterestRate);
        assertEq(kinkInterestRate, newKinkInterestRate);
        assertEq(kinkUtilizationRatio, newKinkUtilizationRatio);
    }
}

contract LinearWithKinkInterestRateModelTestAccess is
    LinearWithKinkInterestRateModelTestBase
{
    function test_access_setRateParams() public {
        expectElevatedAccess();
        interestRateModelKinkNinety.setRateParams(
            0.02e18,
            0.75e18,
            0.5e18,
            0.1e18
        );
    }
}

contract LinearWithKinkInterestRateModelTestAdmin is LinearWithKinkInterestRateModelTestBase
{
    event InterestRateParamsSet(
        uint80 _baseInterestRate, 
        uint80 _maxInterestRate, 
        uint256 _kinkUtilizationRatio, 
        uint80 _kinkInterestRate
    );

    function test_setRateParams_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit();
        emit InterestRateParamsSet(0.02e18, 0.75e18, 0.5e18, 0.1e18);
        interestRateModelKinkNinety.setRateParams(
            0.02e18,
            0.75e18,
            0.5e18,
            0.1e18
        );
        assertNewRateParams(
            interestRateModelKinkNinety,
            0.02e18,
            0.75e18,
            0.5e18,
            0.1e18
        );
    }

    function test_setRateParams_failZero() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(
            abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector)
        );
        interestRateModelKinkNinety.setRateParams(0e18, 0e18, 0e18, 0e18);
    }

    function test_setRateParams_failMax() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(
            abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector)
        );
        interestRateModelKinkNinety.setRateParams(
            type(uint80).max,
            type(uint80).max,
            type(uint256).max,
            type(uint80).max
        );
    }

    function test_setRateParams_failWrongOrder() public {
        vm.startPrank(origamiMultisig);
        // Base rate is bigger thank Kink rate
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        interestRateModelKinkNinety.setRateParams(100, 100, 100, 99);

        // Kink rate is bigger thank Max rate
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        interestRateModelKinkNinety.setRateParams(100, 99, 100, 100);
    }

    function test_setRateParams_failSlope() public {
        vm.startPrank(origamiMultisig);

        // base->kink slope > kink->max slope
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        interestRateModelKinkNinety.setRateParams(0.1e18, 0.29999e18, 0.5e18, 0.2e18);

        // base->kink slope == kink->max slope
        interestRateModelKinkNinety.setRateParams(0.1e18, 0.3e18, 0.5e18, 0.2e18);

        // base->kink slope < kink->max slope
        interestRateModelKinkNinety.setRateParams(0.1e18, 3.0001e18, 0.5e18, 0.2e18);
    }
}

contract LinearWithKinkInterestRateModelTestCalculateIR is LinearWithKinkInterestRateModelTestBase
{
    function test_calculateInterestRateKink_zeroUR() public view {
        uint256 utilizationRatio = 0.0e18; // 0% UR
        uint256 expectedInterestRate = interestRateModelKinkNinety
            .calculateInterestRate(utilizationRatio);
        assertEq(expectedInterestRate, IR_AT_0_UR); // 5% IR
    }

    function test_calculateInterestRateKink_oneUR() public view {
        uint256 utilizationRatio = 0.01e18; // 1% UR
        uint256 expectedInterestRate = interestRateModelKinkNinety
            .calculateInterestRate(utilizationRatio);
        assertEq(expectedInterestRate, 0.050555555555555556e18); // ~5.06% IR
    }

    function test_calculateInterestRateKink_HalfUR() public view {
        uint256 expectedInterestRate = interestRateModelKinkNinety
            .calculateInterestRate(UTILIZATION_RATIO_90 / 2);
        assertEq(expectedInterestRate, 0.075e18); // ~7.5% IR
    }

    function test_calculateInterestRateKink_BeforeKink() public view {
        uint256 expectedInterestRate = interestRateModelKinkNinety
            .calculateInterestRate(UTILIZATION_RATIO_90 - 15);
        assertEq(expectedInterestRate, 0.1e18); // Rounded up to 10% IR
    }

    function test_calculateInterestRateKink_AtKink() public view {
        uint256 expectedInterestRate = interestRateModelKinkNinety
            .calculateInterestRate(UTILIZATION_RATIO_90);

        assertEq(expectedInterestRate, 0.1e18); // 10% IR
    }

    function test_calculateInterestRateKink_AfterKink() public view {
        uint256 expectedInterestRate = interestRateModelKinkNinety
            .calculateInterestRate(UTILIZATION_RATIO_90 + 1);
        assertEq(expectedInterestRate, 0.100000000000000001e18); // >10% IR
    }

    function test_calculateInterestRateKink_HalfWayUpKink() public view {
        uint256 expectedInterestRate = interestRateModelKinkNinety
            .calculateInterestRate(
                UTILIZATION_RATIO_90 + (1e18 - UTILIZATION_RATIO_90) / 2
            );
        assertEq(expectedInterestRate, 0.15e18); // 15% IR
    }

    function test_calculateInterestRateKink_BeforeHundredUR() public view {
        uint256 expectedInterestRate = interestRateModelKinkNinety
            .calculateInterestRate(1e18 - 1);
        assertEq(expectedInterestRate, 0.199999999999999999e18); // ~19.99% IR
    }

    function test_calculateInterestRateKink_HundredUR() public view {
        uint256 expectedInterestRate = interestRateModelKinkNinety
            .calculateInterestRate(1e18);
        assertEq(expectedInterestRate, IR_AT_100_UR); // ~20% IR
    }

    function test_calculateInterestRateKink_AfterHundredUR() public view {
        uint256 expectedInterestRate = interestRateModelKinkNinety
            .calculateInterestRate(1e18 + 1);
        assertEq(expectedInterestRate, IR_AT_100_UR); // ~20% IR
    }

    function test_calculateInterestRateFlat_ZeroUR() public view {
        uint256 utilizationRatio = 0e18; // 0% UR
        uint256 expectedInterestRate = interestRateModelFlat
            .calculateInterestRate(utilizationRatio);
        assertEq(expectedInterestRate, FLAT_IR_12); // 12% IR
    }

    function test_calculateInterestRateFlat_OneUR() public view {
        uint256 utilizationRatio = 0.01e18; // 1% UR
        uint256 expectedInterestRate = interestRateModelFlat
            .calculateInterestRate(utilizationRatio);
        assertEq(expectedInterestRate, FLAT_IR_12); // 12% IR
    }

    function test_calculateInterestRateFlat_HalfUR() public view {
        uint256 expectedInterestRate = interestRateModelFlat
            .calculateInterestRate(UTILIZATION_RATIO_90 / 2);
        assertEq(expectedInterestRate, FLAT_IR_12); // 12% IR
    }

    function test_calculateInterestRateFlat_BeforeKink() public view {
        uint256 expectedInterestRate = interestRateModelFlat
            .calculateInterestRate(UTILIZATION_RATIO_90 - 1);
        assertEq(expectedInterestRate, FLAT_IR_12); // 12% IR
    }

    function test_calculateInterestRateFlat_AtKink() public view {
        uint256 expectedInterestRate = interestRateModelFlat
            .calculateInterestRate(UTILIZATION_RATIO_90);
        assertEq(expectedInterestRate, FLAT_IR_12); // 12% IR
    }

    function test_calculateInterestRateFlat_AfterKink() public view {
        uint256 expectedInterestRate = interestRateModelFlat
            .calculateInterestRate(UTILIZATION_RATIO_90 + 1);
        assertEq(expectedInterestRate, FLAT_IR_12); // 12% IR
    }

    function test_calculateInterestRateFlat_HundredUR() public view {
        uint256 expectedInterestRate = interestRateModelFlat
            .calculateInterestRate(100e18);
        assertEq(expectedInterestRate, FLAT_IR_12); // 12% IR
    }

    function test_calculateInterestRateFlat_AfterHundredUR() public view {
        uint256 expectedInterestRate = interestRateModelFlat
            .calculateInterestRate(100e18 + 1);
        assertEq(expectedInterestRate, FLAT_IR_12); // 12% IR
    }

    function test_calculateInterest_ExceedPrecission() public view {
        uint256 utilizationRatio = 0.1e20;
        uint256 expectedInterestRate = interestRateModelFlat
            .calculateInterestRate(utilizationRatio);
        assertEq(expectedInterestRate, FLAT_IR_12); // 12% IR
    }

    function test_calculateInterest_MaxUR() public view {
        uint256 utilizationRatio = type(uint256).max;
        uint256 expectedInterestRate = interestRateModelFlat
            .calculateInterestRate(utilizationRatio);
        assertEq(expectedInterestRate, FLAT_IR_12); // 12% IR
    }

    function test_calculateInterestRateKink900_HundredUR() public {
        vm.startPrank(origamiMultisig);
        interestRateModelKinkNinety.setRateParams(
            uint80(IR_AT_0_UR), // 5% at 0% UR
            9e18, // 900% Max interest rate at 100% UR
            UTILIZATION_RATIO_90, // Kink at 90%
            uint80(IR_AT_KINK_90) // 10% IR at kink
        );
        assertNewRateParams(
            interestRateModelKinkNinety,
            uint80(IR_AT_0_UR),
            9e18,
            UTILIZATION_RATIO_90,
            uint80(IR_AT_KINK_90)
        );
        
        // we should expect 900% IR  at 100% UR, however, there is a hard cap at 500%
        uint256 expectedInterestRate = interestRateModelKinkNinety
            .calculateInterestRate(100e18);
        assertEq(expectedInterestRate, MAX_ALLOWED_INTEREST_RATE); // 500% IR
    }
}
