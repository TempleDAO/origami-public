pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { DynamicFees } from "contracts/libraries/DynamicFees.sol";
import { DummyOracle } from "contracts/test/common/DummyOracle.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { OrigamiStableChainlinkOracle } from "contracts/common/oracle/OrigamiStableChainlinkOracle.sol";
import { Range } from "contracts/libraries/Range.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

contract DynamicFeesMock {
    function dynamicDepositFeeBps(
        IOrigamiOracle oracle,
        address expectedBaseToken,
        uint64 minDepositFeeBps,
        uint256 feeLeverageFactor
    ) external view returns (uint256) {
        return DynamicFees.dynamicFeeBps(
            DynamicFees.FeeType.DEPOSIT_FEE,
            oracle, 
            expectedBaseToken, 
            minDepositFeeBps, 
            feeLeverageFactor
        );
    }

    function dynamicExitFeeBps(
        IOrigamiOracle oracle,
        address expectedBaseToken,
        uint64 minExitFeeBps,
        uint256 feeLeverageFactor
    ) external view returns (uint256) {
        return DynamicFees.dynamicFeeBps(
            DynamicFees.FeeType.EXIT_FEE,
            oracle, 
            expectedBaseToken, 
            minExitFeeBps, 
            feeLeverageFactor
        );
    }
}

contract DynamicFeesTest is OrigamiTest {
    DummyOracle public clOracle;
    OrigamiStableChainlinkOracle public oOracle;
    DynamicFeesMock public dynamicFeesMock;
    
    uint256 public constant HISTORIC_RATE = 1e18;
    uint256 public constant ORACLE_RATE = 1.004e18;

    address public token1 = makeAddr("token1");
    address public token2 = makeAddr("token2");

    function setUp() public {

        // 18 decimals
        clOracle = new DummyOracle(
            DummyOracle.Answer({
                roundId: 1,
                answer: int256(ORACLE_RATE),
                startedAt: 0,
                updatedAtLag: 0,
                answeredInRound: 1
            }),
            18
        );

        oOracle = new OrigamiStableChainlinkOracle(
            origamiMultisig,
            "TOKEN1/TOKEN2",
            token1,
            18,
            token2,
            18,
            HISTORIC_RATE,
            address(clOracle),
            100 days,
            Range.Data(0.99e18, 1.01e18)
        );

        dynamicFeesMock = new DynamicFeesMock();
    }

    function test_dynamicFeeBps_fail_unknownToken() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(alice)));
        dynamicFeesMock.dynamicDepositFeeBps(oOracle, alice, 0, 0);
    }

    function test_dynamicDepositFeeBps_notInverted() public {
        // spot > hist
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracle, token1, 0, 0), 0);
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracle, token1, 50, 0), 50); // min applied
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracle, token1, 50, 20), 50); // min applied

        // spot < hist
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(1, 0.9993e18, 0, 0, 1)
        );
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracle, token1, 50, 1), 50); // min applied
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracle, token1, 50, 20), 140); // 20 * 7bps

        // spot == hist
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(1, 1e18, 0, 0, 1)
        );
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracle, token1, 50, 1), 50); // min applied
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracle, token1, 50, 20), 50); // min applied
    }

    function test_dynamicDepositFeeBps_inverted() public {
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(1, 0.996e18, 0, 0, 1)
        );

        // spot > hist
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracle, token2, 0, 0), 0);
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracle, token2, 50, 0), 50); // min applied
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracle, token2, 50, 20), 50); // min applied

        // spot < hist
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(1, 1.0007e18, 0, 0, 1)
        );
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracle, token2, 50, 1), 50); // min applied
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracle, token2, 50, 20), 140); // 20 * 7bps

        // spot == hist
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(1, 1e18, 0, 0, 1)
        );
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracle, token2, 50, 1), 50); // min applied
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracle, token2, 50, 20), 50); // min applied
    }

    function test_dynamicExitFeeBps_notInverted() public {
        // spot > hist
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracle, token1, 0, 0), 0);
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracle, token1, 50, 0), 50); // min applied
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracle, token1, 50, 20), 800); // 20 * 40

        // spot < hist
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(1, 0.9993e18, 0, 0, 1)
        );
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracle, token1, 50, 0), 50); // min applied
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracle, token1, 50, 20), 50); // min applied

        // spot == hist
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(1, 1e18, 0, 0, 1)
        );
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracle, token1, 50, 0), 50); // min applied
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracle, token1, 50, 20), 50); // min applied
    }

    function test_dynamicExitFeeBps_inverted() public {
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(1, 0.996e18, 0, 0, 1)
        );

        // spot > hist
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracle, token2, 0, 0), 0);
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracle, token2, 50, 0), 50); // min applied
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracle, token2, 50, 20), 800); // 20 * 40

        // spot < hist
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(1, 1.0007e18, 0, 0, 1)
        );
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracle, token2, 50, 0), 50); // min applied
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracle, token2, 50, 20), 50); // min applied

        // spot == hist
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(1, 1e18, 0, 0, 1)
        );
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracle, token2, 50, 0), 50); // min applied
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracle, token2, 50, 20), 50); // min applied
    }
}
