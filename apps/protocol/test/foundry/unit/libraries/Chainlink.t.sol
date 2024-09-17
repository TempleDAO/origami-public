pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { Chainlink } from "contracts/libraries/Chainlink.sol";
import { DummyOracle } from "contracts/test/common/DummyOracle.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

contract ChainlinkMock {
    function price(
        Chainlink.Config memory config,
        OrigamiMath.Rounding roundingMode
    ) external view returns (uint256) {
        return Chainlink.price(config, roundingMode);
    }

    function scalingFactor(
        IAggregatorV3Interface oracle,
        uint8 targetDecimals
    ) external view returns (uint128 scalar, bool scaleDown) {
        return Chainlink.scalingFactor(oracle, targetDecimals);
    }
}

contract ChainlinkTest is OrigamiTest {
    
    DummyOracle public oracle;
    ChainlinkMock public chainlinkMock;

    function setUp() public {

        // 8 decimals
        oracle = new DummyOracle(
            DummyOracle.Answer({
                roundId: 1,
                answer: 1.00044127e8,
                startedAt: 0,
                updatedAtLag: 0,
                answeredInRound: 1
            }),
            8
        );

        chainlinkMock = new ChainlinkMock();
    }

    function test_scalingFactor() public {
        (uint128 scalar, bool scaleDown) = chainlinkMock.scalingFactor(oracle, 18);
        assertEq(scalar, 1e10);
        assertEq(scaleDown, false);

        (scalar, scaleDown) = chainlinkMock.scalingFactor(oracle, 8);
        assertEq(scalar, 1);
        assertEq(scaleDown, false);

        (scalar, scaleDown) = chainlinkMock.scalingFactor(oracle, 4);
        assertEq(scalar, 1e4);
        assertEq(scaleDown, true);
    }

    function test_price_failStaleRound_withValidation() public {
        (uint128 scalar, bool scaleDown) = chainlinkMock.scalingFactor(oracle, 18);
        Chainlink.Config memory config = Chainlink.Config(oracle, scaleDown, scalar, 1 days, true, true);

        vm.warp(1000000);
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(2, 1e18, block.timestamp, block.timestamp - 10 days, 1)
        );

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.StalePrice.selector, address(oracle), 136000, 1e18));        
        chainlinkMock.price(config, OrigamiMath.Rounding.ROUND_DOWN);
    }

    function test_price_zeroLastUpdatedAt_noValidation() public {
        (uint128 scalar, bool scaleDown) = chainlinkMock.scalingFactor(oracle, 18);
        Chainlink.Config memory config = Chainlink.Config(oracle, scaleDown, scalar, 1 days, false, false);

        vm.warp(1000000);
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(0, 1e8, 0, 0, 0)
        );

        assertEq(
            chainlinkMock.price(config, OrigamiMath.Rounding.ROUND_DOWN),
            1e18
        );
    }

    function test_price_zeroRoundId_noValidation() public {
        (uint128 scalar, bool scaleDown) = chainlinkMock.scalingFactor(oracle, 18);
        Chainlink.Config memory config = Chainlink.Config(oracle, scaleDown, scalar, 1 days, false, true);

        vm.warp(1000000);
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(0, 1e8, block.timestamp, block.timestamp, 0)
        );

        assertEq(
            chainlinkMock.price(config, OrigamiMath.Rounding.ROUND_DOWN),
            1e18
        );
    }

    function test_price_zeroRoundId_withValidation() public {
        (uint128 scalar, bool scaleDown) = chainlinkMock.scalingFactor(oracle, 18);
        Chainlink.Config memory config = Chainlink.Config(oracle, scaleDown, scalar, 1 days, true, true);

        vm.warp(1000000);
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(0, 1e8, block.timestamp, block.timestamp, 0)
        );

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.InvalidOracleData.selector, address(oracle)));
        chainlinkMock.price(config, OrigamiMath.Rounding.ROUND_DOWN);
    }

    function test_price_okThreshold() public {
        (uint128 scalar, bool scaleDown) = chainlinkMock.scalingFactor(oracle, 18);
        Chainlink.Config memory config = Chainlink.Config(oracle, scaleDown, scalar, 10 days, true, true);

        vm.warp(1000000);
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(2, 123e8, block.timestamp, block.timestamp - 10 days, 2)
        );

        assertEq(
            chainlinkMock.price(config, OrigamiMath.Rounding.ROUND_DOWN),
            123e18
        );
    }

    function test_price_negativePrice() public {
        (uint128 scalar, bool scaleDown) = chainlinkMock.scalingFactor(oracle, 18);
        Chainlink.Config memory config = Chainlink.Config(oracle, scaleDown, scalar, 10 days, true, true);

        vm.warp(1000000);
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(2, -123e8, block.timestamp, block.timestamp - 10 days, 2)
        );

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.InvalidPrice.selector, address(oracle), -123e8));        
        chainlinkMock.price(config, OrigamiMath.Rounding.ROUND_DOWN);
    }

    function test_price_scaleDown() public {
        (uint128 scalar, bool scaleDown) = chainlinkMock.scalingFactor(oracle, 6);
        assertEq(scaleDown, true);
        Chainlink.Config memory config = Chainlink.Config(oracle, scaleDown, scalar, 10 days, true, true);

        vm.warp(1000000);
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(2, 123.45678999e8, block.timestamp, block.timestamp - 10 days, 2)
        );

        assertEq(
            chainlinkMock.price(config, OrigamiMath.Rounding.ROUND_DOWN),
            123.456789e6
        );
        assertEq(
            chainlinkMock.price(config, OrigamiMath.Rounding.ROUND_UP),
            123.45679e6
        );
    }

    function test_price_scaleUp() public {
        (uint128 scalar, bool scaleDown) = chainlinkMock.scalingFactor(oracle, 18);
        assertEq(scaleDown, false);
        Chainlink.Config memory config = Chainlink.Config(oracle, scaleDown, scalar, 10 days, true, true);

        vm.warp(1000000);
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(2, 123.12312312e8, block.timestamp, block.timestamp - 10 days, 2)
        );

        assertEq(
            chainlinkMock.price(config, OrigamiMath.Rounding.ROUND_DOWN),
            123.12312312e18
        );
        assertEq(
            chainlinkMock.price(config, OrigamiMath.Rounding.ROUND_UP),
            123.12312312e18
        );
    }
}
