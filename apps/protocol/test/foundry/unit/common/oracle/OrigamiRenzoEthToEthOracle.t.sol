pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { DummyOracle } from "contracts/test/common/DummyOracle.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IRenzoRestakeManager } from "contracts/interfaces/external/renzo/IRenzoRestakeManager.sol";
import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { OrigamiRenzoEthToEthOracle } from "contracts/common/oracle/OrigamiRenzoEthToEthOracle.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

contract MockRenzoRestakeManager is IRenzoRestakeManager {
    function calculateTVLs() external pure returns (uint256[][] memory, uint256[] memory, uint256) {
        return (new uint256[][](0), new uint256[](0), 971_403.774462518193814373e18);
    }
}

/* solhint-disable func-name-mixedcase, contract-name-camelcase, not-rely-on-time */
contract OrigamiRenzoEthToEthOracleTestBase is OrigamiTest {
    OrigamiRenzoEthToEthOracle public oEzEthToEthOracle;

    IERC20 internal ezEthToken;
    MockRenzoRestakeManager internal renzoRestakeManager;
    IAggregatorV3Interface internal redstoneEzEthToEthOracle;

    uint128 public constant stalenessThreshold = 12 hours + 15 minutes;
    uint256 public constant validPriceDiffBps = 100; // 1%

    function setUp() public {
        vm.warp(1713314062);

        ezEthToken = new DummyMintableToken(origamiMultisig, "ezETH", "ezETH", 18);
        deal(address(ezEthToken), origamiMultisig, 963_515.321545974203801303e18, true);

        renzoRestakeManager = new MockRenzoRestakeManager();

        redstoneEzEthToEthOracle = new DummyOracle(
            DummyOracle.Answer({
                roundId: 130,
                answer: 1.00794187e8,
                startedAt: 1713307907,
                updatedAtLag: 0,
                answeredInRound: 130
            }),
            8
        );

        oEzEthToEthOracle = new OrigamiRenzoEthToEthOracle(
            origamiMultisig,
            IOrigamiOracle.BaseOracleParams(
                "ezETH/ETH",
                address(ezEthToken),
                18,
                address(0),
                18
            ),
            address(redstoneEzEthToEthOracle),
            stalenessThreshold,
            validPriceDiffBps,
            address(renzoRestakeManager)
        );
    }
}

contract OrigamiRenzoEthToEthOracleTestAdmin is OrigamiRenzoEthToEthOracleTestBase {
    event MaxRelativeToleranceBpsSet(uint256 bps);

    function test_initialization() public {
        assertEq(address(oEzEthToEthOracle.spotPriceOracle()), address(redstoneEzEthToEthOracle));
        assertEq(oEzEthToEthOracle.spotPriceStalenessThreshold(), stalenessThreshold);
        assertEq(oEzEthToEthOracle.spotPricePrecisionScalar(), 1e10);
        assertEq(oEzEthToEthOracle.spotPricePrecisionScaleDown(), false);
        assertEq(oEzEthToEthOracle.maxRelativeToleranceBps(), validPriceDiffBps);
        assertEq(address(oEzEthToEthOracle.renzoRestakeManager()), address(renzoRestakeManager));
    }

    function test_setMaxRelativeToleranceBps_failTooMuch() public {
        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        oEzEthToEthOracle.setMaxRelativeToleranceBps(10_001);
    }

    function test_setMaxRelativeToleranceBps_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(oEzEthToEthOracle));
        emit MaxRelativeToleranceBpsSet(999);
        oEzEthToEthOracle.setMaxRelativeToleranceBps(999);
        assertEq(oEzEthToEthOracle.maxRelativeToleranceBps(), 999);
    }
}

contract OrigamiRenzoEthToEthOracleTestAccess is OrigamiRenzoEthToEthOracleTestBase {
    function test_setMaxRelativeToleranceBps_access() public {
        expectElevatedAccess();
        oEzEthToEthOracle.setMaxRelativeToleranceBps(999);
    }
}

contract OrigamiRenzoEthToEthOracleTestPrice is OrigamiRenzoEthToEthOracleTestBase {
    function test_latestPrice_spot_underThreshold() public {
        assertEq(
            oEzEthToEthOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            1.00794187e18
        );
    }

    function test_latestPrice_spot_overThreshold_premium() public {
        uint256 expectedRefPrice = 1.008187158771784608e18;
        uint256 oraclePrice = expectedRefPrice * 1.01e18 / 1e18;
        vm.mockCall(
            address(redstoneEzEthToEthOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(0, oraclePrice / 1e10 + 1, block.timestamp, block.timestamp, 0)
        );
        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.AboveMaxValidRange.selector, address(redstoneEzEthToEthOracle), 1.01826904e18, expectedRefPrice));
        oEzEthToEthOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP);
    }

    function test_latestPrice_spot_atThreshold_premium() public {
        uint256 expectedRefPrice = 1.008187158771784608e18;
        uint256 oraclePrice = expectedRefPrice * 1.01e18 / 1e18;
        vm.mockCall(
            address(redstoneEzEthToEthOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(0, oraclePrice / 1e10, block.timestamp, block.timestamp, 0)
        );
        assertEq(
            oEzEthToEthOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP),
            1.01826903e18
        );
    }

    function test_latestPrice_spot_overThreshold_discount() public {
        uint256 expectedRefPrice = 1.008187158771784608e18;
        uint256 oraclePrice = expectedRefPrice * 0.99e18 / 1e18;
        vm.mockCall(
            address(redstoneEzEthToEthOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(0, oraclePrice / 1e10, block.timestamp, block.timestamp, 0)
        );
        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.AboveMaxValidRange.selector, address(redstoneEzEthToEthOracle), 0.99810528e18, expectedRefPrice));
        oEzEthToEthOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP);
    }

    function test_latestPrice_spot_atThreshold_discount() public {
        uint256 expectedRefPrice = 1.008187158771784608e18;
        uint256 oraclePrice = expectedRefPrice * 0.99e18 / 1e18;
        vm.mockCall(
            address(redstoneEzEthToEthOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(0, oraclePrice / 1e10 + 1, block.timestamp, block.timestamp, 0)
        );
        assertEq(
            oEzEthToEthOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP),
            0.99810529e18
        );
    }

    function test_latestPrice_historic_underThreshold() public {
        assertEq(
            oEzEthToEthOracle.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            1.008187158771784608e18
        );
    }

    function test_latestPrice_historic_overThreshold() public {
        // No error on historic if over threshold
        vm.mockCall(
            address(redstoneEzEthToEthOracle),
            abi.encodeWithSelector(DummyOracle.latestRoundData.selector),
            abi.encode(0, 1.047e8, block.timestamp, block.timestamp, 0)
        );
        assertEq(
            oEzEthToEthOracle.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            1.008187158771784608e18
        );
    }
}
