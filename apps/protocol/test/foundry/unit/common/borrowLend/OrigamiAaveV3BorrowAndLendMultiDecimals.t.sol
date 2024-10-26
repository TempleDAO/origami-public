pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Errors as AaveErrors } from "@aave/core-v3/contracts/protocol/libraries/helpers/Errors.sol";
import { DataTypes as AaveDataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import { IPool as IAavePool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiAaveV3BorrowAndLend } from "contracts/common/borrowAndLend/OrigamiAaveV3BorrowAndLend.sol";
import { ReserveConfiguration as AaveReserveConfiguration } from "@aave/core-v3/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import { OrigamiAaveV3BorrowAndLendConstants as Constants } from "test/foundry/unit/common/borrowLend/OrigamiAaveV3BorrowAndLendConstants.t.sol";

contract OrigamiAaveV3BorrowAndLendMultiDecimalsTestBase is OrigamiTest {
    using SafeERC20 for IERC20;

    error InvalidCount(uint256 count);

    address public posOwner = makeAddr("posOwner");
    
    uint256 internal constant borrowLendCount = 5;

    mapping(uint256 => BorrowLendContract) internal borrowLendContracts;

    address[borrowLendCount] internal supplyTokens = [
        Constants.WBTC_ADDRESS,
        Constants.DAI_ADDRESS,
        Constants.USDT_ADDRESS,
        Constants.WSTETH_ADDRESS,
        Constants.RETH_ADDRESS
    ];

    address[borrowLendCount] internal borrowTokens = [
        Constants.USDT_ADDRESS,
        Constants.WSTETH_ADDRESS,
        Constants.DAI_ADDRESS,
        Constants.WBTC_ADDRESS,
        Constants.USDC_ADDRESS
    ];

    uint256[borrowLendCount] internal supplyAmounts = [
        1e8, // LTV 73%
        10_000e18, // LTV 63%
        10_000e6, // LTV 75%
        10e18, // LTV 78.5%
        5e18 // LTV 74.5%
    ];

    uint256[borrowLendCount] internal borrowAmounts = [
        15_000e6,
        0.48e18,
        2_000e18,
        0.15e8,
        2_000e6
    ];

    uint256[borrowLendCount] internal ltvValues = [
        7300,
        6300,
        7500,
        7850,
        7450
    ];

    uint256[borrowLendCount] internal liquidationTHs = [
        7800,
        7700,
        7800,
        8100,
        7700
    ];

    uint256[borrowLendCount] internal eModes = [0, 1, 0, 0, 0];

    struct BorrowLendContract {
        IERC20 supplyToken;
        IERC20 borrowToken;
        address supplyAToken;
        address borrowDebtToken;
        OrigamiAaveV3BorrowAndLend borrowLend;
    }

    function setUp() public {
        fork("mainnet", 19916626);
        vm.warp(1716274482);

        for(uint256 i; i < supplyTokens.length; ++i) {
            generateNewLendBorrow(i, supplyTokens[i], borrowTokens[i]);
        }
    }

    function generateNewLendBorrow(uint256 ind, address _supplyToken, address _borrowToken) internal {
        OrigamiAaveV3BorrowAndLend borrowLend = new OrigamiAaveV3BorrowAndLend(
            origamiMultisig,
            address(_supplyToken),
            address(_borrowToken),
            Constants.SPARK_POOL,
            uint8(eModes[ind])
        );

        vm.startPrank(origamiMultisig);
        borrowLend.setPositionOwner(posOwner);
        vm.stopPrank();

        AaveDataTypes.ReserveData memory _reserveData = IAavePool(Constants.SPARK_POOL).getReserveData(_supplyToken);
        address supplyAToken = _reserveData.aTokenAddress;

        _reserveData = IAavePool(Constants.SPARK_POOL).getReserveData(_borrowToken);
        address borrowDebtToken = _reserveData.variableDebtTokenAddress;

        borrowLendContracts[ind] = BorrowLendContract(
            IERC20(_supplyToken),
            IERC20(_borrowToken),
            supplyAToken,
            borrowDebtToken,
            borrowLend
        );
    }

    function mintToken(IERC20 _token, address _to, uint256 _amount) internal {
        // USDC is proxy so need to transfer from whale address
        if (address(_token) == Constants.USDC_ADDRESS) {
            vm.startPrank(Constants.USDC_WHALE);
            IERC20(Constants.USDC_ADDRESS).safeTransfer(_to, _amount);
            vm.stopPrank();
        } else {
            doMint(_token, _to, _amount);
        }
    }

    function approveToken(IERC20 _token, address _spender, uint256 _amount) internal {
        // USDT need to safeApprove or forceApprove
        if (address(_token) == Constants.USDT_ADDRESS) {
            _token.safeApprove(_spender, _amount);
        } else {
            _token.approve(_spender, _amount);
        }
    }

    function supply(uint256 count, uint256 amount) internal {
        if(count >= borrowLendCount) revert InvalidCount(count);

        BorrowLendContract storage info = borrowLendContracts[count];

        mintToken(info.supplyToken, address(info.borrowLend), amount);

        vm.startPrank(posOwner);
        info.borrowLend.supply(amount);
    }

    function isStable(address _token) internal pure returns(bool) {
        return _token == Constants.DAI_ADDRESS || _token == Constants.USDC_ADDRESS || _token == Constants.USDT_ADDRESS;
    }

    function revertPerToken(address _token) internal {
        if (_token == Constants.WBTC_ADDRESS || _token == Constants.USDT_ADDRESS) vm.expectRevert();
        else if(_token == Constants.DAI_ADDRESS) vm.expectRevert("Dai/insufficient-balance");
        else vm.expectRevert("ERC20: transfer amount exceeds balance");
    }
}

contract OrigamiAaveV3BorrowAndLendMultiDecimalsTestAdmin is OrigamiAaveV3BorrowAndLendMultiDecimalsTestBase {
    event ReferralCodeSet(uint16 code);
    event PositionOwnerSet(address indexed account);
    event AavePoolSet(address indexed pool);

    event ReserveUsedAsCollateralEnabled(address indexed reserve, address indexed user);
    event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);

    function test_initialization() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];

            assertEq(address(info.borrowLend.aavePool()), Constants.SPARK_POOL);
            assertEq(address(info.borrowLend.aaveAToken()), info.supplyAToken);
            assertEq(address(info.borrowLend.aaveDebtToken()), info.borrowDebtToken);

            assertEq(info.borrowLend.supplyToken(), address(info.supplyToken));
            assertEq(info.borrowLend.borrowToken(), address(info.borrowToken));
            assertEq(info.borrowLend.positionOwner(), posOwner);

            assertEq(info.borrowLend.referralCode(), 0);

            // eMode updated
            assertEq(info.borrowLend.aavePool().getUserEMode(address(info.borrowLend)), eModes[ind]);
        }
    }

    function test_constructor_zeroEMode() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            borrowLendContracts[ind].borrowLend = new OrigamiAaveV3BorrowAndLend(
                origamiMultisig, 
                supplyTokens[0], 
                borrowTokens[0],
                Constants.SPARK_POOL,
                0
            );

            assertEq(borrowLendContracts[ind].borrowLend.aavePool().getUserEMode(address(borrowLendContracts[ind].borrowLend)), 0);
        }
    }

    function test_setPositionOwner_success() public {
        vm.startPrank(origamiMultisig);

        for(uint256 ind; ind < borrowLendCount; ++ind) {
            OrigamiAaveV3BorrowAndLend borrowLendItem = borrowLendContracts[ind].borrowLend;

            vm.expectEmit(address(borrowLendItem));
            emit PositionOwnerSet(alice);
            borrowLendItem.setPositionOwner(alice);
            assertEq(borrowLendItem.positionOwner(), alice);
        }
    }

    function test_setReferralCode_success() public {
        vm.startPrank(origamiMultisig);

        for(uint256 ind; ind < borrowLendCount; ++ind) {
            OrigamiAaveV3BorrowAndLend borrowLendItem = borrowLendContracts[ind].borrowLend;
            vm.expectEmit(address(borrowLendItem));
            emit ReferralCodeSet(123);
            borrowLendItem.setReferralCode(123);
            assertEq(borrowLendItem.referralCode(), 123);
        }
    }

    function test_setUserUseReserveAsCollateral_fail() public {
        vm.startPrank(origamiMultisig);

        for(uint256 ind; ind < borrowLendCount; ++ind) {
            vm.expectRevert(bytes(AaveErrors.UNDERLYING_BALANCE_ZERO));
            borrowLendContracts[ind].borrowLend.setUserUseReserveAsCollateral(true);
        }
    }

    function test_setUserUseReserveAsCollateral_success() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            if (isStable(address(info.supplyToken))) continue;

            supply(ind, supplyAmounts[ind]);

            vm.startPrank(origamiMultisig);
            
            vm.expectEmit(address(borrowLendItem.aavePool()));
            emit ReserveUsedAsCollateralDisabled(address(info.supplyToken), address(borrowLendItem));
            borrowLendItem.setUserUseReserveAsCollateral(false);

            vm.expectEmit(address(borrowLendItem.aavePool()));
            emit ReserveUsedAsCollateralEnabled(address(info.supplyToken), address(borrowLendItem));
            borrowLendItem.setUserUseReserveAsCollateral(true);
        }
    }

    function test_setEModeCategory() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            supply(ind, supplyAmounts[ind]);
            borrowLendItem.borrow(borrowAmounts[ind], posOwner);

            vm.startPrank(origamiMultisig);
            borrowLendItem.setEModeCategory(0);
            
            assertEq(borrowLendItem.aavePool().getUserEMode(address(borrowLendItem)), 0);

            vm.startPrank(posOwner);
            borrowLendItem.borrow(borrowAmounts[ind] * 2, posOwner);
        }
    }

    function test_setAavePool() public {
        vm.startPrank(origamiMultisig);

        for(uint256 ind; ind < borrowLendCount; ++ind) {
            OrigamiAaveV3BorrowAndLend borrowLendItem = borrowLendContracts[ind].borrowLend;

            vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, 0));
            borrowLendItem.setAavePool(address(0));

            vm.expectEmit(address(borrowLendItem));
            emit AavePoolSet(alice);
            borrowLendItem.setAavePool(alice);
            assertEq(address(borrowLendItem.aavePool()), alice);
        }
    }

    function test_recoverToken_nonAToken() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            OrigamiAaveV3BorrowAndLend borrowLendItem = borrowLendContracts[ind].borrowLend;
            
            check_recoverToken(address(borrowLendItem));
        }
    }

    function test_suppliedBalance_externalSupply() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            uint256 amount = supplyAmounts[ind];
            uint256 externalSupply = amount / 10;

            supply(ind, amount);
    
            mintToken(info.supplyToken, address(alice), externalSupply);

            vm.startPrank(alice);

    
            approveToken(info.supplyToken, address(borrowLendItem.aavePool()), externalSupply);
            borrowLendItem.aavePool().supply(address(info.supplyToken), externalSupply, address(alice), 0);

            uint256 balanceBefore = IERC20(info.supplyAToken).balanceOf(address(borrowLendItem));
            assertEq(balanceBefore, amount);

            uint256 suppliedBalance = borrowLendItem.suppliedBalance();
            assertEq(suppliedBalance, amount);
        }
    }

    function test_suppliedBalance_donation() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            uint256 amount = supplyAmounts[ind];
            uint256 donationAmount = amount / 10;

            supply(ind, amount);

            // USDC is proxy so need to transfer from whale address
            mintToken(info.supplyToken, address(alice), donationAmount);

            vm.startPrank(alice);

            approveToken(info.supplyToken, address(borrowLendItem.aavePool()), donationAmount);
            borrowLendItem.aavePool().supply(address(info.supplyToken), donationAmount, address(borrowLendItem), 0);

            // Note: The actual balanceOf() gets rounded up over the total
            uint256 actualBalance = IERC20(info.supplyAToken).balanceOf(address(borrowLendItem));
            assertEq(actualBalance, amount + donationAmount);

            // but our suppliedBalance stays correct
            uint256 suppliedBalance = borrowLendItem.suppliedBalance();
            assertEq(suppliedBalance, amount);
        }
    }

    function test_recoverToken_aToken() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            uint256 amount = supplyAmounts[ind];
            uint256 donationAmount = amount / 5;

            // bootstrap and donate
            {
                supply(ind, amount);
    
                mintToken(info.supplyToken, address(alice), donationAmount);
                vm.startPrank(alice);
                approveToken(info.supplyToken, address(borrowLendItem.aavePool()), donationAmount);
                borrowLendItem.aavePool().supply(address(info.supplyToken), donationAmount, address(borrowLendItem), 0);

                // Note: The actual balanceOf() gets rounded up over the total
                uint256 balanceBefore = IERC20(info.supplyAToken).balanceOf(address(borrowLendItem));
                assertApproxEqAbs(balanceBefore, amount + donationAmount, 1);

                // but our suppliedBalance stays correct
                uint256 suppliedBalance = borrowLendItem.suppliedBalance();
                assertEq(suppliedBalance, amount);
            }

            vm.startPrank(origamiMultisig);

            // Under the donated amount
            uint256 recoverAmount = donationAmount - 1;
            vm.expectEmit();
            emit CommonEventsAndErrors.TokenRecovered(bob, info.supplyAToken, recoverAmount);
            borrowLendItem.recoverToken(info.supplyAToken, bob, recoverAmount);

            // Exactly the donated amount
            recoverAmount = 1;
            vm.expectEmit();
            emit CommonEventsAndErrors.TokenRecovered(bob, info.supplyAToken, recoverAmount);
            borrowLendItem.recoverToken(info.supplyAToken, bob, recoverAmount);

            // Over the donatd amount
            vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAmount.selector, info.supplyAToken, recoverAmount));
            borrowLendItem.recoverToken(info.supplyAToken, bob, recoverAmount);
        }
    }

    function test_recoverToken_rounding() public {
        uint256 RAY = 1e27;
        bytes[] memory checkBalances = new bytes[](5);
        checkBalances[0] = abi.encode(100208525, 120250230, 20041705);
        checkBalances[1] = abi.encode(10660775309530783840050, 12792930371436940608060, 2132155061906156768010);
        checkBalances[2] = supplyTokens[2] == Constants.USDC_ADDRESS ? abi.encode(10665096086, 12798115304, 2133019218) : abi.encode(10680852313, 12817022776, 2136170463);
        checkBalances[3] = abi.encode(10005419817350963394, 12006503780821156073, 2001083963470192679);
        checkBalances[4] = abi.encode(5006688842884845476, 6008026611461814572, 1001337768576969096);

        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            uint256 index = borrowLendItem.aavePool().getReserveNormalizedIncome(address(info.supplyToken));
        
            uint256 B = supplyAmounts[ind];
            uint256 amount1 = (B * index + RAY / 2) / RAY;
            supply(ind, amount1);

            (uint256 _expectedSuppliedBalance, uint256 _aTokenBalance, uint256 _recoverTokenAmount) = abi.decode(checkBalances[ind], (uint256,uint256,uint256));
            assertApproxEqAbs(borrowLendItem.aaveAToken().scaledBalanceOf(address(borrowLendItem)), B, 1);
            assertEq(borrowLendItem.suppliedBalance(), _expectedSuppliedBalance);
            assertEq(borrowLendItem.aaveAToken().balanceOf(address(borrowLendItem)), _expectedSuppliedBalance);

            // Alice donates
            uint256 A = supplyAmounts[ind] / 5;   
            {
                uint256 amount2 = (A * index + RAY / 2) / RAY;
                mintToken(info.supplyToken, address(alice), amount2);

                vm.startPrank(alice);

                approveToken(info.supplyToken, address(borrowLendItem.aavePool()), amount2);
                borrowLendItem.aavePool().supply(address(info.supplyToken), amount2, address(borrowLendItem), 0);
            }

            assertEq(borrowLendItem.aaveAToken().scaledBalanceOf(address(borrowLendItem)), B + A);
            assertEq(borrowLendItem.suppliedBalance(), _expectedSuppliedBalance);
            assertEq(borrowLendItem.aaveAToken().balanceOf(address(borrowLendItem)), _aTokenBalance);

            uint256 recoverTokenAmount = IERC20(info.supplyAToken).balanceOf(address(borrowLendItem)) - borrowLendItem.suppliedBalance();
            assertEq(recoverTokenAmount, _recoverTokenAmount);

            vm.startPrank(origamiMultisig);
            borrowLendItem.recoverToken(info.supplyAToken, bob, recoverTokenAmount - 1);

            assertApproxEqAbs(borrowLendItem.aaveAToken().scaledBalanceOf(address(borrowLendItem)), B, 1);
            assertApproxEqAbs(borrowLendItem.suppliedBalance(), _expectedSuppliedBalance, 1);
            assertApproxEqAbs(borrowLendItem.aaveAToken().balanceOf(address(borrowLendItem)), _expectedSuppliedBalance, 1);

            uint256 prevCollectorSupplyBalance = info.supplyToken.balanceOf(feeCollector);

            vm.startPrank(borrowLendItem.positionOwner());
            borrowLendItem.withdraw(borrowLendItem.suppliedBalance(), feeCollector);

            assertApproxEqAbs(borrowLendItem.aaveAToken().scaledBalanceOf(address(borrowLendItem)), 0, 1);
            assertApproxEqAbs(borrowLendItem.suppliedBalance(), 0, 1);
            assertApproxEqAbs(borrowLendItem.aaveAToken().balanceOf(address(borrowLendItem)), 0, 1);
            assertApproxEqAbs(info.supplyToken.balanceOf(feeCollector), prevCollectorSupplyBalance + _expectedSuppliedBalance, 1);
        }
    }
}

contract OrigamiAaveV3BorrowAndLendMultiDecimalsTestAccess is OrigamiAaveV3BorrowAndLendMultiDecimalsTestBase {

    function test_access_setPositionOwner() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            OrigamiAaveV3BorrowAndLend borrowLendItem = borrowLendContracts[ind].borrowLend;
            
            expectElevatedAccess();
            borrowLendItem.setPositionOwner(alice);
        }
    }

    function test_access_setReferralCode() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            OrigamiAaveV3BorrowAndLend borrowLendItem = borrowLendContracts[ind].borrowLend;

            expectElevatedAccess();
            borrowLendItem.setReferralCode(123);
        }
    }

    function test_access_setUserUseReserveAsCollateral() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            OrigamiAaveV3BorrowAndLend borrowLendItem = borrowLendContracts[ind].borrowLend;

            expectElevatedAccess();
            borrowLendItem.setUserUseReserveAsCollateral(false);
        }
    }

    function test_access_setEModeCategory() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            OrigamiAaveV3BorrowAndLend borrowLendItem = borrowLendContracts[ind].borrowLend;

            expectElevatedAccess();
            borrowLendItem.setEModeCategory(5);
        }
    }

    function test_access_setAavePool() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            OrigamiAaveV3BorrowAndLend borrowLendItem = borrowLendContracts[ind].borrowLend;

            expectElevatedAccess();
            borrowLendItem.setAavePool(alice);
        }
    }

    function test_access_supply() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            expectElevatedAccess();
            borrowLendItem.supply(5);

            vm.prank(posOwner);
            revertPerToken(address(info.supplyToken));
            borrowLendItem.supply(5);

            vm.prank(origamiMultisig);
            revertPerToken(address(info.supplyToken));
            borrowLendItem.supply(5);
        }
    }

    function test_access_withdraw() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            OrigamiAaveV3BorrowAndLend borrowLendItem = borrowLendContracts[ind].borrowLend;

            expectElevatedAccess();
            borrowLendItem.withdraw(5, alice);

            vm.prank(posOwner);
            vm.expectRevert(bytes(AaveErrors.NOT_ENOUGH_AVAILABLE_USER_BALANCE));
            borrowLendItem.withdraw(5, alice);

            vm.prank(origamiMultisig);
            vm.expectRevert(bytes(AaveErrors.NOT_ENOUGH_AVAILABLE_USER_BALANCE));
            borrowLendItem.withdraw(5, alice);
        }
    }

    function test_access_borrow() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            OrigamiAaveV3BorrowAndLend borrowLendItem = borrowLendContracts[ind].borrowLend;

            expectElevatedAccess();
            borrowLendItem.borrow(5, alice);

            vm.prank(posOwner);
            vm.expectRevert(bytes(AaveErrors.COLLATERAL_BALANCE_IS_ZERO));
            borrowLendItem.borrow(5, alice);

            vm.prank(origamiMultisig);
            vm.expectRevert(bytes(AaveErrors.COLLATERAL_BALANCE_IS_ZERO));
            borrowLendItem.borrow(5, alice);
        }
    }

    function test_access_repay() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            OrigamiAaveV3BorrowAndLend borrowLendItem = borrowLendContracts[ind].borrowLend;

            expectElevatedAccess();
            borrowLendItem.repay(5);

            vm.prank(posOwner);
            borrowLendItem.repay(5);

            vm.prank(origamiMultisig);
            borrowLendItem.repay(5);
        }
    }

    function test_access_repayAndWithdraw() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            OrigamiAaveV3BorrowAndLend borrowLendItem = borrowLendContracts[ind].borrowLend;

            expectElevatedAccess();
            borrowLendItem.repayAndWithdraw(5, 5, alice);

            vm.prank(posOwner);
            vm.expectRevert(bytes(AaveErrors.NOT_ENOUGH_AVAILABLE_USER_BALANCE));
            borrowLendItem.repayAndWithdraw(5, 5, alice);

            vm.prank(origamiMultisig);
            vm.expectRevert(bytes(AaveErrors.NOT_ENOUGH_AVAILABLE_USER_BALANCE));
            borrowLendItem.repayAndWithdraw(5, 5, alice);
        }
    }

    function test_access_supplyAndBorrow() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            expectElevatedAccess();
            borrowLendItem.supplyAndBorrow(5, 5, alice);

            vm.prank(posOwner);
            revertPerToken(address(info.supplyToken));
            borrowLendItem.supplyAndBorrow(5, 5, alice);

            vm.prank(origamiMultisig);
            revertPerToken(address(info.supplyToken));
            borrowLendItem.supplyAndBorrow(5, 5, alice);
        }
    }

    function test_access_recoverToken() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            OrigamiAaveV3BorrowAndLend borrowLendItem = borrowLendContracts[ind].borrowLend;

            expectElevatedAccess();
            borrowLendItem.recoverToken(alice, alice, 100e18);
        }
    }
}

contract OrigamiAaveV3BorrowAndLendMultiDecimalsTestViews is OrigamiAaveV3BorrowAndLendMultiDecimalsTestBase {
    using AaveReserveConfiguration for AaveDataTypes.ReserveConfigurationMap;

    function test_suppliedBalance_donationNotIncluded() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            assertEq(borrowLendItem.suppliedBalance(), 0);

            // Mint just less than the amount as a donation
            mintToken(info.supplyToken, address(alice), supplyAmounts[ind]);
            
            vm.startPrank(alice);

            approveToken(info.supplyToken, address(borrowLendItem.aavePool()), supplyAmounts[ind]);
            borrowLendItem.aavePool().supply(address(info.supplyToken), supplyAmounts[ind], address(borrowLendItem), 0);

            assertEq(borrowLendItem.suppliedBalance(), 0);
            assertEq(borrowLendItem.aaveAToken().balanceOf(address(borrowLendItem)), supplyAmounts[ind]);

            uint256 amount = supplyAmounts[ind] / 10;
            supply(ind, amount);
            assertEq(borrowLendItem.suppliedBalance(), amount);
            assertApproxEqAbs(borrowLendItem.aaveAToken().balanceOf(address(borrowLendItem)), supplyAmounts[ind] + amount, 1);
        }
    }

    function test_suppliedBalance_success() public {
        uint256[] memory checkBalances = new uint256[](5);
        checkBalances[0] = 100090721;
        checkBalances[1] = 10601764127483117653567;
        checkBalances[2] = supplyTokens[2] == Constants.USDC_ADDRESS ? 10605300028 : 10568455331; // USDT
        checkBalances[3] = 10000165548776924406;
        checkBalances[4] = 5000380166770655892;

        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            supply(ind, supplyAmounts[ind]);
            borrowLendItem.borrow(borrowAmounts[ind], posOwner);

            assertEq(borrowLendItem.suppliedBalance(), supplyAmounts[ind]);
        }

        // 365 days later
        vm.warp(block.timestamp + 365 days);
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            assertEq(borrowLendItem.suppliedBalance(), checkBalances[ind]);
            assertEq(borrowLendItem.aaveAToken().balanceOf(address(borrowLendItem)), checkBalances[ind]);

            uint256 withdrawAmount = supplyAmounts[ind] / 5;
            borrowLendItem.withdraw(withdrawAmount, alice);
            assertApproxEqAbs(borrowLendItem.suppliedBalance(), checkBalances[ind] - withdrawAmount, 1);

            assertApproxEqAbs(borrowLendItem.aaveAToken().balanceOf(address(borrowLendItem)), checkBalances[ind] - withdrawAmount, 1);
        }
    }

    function test_debtBalance() public {
        uint256[] memory afterDebtAmounts = new uint256[](5);
        afterDebtAmounts[0] = supplyTokens[2] == Constants.USDC_ADDRESS ? 16226614248 : 16226603677;
        afterDebtAmounts[1] = 481501638259417763;
        afterDebtAmounts[2] = 2185269356435658492118;
        afterDebtAmounts[3] = 15151355;
        afterDebtAmounts[4] = supplyTokens[2] == Constants.USDC_ADDRESS ? 2168983435 : 2168984678;

        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;
        
            assertEq(borrowLendItem.debtBalance(), 0);

            uint256 amount = supplyAmounts[ind];
            supply(ind, amount);
            borrowLendItem.borrow(borrowAmounts[ind], posOwner);
            assertEq(borrowLendItem.debtBalance(), borrowAmounts[ind]);
        }

        vm.warp(block.timestamp + 365 days);
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            uint256 afterDebt = borrowLendItem.debtBalance();
            assertEq(afterDebt, afterDebtAmounts[ind]);

            mintToken(info.borrowToken, address(borrowLendItem), borrowAmounts[ind] / 2);
            vm.startPrank(posOwner);
            uint256 amountRepaid = borrowLendItem.repay(borrowAmounts[ind] / 2);
            assertApproxEqAbs(amountRepaid, borrowAmounts[ind] / 2, 1);
            assertApproxEqAbs(borrowLendItem.debtBalance(), afterDebt - borrowAmounts[ind] / 2, 1);
            assertApproxEqAbs(borrowLendItem.aaveDebtToken().balanceOf(address(borrowLendItem)), afterDebt - borrowAmounts[ind] / 2, 1);
        }
    }

    function test_isSafeAlRatio_ethEMode() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            uint256 eMode = borrowLendItem.aavePool().getUserEMode(address(borrowLendItem));            
            uint256 ltvVal = eMode == 0 ? ltvValues[ind] : IAavePool(Constants.SPARK_POOL).getEModeCategoryData(uint8(eMode)).ltv;
            uint256 thresholdVal = 1e22 / ltvVal;

            assertEq(borrowLendItem.isSafeAlRatio(thresholdVal), true);
            assertEq(borrowLendItem.isSafeAlRatio(thresholdVal + 1), true);
            assertEq(borrowLendItem.isSafeAlRatio(thresholdVal - 1), false);
        }
    }

    function test_isSafeAlRatio_nonEthEMode() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            vm.startPrank(origamiMultisig);
            borrowLendItem.setEModeCategory(0);

            uint256 thresholdVal = 1e22 / ltvValues[ind];
            assertEq(borrowLendItem.isSafeAlRatio(thresholdVal + 1), true);
            assertEq(borrowLendItem.isSafeAlRatio(thresholdVal), true);
            assertEq(borrowLendItem.isSafeAlRatio(thresholdVal - 1), false);
        }
    }

    function test_availableToWithdraw() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            uint256 withdrawAmount = info.supplyToken.balanceOf(info.supplyAToken);

            assertEq(borrowLendItem.availableToWithdraw(), withdrawAmount);

            supply(ind, supplyAmounts[ind]);
            borrowLendItem.borrow(borrowAmounts[ind], posOwner);

            assertEq(borrowLendItem.availableToWithdraw(), withdrawAmount + supplyAmounts[ind]);
        }
    }

    function test_availableToBorrow() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            AaveDataTypes.ReserveData memory _reserveData = IAavePool(Constants.SPARK_POOL).getReserveData(address(info.borrowToken));
            uint256 borrowCap = _reserveData.configuration.getBorrowCap() * (10 ** _reserveData.configuration.getDecimals());
            uint256 balance = info.borrowToken.balanceOf(_reserveData.aTokenAddress);

            uint256 availableBorrow = (borrowCap > 0 && borrowCap < balance) ? borrowCap : balance;
            assertEq(borrowLendItem.availableToBorrow(), availableBorrow);

            supply(ind, supplyAmounts[ind]);
            borrowLendItem.borrow(borrowAmounts[ind], posOwner);
            balance -= borrowAmounts[ind];
            availableBorrow = (borrowCap > 0 && borrowCap < balance) ? borrowCap : balance;
            assertEq(borrowLendItem.availableToBorrow(), availableBorrow);
        }
    }

    function test_availableToSupply() public {
        uint256[] memory availableAmounts = new uint[](5);
        availableAmounts[0] = 954845772295;
        availableAmounts[1] = 210699651368062277352600764;
        availableAmounts[2] = supplyTokens[2] == Constants.USDC_ADDRESS ? 348788114741636 : 296907069247963; // USDT
        availableAmounts[3] = 218840917315766879294287;
        availableAmounts[4] = 44934876716530125734095;

        uint256[] memory afterAvailableAmounts = new uint[](5);
        afterAvailableAmounts[0] = 954745763755;
        afterAvailableAmounts[1] = 210689601241068581914390124;
        afterAvailableAmounts[2] = supplyTokens[2] == Constants.USDC_ADDRESS ? 348778101800015 : 296897069247963; // USDT
        afterAvailableAmounts[3] = 218830917315766879294287;
        afterAvailableAmounts[4] = 44929876619738066577817;

        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            (
                uint256 supplyCap,
                uint256 available
            ) = borrowLendItem.availableToSupply();

            AaveDataTypes.ReserveData memory reserveinfo = IAavePool(Constants.SPARK_POOL).getReserveData(address(info.supplyToken));

            assertEq(supplyCap, reserveinfo.configuration.getSupplyCap() * (10 ** reserveinfo.configuration.getDecimals()));
            assertEq(available, availableAmounts[ind]);

            supply(ind, supplyAmounts[ind]);
            borrowLendItem.borrow(borrowAmounts[ind], posOwner);

            (
                supplyCap,
                available
            ) = borrowLendItem.availableToSupply();

            assertEq(supplyCap, reserveinfo.configuration.getSupplyCap() * (10 ** reserveinfo.configuration.getDecimals()));
            assertApproxEqAbs(available, afterAvailableAmounts[ind], 1);
        }
    }

    function test_debtAccountData() public {
        bytes[] memory debtInfos = new bytes[](5);
        debtInfos[0] = abi.encode(7114809232269, 1500045390000, 3693765349556, 3699588851221362042);
        debtInfos[1] = abi.encode(1000285990000, 205801690476, 424378483224,  3742535887429072704);
        debtInfos[2] = supplyTokens[2] == Constants.USDC_ADDRESS ? abi.encode(999950000000, 200057198000, 549905302000, 3898690013642998239) : abi.encode(1000030260000, 200057198000, 549965497000, 3899002938149718562); // USDT
        debtInfos[3] = abi.encode(4287535218250, 1067221384840, 2298493761486, 3254154738759910399);
        debtInfos[4] = abi.encode(2032435788180, 199990000000, 1314174662194, 7825269047947397370);

        uint[] memory checkVals = new uint[](4);
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;
        
            uint256 amount = supplyAmounts[ind];
            supply(ind, amount);
            borrowLendItem.borrow(borrowAmounts[ind], posOwner);

            (checkVals[0], checkVals[1], checkVals[2], checkVals[3]) = abi.decode(debtInfos[ind], (uint256,uint256,uint256,uint256));

            (
                uint256 totalCollateralBase,
                uint256 totalDebtBase,
                uint256 availableBorrowsBase,
                uint256 currentLiquidationThreshold,
                uint256 ltv,
                uint256 healthFactor
            ) = borrowLendItem.debtAccountData();

            assertEq(totalCollateralBase, checkVals[0]);
            assertEq(totalDebtBase, checkVals[1]);
            assertEq(availableBorrowsBase, checkVals[2]);
            assertEq(healthFactor, checkVals[3]);
            assertEq(ltv, ltvValues[ind]);
            assertEq(currentLiquidationThreshold, liquidationTHs[ind]);
        }
    }
}

contract OrigamiAaveV3BorrowAndLendMultiDecimalsTestSupply is OrigamiAaveV3BorrowAndLendMultiDecimalsTestBase {
    function test_supply_fail() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            uint256 amount = supplyAmounts[ind];
            mintToken(info.supplyToken, address(borrowLendItem), amount);

            vm.startPrank(posOwner);
            revertPerToken(address(info.supplyToken));
            borrowLendItem.supply(amount + 1);
        }
    }

    function test_supply_success() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            uint256 amount = supplyAmounts[ind];
            mintToken(info.supplyToken, address(borrowLendItem), amount);

            vm.startPrank(posOwner);
            borrowLendItem.supply(amount);
            assertEq(borrowLendItem.suppliedBalance(), amount);
            assertEq(info.supplyToken.balanceOf(address(borrowLendItem)), 0);
        }
    }

    function test_withdraw_fail() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            uint256 amount = supplyAmounts[ind];
            supply(ind, amount);
            
            vm.expectRevert(bytes(AaveErrors.NOT_ENOUGH_AVAILABLE_USER_BALANCE));
            borrowLendItem.withdraw(amount + 1, alice);
        }
    }

    function test_withdraw_success() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            uint256 amount = supplyAmounts[ind];
            supply(ind, amount);
            
            uint256 amountOut = borrowLendItem.withdraw(amount / 2, alice);
            assertApproxEqAbs(amountOut, amount / 2, 1);
            assertApproxEqAbs(borrowLendItem.suppliedBalance(), amount / 2, 1);
            assertEq(info.supplyToken.balanceOf(address(posOwner)), 0);
            assertEq(info.supplyToken.balanceOf(address(borrowLendItem)), 0);
            assertEq(info.supplyToken.balanceOf(address(alice)), amount / 2);

            amountOut = borrowLendItem.withdraw(type(uint256).max, alice);
            assertApproxEqAbs(amountOut, amount / 2, 1);
            assertApproxEqAbs(info.supplyToken.balanceOf(address(alice)), amount, 1);
        }
    }

    function test_borrow_fail() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            supply(ind, supplyAmounts[ind]);

            vm.expectRevert(bytes(AaveErrors.COLLATERAL_CANNOT_COVER_NEW_BORROW));
            borrowLendItem.borrow(borrowAmounts[ind] * 10, alice);
        }
    }

    function test_borrow_success() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            uint256 beforeAliceSupplyBalance = info.supplyToken.balanceOf(address(alice));

            supply(ind, supplyAmounts[ind]);
            borrowLendItem.borrow(borrowAmounts[ind], alice);

            assertEq(borrowLendItem.suppliedBalance(), supplyAmounts[ind]);
            assertEq(borrowLendItem.debtBalance(), borrowAmounts[ind]);
            assertEq(info.supplyToken.balanceOf(address(posOwner)), 0);
            assertEq(info.supplyToken.balanceOf(address(borrowLendItem)), 0);
            assertEq(info.supplyToken.balanceOf(address(alice)), beforeAliceSupplyBalance);
            assertEq(info.borrowToken.balanceOf(address(posOwner)), 0);
            assertEq(info.borrowToken.balanceOf(address(borrowLendItem)), 0);
            assertEq(info.borrowToken.balanceOf(address(alice)), borrowAmounts[ind]);
        }
    }

    function test_repay_fail() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            supply(ind, supplyAmounts[ind]);
            borrowLendItem.borrow(borrowAmounts[ind], alice);

            mintToken(info.borrowToken, address(borrowLendItem), borrowAmounts[ind] / 2);

            vm.expectRevert();
            borrowLendItem.repay(borrowAmounts[ind]);
        }
    }

    function test_repay_success() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            uint256 beforeAliceSupplyBalance = info.supplyToken.balanceOf(address(alice));

            supply(ind, supplyAmounts[ind]);
            borrowLendItem.borrow(borrowAmounts[ind], alice);

            mintToken(info.borrowToken, address(borrowLendItem), borrowAmounts[ind] / 2);

            vm.startPrank(posOwner);
            uint256 amountRepaid = borrowLendItem.repay(borrowAmounts[ind] / 2);
            assertEq(amountRepaid, borrowAmounts[ind] / 2);
            assertEq(borrowLendItem.suppliedBalance(), supplyAmounts[ind]);
            assertApproxEqAbs(borrowLendItem.debtBalance(), borrowAmounts[ind] / 2, 1);
            assertEq(info.supplyToken.balanceOf(address(borrowLendItem)), 0);
            assertEq(info.supplyToken.balanceOf(address(alice)), beforeAliceSupplyBalance);
            assertEq(info.borrowToken.balanceOf(address(borrowLendItem)), 0);
            assertEq(info.borrowToken.balanceOf(address(alice)), borrowAmounts[ind]);

            mintToken(info.borrowToken, address(borrowLendItem), borrowAmounts[ind]);
            vm.startPrank(posOwner);
            amountRepaid = borrowLendItem.repay(borrowAmounts[ind]);
            assertApproxEqAbs(amountRepaid, borrowAmounts[ind] / 2, 1);
            assertEq(borrowLendItem.suppliedBalance(), supplyAmounts[ind]);
            assertEq(borrowLendItem.debtBalance(), 0);
            assertEq(info.supplyToken.balanceOf(address(borrowLendItem)), 0);
            assertEq(info.supplyToken.balanceOf(address(alice)), beforeAliceSupplyBalance);
            assertApproxEqAbs(info.borrowToken.balanceOf(address(borrowLendItem)), borrowAmounts[ind] / 2, 1);
            assertEq(info.borrowToken.balanceOf(address(alice)), borrowAmounts[ind]);

            amountRepaid = borrowLendItem.repay(borrowAmounts[ind]);
            assertEq(amountRepaid, 0);
            assertEq(borrowLendItem.suppliedBalance(), supplyAmounts[ind]);
            assertEq(borrowLendItem.debtBalance(), 0);
            assertEq(info.supplyToken.balanceOf(address(borrowLendItem)), 0);
            assertEq(info.supplyToken.balanceOf(address(alice)), beforeAliceSupplyBalance);
            assertApproxEqAbs(info.borrowToken.balanceOf(address(borrowLendItem)), borrowAmounts[ind] / 2, 1);
            assertEq(info.borrowToken.balanceOf(address(alice)), borrowAmounts[ind]);

            // recover remaing borrowToken to alice
            vm.startPrank(origamiMultisig);
            borrowLendItem.recoverToken(address(info.borrowToken), alice, info.borrowToken.balanceOf(address(borrowLendItem)));
            assertEq(info.borrowToken.balanceOf(address(borrowLendItem)), 0);
            assertApproxEqAbs(info.borrowToken.balanceOf(address(alice)), borrowAmounts[ind] * 3 / 2, 1);
        }
    }

    function test_supplyAndBorrow_success() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;
        
            mintToken(info.supplyToken, address(borrowLendItem), supplyAmounts[ind]);

            uint256 beforeAliceSupplyBalance = info.supplyToken.balanceOf(address(alice));
            
            vm.startPrank(posOwner);
            borrowLendItem.supplyAndBorrow(supplyAmounts[ind], borrowAmounts[ind], alice);

            assertEq(borrowLendItem.suppliedBalance(), supplyAmounts[ind]);
            assertEq(borrowLendItem.debtBalance(), borrowAmounts[ind]);
            assertEq(info.supplyToken.balanceOf(address(borrowLendItem)), 0);
            assertEq(info.supplyToken.balanceOf(address(alice)), beforeAliceSupplyBalance);
            assertEq(info.borrowToken.balanceOf(address(borrowLendItem)), 0);
            assertEq(info.borrowToken.balanceOf(address(alice)), borrowAmounts[ind]);
        }
    }

    function test_repayAndWithdraw_success() public {
        for(uint256 ind; ind < borrowLendCount; ++ind) {
            BorrowLendContract storage info = borrowLendContracts[ind];
            OrigamiAaveV3BorrowAndLend borrowLendItem = info.borrowLend;

            mintToken(info.supplyToken, address(borrowLendItem), supplyAmounts[ind]);

            uint256 beforeAliceSupplyBalance = info.supplyToken.balanceOf(address(alice));

            uint256 beforeAliceBorrow = info.borrowToken.balanceOf(address(alice));
            
            vm.startPrank(posOwner);
            borrowLendItem.supplyAndBorrow(supplyAmounts[ind], borrowAmounts[ind], alice);

            mintToken(info.borrowToken, address(borrowLendItem), borrowAmounts[ind] / 2);

            vm.startPrank(posOwner);
            (uint256 debtRepaidAmount, uint256 withdrawnAmount) = borrowLendItem.repayAndWithdraw(borrowAmounts[ind] / 2, supplyAmounts[ind] / 2, alice);

            assertApproxEqAbs(debtRepaidAmount, borrowAmounts[ind] / 2, 1);
            assertEq(withdrawnAmount, supplyAmounts[ind] / 2);
            
            assertApproxEqAbs(borrowLendItem.suppliedBalance(), supplyAmounts[ind] / 2, 1);
            assertApproxEqAbs(borrowLendItem.debtBalance(), borrowAmounts[ind] / 2, 1);
            assertEq(info.supplyToken.balanceOf(address(borrowLendItem)), 0);
            assertEq(info.supplyToken.balanceOf(address(alice)), beforeAliceSupplyBalance + supplyAmounts[ind] / 2);
            assertEq(info.borrowToken.balanceOf(address(borrowLendItem)), 0);
            assertEq(info.borrowToken.balanceOf(address(alice)), beforeAliceBorrow + borrowAmounts[ind]);
        }
    }
}