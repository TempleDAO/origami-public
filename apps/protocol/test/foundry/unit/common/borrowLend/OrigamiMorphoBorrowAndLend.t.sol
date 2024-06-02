pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { 
    IMorpho, 
    Id as MorphoMarketId,
    MarketParams as MorphoMarketParams
} from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";
import { ErrorsLib as MorphoErrors } from "@morpho-org/morpho-blue/src/libraries/ErrorsLib.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { stdError } from "forge-std/StdError.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiMorphoBorrowAndLend } from "contracts/common/borrowAndLend/OrigamiMorphoBorrowAndLend.sol";
import { DummyLovTokenSwapper } from "contracts/test/investments/lovToken/DummyLovTokenSwapper.sol";

contract OrigamiMorphoBorrowAndLendTestBase is OrigamiTest {
    IERC20 internal daiToken;
    IERC20 internal sUsdeToken;
    OrigamiMorphoBorrowAndLend internal borrowLend;
    DummyLovTokenSwapper swapper;

    address public posOwner = makeAddr("posOwner");

    address internal constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address internal constant MORPHO_MARKET_ORACLE = 0x5D916980D5Ae1737a8330Bf24dF812b2911Aae25;
    address internal constant MORPHO_MARKET_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    uint96 internal constant MORPHO_MARKET_LLTV = 0.77e18; // 77%
    uint96 internal constant MAX_SAFE_LLTV = 0.75e18; // 75%

    address public constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant SUSDE_ADDRESS = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;

    function setUp() public {
        fork("mainnet", 19506752);
        vm.warp(1711311924);

        daiToken = IERC20(DAI_ADDRESS);
        sUsdeToken = IERC20(SUSDE_ADDRESS);

        borrowLend = new OrigamiMorphoBorrowAndLend(
            origamiMultisig,
            address(sUsdeToken),
            address(daiToken),
            MORPHO,
            MORPHO_MARKET_ORACLE,
            MORPHO_MARKET_IRM,
            MORPHO_MARKET_LLTV,
            MAX_SAFE_LLTV
        );

        swapper = new DummyLovTokenSwapper();

        vm.startPrank(origamiMultisig);
        borrowLend.setPositionOwner(posOwner);
        borrowLend.setSwapper(address(swapper));
        vm.stopPrank();
    }

    function supply(uint256 amount) internal {
        deal(address(sUsdeToken), address(borrowLend), amount);
        vm.startPrank(posOwner);
        borrowLend.supply(amount);
    }

    function supplyCapitalIntoMorpho(uint256 amount) internal {
        deal(address(daiToken), origamiMultisig, amount);
        vm.startPrank(origamiMultisig);
        IMorpho morpho = borrowLend.morpho();
        SafeERC20.forceApprove(daiToken, address(morpho), amount);
        morpho.supply(borrowLend.getMarketParams(), amount, 0, origamiMultisig, "");
        vm.stopPrank();
    }

    function increaseLeverage() internal {
        supplyCapitalIntoMorpho(100_000e18);
        uint256 supplyAmount = 130e18;
        supply(supplyAmount);

        // Simulate the swapper not giving enough
        deal(address(sUsdeToken), address(swapper), 500e18);
        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: 500e18
        });

        vm.startPrank(posOwner);
        borrowLend.increaseLeverage(500e18, 500e18, abi.encode(swapData), 0);

        assertEq(borrowLend.suppliedBalance(), 630e18);
        assertEq(borrowLend.debtBalance(), 500e18);
    }
}

contract OrigamiMorphoBorrowAndLendTestAdmin is OrigamiMorphoBorrowAndLendTestBase {
    event MaxSafeLtvSet(uint256 _maxSafeLtv);
    event SwapperSet(address indexed swapper);
    event PositionOwnerSet(address indexed account);

    function test_initialization() public {
        assertEq(address(borrowLend.morpho()), MORPHO);
        assertEq(address(borrowLend.supplyToken()), address(sUsdeToken));
        assertEq(address(borrowLend.borrowToken()), address(daiToken));
        assertEq(address(borrowLend.morphoMarketOracle()), MORPHO_MARKET_ORACLE);
        assertEq(address(borrowLend.morphoMarketIrm()), MORPHO_MARKET_IRM);
        assertEq(borrowLend.morphoMarketLltv(), MORPHO_MARKET_LLTV);
        assertEq(MorphoMarketId.unwrap(borrowLend.marketId()), hex"42dcfb38bb98767afb6e38ccf90d59d0d3f0aa216beb3a234f12850323d17536");

        assertEq(borrowLend.positionOwner(), posOwner);
        assertEq(address(borrowLend.swapper()), address(swapper));

        assertEq(borrowLend.suppliedBalance(), 0);
        assertEq(borrowLend.debtBalance(), 0);
        assertEq(borrowLend.availableToWithdraw(), 0);
        assertEq(borrowLend.availableToBorrow(), 12);

        assertEq(daiToken.allowance(address(borrowLend), address(MORPHO)), type(uint256).max);
        assertEq(sUsdeToken.allowance(address(borrowLend), address(MORPHO)), type(uint256).max);
    }

    function test_constructor_fail() public {
        // Bad market
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        borrowLend = new OrigamiMorphoBorrowAndLend(
            origamiMultisig,
            address(sUsdeToken),
            address(daiToken),
            MORPHO,
            MORPHO_MARKET_ORACLE,
            MORPHO_MARKET_IRM,
            0.99e18, // LLTV doesn't exist
            MAX_SAFE_LLTV
        );

        // not safe maxSafeLTV
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        borrowLend = new OrigamiMorphoBorrowAndLend(
            origamiMultisig,
            address(sUsdeToken),
            address(daiToken),
            MORPHO,
            MORPHO_MARKET_ORACLE,
            MORPHO_MARKET_IRM,
            0.915e18,
            0.915e18 // not safe
        );
    }

    function test_setPositionOwner_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(borrowLend));
        emit PositionOwnerSet(alice);
        borrowLend.setPositionOwner(alice);
        assertEq(borrowLend.positionOwner(), alice);
    }

    function test_recoverToken_noDebt() public {
        deal(address(sUsdeToken), address(borrowLend), 100);
        deal(address(daiToken), address(borrowLend), 100);

        // Supply token
        vm.startPrank(origamiMultisig);
        vm.expectEmit();
        emit CommonEventsAndErrors.TokenRecovered(alice, address(sUsdeToken), 100);
        borrowLend.recoverToken(address(sUsdeToken), alice, 100);
        assertEq(sUsdeToken.balanceOf(alice), 100);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);

        // Borrow token
        vm.expectEmit();
        emit CommonEventsAndErrors.TokenRecovered(alice, address(daiToken), 100);
        borrowLend.recoverToken(address(daiToken), alice, 100);
        assertEq(daiToken.balanceOf(alice), 100);
        assertEq(daiToken.balanceOf(address(borrowLend)), 0);

        // Other random token still works
        check_recoverToken(address(borrowLend));
    }

    function test_recoverToken_withDebt_fail() public {
        increaseLeverage();

        deal(address(sUsdeToken), address(borrowLend), 100);
        deal(address(daiToken), address(borrowLend), 100);

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(sUsdeToken)));
        borrowLend.recoverToken(address(sUsdeToken), alice, 100);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(daiToken)));
        borrowLend.recoverToken(address(daiToken), alice, 100);

        // Other random token still works
        check_recoverToken(address(borrowLend));
    }

    function test_setMaxSafeLtv_failure() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        borrowLend.setMaxSafeLtv(MORPHO_MARKET_LLTV);
    }

    function test_setMaxSafeLtv_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(borrowLend));
        emit MaxSafeLtvSet(MORPHO_MARKET_LLTV-1);
        borrowLend.setMaxSafeLtv(MORPHO_MARKET_LLTV-1);
        assertEq(borrowLend.maxSafeLtv(), MORPHO_MARKET_LLTV-1);
    }

    function test_setSwapper_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        borrowLend.setSwapper(address(0));
    }

    function test_setSwapper_success() public {
        vm.startPrank(origamiMultisig);

        vm.expectEmit(address(borrowLend));
        emit SwapperSet(alice);
        borrowLend.setSwapper(alice);
        assertEq(address(borrowLend.swapper()), alice);
        assertEq(sUsdeToken.allowance(address(borrowLend), alice), type(uint256).max);
        assertEq(daiToken.allowance(address(borrowLend), alice), type(uint256).max);

        vm.expectEmit(address(borrowLend));
        emit SwapperSet(bob);
        borrowLend.setSwapper(bob);
        assertEq(address(borrowLend.swapper()), bob);
        assertEq(sUsdeToken.allowance(address(borrowLend), alice), 0);
        assertEq(sUsdeToken.allowance(address(borrowLend), bob), type(uint256).max);
        assertEq(daiToken.allowance(address(borrowLend), alice), 0);
        assertEq(daiToken.allowance(address(borrowLend), bob), type(uint256).max);
    }

    function test_suppliedBalance_externalSupply() public {
        uint256 amount = 50e18;
        uint256 externalSupply = 3e18;

        supply(amount);

        vm.startPrank(alice);
        deal(address(sUsdeToken), address(alice), externalSupply);
        sUsdeToken.approve(address(borrowLend.morpho()), externalSupply);
        borrowLend.morpho().supplyCollateral(borrowLend.getMarketParams(), externalSupply, address(alice), "");

        uint256 suppliedBalance = borrowLend.suppliedBalance();
        assertEq(suppliedBalance, amount);
    }

    function test_suppliedBalance_donation() public {
        uint256 amount = 50e18;
        uint256 donationAmount = 3e18;

        supply(amount);

        vm.startPrank(alice);
        deal(address(sUsdeToken), address(alice), donationAmount);
        sUsdeToken.approve(address(borrowLend.morpho()), donationAmount);
        borrowLend.morpho().supplyCollateral(borrowLend.getMarketParams(), donationAmount, address(borrowLend), "");

        // Cannot restrict a donation into morpho
        uint256 suppliedBalance = borrowLend.suppliedBalance();
        assertEq(suppliedBalance, amount + 3e18);
    }
}

contract OrigamiMorphoBorrowAndLendTestAccess is OrigamiMorphoBorrowAndLendTestBase {

    function test_access_setPositionOwner() public {
        expectElevatedAccess();
        borrowLend.setPositionOwner(alice);
    }

    function test_access_setMaxSafeLtv() public {
        expectElevatedAccess();
        borrowLend.setMaxSafeLtv(0.75e18);
    }

    function test_access_setSwapper() public {
        expectElevatedAccess();
        borrowLend.setSwapper(address(alice));
    }

    function test_access_supply() public {
        expectElevatedAccess();
        borrowLend.supply(5);

        vm.prank(posOwner);
        vm.expectRevert(bytes(MorphoErrors.TRANSFER_FROM_REVERTED));
        borrowLend.supply(5);

        vm.prank(origamiMultisig);
        vm.expectRevert(bytes(MorphoErrors.TRANSFER_FROM_REVERTED));
        borrowLend.supply(5);
    }

    function test_access_withdraw() public {
        expectElevatedAccess();
        borrowLend.withdraw(5, alice);

        vm.prank(posOwner);
        vm.expectRevert(stdError.arithmeticError);
        borrowLend.withdraw(5, alice);

        vm.prank(origamiMultisig);
        vm.expectRevert(stdError.arithmeticError);
        borrowLend.withdraw(5, alice);
    }

    function test_access_borrow() public {
        expectElevatedAccess();
        borrowLend.borrow(5, alice);

        vm.prank(posOwner);
        vm.expectRevert(bytes(MorphoErrors.INSUFFICIENT_COLLATERAL));
        borrowLend.borrow(5, alice);

        vm.prank(origamiMultisig);
        vm.expectRevert(bytes(MorphoErrors.INSUFFICIENT_COLLATERAL));
        borrowLend.borrow(5, alice);
    }

    function test_access_repay() public {
        expectElevatedAccess();
        borrowLend.repay(5);

        vm.prank(posOwner);
        borrowLend.repay(5);

        vm.prank(origamiMultisig);
        borrowLend.repay(5);
    }

    function test_access_repayAndWithdraw() public {
        expectElevatedAccess();
        borrowLend.repayAndWithdraw(5, 5, alice);

        vm.prank(posOwner);
        vm.expectRevert(stdError.arithmeticError);
        borrowLend.repayAndWithdraw(5, 5, alice);

        vm.prank(origamiMultisig);
        vm.expectRevert(stdError.arithmeticError);
        borrowLend.repayAndWithdraw(5, 5, alice);
    }

    function test_access_supplyAndBorrow() public {
        expectElevatedAccess();
        borrowLend.supplyAndBorrow(5, 5, alice);

        vm.prank(posOwner);
        vm.expectRevert(bytes(MorphoErrors.TRANSFER_FROM_REVERTED));
        borrowLend.supplyAndBorrow(5, 5, alice);

        vm.prank(origamiMultisig);
        vm.expectRevert(bytes(MorphoErrors.TRANSFER_FROM_REVERTED));
        borrowLend.supplyAndBorrow(5, 5, alice);
    }

    function test_access_increaseLeverage() public {
        expectElevatedAccess();
        borrowLend.increaseLeverage(5, 5, "", 0);

        vm.prank(posOwner);
        vm.expectRevert(bytes(MorphoErrors.INSUFFICIENT_COLLATERAL));
        borrowLend.increaseLeverage(5, 5, "", 0);

        vm.prank(origamiMultisig);
        vm.expectRevert(bytes(MorphoErrors.INSUFFICIENT_COLLATERAL));
        borrowLend.increaseLeverage(5, 5, "", 0);
    }

    function test_access_onMorphoSupplyCollateral() public {
        expectElevatedAccess();
        borrowLend.onMorphoSupplyCollateral(5, "");

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        borrowLend.onMorphoSupplyCollateral(5, "");
    }

    function test_access_decreaseLeverage() public {
        expectElevatedAccess();
        borrowLend.decreaseLeverage(5, 5, "", 0);

        vm.prank(posOwner);
        borrowLend.decreaseLeverage(5, 5, "", 0);

        vm.prank(origamiMultisig);
        borrowLend.decreaseLeverage(5, 5, "", 0);
    }

    function test_access_onMorphoRepay() public {
        expectElevatedAccess();
        borrowLend.onMorphoRepay(5, "");

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        borrowLend.onMorphoRepay(5, "");
    }

    function test_access_recoverToken() public {
        expectElevatedAccess();
        borrowLend.recoverToken(alice, alice, 100e18);
    }
}

contract OrigamiMorphoBorrowAndLendTestViews is OrigamiMorphoBorrowAndLendTestBase {
    function test_suppliedBalance_withDonation() public {
        assertEq(borrowLend.suppliedBalance(), 0);

        // Mint just less than the amount as a donation
        uint256 donationAmount = 5e18;
        vm.startPrank(alice);
        deal(address(sUsdeToken), address(alice), donationAmount);
        sUsdeToken.approve(address(borrowLend.morpho()), donationAmount);
        borrowLend.morpho().supplyCollateral(borrowLend.getMarketParams(), donationAmount, address(borrowLend), "");

        assertEq(borrowLend.suppliedBalance(), donationAmount);

        uint256 amount = 50e18;
        supply(amount);
        assertEq(borrowLend.suppliedBalance(), amount+donationAmount);
    }

    function test_suppliedBalance_success() public {
        supplyCapitalIntoMorpho(100_000e18);
        uint256 amount = 50e18;
        supply(amount);
        borrowLend.borrow(10e18, posOwner);

        assertEq(borrowLend.suppliedBalance(), amount);

        // No yield on morpho collateral
        vm.warp(block.timestamp + 365 days);
        assertEq(borrowLend.suppliedBalance(), 50e18);

        borrowLend.withdraw(10e18, alice);
        assertEq(borrowLend.suppliedBalance(), 40e18);
    }

    function test_supplyAndDebtBalance() public {
        supplyCapitalIntoMorpho(100_000e18);
        assertEq(borrowLend.debtBalance(), 0);

        uint256 amount = 100e18;
        supply(amount);
        borrowLend.borrow(40e18, posOwner);
        assertEq(borrowLend.suppliedBalance(), 100e18);
        assertEq(borrowLend.debtBalance(), 40e18);

        vm.warp(block.timestamp + 365 days);
        assertEq(borrowLend.suppliedBalance(), 100e18);
        assertEq(borrowLend.debtBalance(), 40.207240009739276960e18);

        deal(address(daiToken), address(borrowLend), 15e18);
        uint256 amountRepaid = borrowLend.repay(15e18);
        assertEq(amountRepaid, 15e18);
        assertEq(borrowLend.suppliedBalance(), 100e18);
        assertEq(borrowLend.debtBalance(), 25.207240009739276960e18);

        uint256 withdrawn = borrowLend.withdraw(15e18, posOwner);
        assertEq(withdrawn, 15e18);
        assertEq(borrowLend.suppliedBalance(), 85e18);
    }

    function test_availableToWithdraw() public {
        supplyCapitalIntoMorpho(100_000e18);
        assertEq(borrowLend.availableToWithdraw(), 0);

        uint256 amount = 100e18;
        supply(amount);
        borrowLend.borrow(40e18, posOwner);
        assertEq(borrowLend.availableToWithdraw(), 100e18);
    }

    function test_availableToBorrow() public {
        supplyCapitalIntoMorpho(100_000e18);
        assertEq(borrowLend.availableToBorrow(), 100_000.000000000000000012e18);

        uint256 amount = 100e18;
        supply(amount);
        borrowLend.borrow(40e18, posOwner);
        assertEq(borrowLend.availableToBorrow(), 99_960.000000000000000012e18);

        // The same borrow interest is added to both supply and borrow
        skip(365 days);
        assertEq(borrowLend.availableToBorrow(), 99_960.000000000000000012e18);
    }

    function test_isSafeAlRatio() public {
        assertEq(borrowLend.isSafeAlRatio(1.333333333333333333e18), true);
        assertEq(borrowLend.isSafeAlRatio(1.333333333333333334e18), true);
        assertEq(borrowLend.isSafeAlRatio(1.333333333333333332e18), false);
    }

    function test_availableToSupply() public {
        supplyCapitalIntoMorpho(100_000e18);
        (
            uint256 supplyCap,
            uint256 available
        ) = borrowLend.availableToSupply();

        assertEq(supplyCap, type(uint256).max);
        assertEq(available, type(uint256).max);

        uint256 amount = 100e18;
        supply(amount);
        borrowLend.borrow(40e18, posOwner);

        (
            supplyCap,
            available
        ) = borrowLend.availableToSupply();

        assertEq(supplyCap, type(uint256).max);
        assertEq(available, type(uint256).max);
    }

    function test_getMarketParams() public {
        MorphoMarketParams memory params = borrowLend.getMarketParams();
        assertEq(params.loanToken, address(daiToken));
        assertEq(params.collateralToken, address(sUsdeToken));
        assertEq(params.oracle, MORPHO_MARKET_ORACLE);
        assertEq(params.irm, MORPHO_MARKET_IRM);
        assertEq(params.lltv, MORPHO_MARKET_LLTV);
    }

    function test_debtAccountData() public {
        supplyCapitalIntoMorpho(100_000e18);

        (
            uint256 collateral,
            uint256 collateralPrice,
            uint256 borrowed,
            uint256 maxBorrow,
            uint256 currentLtv,
            uint256 healthFactor
        ) = borrowLend.debtAccountData();

        {
            assertEq(collateral, 0);
            assertEq(collateralPrice, 1.034528270492912801e36);
            assertEq(borrowed, 0);
            assertEq(maxBorrow, 0);
            assertEq(currentLtv, 0);
            assertEq(healthFactor, type(uint256).max);
        }

        uint256 amount = 100e18;
        supply(amount);
        borrowLend.borrow(40e18, posOwner);
        vm.warp(block.timestamp + 365 days);

        (
            collateral,
            collateralPrice,
            borrowed,
            maxBorrow,
            currentLtv,
            healthFactor
        ) = borrowLend.debtAccountData();

        {
            assertEq(collateral, 100e18);
            assertEq(collateralPrice, 1.034629855932056289e36);
            assertEq(borrowed, 40.207240009739276960e18);
            assertEq(maxBorrow, 79.666498906768334253e18);
            assertEq(currentLtv, 0.388614728051880901e18);
            assertEq(healthFactor, 1.981396855080601441e18);
        }
    }
}

contract OrigamiMorphoBorrowAndLendTestSupply is OrigamiMorphoBorrowAndLendTestBase {
    function test_supply_fail() public {
        uint256 amount = 50e18;
        deal(address(sUsdeToken), address(borrowLend), amount);
        vm.startPrank(posOwner);
        vm.expectRevert(bytes(MorphoErrors.TRANSFER_FROM_REVERTED));
        borrowLend.supply(amount+1);
    }

    function test_supply_success() public {
        uint256 amount = 50e18;
        deal(address(sUsdeToken), address(borrowLend), amount);
        vm.startPrank(posOwner);
        borrowLend.supply(amount);
        assertEq(borrowLend.suppliedBalance(), amount);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
    }

    function test_withdraw_fail() public {
        uint256 amount = 50e18;
        supply(amount);
        
        vm.expectRevert(stdError.arithmeticError);
        borrowLend.withdraw(amount+1, alice);
    }

    function test_withdraw_success() public {
        uint256 amount = 50e18;
        supply(amount);
        
        uint256 amountOut = borrowLend.withdraw(amount/2, alice);
        assertEq(amountOut, amount/2);
        assertEq(borrowLend.suppliedBalance(), 25e18);
        assertEq(sUsdeToken.balanceOf(address(posOwner)), 0);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
        assertEq(sUsdeToken.balanceOf(address(alice)), 25e18);

        // Withdraw it all
        amountOut = borrowLend.withdraw(type(uint256).max, alice);
        assertEq(amountOut, amount/2);
        assertEq(sUsdeToken.balanceOf(address(alice)), amount);
    }

    function test_borrow_fail() public {
        uint256 amount = 50e18;
        supply(amount);
        
        vm.expectRevert(bytes(MorphoErrors.INSUFFICIENT_COLLATERAL));
        borrowLend.borrow(60e18, alice);
    }

    function test_borrow_success() public {
        supplyCapitalIntoMorpho(100_000e18);
        uint256 amount = 100e18;
        supply(amount);

        borrowLend.borrow(50e18, alice);
        assertEq(borrowLend.suppliedBalance(), amount);
        assertEq(borrowLend.debtBalance(), 50e18);
        assertEq(sUsdeToken.balanceOf(address(posOwner)), 0);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
        assertEq(sUsdeToken.balanceOf(address(alice)), 0);
        assertEq(daiToken.balanceOf(address(posOwner)), 0);
        assertEq(daiToken.balanceOf(address(borrowLend)), 0);
        assertEq(daiToken.balanceOf(address(alice)), 50e18);
    }

    function test_repay_fail() public {
        supplyCapitalIntoMorpho(100_000e18);
        uint256 amount = 100e18;
        supply(amount);
        borrowLend.borrow(50e18, alice);

        deal(address(daiToken), address(borrowLend), 1e18);
        vm.expectRevert(bytes(MorphoErrors.TRANSFER_FROM_REVERTED));
        borrowLend.repay(10e18);
    }

    function test_repay_success() public {
        supplyCapitalIntoMorpho(100_000e18);
        uint256 supplyAmount = 100e18;
        supply(supplyAmount);
        uint256 borrowAmount = 50e18;
        borrowLend.borrow(borrowAmount, alice);

        deal(address(daiToken), address(borrowLend), 10e18);
        uint256 amountRepaid = borrowLend.repay(10e18);
        assertEq(amountRepaid, 10e18);
        assertEq(borrowLend.suppliedBalance(), supplyAmount);
        assertEq(borrowLend.debtBalance(), 40e18);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
        assertEq(sUsdeToken.balanceOf(address(alice)), 0);
        assertEq(daiToken.balanceOf(address(borrowLend)), 0);
        assertEq(daiToken.balanceOf(address(alice)), 50e18);

        deal(address(daiToken), address(borrowLend), 100e18);
        amountRepaid = borrowLend.repay(100e18);
        assertEq(amountRepaid, 40e18);
        assertEq(borrowLend.suppliedBalance(), supplyAmount);
        assertEq(borrowLend.debtBalance(), 0);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
        assertEq(sUsdeToken.balanceOf(address(alice)), 0);
        assertEq(daiToken.balanceOf(address(borrowLend)), 60e18);
        assertEq(daiToken.balanceOf(address(alice)), 50e18);

        amountRepaid = borrowLend.repay(100e18);
        assertEq(amountRepaid, 0);
        assertEq(borrowLend.suppliedBalance(), supplyAmount);
        assertEq(borrowLend.debtBalance(), 0);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
        assertEq(sUsdeToken.balanceOf(address(alice)), 0);
        assertEq(daiToken.balanceOf(address(borrowLend)), 60e18);
        assertEq(daiToken.balanceOf(address(alice)), 50e18);

        vm.startPrank(origamiMultisig);
        borrowLend.recoverToken(address(daiToken), alice, 60e18);
        assertEq(daiToken.balanceOf(address(borrowLend)), 0);
        assertEq(daiToken.balanceOf(address(alice)), 110e18);
    }

    function test_supplyAndBorrow_success() public {
        supplyCapitalIntoMorpho(100_000e18);
        uint256 supplyAmount = 100e18;
        uint256 borrowAmount = 50e18;
        deal(address(sUsdeToken), address(borrowLend), supplyAmount);
        vm.startPrank(posOwner);
        borrowLend.supplyAndBorrow(supplyAmount, borrowAmount, alice);

        assertEq(borrowLend.suppliedBalance(), supplyAmount);
        assertEq(borrowLend.debtBalance(), borrowAmount);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
        assertEq(sUsdeToken.balanceOf(address(alice)), 0);
        assertEq(daiToken.balanceOf(address(borrowLend)), 0);
        assertEq(daiToken.balanceOf(address(alice)), borrowAmount);
    }

    function test_repayAndWithdraw_success() public {
        supplyCapitalIntoMorpho(100_000e18);
        uint256 supplyAmount = 100e18;
        uint256 borrowAmount = 50e18;
        deal(address(sUsdeToken), address(borrowLend), supplyAmount);
        vm.startPrank(posOwner);
        borrowLend.supplyAndBorrow(supplyAmount, borrowAmount, alice);

        deal(address(daiToken), address(borrowLend), borrowAmount/2);
        (uint256 debtRepaidAmount, uint256 withdrawnAmount) = borrowLend.repayAndWithdraw(borrowAmount/2, borrowAmount/2, alice);
        assertEq(debtRepaidAmount, borrowAmount/2);
        assertEq(withdrawnAmount, borrowAmount/2);

        assertEq(borrowLend.suppliedBalance(), 75e18);
        assertEq(borrowLend.debtBalance(), 25e18);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
        assertEq(sUsdeToken.balanceOf(address(alice)), 25e18);
        assertEq(daiToken.balanceOf(address(borrowLend)), 0);
        assertEq(daiToken.balanceOf(address(alice)), 50e18);
    }
}

contract OrigamiMorphoBorrowAndLendTestIncreaseLeverage is OrigamiMorphoBorrowAndLendTestBase {
    function test_increaseLeverage_fail_notEnoughCollateral() public {
        supplyCapitalIntoMorpho(100_000e18);
        uint256 supplyAmount = 10e18;
        supply(supplyAmount);

        vm.startPrank(posOwner);
        vm.expectRevert(bytes(MorphoErrors.INSUFFICIENT_COLLATERAL));
        borrowLend.increaseLeverage(50e18, 50e18, "", 0);
    }

    function test_increaseLeverage_fail_noSwapper() public {
        supplyCapitalIntoMorpho(100_000e18);
        uint256 supplyAmount = 65e18;
        supply(supplyAmount);

        vm.startPrank(posOwner);
        vm.expectRevert();
        borrowLend.increaseLeverage(50e18, 50e18, "", 0);
    }

    function test_increaseLeverage_fail_slippage() public {
        supplyCapitalIntoMorpho(100_000e18);
        uint256 supplyAmount = 65e18;
        supply(supplyAmount);

        // Simulate the swapper not giving enough
        deal(address(sUsdeToken), address(swapper), 100e18);
        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: 49e18
        });

        vm.startPrank(posOwner);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, 50e18, 49e18));
        borrowLend.increaseLeverage(50e18, 50e18, abi.encode(swapData), 0);
    }

    function test_increaseLeverage_success_withSurplus() public {
        supplyCapitalIntoMorpho(100_000e18);
        uint256 supplyAmount = 65e18;
        supply(supplyAmount);

        // sUSDe -> DAI = 1.05
        deal(address(sUsdeToken), address(swapper), 100e18);
        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: 52.5e18
        });

        vm.startPrank(posOwner);
        borrowLend.increaseLeverage(50e18, 50e18, abi.encode(swapData), 100e18);

        assertEq(borrowLend.suppliedBalance(), 65e18 + 50e18);
        assertEq(borrowLend.debtBalance(), 50e18);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 2.5e18); // surplus
        assertEq(sUsdeToken.balanceOf(address(swapper)), 47.5e18);
        assertEq(daiToken.balanceOf(address(borrowLend)), 0);
        assertEq(daiToken.balanceOf(address(swapper)), 50e18);
    }

    function test_increaseLeverage_success_surplusSuppiled() public {
        supplyCapitalIntoMorpho(100_000e18);
        uint256 supplyAmount = 65e18;
        supply(supplyAmount);

        // sUSDe -> DAI = 1.05
        deal(address(sUsdeToken), address(swapper), 100e18);
        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: 52.5e18
        });

        vm.startPrank(posOwner);
        borrowLend.increaseLeverage(50e18, 50e18, abi.encode(swapData), 2e18);

        assertEq(borrowLend.suppliedBalance(), 65e18 + 52.5e18);
        assertEq(borrowLend.debtBalance(), 50e18);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
        assertEq(sUsdeToken.balanceOf(address(swapper)), 47.5e18);
        assertEq(daiToken.balanceOf(address(borrowLend)), 0);
        assertEq(daiToken.balanceOf(address(swapper)), 50e18);
    }
}

contract OrigamiMorphoBorrowAndLendTestDecreaseLeverage is OrigamiMorphoBorrowAndLendTestBase {
    function test_decreaseLeverage_fail_slippage() public {
        increaseLeverage();

        // Simulate the swapper not giving enough
        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: 99e18
        });

        vm.startPrank(posOwner);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, 100e18, 99e18));
        borrowLend.decreaseLeverage(100e18, 100e18, abi.encode(swapData), 0);
    }

    function test_decreaseLeverage_fail_withdrawMaxCollateral() public {
        increaseLeverage();

        // Simulate the swapper not giving enough
        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: 99e18
        });

        vm.startPrank(posOwner);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAmount.selector, address(sUsdeToken), type(uint256).max));
        borrowLend.decreaseLeverage(600e18, type(uint256).max, abi.encode(swapData), 0);
    }

    function test_decreaseLeverage_success_withSurplus() public {
        increaseLeverage();
        
        // sUSDe -> DAI = 1.025
        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: 102.5e18
        });

        vm.startPrank(posOwner);
        (uint256 repaid, uint256 surplusRepaid) = borrowLend.decreaseLeverage(100e18, 100e18, abi.encode(swapData), 100e18);

        assertEq(repaid, 100e18);
        assertEq(surplusRepaid, 0);
        assertEq(borrowLend.suppliedBalance(), 530e18);
        assertEq(borrowLend.debtBalance(), 400e18);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
        assertEq(sUsdeToken.balanceOf(address(swapper)), 100e18);
        assertEq(daiToken.balanceOf(address(borrowLend)), 2.5e18);
        assertEq(daiToken.balanceOf(address(swapper)), 397.5e18);
    }

    function test_decreaseLeverage_success_surplusRepaid() public {
        increaseLeverage();
        
        // sUSDe -> DAI = 1.025
        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: 102.5e18
        });

        vm.startPrank(posOwner);
        (uint256 repaid, uint256 surplusRepaid) = borrowLend.decreaseLeverage(100e18, 100e18, abi.encode(swapData), 2e18);

        assertEq(repaid, 100e18);
        assertEq(surplusRepaid, 2.5e18);
        assertEq(borrowLend.suppliedBalance(), 530e18);
        assertEq(borrowLend.debtBalance(), 397.5e18);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
        assertEq(sUsdeToken.balanceOf(address(swapper)), 100e18);
        assertEq(daiToken.balanceOf(address(borrowLend)), 0);
        assertEq(daiToken.balanceOf(address(swapper)), 397.5e18);
    }

    function test_decreaseLeverage_tooMuch_overSurplusThreshold() public {
        increaseLeverage();
        
        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: 602e18
        });
        deal(address(daiToken), address(swapper), 602e18);

        vm.startPrank(posOwner);
        (uint256 repaid, uint256 surplusRepaid) = borrowLend.decreaseLeverage(600e18, 100e18, abi.encode(swapData), 2e18);

        assertEq(repaid, 500e18);
        assertEq(surplusRepaid, 0);
        assertEq(borrowLend.suppliedBalance(), 530e18);
        assertEq(borrowLend.debtBalance(), 0);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
        assertEq(sUsdeToken.balanceOf(address(swapper)), 100e18);
        assertEq(daiToken.balanceOf(address(borrowLend)), 102e18);
        assertEq(daiToken.balanceOf(address(swapper)), 0);
    }
}