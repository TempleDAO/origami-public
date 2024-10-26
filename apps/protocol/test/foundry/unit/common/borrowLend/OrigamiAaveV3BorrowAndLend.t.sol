pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Errors as AaveErrors } from "@aave/core-v3/contracts/protocol/libraries/helpers/Errors.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiAaveV3BorrowAndLend } from "contracts/common/borrowAndLend/OrigamiAaveV3BorrowAndLend.sol";
import { IAaveV3RewardsController } from "contracts/interfaces/external/aave/aave-v3-periphery/IAaveV3RewardsController.sol";

contract OrigamiAaveV3BorrowAndLendTestBase is OrigamiTest {
    IERC20 internal wethToken;
    IERC20 internal wstEthToken;
    OrigamiAaveV3BorrowAndLend internal borrowLend;

    address public posOwner = makeAddr("posOwner");

    address internal constant SPARK_POOL = 0xC13e21B648A5Ee794902342038FF3aDAB66BE987;
    address internal constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WSTETH_ADDRESS = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    address internal constant SPARK_WSTETH_A_TOKEN = 0x12B54025C112Aa61fAce2CDB7118740875A566E9;
    address internal constant SPARK_WETH_DEBT_TOKEN = 0x2e7576042566f8D6990e07A1B61Ad1efd86Ae70d;
    uint8 internal constant SPARK_EMODE_ETH = 1;

    function setUp() public {
        fork("mainnet", 19238000);
        vm.warp(1708056616);
        wethToken = IERC20(WETH_ADDRESS);
        wstEthToken = IERC20(WSTETH_ADDRESS);

        borrowLend = new OrigamiAaveV3BorrowAndLend(
            origamiMultisig,
            address(wstEthToken),
            address(wethToken),
            SPARK_POOL,
            SPARK_EMODE_ETH
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

contract MockRewardController is IAaveV3RewardsController {
    address internal constant WSTETH_ADDRESS = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    function claimAllRewards(
        address[] calldata /*assets*/,
        address to
    ) external override returns (
        address[] memory rewardsList, 
        uint256[] memory claimedAmounts
    ) {
        IERC20(WSTETH_ADDRESS).transfer(to, 6.9e18);
        rewardsList = new address[](1);
        rewardsList[0] = WSTETH_ADDRESS;
        claimedAmounts = new uint256[](1);
        claimedAmounts[0] = 6.9e18;
    }
}

contract OrigamiAaveV3BorrowAndLendTestAdmin is OrigamiAaveV3BorrowAndLendTestBase {
    event ReferralCodeSet(uint16 code);
    event PositionOwnerSet(address indexed account);
    event AavePoolSet(address indexed pool);

    event ReserveUsedAsCollateralEnabled(address indexed reserve, address indexed user);
    event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);

    function test_initialization() public {
        assertEq(address(borrowLend.aavePool()), SPARK_POOL);
        assertEq(address(borrowLend.aaveAToken()), SPARK_WSTETH_A_TOKEN);
        assertEq(address(borrowLend.aaveDebtToken()), SPARK_WETH_DEBT_TOKEN);

        assertEq(borrowLend.supplyToken(), WSTETH_ADDRESS);
        assertEq(borrowLend.borrowToken(), WETH_ADDRESS);
        assertEq(borrowLend.positionOwner(), posOwner);

        assertEq(borrowLend.referralCode(), 0);
        assertEq(borrowLend.aavePool().getUserEMode(address(borrowLend)), SPARK_EMODE_ETH);
    }

    function test_constructor_zeroEMode() public {
        borrowLend = new OrigamiAaveV3BorrowAndLend(
            origamiMultisig, 
            address(wstEthToken), 
            address(wethToken),
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

    function test_setEModeCategory() public {
        uint256 amount = 50e18;
        supply(amount);
        borrowLend.borrow(45e18, posOwner);

        assertEq(borrowLend.aavePool().getUserEMode(address(borrowLend)), 1);

        vm.startPrank(origamiMultisig);
        borrowLend.setEModeCategory(0);
        assertEq(borrowLend.aavePool().getUserEMode(address(borrowLend)), 0);
        borrowLend.setEModeCategory(1);

        vm.startPrank(posOwner);
        borrowLend.borrow(3e18, posOwner);
        vm.startPrank(origamiMultisig);

        // After this borrow, can't set the e-mode down as the new LTV would be too low
        vm.expectRevert(bytes(AaveErrors.HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD));
        borrowLend.setEModeCategory(0);
    }

    function test_setAavePool() public {
        vm.startPrank(origamiMultisig);
        
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, 0));
        borrowLend.setAavePool(address(0));

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, SPARK_POOL));
        borrowLend.setAavePool(SPARK_POOL);

        vm.expectEmit(address(borrowLend));
        emit AavePoolSet(alice);
        borrowLend.setAavePool(alice);
        assertEq(address(borrowLend.aavePool()), alice);
        assertEq(wethToken.allowance(address(borrowLend), SPARK_POOL), 0);
        assertEq(wstEthToken.allowance(address(borrowLend), SPARK_POOL), 0);
        assertEq(wethToken.allowance(address(borrowLend), alice), type(uint256).max);
        assertEq(wstEthToken.allowance(address(borrowLend), alice), type(uint256).max);
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

    function test_claim_rewards() public {
        IAaveV3RewardsController rewardController = new MockRewardController();
        deal(address(wstEthToken), address(rewardController), 1_000e18, false);

        uint256 amount = 50e18;
        supply(amount);
        borrowLend.borrow(amount, alice);

        skip(30 days);

        address[] memory assets = new address[](1);
        assets[0] = address(wstEthToken);

        assertEq(wstEthToken.balanceOf(alice), 0);
        assertEq(wstEthToken.balanceOf(address(rewardController)), 1_000e18);

        vm.startPrank(origamiMultisig);
        (
            address[] memory rewardsList, 
            uint256[] memory claimedAmounts
        ) = borrowLend.claimAllRewards(
            address(rewardController),
            assets,
            alice
        );

        assertEq(rewardsList.length, 1);
        assertEq(rewardsList[0], WSTETH_ADDRESS);
        assertEq(claimedAmounts.length, 1);
        assertEq(claimedAmounts[0], 6.9e18);
        assertEq(wstEthToken.balanceOf(alice), 6.9e18);
        assertEq(wstEthToken.balanceOf(address(rewardController)), 1_000e18 - 6.9e18);
    }
}

contract OrigamiAaveV3BorrowAndLendTestAccess is OrigamiAaveV3BorrowAndLendTestBase {

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

    function test_access_claimRewards() public {
        expectElevatedAccess();
        borrowLend.claimAllRewards(
            alice,
            new address[](0),
            alice
        );
    }
}

contract OrigamiAaveV3BorrowAndLendTestViews is OrigamiAaveV3BorrowAndLendTestBase {
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
        uint256 amount = 50e18;
        supply(amount);
        borrowLend.borrow(10e18, posOwner);

        assertEq(borrowLend.suppliedBalance(), amount);

        vm.warp(block.timestamp + 365 days);
        assertEq(borrowLend.suppliedBalance(), 50.000016714851337439e18);
        assertEq(borrowLend.aaveAToken().balanceOf(address(borrowLend)), 50.000016714851337439e18);

        borrowLend.withdraw(10e18, alice);
        assertEq(borrowLend.suppliedBalance(), 40.000016714851337438e18);

        assertEq(borrowLend.aaveAToken().balanceOf(address(borrowLend)), 40.000016714851337438e18);
    }

    function test_debtBalance() public {
        assertEq(borrowLend.debtBalance(), 0);

        uint256 amount = 50e18;
        supply(amount);
        borrowLend.borrow(40e18, posOwner);
        assertEq(borrowLend.debtBalance(), 40e18);

        vm.warp(block.timestamp + 365 days);
        assertEq(borrowLend.debtBalance(), 40.742658211257227091e18);

        deal(address(wethToken), address(borrowLend), 15e18);
        uint256 amountRepaid = borrowLend.repay(15e18);
        assertEq(amountRepaid, 15e18);
        assertEq(borrowLend.debtBalance(), 25.742658211257227091e18);

        assertEq(borrowLend.aaveDebtToken().balanceOf(address(borrowLend)), 25.742658211257227091e18);
    }

    function test_isSafeAlRatio_ethEMode() public {
        // 90% LTV
        assertEq(borrowLend.isSafeAlRatio(1.112e18), true);
        assertEq(borrowLend.isSafeAlRatio(1.111111111111111111e18), true);
        assertEq(borrowLend.isSafeAlRatio(1.111111111111111110e18), false);
        assertEq(borrowLend.isSafeAlRatio(1.111e18), false);
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

        uint256 amount = 50e18;
        supply(amount);
        borrowLend.borrow(40e18, posOwner);
        assertEq(borrowLend.availableToWithdraw(), 690_501.266537189612160058e18);
    }

    function test_availableToBorrow() public {
        assertEq(borrowLend.availableToBorrow(), 114_870.698797517399176768e18);

        uint256 amount = 50e18;
        supply(amount);
        borrowLend.borrow(40e18, posOwner);
        assertEq(borrowLend.availableToBorrow(), 114_830.698797517399176768e18);
    }

    function test_availableToSupply() public {
        (
            uint256 supplyCap,
            uint256 available
        ) = borrowLend.availableToSupply();

        assertEq(supplyCap, 800_000e18);
        assertEq(available, 109_440.764612771907497262e18);

        uint256 amount = 50e18;
        supply(amount);
        borrowLend.borrow(40e18, posOwner);

        (
            supplyCap,
            available
        ) = borrowLend.availableToSupply();

        assertEq(supplyCap, 800_000e18);
        assertEq(available, 109_390.764603401718130389e18);
    }

    function test_debtAccountData() public {
        uint256 amount = 50e18;
        supply(amount);
        borrowLend.borrow(40e18, posOwner);

        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = borrowLend.debtAccountData();
        assertEq(totalCollateralBase, 164_723.04314350e8);
        assertEq(totalDebtBase, 113_876e8);
        assertEq(availableBorrowsBase, 34_374.73882915e8);
        assertEq(currentLiquidationThreshold, 9300);
        assertEq(ltv, 9000);
        assertEq(healthFactor, 1.345256508162035899e18);
    }
}

contract OrigamiAaveV3BorrowAndLendTestSupply is OrigamiAaveV3BorrowAndLendTestBase {
    function test_supply_fail() public {
        uint256 amount = 50e18;
        doMint(wstEthToken, address(borrowLend), amount);
        vm.startPrank(posOwner);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        borrowLend.supply(amount+1);
    }

    function test_supply_success() public {
        uint256 amount = 50e18;
        doMint(wstEthToken, address(borrowLend), amount);
        vm.startPrank(posOwner);
        borrowLend.supply(amount);
        assertEq(borrowLend.suppliedBalance(), amount);
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
        borrowLend.borrow(60e18, alice);
    }

    function test_borrow_success() public {
        uint256 amount = 50e18;
        supply(amount);

        borrowLend.borrow(amount, alice);
        assertEq(borrowLend.suppliedBalance(), amount);
        assertEq(borrowLend.debtBalance(), 50e18);
        assertEq(wstEthToken.balanceOf(address(posOwner)), 0);
        assertEq(wstEthToken.balanceOf(address(borrowLend)), 0);
        assertEq(wstEthToken.balanceOf(address(alice)), 0);
        assertEq(wethToken.balanceOf(address(posOwner)), 0);
        assertEq(wethToken.balanceOf(address(borrowLend)), 0);
        assertEq(wethToken.balanceOf(address(alice)), amount);
    }

    function test_repay_fail() public {
        uint256 amount = 50e18;
        supply(amount);
        borrowLend.borrow(amount, alice);

        deal(address(wethToken), address(borrowLend), 1e18);
        vm.expectRevert();
        borrowLend.repay(10e18);
    }

    function test_repay_success() public {
        uint256 amount = 50e18;
        supply(amount);
        borrowLend.borrow(amount, alice);

        deal(address(wethToken), address(borrowLend), 10e18);
        uint256 amountRepaid = borrowLend.repay(10e18);
        assertEq(amountRepaid, 10e18);
        assertEq(borrowLend.suppliedBalance(), amount);
        assertEq(borrowLend.debtBalance(), 40e18);
        assertEq(wstEthToken.balanceOf(address(borrowLend)), 0);
        assertEq(wstEthToken.balanceOf(address(alice)), 0);
        assertEq(wethToken.balanceOf(address(borrowLend)), 0);
        assertEq(wethToken.balanceOf(address(alice)), 50e18);

        deal(address(wethToken), address(borrowLend), 100e18);
        amountRepaid = borrowLend.repay(100e18);
        assertEq(amountRepaid, 40e18);
        assertEq(borrowLend.suppliedBalance(), amount);
        assertEq(borrowLend.debtBalance(), 0);
        assertEq(wstEthToken.balanceOf(address(borrowLend)), 0);
        assertEq(wstEthToken.balanceOf(address(alice)), 0);
        assertEq(wethToken.balanceOf(address(borrowLend)), 60e18);
        assertEq(wethToken.balanceOf(address(alice)), 50e18);

        amountRepaid = borrowLend.repay(100e18);
        assertEq(amountRepaid, 0);
        assertEq(borrowLend.suppliedBalance(), amount);
        assertEq(borrowLend.debtBalance(), 0);
        assertEq(wstEthToken.balanceOf(address(borrowLend)), 0);
        assertEq(wstEthToken.balanceOf(address(alice)), 0);
        assertEq(wethToken.balanceOf(address(borrowLend)), 60e18);
        assertEq(wethToken.balanceOf(address(alice)), 50e18);

        vm.startPrank(origamiMultisig);
        borrowLend.recoverToken(address(wethToken), alice, 60e18);
        assertEq(wethToken.balanceOf(address(borrowLend)), 0);
        assertEq(wethToken.balanceOf(address(alice)), 110e18);
    }

    function test_supplyAndBorrow_success() public {
        uint256 amount = 50e18;
        doMint(wstEthToken, address(borrowLend), amount);
        vm.startPrank(posOwner);
        borrowLend.supplyAndBorrow(amount, amount, alice);

        assertEq(borrowLend.suppliedBalance(), amount);
        assertEq(borrowLend.debtBalance(), amount);
        assertEq(wstEthToken.balanceOf(address(borrowLend)), 0);
        assertEq(wstEthToken.balanceOf(address(alice)), 0);
        assertEq(wethToken.balanceOf(address(borrowLend)), 0);
        assertEq(wethToken.balanceOf(address(alice)), amount);
    }

    function test_repayAndWithdraw_success() public {
        uint256 amount = 50e18;
        doMint(wstEthToken, address(borrowLend), amount);
        vm.startPrank(posOwner);
        borrowLend.supplyAndBorrow(amount, amount, alice);

        deal(address(wethToken), address(borrowLend), amount/2);
        (uint256 debtRepaidAmount, uint256 withdrawnAmount) = borrowLend.repayAndWithdraw(amount/2, amount/2, alice);
        assertEq(debtRepaidAmount, amount/2);
        assertEq(withdrawnAmount, amount/2);

        assertEq(borrowLend.suppliedBalance(), amount/2);
        assertEq(borrowLend.debtBalance(), amount/2 + 1);
        assertEq(wstEthToken.balanceOf(address(borrowLend)), 0);
        assertEq(wstEthToken.balanceOf(address(alice)), amount/2);
        assertEq(wethToken.balanceOf(address(borrowLend)), 0);
        assertEq(wethToken.balanceOf(address(alice)), amount);
    }
}