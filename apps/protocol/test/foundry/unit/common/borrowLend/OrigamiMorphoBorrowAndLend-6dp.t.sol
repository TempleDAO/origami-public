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

// Testing with an 18dp collateral token (sUSDe) and 6dp borrow token (USDT)
contract OrigamiMorphoBorrowAndLend_6dp_TestBase is OrigamiTest {
    IERC20 internal usdtToken;
    IERC20 internal sUsdeToken;
    OrigamiMorphoBorrowAndLend internal borrowLend;
    DummyLovTokenSwapper swapper;

    address public posOwner = makeAddr("posOwner");

    address internal constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address internal constant MORPHO_MARKET_ORACLE = 0xE47E36457D0cF83A74AE1e45382B7A044f7abd99;
    address internal constant MORPHO_MARKET_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    uint96 internal constant MORPHO_MARKET_LLTV = 0.915e18; // 91.5%
    uint96 internal constant MAX_SAFE_LLTV = 0.75e18; // 75%

    address public constant USDT_ADDRESS = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant SUSDE_ADDRESS = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;

    function setUp() public {
        fork("mainnet", 19506752);
        vm.warp(1711311924);

        usdtToken = IERC20(USDT_ADDRESS);
        sUsdeToken = IERC20(SUSDE_ADDRESS);

        borrowLend = new OrigamiMorphoBorrowAndLend(
            origamiMultisig,
            address(sUsdeToken),
            address(usdtToken),
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
        doMint(sUsdeToken, address(borrowLend), amount);
        vm.startPrank(posOwner);
        borrowLend.supply(amount);
    }

    function supplyCapitalIntoMorpho(uint256 amount) internal {
        doMint(usdtToken, origamiMultisig, amount);
        vm.startPrank(origamiMultisig);
        IMorpho morpho = borrowLend.morpho();
        SafeERC20.forceApprove(usdtToken, address(morpho), amount);
        morpho.supply(borrowLend.getMarketParams(), amount, 0, origamiMultisig, "");
        vm.stopPrank();
    }
}

contract OrigamiMorphoBorrowAndLend_6dp_TestAdmin is OrigamiMorphoBorrowAndLend_6dp_TestBase {
    event MaxSafeLtvSet(uint256 _maxSafeLtv);
    event SwapperSet(address indexed swapper);
    event PositionOwnerSet(address indexed account);

    function test_initialization() public {
        assertEq(address(borrowLend.morpho()), MORPHO);
        assertEq(address(borrowLend.supplyToken()), address(sUsdeToken));
        assertEq(address(borrowLend.borrowToken()), address(usdtToken));
        assertEq(address(borrowLend.morphoMarketOracle()), MORPHO_MARKET_ORACLE);
        assertEq(address(borrowLend.morphoMarketIrm()), MORPHO_MARKET_IRM);
        assertEq(borrowLend.morphoMarketLltv(), MORPHO_MARKET_LLTV);
        assertEq(MorphoMarketId.unwrap(borrowLend.marketId()), hex"dc5333039bcf15f1237133f74d5806675d83d9cf19cfd4cfdd9be674842651bf");

        assertEq(borrowLend.positionOwner(), posOwner);
        assertEq(address(borrowLend.swapper()), address(swapper));

        assertEq(borrowLend.suppliedBalance(), 0);
        assertEq(borrowLend.debtBalance(), 0);
        assertEq(borrowLend.availableToWithdraw(), 0);
        assertEq(borrowLend.availableToBorrow(), 0);

        assertEq(usdtToken.allowance(address(borrowLend), address(MORPHO)), type(uint256).max);
        assertEq(sUsdeToken.allowance(address(borrowLend), address(MORPHO)), type(uint256).max);
    }

    function test_constructor_fail_badMarket() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        borrowLend = new OrigamiMorphoBorrowAndLend(
            origamiMultisig,
            address(sUsdeToken),
            address(usdtToken),
            MORPHO,
            MORPHO_MARKET_ORACLE,
            MORPHO_MARKET_IRM,
            0.99e18, // LLTV doesn't exist
            MAX_SAFE_LLTV
        );
    }

    function test_setPositionOwner_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(borrowLend));
        emit PositionOwnerSet(alice);
        borrowLend.setPositionOwner(alice);
        assertEq(borrowLend.positionOwner(), alice);
    }

    function test_recoverToken() public {
        check_recoverToken(address(borrowLend));
    }

    function test_setMaxSafeLtv_failure() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        borrowLend.setMaxSafeLtv(MORPHO_MARKET_LLTV+1);
    }

    function test_setMaxSafeLtv_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(borrowLend));
        emit MaxSafeLtvSet(0.50e18);
        borrowLend.setMaxSafeLtv(0.50e18);
        assertEq(borrowLend.maxSafeLtv(), 0.50e18);
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
        assertEq(usdtToken.allowance(address(borrowLend), alice), type(uint256).max);

        vm.expectEmit(address(borrowLend));
        emit SwapperSet(bob);
        borrowLend.setSwapper(bob);
        assertEq(address(borrowLend.swapper()), bob);
        assertEq(sUsdeToken.allowance(address(borrowLend), alice), 0);
        assertEq(sUsdeToken.allowance(address(borrowLend), bob), type(uint256).max);
        assertEq(usdtToken.allowance(address(borrowLend), alice), 0);
        assertEq(usdtToken.allowance(address(borrowLend), bob), type(uint256).max);
    }

    function test_suppliedBalance_externalSupply() public {
        uint256 amount = 50e18;
        uint256 externalSupply = 3e18;

        supply(amount);

        vm.startPrank(alice);
        doMint(sUsdeToken, address(alice), externalSupply);
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
        doMint(sUsdeToken, address(alice), donationAmount);
        sUsdeToken.approve(address(borrowLend.morpho()), donationAmount);
        borrowLend.morpho().supplyCollateral(borrowLend.getMarketParams(), donationAmount, address(borrowLend), "");

        // Cannot restrict a donation into morpho
        uint256 suppliedBalance = borrowLend.suppliedBalance();
        assertEq(suppliedBalance, amount + 3e18);
    }
}

contract OrigamiMorphoBorrowAndLend_6dp_TestAccess is OrigamiMorphoBorrowAndLend_6dp_TestBase {

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

contract OrigamiMorphoBorrowAndLend_6dp_TestViews is OrigamiMorphoBorrowAndLend_6dp_TestBase {
    function test_suppliedBalance_withDonation() public {
        assertEq(borrowLend.suppliedBalance(), 0);

        // Mint just less than the amount as a donation
        uint256 donationAmount = 5e18;
        vm.startPrank(alice);
        doMint(sUsdeToken, address(alice), donationAmount);
        sUsdeToken.approve(address(borrowLend.morpho()), donationAmount);
        borrowLend.morpho().supplyCollateral(borrowLend.getMarketParams(), donationAmount, address(borrowLend), "");

        assertEq(borrowLend.suppliedBalance(), donationAmount);

        uint256 amount = 50e18;
        supply(amount);
        assertEq(borrowLend.suppliedBalance(), amount+donationAmount);
    }

    function test_suppliedBalance_success() public {
        supplyCapitalIntoMorpho(100_000e6);
        uint256 amount = 50e18;
        supply(amount);
        borrowLend.borrow(10e6, posOwner);

        assertEq(borrowLend.suppliedBalance(), amount);

        // No yield on morpho collateral
        vm.warp(block.timestamp + 365 days);
        assertEq(borrowLend.suppliedBalance(), 50e18);

        borrowLend.withdraw(10e18, alice);
        assertEq(borrowLend.suppliedBalance(), 40e18);
    }

    function test_supplyAndDebtBalance() public {
        supplyCapitalIntoMorpho(100_000e6);
        assertEq(borrowLend.debtBalance(), 0);

        uint256 amount = 100e18;
        supply(amount);
        borrowLend.borrow(40e6, posOwner);
        assertEq(borrowLend.suppliedBalance(), 100e18);
        assertEq(borrowLend.debtBalance(), 40e6 + 1);

        vm.warp(block.timestamp + 365 days);
        assertEq(borrowLend.suppliedBalance(), 100e18);
        assertEq(borrowLend.debtBalance(), 41.111655e6);

        deal(address(usdtToken), address(borrowLend), 15e6);
        uint256 amountRepaid = borrowLend.repay(15e6);
        assertEq(amountRepaid, 15e6);
        assertEq(borrowLend.suppliedBalance(), 100e18);
        assertEq(borrowLend.debtBalance(), 26.111655e6);

        uint256 withdrawn = borrowLend.withdraw(15e18, posOwner);
        assertEq(withdrawn, 15e18);
        assertEq(borrowLend.suppliedBalance(), 85e18);
    }

    function test_availableToWithdraw() public {
        supplyCapitalIntoMorpho(100_000e6);
        assertEq(borrowLend.availableToWithdraw(), 0);

        uint256 amount = 100e18;
        supply(amount);
        borrowLend.borrow(40e6, posOwner);
        assertEq(borrowLend.availableToWithdraw(), 100e18);
    }

    function test_availableToBorrow() public {
        supplyCapitalIntoMorpho(100_000e6);
        assertEq(borrowLend.availableToBorrow(), 100_000e6);

        uint256 amount = 100e18;
        supply(amount);
        borrowLend.borrow(40e6, posOwner);
        assertEq(borrowLend.availableToBorrow(), 99_960e6);

        // The same borrow interest is added to both supply and borrow
        skip(365 days);
        assertEq(borrowLend.availableToBorrow(), 99_960e6);
    }

    function test_isSafeAlRatio() public {
        assertEq(borrowLend.isSafeAlRatio(1.333333333333333333e18), true);
        assertEq(borrowLend.isSafeAlRatio(1.333333333333333334e18), true);
        assertEq(borrowLend.isSafeAlRatio(1.333333333333333332e18), false);
    }

    function test_availableToSupply() public {
        supplyCapitalIntoMorpho(100_000e6);
        (
            uint256 supplyCap,
            uint256 available
        ) = borrowLend.availableToSupply();

        assertEq(supplyCap, type(uint256).max);
        assertEq(available, type(uint256).max);

        uint256 amount = 100e18;
        supply(amount);
        borrowLend.borrow(40e6, posOwner);

        (
            supplyCap,
            available
        ) = borrowLend.availableToSupply();

        assertEq(supplyCap, type(uint256).max);
        assertEq(available, type(uint256).max);
    }

    function test_getMarketParams() public {
        MorphoMarketParams memory params = borrowLend.getMarketParams();
        assertEq(params.loanToken, address(usdtToken));
        assertEq(params.collateralToken, address(sUsdeToken));
        assertEq(params.oracle, MORPHO_MARKET_ORACLE);
        assertEq(params.irm, MORPHO_MARKET_IRM);
        assertEq(params.lltv, MORPHO_MARKET_LLTV);
    }

    function test_debtAccountData() public {
        supplyCapitalIntoMorpho(100_000e6);

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
            assertEq(collateralPrice, 1.037333213873469905888859e24);
            assertEq(borrowed, 0);
            assertEq(maxBorrow, 0);
            assertEq(currentLtv, 0);
            assertEq(healthFactor, type(uint256).max);
        }

        uint256 amount = 100e18;
        supply(amount);
        borrowLend.borrow(40e6, posOwner);
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
            assertEq(collateralPrice, 1.037333213873469905888859e24);
            assertEq(borrowed, 41.111655e6);
            assertEq(maxBorrow, 94.915988e6);
            assertEq(currentLtv, 0.396320628739920513e18);
            assertEq(healthFactor, 2.308736731712698017e18);
        }
    }
}

contract OrigamiMorphoBorrowAndLend_6dp_TestSupply is OrigamiMorphoBorrowAndLend_6dp_TestBase {
    function test_supply_fail() public {
        uint256 amount = 50e18;
        doMint(sUsdeToken, address(borrowLend), amount);
        vm.startPrank(posOwner);
        vm.expectRevert(bytes(MorphoErrors.TRANSFER_FROM_REVERTED));
        borrowLend.supply(amount+1);
    }

    function test_supply_success() public {
        uint256 amount = 50e18;
        doMint(sUsdeToken, address(borrowLend), amount);
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
        borrowLend.borrow(60e6, alice);
    }

    function test_borrow_success() public {
        supplyCapitalIntoMorpho(100_000e6);
        uint256 amount = 100e18;
        supply(amount);

        borrowLend.borrow(50e6, alice);
        assertEq(borrowLend.suppliedBalance(), amount);
        assertEq(borrowLend.debtBalance(), 50e6+1);
        assertEq(sUsdeToken.balanceOf(address(posOwner)), 0);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
        assertEq(sUsdeToken.balanceOf(address(alice)), 0);
        assertEq(usdtToken.balanceOf(address(posOwner)), 0);
        assertEq(usdtToken.balanceOf(address(borrowLend)), 0);
        assertEq(usdtToken.balanceOf(address(alice)), 50e6);
    }

    function test_repay_fail() public {
        supplyCapitalIntoMorpho(100_000e6);
        uint256 amount = 100e18;
        supply(amount);
        borrowLend.borrow(50e6, alice);

        deal(address(usdtToken), address(borrowLend), 1e6);
        vm.expectRevert(bytes(MorphoErrors.TRANSFER_FROM_REVERTED));
        borrowLend.repay(10e6);
    }

    function test_repay_success() public {
        supplyCapitalIntoMorpho(100_000e6);
        uint256 supplyAmount = 100e18;
        supply(supplyAmount);
        uint256 borrowAmount = 50e6;
        borrowLend.borrow(borrowAmount, alice);

        deal(address(usdtToken), address(borrowLend), 10e6);
        uint256 amountRepaid = borrowLend.repay(10e6);
        assertEq(amountRepaid, 10e6);
        assertEq(borrowLend.suppliedBalance(), supplyAmount);
        assertEq(borrowLend.debtBalance(), 40e6+1);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
        assertEq(sUsdeToken.balanceOf(address(alice)), 0);
        assertEq(usdtToken.balanceOf(address(borrowLend)), 0);
        assertEq(usdtToken.balanceOf(address(alice)), 50e6);

        deal(address(usdtToken), address(borrowLend), 100e6);
        amountRepaid = borrowLend.repay(100e6);
        assertEq(amountRepaid, 40e6+1);
        assertEq(borrowLend.suppliedBalance(), supplyAmount);
        assertEq(borrowLend.debtBalance(), 0);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
        assertEq(sUsdeToken.balanceOf(address(alice)), 0);
        assertEq(usdtToken.balanceOf(address(borrowLend)), 60e6-1);
        assertEq(usdtToken.balanceOf(address(alice)), 50e6);

        amountRepaid = borrowLend.repay(100e6);
        assertEq(amountRepaid, 0);
        assertEq(borrowLend.suppliedBalance(), supplyAmount);
        assertEq(borrowLend.debtBalance(), 0);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
        assertEq(sUsdeToken.balanceOf(address(alice)), 0);
        assertEq(usdtToken.balanceOf(address(borrowLend)), 60e6-1);
        assertEq(usdtToken.balanceOf(address(alice)), 50e6);

        vm.startPrank(origamiMultisig);
        borrowLend.recoverToken(address(usdtToken), alice, 60e6-1);
        assertEq(usdtToken.balanceOf(address(borrowLend)), 0);
        assertEq(usdtToken.balanceOf(address(alice)), 110e6-1);
    }

    function test_supplyAndBorrow_success() public {
        supplyCapitalIntoMorpho(100_000e6);
        uint256 supplyAmount = 100e18;
        uint256 borrowAmount = 50e6;
        doMint(sUsdeToken, address(borrowLend), supplyAmount);
        vm.startPrank(posOwner);
        borrowLend.supplyAndBorrow(supplyAmount, borrowAmount, alice);

        assertEq(borrowLend.suppliedBalance(), supplyAmount);
        assertEq(borrowLend.debtBalance(), borrowAmount+1);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
        assertEq(sUsdeToken.balanceOf(address(alice)), 0);
        assertEq(usdtToken.balanceOf(address(borrowLend)), 0);
        assertEq(usdtToken.balanceOf(address(alice)), borrowAmount);
    }

    function test_repayAndWithdraw_success() public {
        supplyCapitalIntoMorpho(100_000e6);
        uint256 supplyAmount = 100e18;
        uint256 borrowAmount = 50e6;
        doMint(sUsdeToken, address(borrowLend), supplyAmount);
        vm.startPrank(posOwner);
        borrowLend.supplyAndBorrow(supplyAmount, borrowAmount, alice);

        deal(address(usdtToken), address(borrowLend), 25e6);
        (uint256 debtRepaidAmount, uint256 withdrawnAmount) = borrowLend.repayAndWithdraw(25e6, 25e18, alice);
        assertEq(debtRepaidAmount, 25e6);
        assertEq(withdrawnAmount, 25e18);

        assertEq(borrowLend.suppliedBalance(), 75e18);
        assertEq(borrowLend.debtBalance(), 25e6+1);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
        assertEq(sUsdeToken.balanceOf(address(alice)), 25e18);
        assertEq(usdtToken.balanceOf(address(borrowLend)), 0);
        assertEq(usdtToken.balanceOf(address(alice)), 50e6);
    }
}

contract OrigamiMorphoBorrowAndLend_6dp_TestIncreaseLeverage is OrigamiMorphoBorrowAndLend_6dp_TestBase {
    function test_increaseLeverage_fail_notEnoughCollateral() public {
        supplyCapitalIntoMorpho(100_000e6);
        uint256 supplyAmount = 10e18;
        supply(supplyAmount);

        vm.startPrank(posOwner);
        vm.expectRevert(bytes(MorphoErrors.INSUFFICIENT_COLLATERAL));
        borrowLend.increaseLeverage(50e18, 50e18, "", 0);
    }

    function test_increaseLeverage_fail_noSwapper() public {
        supplyCapitalIntoMorpho(100_000e6);
        uint256 supplyAmount = 65e18;
        supply(supplyAmount);

        vm.startPrank(posOwner);
        vm.expectRevert();
        borrowLend.increaseLeverage(50e18, 50e18, "", 0);
    }

    function test_increaseLeverage_fail_slippage() public {
        supplyCapitalIntoMorpho(100_000e6);
        uint256 supplyAmount = 65e18;
        supply(supplyAmount);

        // Simulate the swapper not giving enough
        doMint(sUsdeToken, address(swapper), 100e18);
        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: 49e18
        });

        vm.startPrank(posOwner);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, 50e18, 49e18));
        borrowLend.increaseLeverage(50e18, 50e6, abi.encode(swapData), 0);
    }

    function test_increaseLeverage_success_withSurplus() public {
        supplyCapitalIntoMorpho(100_000e6);
        uint256 supplyAmount = 65e18;
        supply(supplyAmount);

        // sUSDe -> DAI = 1.05
        doMint(sUsdeToken, address(swapper), 100e18);
        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: 52.5e18
        });

        vm.startPrank(posOwner);
        borrowLend.increaseLeverage(50e18, 50e6, abi.encode(swapData), 100e18);

        assertEq(borrowLend.suppliedBalance(), 65e18 + 50e18);
        assertEq(borrowLend.debtBalance(), 50e6+1);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 2.5e18); // surplus
        assertEq(sUsdeToken.balanceOf(address(swapper)), 47.5e18);
        assertEq(usdtToken.balanceOf(address(borrowLend)), 0);
        assertEq(usdtToken.balanceOf(address(swapper)), 50e6);
    }

    function test_increaseLeverage_success_surplusSuppiled() public {
        supplyCapitalIntoMorpho(100_000e6);
        uint256 supplyAmount = 65e18;
        supply(supplyAmount);

        // sUSDe -> DAI = 1.05
        doMint(sUsdeToken, address(swapper), 100e18);
        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: 52.5e18
        });

        vm.startPrank(posOwner);
        borrowLend.increaseLeverage(50e18, 50e6, abi.encode(swapData), 2e18);

        assertEq(borrowLend.suppliedBalance(), 65e18 + 52.5e18);
        assertEq(borrowLend.debtBalance(), 50e6+1);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
        assertEq(sUsdeToken.balanceOf(address(swapper)), 47.5e18);
        assertEq(usdtToken.balanceOf(address(borrowLend)), 0);
        assertEq(usdtToken.balanceOf(address(swapper)), 50e6);
    }
}

contract OrigamiMorphoBorrowAndLend_6dp_TestDecreaseLeverage is OrigamiMorphoBorrowAndLend_6dp_TestBase {
    function increaseLeverage() internal {
        supplyCapitalIntoMorpho(100_000e6);
        uint256 supplyAmount = 130e18;
        supply(supplyAmount);

        // Simulate the swapper not giving enough
        doMint(sUsdeToken, address(swapper), 500e18);
        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: 500e18
        });

        vm.startPrank(posOwner);
        borrowLend.increaseLeverage(500e18, 500e6, abi.encode(swapData), 0);

        assertEq(borrowLend.suppliedBalance(), 630e18);
        assertEq(borrowLend.debtBalance(), 500e6+1);
    }

    function test_decreaseLeverage_fail_slippage() public {
        increaseLeverage();

        // Simulate the swapper not giving enough
        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: 99e6
        });

        vm.startPrank(posOwner);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, 100e6, 99e6));
        borrowLend.decreaseLeverage(100e6, 100e18, abi.encode(swapData), 0);
    }

    function test_decreaseLeverage_success_withSurplus() public {
        increaseLeverage();
        
        // sUSDe -> DAI = 1.025
        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: 102.5e6
        });

        vm.startPrank(posOwner);
        borrowLend.decreaseLeverage(100e6, 100e18, abi.encode(swapData), 100e6);

        assertEq(borrowLend.suppliedBalance(), 530e18);
        assertEq(borrowLend.debtBalance(), 400e6+1);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
        assertEq(sUsdeToken.balanceOf(address(swapper)), 100e18);
        assertEq(usdtToken.balanceOf(address(borrowLend)), 2.5e6);
        assertEq(usdtToken.balanceOf(address(swapper)), 397.5e6);
    }

    function test_decreaseLeverage_success_surplusRepaid() public {
        increaseLeverage();
        
        // sUSDe -> DAI = 1.025
        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: 102.5e6
        });

        vm.startPrank(posOwner);
        borrowLend.decreaseLeverage(100e6, 100e18, abi.encode(swapData), 2e6);

        assertEq(borrowLend.suppliedBalance(), 530e18);
        assertEq(borrowLend.debtBalance(), 397.5e6+1);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
        assertEq(sUsdeToken.balanceOf(address(swapper)), 100e18);
        assertEq(usdtToken.balanceOf(address(borrowLend)), 0);
        assertEq(usdtToken.balanceOf(address(swapper)), 397.5e6);
    }
}