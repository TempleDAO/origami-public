pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Errors as AaveErrors } from "@aave/core-v3/contracts/protocol/libraries/helpers/Errors.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiAaveV3BorrowAndLend } from "contracts/common/borrowAndLend/OrigamiAaveV3BorrowAndLend.sol";

contract OrigamiAaveV3BorrowAndLendNotMatchingDecimalsTestBase is OrigamiTest {
    IERC20 internal wbtcToken;
    IERC20 internal wstEthToken;
    OrigamiAaveV3BorrowAndLend internal borrowLend;

    address public posOwner = makeAddr("posOwner");

    address internal constant SPARK_POOL = 0xC13e21B648A5Ee794902342038FF3aDAB66BE987;
    address internal constant WBTC_ADDRESS = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant WSTETH_ADDRESS = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    address internal constant SPARK_WSTETH_A_TOKEN = 0x12B54025C112Aa61fAce2CDB7118740875A566E9;
    address internal constant SPARK_WBTC_DEBT_TOKEN = 0xf6fEe3A8aC8040C3d6d81d9A4a168516Ec9B51D2;
    uint8 internal constant SPARK_EMODE_NONE = 0;

    function setUp() public {
        fork("mainnet", 19238000);
        vm.warp(1708056616);
        wbtcToken = IERC20(WBTC_ADDRESS);
        wstEthToken = IERC20(WSTETH_ADDRESS);

        borrowLend = new OrigamiAaveV3BorrowAndLend(
            origamiMultisig,
            address(wstEthToken),
            address(wbtcToken),
            SPARK_POOL,
            SPARK_EMODE_NONE
        );

        vm.startPrank(origamiMultisig);
        borrowLend.setPositionOwner(posOwner);
        vm.stopPrank();
    }

    function supply(uint256 amount) internal {
        doMint(wstEthToken, address(borrowLend), amount);
        vm.startPrank(posOwner);
        borrowLend.supply(amount);
    }
}

contract OrigamiAaveV3BorrowAndLendNotMatchingDecimalsTestAdmin is OrigamiAaveV3BorrowAndLendNotMatchingDecimalsTestBase {
    event ReferralCodeSet(uint16 code);
    event PositionOwnerSet(address indexed account);
    event AavePoolSet(address indexed pool);

    event ReserveUsedAsCollateralEnabled(address indexed reserve, address indexed user);
    event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);

    function test_initialization() public {
        assertEq(address(borrowLend.aavePool()), SPARK_POOL);
        assertEq(address(borrowLend.aaveAToken()), SPARK_WSTETH_A_TOKEN);
        assertEq(address(borrowLend.aaveDebtToken()), SPARK_WBTC_DEBT_TOKEN);

        assertEq(borrowLend.supplyToken(), WSTETH_ADDRESS);
        assertEq(borrowLend.borrowToken(), WBTC_ADDRESS);
        assertEq(borrowLend.positionOwner(), posOwner);

        assertEq(borrowLend.referralCode(), 0);
        assertEq(borrowLend.aavePool().getUserEMode(address(borrowLend)), SPARK_EMODE_NONE);
    }

    function test_constructor_zeroEMode() public {
        borrowLend = new OrigamiAaveV3BorrowAndLend(
            origamiMultisig, 
            address(wstEthToken), 
            address(wbtcToken),
            SPARK_POOL,
            0
        );
        assertEq(borrowLend.aavePool().getUserEMode(address(borrowLend)), 0);
    }

    function test_setPositionOwner_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(borrowLend));
        emit PositionOwnerSet(alice);
        borrowLend.setPositionOwner(alice);
        assertEq(borrowLend.positionOwner(), alice);
    }

    function test_setReferralCode_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(borrowLend));
        emit ReferralCodeSet(123);
        borrowLend.setReferralCode(123);
        assertEq(borrowLend.referralCode(), 123);
    }

    function test_setUserUseReserveAsCollateral_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(bytes(AaveErrors.UNDERLYING_BALANCE_ZERO));
        borrowLend.setUserUseReserveAsCollateral(true);
    }

    function test_setUserUseReserveAsCollateral_success() public {
        uint256 amount = 50e18;
        supply(amount);

        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(borrowLend.aavePool()));
        emit ReserveUsedAsCollateralDisabled(address(wstEthToken), address(borrowLend));
        borrowLend.setUserUseReserveAsCollateral(false);

        vm.expectEmit(address(borrowLend.aavePool()));
        emit ReserveUsedAsCollateralEnabled(address(wstEthToken), address(borrowLend));
        borrowLend.setUserUseReserveAsCollateral(true);
    }

    function test_setAavePool() public {
        vm.startPrank(origamiMultisig);
        
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, 0));
        borrowLend.setAavePool(address(0));

        vm.expectEmit(address(borrowLend));
        emit AavePoolSet(alice);
        borrowLend.setAavePool(alice);
        assertEq(address(borrowLend.aavePool()), alice);
    }

    function test_recoverToken_nonAToken() public {
        check_recoverToken(address(borrowLend));
    }

    function test_suppliedBalance_externalSupply() public {
        uint256 amount = 50e18;
        uint256 externalSupply = 3e18;

        supply(amount);

        vm.startPrank(alice);
        doMint(wstEthToken, address(alice), externalSupply);
        wstEthToken.approve(address(borrowLend.aavePool()), externalSupply);
        borrowLend.aavePool().supply(address(wstEthToken), externalSupply, address(alice), 0);

        uint256 balanceBefore = IERC20(SPARK_WSTETH_A_TOKEN).balanceOf(address(borrowLend));
        assertEq(balanceBefore, amount);

        uint256 suppliedBalance = borrowLend.suppliedBalance();
        assertEq(suppliedBalance, amount);
    }

    function test_suppliedBalance_donation() public {
        uint256 amount = 50e18;
        uint256 donationAmount = 3e18;

        supply(amount);

        vm.startPrank(alice);
        doMint(wstEthToken, address(alice), donationAmount);
        wstEthToken.approve(address(borrowLend.aavePool()), donationAmount);
        borrowLend.aavePool().supply(address(wstEthToken), donationAmount, address(borrowLend), 0);

        // Note: The actual balanceOf() gets rounded up over the total
        uint256 actualBalance = IERC20(SPARK_WSTETH_A_TOKEN).balanceOf(address(borrowLend));
        assertEq(actualBalance, amount + donationAmount + 1);

        // but our suppliedBalance stays correct
        uint256 suppliedBalance = borrowLend.suppliedBalance();
        assertEq(suppliedBalance, amount);
    }

    function test_recoverToken_aToken() public {
        uint256 amount = 50e18;
        uint256 donationAmount = 3e18;

        // bootstrap and donate
        {
            supply(amount);

            vm.startPrank(alice);
            doMint(wstEthToken, address(alice), donationAmount);
            wstEthToken.approve(address(borrowLend.aavePool()), donationAmount);
            borrowLend.aavePool().supply(address(wstEthToken), donationAmount, address(borrowLend), 0);

            // Note: The actual balanceOf() gets rounded up over the total
            uint256 balanceBefore = IERC20(SPARK_WSTETH_A_TOKEN).balanceOf(address(borrowLend));
            assertEq(balanceBefore, amount + donationAmount + 1);

            // but our suppliedBalance stays correct
            uint256 suppliedBalance = borrowLend.suppliedBalance();
            assertEq(suppliedBalance, amount);
        }

        vm.startPrank(origamiMultisig);

        // Under the donated amount
        uint256 recoverAmount = 3e18-1;
        vm.expectEmit();
        emit CommonEventsAndErrors.TokenRecovered(bob, SPARK_WSTETH_A_TOKEN, recoverAmount);
        borrowLend.recoverToken(SPARK_WSTETH_A_TOKEN, bob, recoverAmount);

        // Exactly the donated amount
        recoverAmount = 1;
        vm.expectEmit();
        emit CommonEventsAndErrors.TokenRecovered(bob, SPARK_WSTETH_A_TOKEN, recoverAmount);
        borrowLend.recoverToken(SPARK_WSTETH_A_TOKEN, bob, recoverAmount);

        // Over the donatd amount
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAmount.selector, SPARK_WSTETH_A_TOKEN, recoverAmount));
        borrowLend.recoverToken(SPARK_WSTETH_A_TOKEN, bob, recoverAmount);
    }

    function test_recoverToken_rounding() public {
        uint256 RAY = 1e27;
        uint256 index = borrowLend.aavePool().getReserveNormalizedIncome(address(wstEthToken));
        
        uint256 B = 5.555555555555555500e18;
        uint256 amount1 = (B * index + RAY / 2) / RAY;
        supply(amount1);

        uint256 expectedSuppliedBalance = 5.555776811883226757e18;
        assertEq(borrowLend.aaveAToken().scaledBalanceOf(address(borrowLend)), B);
        assertEq(borrowLend.suppliedBalance(), expectedSuppliedBalance);
        assertEq(borrowLend.aaveAToken().balanceOf(address(borrowLend)), expectedSuppliedBalance);

        // Alice donates
        uint256 A = 3e18;   
        {
            uint256 amount2 = (A * index + RAY / 2) / RAY;
            vm.startPrank(alice);
            doMint(wstEthToken, address(alice), amount2);
            wstEthToken.approve(address(borrowLend.aavePool()), amount2);
            borrowLend.aavePool().supply(address(wstEthToken), amount2, address(borrowLend), 0);
        }

        assertEq(borrowLend.aaveAToken().scaledBalanceOf(address(borrowLend)), B + A);
        assertEq(borrowLend.suppliedBalance(), expectedSuppliedBalance);
        assertEq(borrowLend.aaveAToken().balanceOf(address(borrowLend)), 8.555896290300169237e18);

        uint256 recoverTokenAmount = IERC20(SPARK_WSTETH_A_TOKEN).balanceOf(address(borrowLend)) - borrowLend.suppliedBalance();
        assertEq(recoverTokenAmount, 3.000119478416942480e18);

        vm.startPrank(origamiMultisig);
        borrowLend.recoverToken(SPARK_WSTETH_A_TOKEN, bob, recoverTokenAmount-1);

        assertEq(borrowLend.aaveAToken().scaledBalanceOf(address(borrowLend)), B);
        assertEq(borrowLend.suppliedBalance(), expectedSuppliedBalance);
        assertEq(borrowLend.aaveAToken().balanceOf(address(borrowLend)), expectedSuppliedBalance);

        vm.startPrank(borrowLend.positionOwner());
        borrowLend.withdraw(borrowLend.suppliedBalance(), feeCollector);

        assertEq(borrowLend.aaveAToken().scaledBalanceOf(address(borrowLend)), 0);
        assertEq(borrowLend.suppliedBalance(), 0);
        assertEq(borrowLend.aaveAToken().balanceOf(address(borrowLend)), 0);
        assertEq(wstEthToken.balanceOf(feeCollector), expectedSuppliedBalance);
    }
}

contract OrigamiAaveV3BorrowAndLendNotMatchingDecimalsTestAccess is OrigamiAaveV3BorrowAndLendNotMatchingDecimalsTestBase {

    function test_access_setPositionOwner() public {
        expectElevatedAccess();
        borrowLend.setPositionOwner(alice);
    }

    function test_access_setReferralCode() public {
        expectElevatedAccess();
        borrowLend.setReferralCode(123);
    }

    function test_access_setUserUseReserveAsCollateral() public {
        expectElevatedAccess();
        borrowLend.setUserUseReserveAsCollateral(false);
    }

    function test_access_setEModeCategory() public {
        expectElevatedAccess();
        borrowLend.setEModeCategory(5);
    }

    function test_access_setAavePool() public {
        expectElevatedAccess();
        borrowLend.setAavePool(alice);
    }

    function test_access_supply() public {
        expectElevatedAccess();
        borrowLend.supply(5);

        vm.prank(posOwner);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        borrowLend.supply(5);

        vm.prank(origamiMultisig);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        borrowLend.supply(5);
    }

    function test_access_withdraw() public {
        expectElevatedAccess();
        borrowLend.withdraw(5, alice);

        vm.prank(posOwner);
        vm.expectRevert(bytes(AaveErrors.NOT_ENOUGH_AVAILABLE_USER_BALANCE));
        borrowLend.withdraw(5, alice);

        vm.prank(origamiMultisig);
        vm.expectRevert(bytes(AaveErrors.NOT_ENOUGH_AVAILABLE_USER_BALANCE));
        borrowLend.withdraw(5, alice);
    }

    function test_access_borrow() public {
        expectElevatedAccess();
        borrowLend.borrow(5, alice);

        vm.prank(posOwner);
        vm.expectRevert(bytes(AaveErrors.COLLATERAL_BALANCE_IS_ZERO));
        borrowLend.borrow(5, alice);

        vm.prank(origamiMultisig);
        vm.expectRevert(bytes(AaveErrors.COLLATERAL_BALANCE_IS_ZERO));
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
        vm.expectRevert(bytes(AaveErrors.NOT_ENOUGH_AVAILABLE_USER_BALANCE));
        borrowLend.repayAndWithdraw(5, 5, alice);

        vm.prank(origamiMultisig);
        vm.expectRevert(bytes(AaveErrors.NOT_ENOUGH_AVAILABLE_USER_BALANCE));
        borrowLend.repayAndWithdraw(5, 5, alice);
    }

    function test_access_supplyAndBorrow() public {
        expectElevatedAccess();
        borrowLend.supplyAndBorrow(5, 5, alice);

        vm.prank(posOwner);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        borrowLend.supplyAndBorrow(5, 5, alice);

        vm.prank(origamiMultisig);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        borrowLend.supplyAndBorrow(5, 5, alice);
    }

    function test_access_recoverToken() public {
        expectElevatedAccess();
        borrowLend.recoverToken(alice, alice, 100e18);
    }
}

contract OrigamiAaveV3BorrowAndLendNotMatchingDecimalsTestViews is OrigamiAaveV3BorrowAndLendNotMatchingDecimalsTestBase {
    function test_suppliedBalance_donationNotIncluded() public {
        assertEq(borrowLend.suppliedBalance(), 0);

        // Mint just less than the amount as a donation
        uint256 donationAmount = 5e18;
        vm.startPrank(alice);
        doMint(wstEthToken, address(alice), donationAmount);
        wstEthToken.approve(address(borrowLend.aavePool()), donationAmount);
        borrowLend.aavePool().supply(address(wstEthToken), donationAmount, address(borrowLend), 0);

        assertEq(borrowLend.suppliedBalance(), 0);
        assertEq(borrowLend.aaveAToken().balanceOf(address(borrowLend)), 5e18);

        uint256 amount = 50e18;
        supply(amount);
        assertEq(borrowLend.suppliedBalance(), amount);
        assertEq(borrowLend.aaveAToken().balanceOf(address(borrowLend)), 55e18);
    }

    function test_suppliedBalance_success() public {
        uint256 supplyAmount = 50e18;
        uint256 borrowAmount = 1.5e8;
        supply(supplyAmount);
        borrowLend.borrow(borrowAmount, posOwner);

        assertEq(borrowLend.suppliedBalance(), supplyAmount);

        vm.warp(block.timestamp + 365 days);
        assertEq(borrowLend.suppliedBalance(), 50.000016714851337439e18);
        assertEq(borrowLend.aaveAToken().balanceOf(address(borrowLend)), 50.000016714851337439e18);

        borrowLend.withdraw(10e18, alice);
        assertEq(borrowLend.suppliedBalance(), 40.000016714851337438e18);

        assertEq(borrowLend.aaveAToken().balanceOf(address(borrowLend)), 40.000016714851337438e18);
    }

    function test_debtBalance() public {
        assertEq(borrowLend.debtBalance(), 0);

        uint256 supplyAmount = 50e18;
        uint256 borrowAmount = 1.5e8;
        supply(supplyAmount);
        borrowLend.borrow(borrowAmount, posOwner);
        assertEq(borrowLend.debtBalance(), borrowAmount);

        vm.warp(block.timestamp + 365 days);
        assertEq(borrowLend.debtBalance(), 1.50089506e8);

        deal(address(wbtcToken), address(borrowLend), 0.5e8);
        uint256 amountRepaid = borrowLend.repay(0.5e8);
        assertEq(amountRepaid, 0.5e8);
        assertEq(borrowLend.debtBalance(), 1.00089506e8);

        assertEq(borrowLend.aaveDebtToken().balanceOf(address(borrowLend)), 1.00089506e8);
    }

    function test_isSafeAlRatio_ethEMode() public {
        // 68.5% LTV
        assertEq(borrowLend.isSafeAlRatio(1.46e18), true);
        assertEq(borrowLend.isSafeAlRatio(1.459855e18), true);
        assertEq(borrowLend.isSafeAlRatio(1.459854e18), false);
        assertEq(borrowLend.isSafeAlRatio(1.459e18), false);
    }

    function test_isSafeAlRatio_nonEthEMode() public {
        vm.startPrank(origamiMultisig);
        borrowLend.setEModeCategory(0);

        // 68.5% LTV
        assertEq(borrowLend.isSafeAlRatio(1.5e18), true);
        assertEq(borrowLend.isSafeAlRatio(1.45e18), false);
    }

    function test_availableToWithdraw() public {
        assertEq(borrowLend.availableToWithdraw(), 690_451.266537189612160058e18);

        uint256 supplyAmount = 50e18;
        uint256 borrowAmount = 1.5e8;
        supply(supplyAmount);
        borrowLend.borrow(borrowAmount, posOwner);
        assertEq(borrowLend.availableToWithdraw(), 690_501.266537189612160058e18);
    }

    function test_availableToBorrow() public {
        uint256 supplyAmount = 50e18;
        uint256 borrowAmount = 1.5e8;
        assertEq(borrowLend.availableToBorrow(), 2_000e8);

        supply(supplyAmount);
        borrowLend.borrow(borrowAmount, posOwner);
        assertEq(borrowLend.availableToBorrow(), 2_000e8);
    }

    function test_availableToSupply() public {
        (
            uint256 supplyCap,
            uint256 available
        ) = borrowLend.availableToSupply();

        assertEq(supplyCap, 800_000e18);
        assertEq(available, 109_440.764612771907497262e18);

        uint256 supplyAmount = 50e18;
        uint256 borrowAmount = 1.5e8;
        supply(supplyAmount);
        borrowLend.borrow(borrowAmount, posOwner);

        (
            supplyCap,
            available
        ) = borrowLend.availableToSupply();

        assertEq(supplyCap, 800_000e18);
        assertEq(available, 109_390.764603401718130389e18);
    }

    function test_debtAccountData() public {
        uint256 supplyAmount = 50e18;
        uint256 borrowAmount = 2e8;
        supply(supplyAmount);
        borrowLend.borrow(borrowAmount, posOwner);

        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = borrowLend.debtAccountData();
        assertEq(totalCollateralBase, 164_723.04314350e8);
        assertEq(totalDebtBase, 104_409.20649806e8);
        assertEq(availableBorrowsBase, 8_426.07805524e8);
        assertEq(currentLiquidationThreshold, 7950);
        assertEq(ltv, 6850);
        assertEq(healthFactor, 1.254245901212870888e18);
    }
}

contract OrigamiAaveV3BorrowAndLendNotMatchingDecimalsTestSupply is OrigamiAaveV3BorrowAndLendNotMatchingDecimalsTestBase {
    function test_supply_fail() public {
        uint256 supplyAmount = 50e18;
        doMint(wstEthToken, address(borrowLend), supplyAmount);
        vm.startPrank(posOwner);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        borrowLend.supply(supplyAmount+1);
    }

    function test_supply_success() public {
        uint256 supplyAmount = 50e18;
        doMint(wstEthToken, address(borrowLend), supplyAmount);
        vm.startPrank(posOwner);
        borrowLend.supply(supplyAmount);
        assertEq(borrowLend.suppliedBalance(), supplyAmount);
        assertEq(wstEthToken.balanceOf(address(borrowLend)), 0);
    }

    function test_withdraw_fail() public {
        uint256 amount = 50e18;
        supply(amount);
        
        vm.expectRevert(bytes(AaveErrors.NOT_ENOUGH_AVAILABLE_USER_BALANCE));
        borrowLend.withdraw(amount+1, alice);
    }

    function test_withdraw_success() public {
        uint256 amount = 50e18;
        supply(amount);
        
        uint256 amountOut = borrowLend.withdraw(amount/2, alice);
        assertEq(amountOut, amount/2);
        assertEq(borrowLend.suppliedBalance(), 25e18);
        assertEq(wstEthToken.balanceOf(address(posOwner)), 0);
        assertEq(wstEthToken.balanceOf(address(borrowLend)), 0);
        assertEq(wstEthToken.balanceOf(address(alice)), 25e18);

        amountOut = borrowLend.withdraw(type(uint256).max, alice);
        assertEq(amountOut, amount/2);
        assertEq(wstEthToken.balanceOf(address(alice)), amount);
    }

    function test_borrow_fail() public {
        uint256 amount = 50e18;
        supply(amount);
        
        vm.expectRevert(bytes(AaveErrors.COLLATERAL_CANNOT_COVER_NEW_BORROW));
        borrowLend.borrow(60e8, alice);
    }

    function test_borrow_success() public {
        uint256 supplyAmount = 50e18;
        uint256 borrowAmount = 1e8;
        supply(supplyAmount);

        borrowLend.borrow(borrowAmount, alice);
        assertEq(borrowLend.suppliedBalance(), supplyAmount);
        assertEq(borrowLend.debtBalance(), borrowAmount);
        assertEq(wstEthToken.balanceOf(address(posOwner)), 0);
        assertEq(wstEthToken.balanceOf(address(borrowLend)), 0);
        assertEq(wstEthToken.balanceOf(address(alice)), 0);
        assertEq(wbtcToken.balanceOf(address(posOwner)), 0);
        assertEq(wbtcToken.balanceOf(address(borrowLend)), 0);
        assertEq(wbtcToken.balanceOf(address(alice)), borrowAmount);
    }

    function test_repay_fail() public {
        uint256 supplyAmount = 50e18;
        uint256 borrowAmount = 1.5e8;
        supply(supplyAmount);
        borrowLend.borrow(borrowAmount, alice);

        deal(address(wbtcToken), address(borrowLend), 0.1e8);
        vm.expectRevert();
        borrowLend.repay(0.2e8);
    }

    function test_repay_success() public {
        uint256 supplyAmount = 50e18;
        uint256 borrowAmount = 1.5e8;
        supply(supplyAmount);
        borrowLend.borrow(borrowAmount, alice);

        deal(address(wbtcToken), address(borrowLend), 0.2e8);
        uint256 amountRepaid = borrowLend.repay(0.2e8);
        assertEq(amountRepaid, 0.2e8);
        assertEq(borrowLend.suppliedBalance(), supplyAmount);
        assertEq(borrowLend.debtBalance(), 1.3e8);
        assertEq(wstEthToken.balanceOf(address(borrowLend)), 0);
        assertEq(wstEthToken.balanceOf(address(alice)), 0);
        assertEq(wbtcToken.balanceOf(address(borrowLend)), 0);
        assertEq(wbtcToken.balanceOf(address(alice)), borrowAmount);

        deal(address(wbtcToken), address(borrowLend), 2e8);
        amountRepaid = borrowLend.repay(2e8);
        assertEq(amountRepaid, 1.3e8);
        assertEq(borrowLend.suppliedBalance(), supplyAmount);
        assertEq(borrowLend.debtBalance(), 0);
        assertEq(wstEthToken.balanceOf(address(borrowLend)), 0);
        assertEq(wstEthToken.balanceOf(address(alice)), 0);
        assertEq(wbtcToken.balanceOf(address(borrowLend)), 0.7e8);
        assertEq(wbtcToken.balanceOf(address(alice)), 1.5e8);

        amountRepaid = borrowLend.repay(2e8);
        assertEq(amountRepaid, 0);
        assertEq(borrowLend.suppliedBalance(), supplyAmount);
        assertEq(borrowLend.debtBalance(), 0);
        assertEq(wstEthToken.balanceOf(address(borrowLend)), 0);
        assertEq(wstEthToken.balanceOf(address(alice)), 0);
        assertEq(wbtcToken.balanceOf(address(borrowLend)), 0.7e8);
        assertEq(wbtcToken.balanceOf(address(alice)), 1.5e8);

        vm.startPrank(origamiMultisig);
        borrowLend.recoverToken(address(wbtcToken), alice, 0.7e8);
        assertEq(wbtcToken.balanceOf(address(borrowLend)), 0);
        assertEq(wbtcToken.balanceOf(address(alice)), 2.2e8);
    }

    function test_supplyAndBorrow_success() public {
        uint256 supplyAmount = 50e18;
        uint256 borrowAmount = 1.5e8;

        doMint(wstEthToken, address(borrowLend), supplyAmount);
        vm.startPrank(posOwner);
        borrowLend.supplyAndBorrow(supplyAmount, borrowAmount, alice);

        assertEq(borrowLend.suppliedBalance(), supplyAmount);
        assertEq(borrowLend.debtBalance(), borrowAmount);
        assertEq(wstEthToken.balanceOf(address(borrowLend)), 0);
        assertEq(wstEthToken.balanceOf(address(alice)), 0);
        assertEq(wbtcToken.balanceOf(address(borrowLend)), 0);
        assertEq(wbtcToken.balanceOf(address(alice)), borrowAmount);
    }

    function test_repayAndWithdraw_success() public {
        uint256 supplyAmount = 50e18;
        uint256 borrowAmount = 1.5e8;

        doMint(wstEthToken, address(borrowLend), supplyAmount);
        vm.startPrank(posOwner);
        borrowLend.supplyAndBorrow(supplyAmount, borrowAmount, alice);

        deal(address(wbtcToken), address(borrowLend), borrowAmount/2);
        (uint256 debtRepaidAmount, uint256 withdrawnAmount) = borrowLend.repayAndWithdraw(borrowAmount/2, supplyAmount/2, alice);
        assertEq(debtRepaidAmount, borrowAmount/2);
        assertEq(withdrawnAmount, supplyAmount/2);

        assertEq(borrowLend.suppliedBalance(), supplyAmount/2);
        assertEq(borrowLend.debtBalance(), borrowAmount/2 - 1);
        assertEq(wstEthToken.balanceOf(address(borrowLend)), 0);
        assertEq(wstEthToken.balanceOf(address(alice)), supplyAmount/2);
        assertEq(wbtcToken.balanceOf(address(borrowLend)), 0);
        assertEq(wbtcToken.balanceOf(address(alice)), borrowAmount);
    }
}