pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiStableChainlinkOracle } from "contracts/common/oracle/OrigamiStableChainlinkOracle.sol";
import { OrigamiErc4626Oracle } from "contracts/common/oracle/OrigamiErc4626Oracle.sol";
import { DummyOracle } from "contracts/test/common/DummyOracle.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { Range } from "contracts/libraries/Range.sol";
import { MockSDaiToken } from "contracts/test/external/maker/MockSDaiToken.m.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";

/* solhint-disable func-name-mixedcase, contract-name-camelcase, not-rely-on-time */
contract OrigamiErc4626OracleTest is OrigamiTest {
    DummyOracle public clUsdeUsdOracle;
    OrigamiStableChainlinkOracle public oUsdeToUsdOracle;
    OrigamiErc4626Oracle public oSUsdeToUsdOracle;
    MockSDaiToken public sUsdeToken;

    uint96 public constant VAULT_INTEREST_RATE = 0.04e18;
    uint256 public constant USDE_USD_HISTORIC_RATE = 1e18;
    uint256 public constant USDE_USD_ORACLE_RATE = 1.001640797743598e18;

    DummyMintableToken public usdEToken;

    address public constant INTERNAL_USD_ADDRESS = 0x000000000000000000000000000000000000115d;

    function setUp() public {
        vm.warp(1672531200); // 1 Jan 2023

        // 18 decimals
        clUsdeUsdOracle = new DummyOracle(
            DummyOracle.Answer({
                roundId: 1,
                answer: int256(USDE_USD_ORACLE_RATE),
                startedAt: 0,
                updatedAtLag: 0,
                answeredInRound: 1
            }),
            18
        );

        usdEToken = new DummyMintableToken(origamiMultisig, "USDe", "USDe", 18);

        sUsdeToken = new MockSDaiToken(usdEToken);
        sUsdeToken.setInterestRate(VAULT_INTEREST_RATE);

        oUsdeToUsdOracle = new OrigamiStableChainlinkOracle(
            origamiMultisig,
            IOrigamiOracle.BaseOracleParams(
                "USDe/USD",
                address(usdEToken),
                18,
                INTERNAL_USD_ADDRESS,
                18
            ),
            USDE_USD_HISTORIC_RATE,
            address(clUsdeUsdOracle),
            100 days,
            Range.Data(0.99e18, 1.01e18),
            false, // Redstone does not use roundId
            true // It does use lastUpdatedAt
        );

        oSUsdeToUsdOracle = new OrigamiErc4626Oracle(
            IOrigamiOracle.BaseOracleParams(
                "sUSDe/USD",
                address(sUsdeToken),
                18, 
                address(INTERNAL_USD_ADDRESS),
                18
            ),
            address(oUsdeToUsdOracle)
        );

        // Kick off the vault accrual
        {
            vm.startPrank(overlord);
            deal(address(usdEToken), overlord, 10_000e18);
            usdEToken.approve(address(sUsdeToken), 10_000e18);
            sUsdeToken.deposit(10_000e18, overlord);

            // Skip forward in time so sUSDe:USDe increases
            skip(400 days);
        }
    }

    function test_latestPrice_spot_roundDown() public {
        uint256 ratio = sUsdeToken.convertToAssets(1e18);
        uint256 expectedRate = 1.045548339562495446e18;
        assertEq(expectedRate, ratio * USDE_USD_ORACLE_RATE / 1e18);

        assertEq(
            oSUsdeToUsdOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            expectedRate
        );
        assertEq(
            oSUsdeToUsdOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            expectedRate + 1
        );

        vm.warp(block.timestamp + 365 days);
        ratio = sUsdeToken.convertToAssets(1e18);
        expectedRate = 1.085613971472239366e18;
        assertEq(expectedRate, ratio * USDE_USD_ORACLE_RATE / 1e18);

        assertEq(
            oSUsdeToUsdOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            expectedRate
        );
        assertEq(
            oSUsdeToUsdOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            expectedRate + 1
        );
    }

    function test_latestPrice_historic() public {
        uint256 ratio = sUsdeToken.convertToAssets(1e18);
        uint256 expectedRate = 1.043835616438356164e18;
        assertEq(expectedRate, ratio * USDE_USD_HISTORIC_RATE / 1e18);

        assertEq(
            oSUsdeToUsdOracle.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            expectedRate
        );
        assertEq(
            oSUsdeToUsdOracle.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            expectedRate
        );

        vm.warp(block.timestamp + 365 days);
        ratio = sUsdeToken.convertToAssets(1e18);
        expectedRate = 1.083835616438356164e18;
        assertEq(expectedRate, ratio * USDE_USD_HISTORIC_RATE / 1e18);

        assertEq(
            oSUsdeToUsdOracle.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            expectedRate
        );
        assertEq(
            oSUsdeToUsdOracle.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            expectedRate
        );
    }

    function test_latestPrices() public {
        (uint256 spot, uint256 hist, address baseAsset, address quoteAsset) = oSUsdeToUsdOracle.latestPrices(
            IOrigamiOracle.PriceType.SPOT_PRICE, 
            OrigamiMath.Rounding.ROUND_UP,
            IOrigamiOracle.PriceType.HISTORIC_PRICE, 
            OrigamiMath.Rounding.ROUND_DOWN
        );
        // Based off the sUSDe/USDe price, so includes the sUSDe/USDe ratio
        assertEq(spot, 1.045548339562495447e18);
        assertEq(hist, 1.043835616438356164e18);
        assertEq(baseAsset, address(sUsdeToken));
        assertEq(quoteAsset, INTERNAL_USD_ADDRESS);
    }
}

contract OrigamiErc4626OracleNoQuoteAssetOracleTest is OrigamiTest {
    OrigamiErc4626Oracle public oSUsdeToUsdOracle;
    MockSDaiToken public sUsdeToken;

    uint96 public constant VAULT_INTEREST_RATE = 0.04e18;

    DummyMintableToken public usdEToken;

    address public constant INTERNAL_USD_ADDRESS = 0x000000000000000000000000000000000000115d;

    function setUp() public {
        vm.warp(1672531200); // 1 Jan 2023

        usdEToken = new DummyMintableToken(origamiMultisig, "USDe", "USDe", 18);
        sUsdeToken = new MockSDaiToken(usdEToken);
        sUsdeToken.setInterestRate(VAULT_INTEREST_RATE);

        oSUsdeToUsdOracle = new OrigamiErc4626Oracle(
            IOrigamiOracle.BaseOracleParams(
                "sUSDe/USD",
                address(sUsdeToken),
                18, 
                address(INTERNAL_USD_ADDRESS),
                18
            ),
            address(0)
        );

        // Kick off the vault accrual
        {
            vm.startPrank(overlord);
            deal(address(usdEToken), overlord, 10_000e18);
            usdEToken.approve(address(sUsdeToken), 10_000e18);
            sUsdeToken.deposit(10_000e18, overlord);

            // Skip forward in time so sUSDe:USDe increases
            skip(400 days);
        }
    }

    function test_latestPrice_spot_roundDown() public {
        uint256 ratio = sUsdeToken.convertToAssets(1e18);
        uint256 expectedRate = 1.043835616438356164e18;
        assertEq(expectedRate, ratio);

        assertEq(
            oSUsdeToUsdOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            expectedRate
        );
        assertEq(
            oSUsdeToUsdOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            expectedRate
        );

        vm.warp(block.timestamp + 365 days);
        ratio = sUsdeToken.convertToAssets(1e18);
        expectedRate = 1.083835616438356164e18;
        assertEq(expectedRate, ratio);

        assertEq(
            oSUsdeToUsdOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            expectedRate
        );
        assertEq(
            oSUsdeToUsdOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            expectedRate
        );
    }

    function test_latestPrice_historic() public {
        uint256 ratio = sUsdeToken.convertToAssets(1e18);
        uint256 expectedRate = 1.043835616438356164e18;
        assertEq(expectedRate, ratio);

        assertEq(
            oSUsdeToUsdOracle.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            expectedRate
        );
        assertEq(
            oSUsdeToUsdOracle.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            expectedRate
        );

        vm.warp(block.timestamp + 365 days);
        ratio = sUsdeToken.convertToAssets(1e18);
        expectedRate = 1.083835616438356164e18;
        assertEq(expectedRate, ratio);

        assertEq(
            oSUsdeToUsdOracle.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            expectedRate
        );
        assertEq(
            oSUsdeToUsdOracle.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            expectedRate
        );
    }

    function test_latestPrices() public {
        (uint256 spot, uint256 hist, address baseAsset, address quoteAsset) = oSUsdeToUsdOracle.latestPrices(
            IOrigamiOracle.PriceType.SPOT_PRICE, 
            OrigamiMath.Rounding.ROUND_UP,
            IOrigamiOracle.PriceType.HISTORIC_PRICE, 
            OrigamiMath.Rounding.ROUND_DOWN
        );
        // Based off the sUSDe/USDe price, so includes the sUSDe/USDe ratio
        assertEq(spot, 1.043835616438356164e18);
        assertEq(hist, 1.043835616438356164e18);
        assertEq(baseAsset, address(sUsdeToken));
        assertEq(quoteAsset, INTERNAL_USD_ADDRESS);
    }
}
