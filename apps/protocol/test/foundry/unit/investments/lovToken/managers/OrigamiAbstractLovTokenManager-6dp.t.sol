pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OrigamiLovTokenTestBase_6dp } from "test/foundry/unit/investments/lovToken/OrigamiLovTokenBase-6dp.t.sol";

import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";
import { IOrigamiManagerPausable } from "contracts/interfaces/investments/util/IOrigamiManagerPausable.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { Range } from "contracts/libraries/Range.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

contract OrigamiAbstractLovTokenManagerTestAdmin_6dp is OrigamiLovTokenTestBase_6dp {
    event FeeConfigSet(uint16 maxExitFeeBps, uint16 minExitFeeBps, uint24 feeLeverageFactor);
    event UserALRangeSet(uint128 floor, uint128 ceiling);
    event RebalanceALRangeSet(uint128 floor, uint128 ceiling);

    function test_initialization() public {
        assertEq(manager.owner(), origamiMultisig);
        assertEq(address(manager.lovToken()), address(lovToken));
        (uint64 minDepositFeeBps, uint64 minExitFeeBps, uint64 feeLeverageFactor) = manager.getFeeConfig();
        assertEq(minDepositFeeBps, MIN_DEPOSIT_FEE_BPS);
        assertEq(minExitFeeBps, MIN_EXIT_FEE_BPS);
        assertEq(feeLeverageFactor, FEE_LEVERAGE_FACTOR);
        assertEq(manager.reserveToken(), address(sUsdcToken));

        (uint128 floor, uint128 ceiling) = manager.userALRange();
        assertEq(floor, 1.001e18);
        assertEq(ceiling, type(uint128).max);

        (floor, ceiling) = manager.rebalanceALRange();
        assertEq(floor, 1.05e18);
        assertEq(ceiling, 1.15e18);

        assertEq(manager.areInvestmentsPaused(), false);
        assertEq(manager.areExitsPaused(), false);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        assertEq(manager.reservesBalance(), 0);
        assertEq(manager.assetToLiabilityRatio(), type(uint128).max);
        assertEq(manager.effectiveExposure(IOrigamiOracle.PriceType.SPOT_PRICE), type(uint128).max);
        assertEq(manager.effectiveExposure(IOrigamiOracle.PriceType.HISTORIC_PRICE), type(uint128).max);
        assertEq(manager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
    }

    function test_setFeeConfig_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        manager.setFeeConfig(10, 10_000 + 1, 15);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        manager.setFeeConfig(10_000 + 1, 10, 15);
    }

    function test_setFeeConfig_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit FeeConfigSet(10, 80, 15e4);
        manager.setFeeConfig(10, 80, 15e4);

        (uint64 minDepositFeeBps, uint64 minExitFeeBps, uint64 feeLeverageFactor) = manager.getFeeConfig();
        assertEq(minDepositFeeBps, 10);
        assertEq(minExitFeeBps, 80);
        assertEq(feeLeverageFactor, 15e4);
    }

    function test_setUserALRange_fail_floor() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(Range.InvalidRange.selector, 1e18, 2e18));
        manager.setUserALRange(1e18, 2e18);
    }

    function test_setUserALRange_fail_order() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(Range.InvalidRange.selector, 2e18, 1e18));
        manager.setUserALRange(2e18, 1e18);
    }

    function test_setUserALRange_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit UserALRangeSet(1.01e18, 50e18);
        manager.setUserALRange(1.01e18, 50e18);

        (uint128 floor, uint128 ceiling) = manager.userALRange();
        assertEq(floor, 1.01e18);
        assertEq(ceiling, 50e18);
    }

    function test_setRebalanceALRange_fail_floor() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(Range.InvalidRange.selector, 1e18, 2e18));
        manager.setRebalanceALRange(1e18, 2e18);
    }

    function test_setRebalanceALRange_fail_order() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(Range.InvalidRange.selector, 2e18, 1e18));
        manager.setRebalanceALRange(2e18, 1e18);
    }

    function test_setRebalanceALRange_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit RebalanceALRangeSet(1.01e18, 50e18);
        manager.setRebalanceALRange(1.01e18, 50e18);

        (uint128 floor, uint128 ceiling) = manager.rebalanceALRange();
        assertEq(floor, 1.01e18);
        assertEq(ceiling, 50e18);
    }

    function test_paused() public {
        assertEq(manager.areInvestmentsPaused(), false);
        assertEq(manager.areExitsPaused(), false);

        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(true, false));
        assertEq(manager.areInvestmentsPaused(), true);
        assertEq(manager.areExitsPaused(), false);

        manager.setPaused(IOrigamiManagerPausable.Paused(false, true));
        assertEq(manager.areInvestmentsPaused(), false);
        assertEq(manager.areExitsPaused(), true);
    }
}

contract OrigamiAbstractLovTokenManagerTestAccess_6dp is OrigamiLovTokenTestBase_6dp {
    function test_access_setFeeConfig() public {
        expectElevatedAccess();
        manager.setFeeConfig(123, 123, 123);
    }

    function test_access_setUserALRange() public {
        expectElevatedAccess();
        manager.setUserALRange(2e18, 3e18);
    }

    function test_access_setRebalanceALRange() public {
        expectElevatedAccess();
        manager.setRebalanceALRange(2e18, 3e18);
    }

    function test_access_investWithToken() public {
        IOrigamiInvestment.InvestQuoteData memory quote;
        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        manager.investWithToken(alice, quote);

        vm.prank(address(lovToken));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(0)));
        manager.investWithToken(alice, quote);
    }

    function test_access_exitToToken() public {
        IOrigamiInvestment.ExitQuoteData memory quote;
        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        manager.exitToToken(alice, quote, alice);

        vm.prank(address(lovToken));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(0)));
        manager.exitToToken(alice, quote, alice);
    }
}

contract OrigamiAbstractLovTokenManagerTestViews_6dp is OrigamiLovTokenTestBase_6dp {
    using OrigamiMath for uint256;

    function investWithSUsdc(uint256 sUsdcAmount, address to) internal override returns (uint256 sharesAmount) {
        mintSUsdc(sUsdcAmount, address(manager));
        vm.startPrank(address(lovToken));

        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = manager.investQuote(
            sUsdcAmount,
            address(sUsdcToken),
            0,
            0
        );

        return manager.investWithToken(to, quoteData);
    }

    function test_sharesToReserves() public {
        // No supply
        assertEq(manager.sharesToReserves(5e18, IOrigamiOracle.PriceType.SPOT_PRICE), 5e6);
        assertEq(manager.sharesToReserves(5e18, IOrigamiOracle.PriceType.HISTORIC_PRICE), 5e6);

        // With supply, no reserves
        uint256 totalSupply = 20e18;
        _setTotalSupply(totalSupply);
        assertEq(manager.sharesToReserves(5e18, IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.sharesToReserves(5e18, IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);

        // With supply, half reserves
        _setTotalSupply(0);
        investWithSUsdc(10e6, alice);
        _setTotalSupply(totalSupply);
        assertEq(manager.sharesToReserves(5e18, IOrigamiOracle.PriceType.SPOT_PRICE), 5e6 / 2);
        assertEq(manager.sharesToReserves(5e18, IOrigamiOracle.PriceType.HISTORIC_PRICE), 5e6 / 2);

        // With supply, equal reserves
        investWithSUsdc(10e6, alice);
        assertEq(manager.sharesToReserves(5e18, IOrigamiOracle.PriceType.SPOT_PRICE), 5e6);
        assertEq(manager.sharesToReserves(5e18, IOrigamiOracle.PriceType.HISTORIC_PRICE), 5e6);

        // After rebalance
        doRebalanceDown(1.11e18);

        {
            uint256 _expectedReserves = 201.818182e6;
            uint256 _expectedLiabilities = 181.818182e6;
            assertEq(manager.reservesBalance(), _expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), _expectedLiabilities);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), _expectedLiabilities);
            assertEq(manager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), (
                _expectedReserves - _expectedLiabilities
            ));
            assertEq(manager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), (
                _expectedReserves - _expectedLiabilities
            ));
            assertEq(manager.sharesToReserves(5e18, IOrigamiOracle.PriceType.SPOT_PRICE), 5e6);
            assertEq(manager.sharesToReserves(5e18, IOrigamiOracle.PriceType.HISTORIC_PRICE), 5e6);
        }
    }

    function _setTotalSupply(uint256 amount) internal {
        vm.mockCall(
            address(lovToken),
            abi.encodeWithSelector(IERC20.totalSupply.selector),
            abi.encode(amount)
        );
    }

    function test_reservesToShares() public {
        // No supply
        assertEq(manager.reservesToShares(5e6, IOrigamiOracle.PriceType.SPOT_PRICE), 5e18);
        assertEq(manager.reservesToShares(5e6, IOrigamiOracle.PriceType.HISTORIC_PRICE), 5e18);

        // With supply, no reserves
        uint256 totalSupply = 20e18;
        _setTotalSupply(totalSupply);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.NoAvailableReserves.selector));
        assertEq(manager.reservesToShares(5e6, IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.NoAvailableReserves.selector));
        assertEq(manager.reservesToShares(5e6, IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);

        // With supply, half reserves
        {
            _setTotalSupply(0);
            investWithSUsdc(10e6, alice);
            _setTotalSupply(totalSupply);
        }
        assertEq(manager.reservesToShares(5e6, IOrigamiOracle.PriceType.SPOT_PRICE), 5e18 * 2);
        assertEq(manager.reservesToShares(5e6, IOrigamiOracle.PriceType.HISTORIC_PRICE), 5e18 * 2);

        // With supply, equal reserves
        investWithSUsdc(10e6, alice);
        assertEq(manager.reservesToShares(5e6, IOrigamiOracle.PriceType.SPOT_PRICE), 5e18);
        assertEq(manager.reservesToShares(5e6, IOrigamiOracle.PriceType.HISTORIC_PRICE), 5e18);

        // After rebalance
        doRebalanceDown(1.11e18);

        {
            uint256 _expectedReserves = 201.818182e6;
            uint256 _expectedLiabilities = 181.818182e6;
            assertEq(manager.reservesBalance(), _expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), _expectedLiabilities);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), _expectedLiabilities);
            assertEq(manager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), (
                _expectedReserves - _expectedLiabilities
            ));                
            assertEq(manager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), (
                _expectedReserves - _expectedLiabilities
            ));
            assertEq(manager.reservesToShares(5e6, IOrigamiOracle.PriceType.SPOT_PRICE), 5e18);
            assertEq(manager.reservesToShares(5e6, IOrigamiOracle.PriceType.HISTORIC_PRICE), 5e18);
        }
    }

    function test_assetToLiabilityRatio() public {
        vm.startPrank(origamiMultisig);
        manager.setRebalanceALRange(1e18+1, type(uint128).max);
        manager.setUserALRange(1e18+1, type(uint128).max);

        // No reserves, no liabilities
        assertEq(manager.reservesBalance(), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        assertEq(manager.assetToLiabilityRatio(), type(uint128).max);

        // with reserves, no liabilities
        investWithSUsdc(10e6, alice);
        assertEq(manager.reservesBalance(), 10e6);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        assertEq(manager.assetToLiabilityRatio(), type(uint128).max);

        // with reserves and liability of 1
        mintSUsdc(1, address(this));
        sUsdcToken.approve(address(manager), 1);
        manager.rebalanceDown(1);
        assertEq(manager.reservesBalance(), 10e6 + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1);
        assertEq(manager.assetToLiabilityRatio(), 1.0000001e25);

        // Add a chunk more
        investWithSUsdc(1_000e6, alice);
        assertEq(manager.reservesBalance(), 1_000e6 + 10e6 + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1);
        assertEq(manager.assetToLiabilityRatio(), 1.010000001e27);

        doRebalanceDown(1.11e18);
        assertEq(manager.reservesBalance(), 10_191.818174e6);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 9_181.818174e6);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 9_181.818174e6);
        assertEq(manager.assetToLiabilityRatio(), 1.110000000093663366e18);
    }

    function test_assetsAndLiabilities_spot() public {
        vm.startPrank(origamiMultisig);
        manager.setRebalanceALRange(1e18+1, type(uint128).max);
        manager.setUserALRange(1e18+1, type(uint128).max);

        // No reserves, no liabilities
        (
            uint256 assets,
            uint256 liabilities,
            uint256 ratio
        ) = manager.assetsAndLiabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        assertEq(assets, 0);
        assertEq(liabilities, 0);
        assertEq(ratio, type(uint128).max);

        // with reserves, no liabilities
        investWithSUsdc(10e6, alice);
        (assets, liabilities, ratio) = manager.assetsAndLiabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        assertEq(assets, 10e6);
        assertEq(liabilities, 0);
        assertEq(ratio, type(uint128).max);

        // with reserves and liability of 1
        mintSUsdc(1, address(this));
        sUsdcToken.approve(address(manager), 1);
        manager.rebalanceDown(1);
        (assets, liabilities, ratio) = manager.assetsAndLiabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        assertEq(assets, 10e6 + 1);
        assertEq(liabilities, 1);
        assertEq(ratio, 1.0000001e25);

        // Add a chunk more
        investWithSUsdc(1_000e6, alice);
        (assets, liabilities, ratio) = manager.assetsAndLiabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        assertEq(assets, 1_000e6 + 10e6 + 1);
        assertEq(liabilities, 1);
        assertEq(ratio, 1.010000001e27);

        doRebalanceDown(1.11e18);
        (assets, liabilities, ratio) = manager.assetsAndLiabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        assertEq(assets, 10_191.818174e6);
        assertEq(liabilities, 9_181.818174e6);
        assertEq(ratio, 1.110000000093663366e18);
    }

    function test_assetsAndLiabilities_historic() public {
        vm.startPrank(origamiMultisig);
        manager.setRebalanceALRange(1e18+1, type(uint128).max);
        manager.setUserALRange(1e18+1, type(uint128).max);

        // No reserves, no liabilities
        (
            uint256 assets,
            uint256 liabilities,
            uint256 ratio
        ) = manager.assetsAndLiabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE);
        assertEq(assets, 0);
        assertEq(liabilities, 0);
        assertEq(ratio, type(uint128).max);

        // with reserves, no liabilities
        investWithSUsdc(10e6, alice);
        (assets, liabilities, ratio) = manager.assetsAndLiabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE);
        assertEq(assets, 10e6);
        assertEq(liabilities, 0);
        assertEq(ratio, type(uint128).max);

        // with reserves and liability of 1
        mintSUsdc(1, address(this));
        sUsdcToken.approve(address(manager), 1);
        manager.rebalanceDown(1);
        (assets, liabilities, ratio) = manager.assetsAndLiabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE);
        assertEq(assets, 10e6 + 1);
        assertEq(liabilities, 1);
        assertEq(ratio, 1.0000001e25);

        // Add a chunk more
        investWithSUsdc(1_000e6, alice);
        (assets, liabilities, ratio) = manager.assetsAndLiabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE);
        assertEq(assets, 1_000e6 + 10e6 + 1);
        assertEq(liabilities, 1);
        assertEq(ratio, 1.010000001e27);

        doRebalanceDown(1.11e18);
        (assets, liabilities, ratio) = manager.assetsAndLiabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE);
        assertEq(assets, 10_191.818174e6);
        assertEq(liabilities, 9_181.818174e6);
        assertEq(ratio, 1.110000000093663366e18);
    }

    function test_effectiveExposure_spot() public {
        vm.startPrank(origamiMultisig);
        manager.setRebalanceALRange(1e18+1, type(uint128).max);
        manager.setUserALRange(1e18+1, type(uint128).max);

        // No reserves, no liabilities
        assertEq(manager.reservesBalance(), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.effectiveExposure(IOrigamiOracle.PriceType.SPOT_PRICE), type(uint128).max);

        // with reserves, no liabilities
        investWithSUsdc(10e6, alice);
        assertEq(manager.reservesBalance(), 10e6);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.effectiveExposure(IOrigamiOracle.PriceType.SPOT_PRICE), 1e18);

        // with reserves and liability of 1
        mintSUsdc(1, address(this));
        sUsdcToken.approve(address(manager), 1);
        manager.rebalanceDown(1);
        assertEq(manager.reservesBalance(), 10e6 + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 1);
        assertEq(manager.effectiveExposure(IOrigamiOracle.PriceType.SPOT_PRICE), 1.0000001e18);

        // Add a chunk more so A/L > uint128.max
        investWithSUsdc(1_000e6, alice);
        assertEq(manager.reservesBalance(), 1_000e6 + 10e6 + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 1);
        assertEq(manager.effectiveExposure(IOrigamiOracle.PriceType.SPOT_PRICE), 1.000000000990099010e18);

        doRebalanceDown(1.111111111111111111e18);
        assertEq(manager.reservesBalance(), 10_099.999993e6);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 9_089.999993e6);
        assertEq(manager.effectiveExposure(IOrigamiOracle.PriceType.SPOT_PRICE), 9.999999993069306931e18);
    }

    function test_effectiveExposure_historic() public {
        vm.startPrank(origamiMultisig);
        manager.setRebalanceALRange(1e18+1, type(uint128).max);
        manager.setUserALRange(1e18+1, type(uint128).max);

        // No reserves, no liabilities
        assertEq(manager.reservesBalance(), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        assertEq(manager.effectiveExposure(IOrigamiOracle.PriceType.HISTORIC_PRICE), type(uint128).max);

        // with reserves, no liabilities
        investWithSUsdc(10e6, alice);
        assertEq(manager.reservesBalance(), 10e6);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        assertEq(manager.effectiveExposure(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1e18);

        // with reserves and liability of 1
        mintSUsdc(1, address(this));
        sUsdcToken.approve(address(manager), 1);
        manager.rebalanceDown(1);
        assertEq(manager.reservesBalance(), 10e6 + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1);
        assertEq(manager.effectiveExposure(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1.0000001e18);

        // Add a chunk more so A/L > uint128.max
        investWithSUsdc(1_000e6, alice);
        assertEq(manager.reservesBalance(), 1_000e6 + 10e6 + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1);
        assertEq(manager.effectiveExposure(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1.000000000990099010e18);

        doRebalanceDown(1.111111111111111111e18);
        assertEq(manager.reservesBalance(), 10_099.999993e6);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 9_089.999993e6);
        assertEq(manager.effectiveExposure(IOrigamiOracle.PriceType.HISTORIC_PRICE), 9.999999993069306931e18);
    }

    function test_tokenPrice() public {
        assertEq(tokenPrices.tokenPrice(address(lovToken)), 1e30);
    }
}

contract OrigamiAbstractLovTokenManagerTestInvest_6dp is OrigamiLovTokenTestBase_6dp {
    using OrigamiMath for uint256;

    function test_maxInvest() public {
        vm.startPrank(origamiMultisig);
        manager.setFeeConfig(500, 0, 15);

        bootstrapSUsdc(123_456e6);

        assertEq(manager.maxInvest(alice), 0);

        // No token supply no reserves
        assertEq(manager.reservesBalance(), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        assertEq(manager.maxInvest(address(usdcToken)), type(uint256).max);

        // with reserves, no liabilities
        investWithSUsdc(10e6, alice);
        assertEq(manager.reservesBalance(), 10e6);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        assertEq(manager.maxInvest(address(usdcToken)), type(uint256).max);

        // with reserves and liability of 1
        mintSUsdc(1, address(this));
        sUsdcToken.approve(address(manager), 1);
        manager.rebalanceDown(1);
        assertEq(manager.reservesBalance(), 10e6 + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1);
        assertEq(
            manager.maxInvest(address(usdcToken)), 
            357_296_485_269_593.164126e6 // close to type(uint128).max scaled down to 10**6
        );

        // Add a chunk more
        investWithSUsdc(1_000e6, alice);
        assertEq(manager.reservesBalance(), 1_000e6 + 10e6 + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1);
        assertEq(manager.maxInvest(address(usdcToken)), 357_296_485_271_256.066359e6);

        doRebalanceDown(1.111111111111111111e18);
        uint256 expectedReserves = 10_099.999993e6;
        uint256 expectedLiabilities = 9_089.999993e6;
        assertEq(manager.reservesBalance(), expectedReserves);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), expectedLiabilities);
        // Share price isn't accurate for full precision, so fully recalculate susdc from first principles
        uint256 expectedFreeShares = (expectedLiabilities * type(uint128).max / 1e18) - expectedReserves;
        uint256 expectedFreeAssets = expectedFreeShares.mulDiv(sUsdcToken.totalAssets(), sUsdcToken.totalSupply(), OrigamiMath.Rounding.ROUND_UP);
        assertEq(manager.maxInvest(address(usdcToken)), expectedFreeAssets);

        // Only a small amount of capacity if the user A/L is capped
        vm.startPrank(origamiMultisig);
        manager.setUserALRange(1e18+1, 1.2e18);
        assertEq(manager.maxInvest(address(usdcToken)), 848.399998e6);

        // Manually force the sUSDC maxDeposit amount to check it uses the min
        manager.setTest__MaxDepositAmt(849e6);
        assertEq(manager.maxInvest(address(usdcToken)), 848.399998e6);
        manager.setTest__MaxDepositAmt(848e6);
        assertEq(manager.maxInvest(address(usdcToken)), 848e6);
    }

    function test_investQuote_fail() public {
        uint256 slippageBps = 100;
        uint256 depositAmount = 0;

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        manager.investQuote(
            depositAmount,
            address(usdcToken),
            slippageBps,
            123
        );
    }

    function test_investQuote_success_fresh() public {
        vm.startPrank(origamiMultisig);

        bootstrapSUsdc(123_456e6);
        uint256 slippageBps = 100;
        uint256 depositAmount = 20e6;

        (IOrigamiInvestment.InvestQuoteData memory quoteData, uint256[] memory investFeeBps) = manager.investQuote(
            depositAmount,
            address(usdcToken),
            slippageBps,
            123
        );

        assertEq(quoteData.fromToken, address(usdcToken));
        assertEq(quoteData.fromTokenAmount, depositAmount);
        assertEq(quoteData.maxSlippageBps, slippageBps);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedInvestmentAmount, 19.009523762e18);
        assertEq(quoteData.minInvestmentAmount, quoteData.expectedInvestmentAmount.subtractBps(slippageBps, OrigamiMath.Rounding.ROUND_UP));
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));
        assertEq(investFeeBps.length, 1);
        assertEq(investFeeBps[0], 20);
    }

    function test_investQuote_success_afterFirstSupply() public {
        bootstrapSUsdc(123_456e6);
        uint256 slippageBps = 100;
        uint256 depositAmount = 20e6;

        investWithSUsdc(100e6, alice);
        doRebalanceDown(1.111111111111111111e18);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, uint256[] memory investFeeBps) = manager.investQuote(
            depositAmount,
            address(usdcToken),
            slippageBps,
            123
        );

        assertEq(quoteData.fromToken, address(usdcToken));
        assertEq(quoteData.fromTokenAmount, depositAmount);
        assertEq(quoteData.maxSlippageBps, slippageBps);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedInvestmentAmount, 18.971504714476e18);
        assertEq(quoteData.minInvestmentAmount, quoteData.expectedInvestmentAmount.subtractBps(slippageBps, OrigamiMath.Rounding.ROUND_UP));
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));
        assertEq(investFeeBps.length, 1);
        assertEq(investFeeBps[0], 20);
    }

    function test_investWithToken_failPaused() public {
        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(true, false));

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = manager.investQuote(
            100,
            address(sUsdcToken),
            100,
            123
        );
        vm.startPrank(address(lovToken));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.IsPaused.selector));
        manager.investWithToken(alice, quoteData);
    }

    function test_investWithToken_fail_notWhitelisted() public {
        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = manager.investQuote(
            100,
            address(sUsdcToken),
            100,
            123
        );
        vm.startPrank(address(lovToken));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        manager.investWithToken(address(lovToken), quoteData);
    }

    function test_investWithToken_fail_zero() public {
        bootstrapSUsdc(123_456e18);
        uint256 slippageBps = 100;

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = manager.investQuote(
            100,
            address(usdcToken),
            slippageBps,
            123
        );
        quoteData.fromTokenAmount = 0;

        vm.startPrank(address(lovToken));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        manager.investWithToken(alice, quoteData);
    }

    function test_investWithToken_fail_slippage() public {
        bootstrapSUsdc(123_456e18);
        uint256 slippageBps = 100;
        uint256 depositAmount = 3e18;

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = manager.investQuote(
            depositAmount,
            address(usdcToken),
            slippageBps,
            123
        );
        quoteData.minInvestmentAmount = quoteData.expectedInvestmentAmount + 1;

        doMint(usdcToken, address(manager), depositAmount);
        vm.startPrank(address(lovToken));
        
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, quoteData.expectedInvestmentAmount + 1, quoteData.expectedInvestmentAmount));
        manager.investWithToken(alice, quoteData);
    }

    function test_invesWithToken_fail_alTooHigh() public {
        bootstrapSUsdc(123_456e18);
        uint256 slippageBps = 100;
        uint256 depositAmount = 500e6;

        investWithSUsdc(100e6, alice);
        doRebalanceDown(1.111111111111111111e18);
        assertEq(lovToken.reservesPerShare(), 1.002004e6);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = manager.investQuote(
            depositAmount,
            address(usdcToken),
            slippageBps,
            123
        );

        vm.startPrank(origamiMultisig);
        manager.setUserALRange(1.1e18, 1.5e18);

        doMint(usdcToken, address(manager), depositAmount);
        vm.startPrank(address(lovToken));

        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiLovTokenManager.ALTooHigh.selector, 
            1.111111110987654321e18,
            1.640211639288653734e18,
            1.5e18
        ));
        manager.investWithToken(alice, quoteData);
    }
    
    function test_invesWithToken_fail_alLower() public {
        bootstrapSUsdc(123_456e6);
        uint256 slippageBps = 10_000;
        uint256 depositAmount = 500e6;

        investWithSUsdc(100e6, alice);
        doRebalanceDown(1.111111111111111111e18);
        assertEq(manager.assetToLiabilityRatio(), 1.111111110987654321e18);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = manager.investQuote(
            depositAmount,
            address(usdcToken),
            slippageBps,
            123
        );

        vm.startPrank(origamiMultisig);
        // Force the assets, so the A/L is too low
        manager.setTest__ForceAssets(935e6);

        doMint(usdcToken, address(manager), depositAmount);
        vm.startPrank(address(lovToken));

        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiLovTokenManager.ALTooLow.selector, 
            1.111111110987654321e18,
            1.038888887734567902e18,
            1.111111110987654321e18
        ));
        manager.investWithToken(alice, quoteData);
    }

    function test_investWithToken_success_depositToken() public {
        uint256 sUsdcPrice = bootstrapSUsdc(123_456e6);
        uint256 slippageBps = 100;
        uint256 depositAmount = 20e6;

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = manager.investQuote(
            depositAmount,
            address(usdcToken),
            slippageBps,
            123
        );

        uint256 expectedFeeBps = 20;
        uint256 expectedReservesBalance = (depositAmount * 1e6 / sUsdcPrice);
        uint256 expectedShares = OrigamiMath.subtractBps(
            expectedReservesBalance * 1e12,
            expectedFeeBps,
            OrigamiMath.Rounding.ROUND_DOWN
        );

        doMint(usdcToken, address(manager), depositAmount);
        vm.startPrank(address(lovToken));
        uint256 shares = manager.investWithToken(alice, quoteData);
        assertEq(shares, expectedShares);

        // lovToken does this itself after the manager returns
        assertEq(lovToken.totalSupply(), 0);
        assertEq(lovToken.balanceOf(alice), 0);

        assertEq(usdcToken.balanceOf(address(manager)), 0);
        assertEq(usdcToken.balanceOf(alice), 0);
        assertEq(usdcToken.balanceOf(address(lovToken)), 0);
        assertEq(manager.reservesBalance(), expectedReservesBalance);
        assertEq(sUsdcToken.balanceOf(address(manager)), manager.reservesBalance());
    }

    function test_invesWithToken_success_afterFirstSupply() public {
        bootstrapSUsdc(123_456e6);
        uint256 slippageBps = 100;
        uint256 depositAmount = 20e6;

        investWithSUsdc(100e6, alice);
        doRebalanceDown(1.111111111111111111e18);
        assertEq(lovToken.reservesPerShare(), 1.002004e6);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = manager.investQuote(
            depositAmount,
            address(usdcToken),
            slippageBps,
            123
        );

        doMint(usdcToken, address(manager), depositAmount);
        vm.startPrank(address(lovToken));
        uint256 shares = manager.investWithToken(alice, quoteData);
        uint256 expectedShares = 18.971504714476000000e18;
        assertEq(shares, expectedShares);

        // lovToken does this itself after the manager returns
        assertEq(lovToken.totalSupply(), 99.8e18);
        assertEq(lovToken.balanceOf(alice), 99.8e18);

        assertEq(usdcToken.balanceOf(address(manager)), 0);
        assertEq(usdcToken.balanceOf(alice), 0);
        assertEq(usdcToken.balanceOf(address(lovToken)), 0);

        // initial deposit 1:1 + rebalance down + new deposit
        uint256 expectedReserves = 100e6 + 900e6 + 19.047620e6;
        assertEq(manager.reservesBalance(), expectedReserves);
        assertEq(sUsdcToken.balanceOf(address(manager)), expectedReserves);
    }

}

contract OrigamiAbstractLovTokenManagerTestExit_6dp is OrigamiLovTokenTestBase_6dp {
    using OrigamiMath for uint256;

    // Not testing the mock manager implementation here - just that it passes through to the manager.
    function test_maxExit() public {
        vm.startPrank(origamiMultisig);
        manager.setFeeConfig(0, 500, 15);
        bootstrapSUsdc(123_456e6);

        assertEq(manager.maxExit(alice), 0);

        // No token supply no reserves
        assertEq(manager.reservesBalance(), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        assertEq(manager.maxExit(address(usdcToken)), 0);

        // with reserves, no liabilities. Capped at total supply (9.98e18 because of deposit fees)
        investWithSUsdc(10e6, alice);
        assertEq(manager.reservesBalance(), 10e6);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        assertEq(manager.maxExit(address(usdcToken)), 9.98e18);

        // with reserves and liability of 1. Still capped at total supply (9.98e18)
        mintSUsdc(1, address(this));
        sUsdcToken.approve(address(manager), 1);
        manager.rebalanceDown(1);
        assertEq(manager.reservesBalance(), 10e6 + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1);
        assertEq(manager.maxExit(address(usdcToken)), 9.98e18);

        // Add a chunk more so A/L > uint128.max
        investWithSUsdc(1_000e6, alice);
        assertEq(manager.reservesBalance(), 1_000e6 + 10e6 + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1);
        assertEq(lovToken.totalSupply(), 1_005.984e18);
        // max amount is still capped at the total supply
        assertEq(manager.maxExit(address(usdcToken)), 1_005.984e18);

        doRebalanceDown(1.111111111111111111e18);
        uint256 expectedReserves = 10_099.999993e6;
        uint256 expectedLiabilities = 9_089.999993e6;
        assertEq(manager.reservesBalance(), expectedReserves);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), expectedLiabilities);
        assertEq(manager.maxExit(address(usdcToken)), 1_005.984e18);

        // Set the A/L such that there's not much capacity - less
        // than the total supply
        vm.startPrank(origamiMultisig);
        manager.setUserALRange(1.05e18, 100e18);
        // This also includes on the exit fee amount
        assertEq(manager.maxExit(address(usdcToken)), 582.411789473684210526e18);

        // Manually force the sUSDC maxDeposit amount to check it uses the min
        manager.setTest__MaxRedeemAmt(556e6);
        assertEq(manager.maxExit(address(usdcToken)), 582.411789473684210526e18);
        manager.setTest__MaxRedeemAmt(100e6);
        uint256 expectedShares = 104.844606565919749869e18;
        assertEq(manager.maxExit(address(usdcToken)), expectedShares);
        // Confirm the exit fees were added
        assertEq(expectedShares * (10_000 - 500) / 10_000 + 1, manager.reservesToShares(100e6, IOrigamiOracle.PriceType.SPOT_PRICE));
    }

    function test_exitQuote_fail_zero() public {
        uint256 slippageBps = 100;
        uint256 exitAmount = 0;

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        manager.exitQuote(
            exitAmount,
            address(usdcToken),
            slippageBps,
            123
        );
    }

    function test_exitQuote_noDeposits() public {
        // No lovToken's minted yet -- sharesToReserves is zero so the quote comes back zero
        uint256 sharePrice1 = bootstrapSUsdc(123_456e6);
        uint256 slippageBps = 100;
        uint256 exitAmount = 15e18;

        (IOrigamiInvestment.ExitQuoteData memory quoteData, uint256[] memory exitFeeBps) = manager.exitQuote(
            exitAmount,
            address(usdcToken),
            slippageBps,
            123
        );

        assertEq(quoteData.investmentTokenAmount, exitAmount);
        assertEq(quoteData.toToken, address(usdcToken));
        assertEq(quoteData.maxSlippageBps, slippageBps);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedToTokenAmount, (exitAmount * sharePrice1 / 1e18).subtractBps(MIN_EXIT_FEE_BPS, OrigamiMath.Rounding.ROUND_DOWN));
        assertEq(quoteData.minToTokenAmount, quoteData.expectedToTokenAmount.subtractBps(slippageBps, OrigamiMath.Rounding.ROUND_UP));
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));

        assertEq(exitFeeBps.length, 1);
        assertEq(exitFeeBps[0], MIN_EXIT_FEE_BPS);
    }

    // Not testing the mock manager implementation here - just that it passes through to the manager.
    function test_exitQuote_success_depositAsset() public {
        bootstrapSUsdc(123_456e6);
        uint256 slippageBps = 100;
        uint256 depositAmount = 20e18;
        investWithSUsdc(depositAmount, alice);

        uint256 exitAmount = 15e18;
        (IOrigamiInvestment.ExitQuoteData memory quoteData, uint256[] memory exitFeeBps) = manager.exitQuote(
            exitAmount,
            address(usdcToken),
            slippageBps,
            123
        );

        uint256 expectedFeeBps = 50;
        uint256 expectedAmount = sUsdcToken.previewRedeem(
            lovToken.sharesToReserves(
                exitAmount.subtractBps(expectedFeeBps, OrigamiMath.Rounding.ROUND_DOWN)
            )
        );

        assertEq(quoteData.investmentTokenAmount, exitAmount);
        assertEq(quoteData.toToken, address(usdcToken));
        assertEq(quoteData.maxSlippageBps, slippageBps);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedToTokenAmount, expectedAmount);
        assertEq(quoteData.minToTokenAmount, expectedAmount.subtractBps(slippageBps, OrigamiMath.Rounding.ROUND_UP));
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));
        assertEq(exitFeeBps.length, 1);
        assertEq(exitFeeBps[0], expectedFeeBps);
    }

    function test_exitToToken_fail_paused() public {
        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(false, true));

        investWithSUsdc(100e18, alice);

        uint256 slippageBps = 100;
        uint256 exitAmount = 15e18;
        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = manager.exitQuote(
            exitAmount,
            address(sUsdcToken),
            slippageBps,
            123
        );
        vm.startPrank(address(lovToken));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.IsPaused.selector));
        manager.exitToToken(alice, quoteData, alice);
    }

    function test_exitToToken_fail_slippage() public {
        investWithSUsdc(100e18, alice);

        uint256 slippageBps = 100;
        uint256 exitAmount = 15e18;
        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = manager.exitQuote(
            exitAmount,
            address(sUsdcToken),
            slippageBps,
            123
        );
        quoteData.minToTokenAmount = quoteData.expectedToTokenAmount + 1;

        vm.startPrank(address(lovToken));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, quoteData.minToTokenAmount, quoteData.expectedToTokenAmount));
        manager.exitToToken(alice, quoteData, alice);
    }

    function test_exitToToken_fail_alTooLow() public {
        bootstrapSUsdc(123_456e6);
        investWithSUsdc(100e6, alice);
        doRebalanceDown(1.111111111111111111e18);

        uint256 slippageBps = 100;
        uint256 exitAmount = 15e18;
        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = manager.exitQuote(
            exitAmount,
            address(sUsdcToken),
            slippageBps,
            123
        );

        vm.startPrank(origamiMultisig);
        manager.setUserALRange(1.1e18, 1.5e18);
        
        vm.startPrank(address(lovToken));
        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiLovTokenManager.ALTooLow.selector, 
            1.111111110987654321e18,
            1.094494545450561616e18,
            1.1e18
        ));
        manager.exitToToken(alice, quoteData, alice);
    }

    function test_exitToToken_fail_alHigher() public {
        bootstrapSUsdc(123_456e6);
        investWithSUsdc(100e18, alice);
        doRebalanceDown(1.111111111111111111e18);
        assertEq(manager.assetToLiabilityRatio(), 1.111111111111111110e18);

        uint256 slippageBps = 100;
        uint256 exitAmount = 15e18;
        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = manager.exitQuote(
            exitAmount,
            address(sUsdcToken),
            slippageBps,
            123
        );

        vm.startPrank(origamiMultisig);
        manager.setUserALRange(1.1e18, 1.5e18);

        vm.startPrank(origamiMultisig);
        // Force the assets, so the A/L is higher than before
        manager.setTest__ForceAssets(1_001e18);

        vm.startPrank(address(lovToken));
        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiLovTokenManager.ALTooHigh.selector, 
            1.111111111111111110e18,
            1.112222222222222221e18,
            1.111111111111111110e18
        ));
        manager.exitToToken(alice, quoteData, alice);
    }

    function test_exitToToken_success_depositToken() public {
        bootstrapSUsdc(123_456e6);
        investWithSUsdc(100e6, alice);
        doRebalanceDown(1.111111111111111111e18);

        uint256 slippageBps = 100;
        uint256 exitAmount = 15e18;
        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = manager.exitQuote(
            exitAmount,
            address(usdcToken),
            slippageBps,
            123
        );

        uint256 expectedFeeBps = 50;
        uint256 expectedSUsdcAmount = lovToken.sharesToReserves(
            exitAmount.subtractBps(expectedFeeBps, OrigamiMath.Rounding.ROUND_DOWN)
        );
        uint256 expectedUsdcAmount = sUsdcToken.previewRedeem(expectedSUsdcAmount);

        vm.startPrank(address(lovToken));
        (
            uint256 toTokenAmount,
            uint256 toBurnAmount
        ) = manager.exitToToken(alice, quoteData, alice);
        assertEq(toTokenAmount, expectedUsdcAmount);
        assertEq(toBurnAmount, exitAmount);

        // lovToken does this itself after the manager returns
        assertEq(lovToken.totalSupply(), 99.8e18);
        assertEq(lovToken.balanceOf(alice), 99.8e18);

        assertEq(usdcToken.balanceOf(address(manager)), 0);
        assertEq(usdcToken.balanceOf(alice), toTokenAmount);
        assertEq(usdcToken.balanceOf(address(lovToken)), 0);
        // initial deposit 1:1 + rebalance down - exit (sUSDC)
        assertEq(manager.reservesBalance(), 100e6 + (900e6 + 1) - expectedSUsdcAmount);
        assertEq(sUsdcToken.balanceOf(address(manager)), manager.reservesBalance());
    }
}
