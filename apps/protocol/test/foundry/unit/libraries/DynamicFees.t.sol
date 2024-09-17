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
    OrigamiStableChainlinkOracle public oOracleInverted;
    DynamicFeesMock public dynamicFeesMock;
    
    uint256 public constant HISTORIC_RATE = 0.9950e18;
    uint256 public constant DELTA = 0.004e18;

    address public token1 = makeAddr("token1");
    address public token2 = makeAddr("token2");

    function setUp() public {

        // 18 decimals
        clOracle = new DummyOracle(
            DummyOracle.Answer({
                roundId: 1,
                answer: int256(HISTORIC_RATE),
                startedAt: 0,
                updatedAtLag: 0,
                answeredInRound: 1
            }),
            18
        );

        oOracle = new OrigamiStableChainlinkOracle(
            origamiMultisig,
            IOrigamiOracle.BaseOracleParams(
                "TOKEN1/TOKEN2",
                token1,
                18,
                token2,
                18
            ),
            HISTORIC_RATE,
            address(clOracle),
            100 days,
            Range.Data(0.99e18, 1.01e18),
            false,
            true
        );

        oOracleInverted = new OrigamiStableChainlinkOracle(
            origamiMultisig,
            IOrigamiOracle.BaseOracleParams(
                "TOKEN1/TOKEN2",
                token1,
                18,
                token2,
                18
            ),
            1e36 / HISTORIC_RATE,
            address(clOracle),
            100 days,
            Range.Data(0.99e18, 1.01e18),
            false,
            true
        );

        dynamicFeesMock = new DynamicFeesMock();
    }

    function test_dynamicFeeBps_fail_unknownToken() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(alice)));
        dynamicFeesMock.dynamicDepositFeeBps(oOracle, alice, 0, 0);
    }

    function test_dynamicDepositFeeBps_notInverted() public {
        // spot > hist
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(1, HISTORIC_RATE + DELTA, 0, block.timestamp, 1)
        );
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracle, token1, 0, 1e4), 0); // asymmetric delta of zero
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracle, token1, 50, 1e4), 50); // min applied
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracle, token1, 50, 15e4), 50); // min applied

        // spot < hist
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(1, HISTORIC_RATE - DELTA, 0, block.timestamp, 1)
        );
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracle, token1, 0, 1e4), 41); // 1 * 40bps
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracle, token1, 50, 1e4), 50); // min applied
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracle, token1, 50, 15e4), 604); // 15 * 40+bps

        // spot == hist
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(1, HISTORIC_RATE, 0, block.timestamp, 1)
        );
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracle, token1, 0, 1e4), 0); // asymmetric delta of zero
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracle, token1, 50, 1e4), 50); // min applied
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracle, token1, 50, 15e4), 50); // min applied
    }

    function test_dynamicDepositFeeBps_inverted() public {
        // spot < hist
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(1, 1e36 / (HISTORIC_RATE + DELTA), 0, block.timestamp, 1)
        );

        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracleInverted, token2, 0, 1e4), 0); // zero delta
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracleInverted, token2, 50, 1e4), 50); // min applied
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracleInverted, token2, 50, 15e4), 50); // min applied

        // spot > hist
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(1, 1e36 / (HISTORIC_RATE - DELTA), 0, block.timestamp, 1)
        );
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracleInverted, token2, 0, 1e4), 41); // 1 * 40bps
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracleInverted, token2, 50, 1e4), 50); // min applied
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracleInverted, token2, 50, 15e4), 604); // 15 * 40+bps

        // spot == hist
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(1, 1e36 / HISTORIC_RATE, 0, block.timestamp, 1)
        );
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracleInverted, token2, 0, 1e4), 0);  // zero delta
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracleInverted, token2, 50, 1e4), 50); // min applied
        assertEq(dynamicFeesMock.dynamicDepositFeeBps(oOracleInverted, token2, 50, 15e4), 50); // min applied
    }

    function test_dynamicExitFeeBps_notInverted() public {
        // spot > hist
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(1, HISTORIC_RATE + DELTA, 0, block.timestamp, 1)
        );
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracle, token1, 0, 1e4), 41);  // 1 * 40bps
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracle, token1, 50, 1e4), 50); // min applied
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracle, token1, 50, 15e4), 604); // 15 * 40+bps

        // spot < hist
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(1, HISTORIC_RATE - DELTA, 0, block.timestamp, 1)
        );
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracle, token1, 0, 1e4), 0);   // asymmetric delta of zero
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracle, token1, 50, 1e4), 50); // min applied
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracle, token1, 50, 15e4), 50); // min applied

        // spot == hist
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(1, HISTORIC_RATE, 0, block.timestamp, 1)
        );
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracle, token1, 0, 1e4), 0); // zero delta
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracle, token1, 50, 1e4), 50); // min applied
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracle, token1, 50, 15e4), 50); // min applied
    }

    function test_dynamicExitFeeBps_inverted() public {
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(1, 1e36 / (HISTORIC_RATE + DELTA), 0, block.timestamp, 1)
        );

        // spot < hist
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracleInverted, token2, 0, 1e4), 41);  // 1 * 40bps (gets rounded up by 1)
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracleInverted, token2, 50, 1e4), 50); // min applied
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracleInverted, token2, 50, 15e4), 604); // 15 * 40+bps

        // spot > hist
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(1, 1e36 / (HISTORIC_RATE - DELTA), 0, block.timestamp, 1)
        );
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracleInverted, token2, 0, 1e4), 0); // asymmetric delta of zero
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracleInverted, token2, 50, 1e4), 50); // min applied
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracleInverted, token2, 50, 15e4), 50); // min applied

        // spot == hist
        vm.mockCall(
            address(clOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(1, 1e36 / HISTORIC_RATE, 0, block.timestamp, 1)
        );
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracleInverted, token2, 0, 1e4), 0); // zero delta
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracleInverted, token2, 50, 1e4), 50); // min applied
        assertEq(dynamicFeesMock.dynamicExitFeeBps(oOracleInverted, token2, 50, 15e4), 50); // min applied
    }
}
