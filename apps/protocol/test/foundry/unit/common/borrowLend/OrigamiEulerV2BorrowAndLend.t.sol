pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { stdError } from "forge-std/StdError.sol";
import { Test } from "forge-std/Test.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiEulerV2BorrowAndLend } from "contracts/common/borrowAndLend/OrigamiEulerV2BorrowAndLend.sol";
import { IOrigamiEulerV2BorrowAndLend } from
    "contracts/interfaces/common/borrowAndLend/IOrigamiEulerV2BorrowAndLend.sol";
import { DummyLovTokenSwapper } from "contracts/test/investments/lovToken/DummyLovTokenSwapper.sol";
import { EVCUtil } from "contracts/external/ethereum-vault-connector/utils/EVCUtil.sol";

import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";
import { IOrigamiBorrowAndLend } from "contracts/interfaces/common/borrowAndLend/IOrigamiBorrowAndLend.sol";

import { IEVC } from "contracts/interfaces/external/ethereum-vault-connector/IEthereumVaultConnector.sol";
import { IEVKEVault as IEVault } from "contracts/interfaces/external/euler/IEVKEVault.sol";
import { AmountCap, AmountCapLib } from "contracts/external/euler-vault-kit/AmountCapLib.sol";

import { stdStorage, StdStorage } from "forge-std/Test.sol";

contract MockMerklDistributor {

    /// @notice User -> Operator -> authorisation to claim on behalf of the user
    mapping(address => mapping(address => uint256)) public operators;

    /// @notice user -> token -> recipient address for when user claims `token`
    /// @dev If the mapping is empty, by default rewards will accrue on the user address
    mapping(address => mapping(address => address)) public claimRecipient;

    event OperatorToggled(address indexed user, address indexed operator, bool isWhitelisted);
    event ClaimRecipientUpdated(address indexed user, address indexed token, address indexed recipient);

    /// @notice Toggles whitelisting for a given user and a given operator
    /// @dev When an operator is whitelisted for a user, the operator can claim rewards on behalf of the user
    function toggleOperator(address user, address operator) external {
        uint256 oldValue = operators[user][operator];
        operators[user][operator] = 1 - oldValue;
        emit OperatorToggled(user, operator, oldValue == 0);
    }

    /// @notice Sets a recipient for a user claiming rewards for a token
    /// @dev This is an optional functionality and if the `recipient` is set to the zero address, then
    /// the user will still accrue all rewards to its address
    /// @dev Users may still specify a different recipient when they claim token rewards with the
    /// `claimWithRecipient` function
    function setClaimRecipient(address recipient, address token) external {
        claimRecipient[msg.sender][token] = recipient;
        emit ClaimRecipientUpdated(msg.sender, token, recipient);
    }
}

contract MainnetAddressesForEulerTests is OrigamiTest {
    // Euler contracts deployed on ETHEREUM MAINNET
    IERC20 internal constant wstEth = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IERC20 internal constant wETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IEVC internal constant eulerEVC = IEVC(0x0C9a3dd6b8F28529d72d7f9cE918D493519EE383);

    // only for recover token tests
    IERC20 internal constant dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    // Euler has governableWhitelistPerspective [0xCDa58e1eB35BF2A510c166D86A860340208C125D]
    // which exposes the verifiedArray() method.
    // That returns an array of vaults deployed by their factory, of which 2 are WETH vaults and 2 are wstETH.
    // From the WETH vaults, I took the one that already has cashs, and a positive totalBorrows
    // From the wstETH vaults, both looked pretty dead, but both had a non-zero IRM,
    // which makes me think they are not escrow vaults, but base vaults, which is what we would use
    IEVault internal constant borrowVault = IEVault(0xD8b27CF359b7D15710a5BE299AF6e7Bf904984C2); // asset = WETH
    IEVault internal constant supplyVault = IEVault(0xbC4B4AC47582c3E38Ce5940B80Da65401F4628f1); // asset = wstETH

    function setUp() public virtual {
        fork("mainnet", 20_715_366);
        vm.warp(1_725_912_806);
    }
}

contract OrigamiEulerV2BorrowAndLendTestBase is OrigamiTest, MainnetAddressesForEulerTests {
    using AmountCapLib for AmountCap;

    OrigamiEulerV2BorrowAndLend internal borrowLend;
    DummyLovTokenSwapper swapper;

    // just to be able to generalize the tests later on
    IERC20 internal constant supplyToken = wstEth;
    IERC20 internal constant borrowToken = wETH;

    address public posOwner = makeAddr("posOwner");
    address public randomUser = makeAddr("randomUser");
    address public user = makeAddr("user");
    address angel = makeAddr("angel");

    // useful error selectors for the tests
    error E_AmountTooLargeToEncode();
    error E_InsufficientCash();
    error E_NoLiability();
    error E_InsufficientBalance();
    error E_RepayTooMuch();
    error E_AccountLiquidity();
    error EVC_EmptyError();
    error EVC_OnBehalfOfAccountNotAuthenticated();

    function setUp() public virtual override {
        // here setup the contract addresses and the fork depending on the network
        super.setUp();

        borrowLend = new OrigamiEulerV2BorrowAndLend(
            origamiMultisig, // initialOwner
            address(supplyToken), // supplyToken
            address(borrowToken), // borrowToken
            address(supplyVault), // supplyVault
            address(borrowVault), // borrowVault
            address(eulerEVC) // ethereumVaultConnector
        );

        swapper = new DummyLovTokenSwapper();

        vm.startPrank(origamiMultisig);
        borrowLend.setPositionOwner(posOwner);
        borrowLend.setSwapper(address(swapper));
        vm.stopPrank();

        //////////////// Setup Vaults in a normal state //////////////

        // This `angel` will help us have vaults with:
        // - some cash in the borrowVault to borrow from
        // - some cash in the supplyVault, and some borrows, so that our supplied tokens accrue interests

        deal(address(borrowToken), angel, 1000 ether);
        deal(address(supplyToken), angel, 1000 ether);

        vm.startPrank(angel);
        borrowToken.approve(address(borrowVault), type(uint256).max);
        borrowVault.deposit(1000 ether, angel);

        supplyToken.approve(address(supplyVault), type(uint256).max);
        supplyVault.deposit(1000 ether, angel);

        // this user will have the opposite controller/collateral pattern than the borrowLend contract,
        // so that he can  borrow from the supplyVault
        eulerEVC.enableController(angel, address(supplyVault));
        eulerEVC.enableCollateral(angel, address(borrowVault));
        supplyVault.borrow(50 ether, angel);
        vm.stopPrank();
    }

    //////////////////// utility functions

    function posOwnerSupplies(uint256 amount) public {
        deal(address(supplyToken), address(borrowLend), amount);
        vm.prank(posOwner);
        borrowLend.supply(amount);
    }

    //////////////////// actual tests

    function test_initialization() public view {
        assertEq(borrowLend.owner(), origamiMultisig);
        assertEq(borrowLend.positionOwner(), posOwner);
        assertEq(address(borrowLend.swapper()), address(swapper));

        assertEq(borrowLend.supplyToken(), address(wstEth));
        assertEq(borrowLend.borrowToken(), address(wETH));
        assertEq(borrowLend.supplyToken(), supplyVault.asset());
        assertEq(borrowLend.borrowToken(), borrowVault.asset());

        assertEq(address(borrowLend.supplyVault()), address(supplyVault));
        assertEq(address(borrowLend.borrowVault()), address(borrowVault));
        assertEq(address(borrowLend.eulerEVC()), address(eulerEVC));

        // permissions and setup
        assertEq(supplyToken.allowance(address(borrowLend), address(supplyVault)), type(uint256).max);
        assertEq(borrowToken.allowance(address(borrowLend), address(borrowVault)), type(uint256).max);
        // EVC should never have permissions as it allows arbitrary calls to any address
        assertEq(supplyToken.allowance(address(borrowLend), address(eulerEVC)), 0);
        assertEq(borrowToken.allowance(address(borrowLend), address(eulerEVC)), 0);

        assertTrue(eulerEVC.isCollateralEnabled(address(borrowLend), address(supplyVault)));
        assertTrue(eulerEVC.isControllerEnabled(address(borrowLend), address(borrowVault)));
        // we don't need permit2 for the borrow lend as we manage allowances granularly
        bytes19 addressPrefix = eulerEVC.getAddressPrefix(address(borrowLend));
        assertTrue(eulerEVC.isPermitDisabledMode(addressPrefix));
        assertTrue(eulerEVC.isLockdownMode(addressPrefix));
    }
}

contract TestAssumptionsOnEulerEVaults is OrigamiEulerV2BorrowAndLendTestBase {
    // this tests some assumptions about how the Euler Vaults work
    // the borrower would be the equivalent of the BorrowAndLend contract
    using AmountCapLib for AmountCap;

    address borrower = makeAddr("borrower");
    address otherUser = makeAddr("otherUser");

    error E_SupplyCapExceeded();
    error E_BorrowCapExceeded();

    function setUp() public override {
        super.setUp();

        // the borrow vault has very little cash, so we should deposit some
        deal(address(borrowToken), otherUser, 1000 ether);

        vm.startPrank(otherUser);
        borrowToken.approve(address(borrowVault), type(uint256).max);
        borrowVault.deposit(1000 ether, otherUser);
        vm.stopPrank();

        vm.startPrank(borrower);
        // approve vaults to deposit / repay
        supplyToken.approve(address(supplyVault), type(uint256).max);
        borrowToken.approve(address(borrowVault), type(uint256).max);
        // setup EVC system for the borrower
        eulerEVC.enableCollateral(borrower, address(supplyVault));
        eulerEVC.enableController(borrower, address(borrowVault));
        vm.stopPrank();
    }

    modifier deposit(uint256 amount, address depositor) {
        deal(address(supplyToken), depositor, amount);
        vm.prank(depositor);
        supplyVault.deposit(amount, depositor);
        _;
    }

    //////////////////////////////////////////////////

    function test_basicDeposit() public {
        uint256 depositAmount = 1 ether;
        deal(address(supplyToken), borrower, depositAmount);

        vm.startPrank(borrower);
        supplyVault.deposit(depositAmount, borrower);
        assertApproxEqRel(supplyVault.convertToAssets(supplyVault.balanceOf(borrower)), depositAmount, 1e6);
        vm.stopPrank();
    }

    function test_basicWithdraw() public deposit(100 ether, borrower) {
        uint256 withdrawAmount = 1 ether;
        uint256 balanceBefore = supplyToken.balanceOf(borrower);

        vm.startPrank(borrower);
        supplyVault.withdraw(withdrawAmount, borrower, borrower);

        assertEq(supplyToken.balanceOf(borrower), balanceBefore + withdrawAmount);
    }

    function test_fullWithdraw() public deposit(0.12342341 ether, borrower) {
        uint256 walletBalanceBefore = supplyToken.balanceOf(borrower);

        vm.startPrank(borrower);
        supplyVault.redeem(type(uint256).max, borrower, borrower);
        assertEq(supplyVault.balanceOf(borrower), 0);
        // The minus-one here is to account for rounding errors when redeeming. The user should get back the exact
        // deposit, but it is never the case.
        assertEq(supplyToken.balanceOf(borrower), walletBalanceBefore + 0.12342341 ether - 1);
    }

    function test_basicBorrow() public deposit(1000 ether, borrower) {
        uint256 borrowAmount = 1 ether;

        assertGt(borrowVault.cash(), borrowAmount);
        uint256 balanceBefore = borrowToken.balanceOf(borrower);

        assertEq(borrowVault.debtOf(borrower), 0);

        vm.prank(borrower);
        borrowVault.borrow(borrowAmount, borrower);
        assertEq(borrowToken.balanceOf(borrower), balanceBefore + borrowAmount);
        assertEq(borrowVault.debtOf(borrower), borrowAmount);
    }

    function test_borrowingMoreThanAvailableReverts() public deposit(1000 ether, borrower) {
        uint256 availableInVault = borrowVault.cash();
        assertGt(availableInVault, 0);

        vm.expectRevert(E_InsufficientCash.selector);
        vm.prank(borrower);
        borrowVault.borrow(availableInVault + 1, borrower);
    }

    /// @dev as the liquidity in the borrowVault is large, to borrow the entire cash(), the borrower needs to make first
    /// a huge deposit
    function test_borrowMaxAmountInferredFromCash() public deposit(10_000 ether, borrower) {
        uint256 availableInVault = borrowVault.cash();
        assertGt(availableInVault, 0);

        vm.prank(borrower);
        borrowVault.borrow(availableInVault, borrower);
    }

    function test_basicBorrowRepay() public deposit(100 ether, borrower) {
        uint256 borrowAmount = 1 ether;
        uint256 repayAmount = 0.5 ether;

        vm.startPrank(borrower);
        borrowVault.borrow(borrowAmount, borrower);
        skip(30 days);

        // debt is expressed in the underlying token (== borrow token, not shares)
        uint256 initialDebt = borrowVault.debtOf(borrower);
        borrowVault.repay(repayAmount, borrower);
        uint256 endDebt = borrowVault.debtOf(borrower);
        assertEq(endDebt, initialDebt - repayAmount);
    }

    function test_repayMoreThanOutstandingDebt() public deposit(100 ether, borrower) {
        // the borrower has some extra borrowToken (to repay more than borrowed)
        deal(address(borrowToken), borrower, 1 ether);
        uint256 borrowAmount = 1 ether;

        vm.startPrank(borrower);
        borrowVault.borrow(borrowAmount, borrower);
        skip(30 days);

        uint256 outstandingDebt = borrowVault.debtOf(borrower);

        vm.expectRevert(E_RepayTooMuch.selector);
        borrowVault.repay(outstandingDebt + 0.1 ether, borrower);
    }

    function test_maxWithdrawView() public deposit(100 ether, borrower) {
        // note that these two only give information about the assets that we would get back IF we could redeem all of
        // the shares
        // and if we didn't have any outstanding debt
        assertApproxEqAbs(supplyVault.convertToAssets(supplyVault.balanceOf(borrower)), 100 ether, 1);
        assertApproxEqAbs(supplyVault.previewRedeem(supplyVault.balanceOf(borrower)), 100 ether, 1);

        // maxWithdraw is not supported by the EVaults
        // so we have to assume there is no debt, and
        assertApproxEqAbs(supplyVault.previewRedeem(supplyVault.balanceOf(borrower)), 100 ether, 1);

        // but If we try to redeem all of our shares, we should get all of our collateral back
        vm.startPrank(borrower);
        supplyToken.approve(address(supplyVault), type(uint256).max);
        supplyVault.redeem(supplyVault.balanceOf(borrower), borrower, borrower);
        assertApproxEqAbs(supplyToken.balanceOf(borrower), 100 ether, 1);
        assertEq(supplyVault.balanceOf(borrower), 0);
        assertEq(supplyVault.balanceOf(borrower), 0);
    }

    function test_EVault_supplyCap() public {
        address governorAdmin = supplyVault.governorAdmin();

        vm.prank(governorAdmin);
        supplyVault.setCaps(10_000, 0); // 0.0156 ether as cap

        (uint16 wrappedSupplyCap,) = supplyVault.caps();
        assertEq(wrappedSupplyCap, 10_000);
        uint256 supplyCap = AmountCap.wrap(wrappedSupplyCap).resolve();

        deal(address(supplyToken), borrower, 1 ether);
        vm.prank(borrower);
        vm.expectRevert(E_SupplyCapExceeded.selector);
        supplyVault.deposit(supplyCap * 2, borrower);
    }

    function test_EVault_borrowCap() public deposit(10 ether, borrower) {
        address governorAdmin = supplyVault.governorAdmin();

        vm.prank(governorAdmin);
        borrowVault.setCaps(0, 10_000); // 0.0156 ether as cap

        uint256 borrowAmount = 0.2 ether;
        vm.prank(borrower);
        vm.expectRevert(E_BorrowCapExceeded.selector);
        borrowVault.borrow(borrowAmount, borrower);
    }

    function test_EVault_borrowWithNoCaps() public deposit(10 ether, borrower) {
        uint256 borrowAmount = 0.2 ether;

        vm.prank(borrower);
        borrowVault.borrow(borrowAmount, borrower);

        assertEq(borrowVault.debtOf(borrower), borrowAmount);
    }
}

contract OrigamiEulerBorrowAndLendTestAdminTests is OrigamiEulerV2BorrowAndLendTestBase {
    function test_constructor_fail_zeroAddresses() public {
        // address 0 for different inputs would fail

        vm.expectRevert();
        borrowLend = new OrigamiEulerV2BorrowAndLend(
            origamiMultisig, // initialOwner
            address(0), // supplyToken
            address(borrowToken), // borrowToken
            address(supplyVault), // supplyVault
            address(borrowVault), // borrowVault
            address(eulerEVC) // ethereumVaultConnector
        );

        vm.expectRevert();
        borrowLend = new OrigamiEulerV2BorrowAndLend(
            origamiMultisig, // initialOwner
            address(supplyToken), // supplyToken
            address(0), // borrowToken
            address(supplyVault), // supplyVault
            address(borrowVault), // borrowVault
            address(eulerEVC) // ethereumVaultConnector
        );

        vm.expectRevert();
        borrowLend = new OrigamiEulerV2BorrowAndLend(
            origamiMultisig, // initialOwner
            address(supplyToken), // supplyToken
            address(borrowToken), // borrowToken
            address(0), // supplyVault
            address(borrowVault), // borrowVault
            address(eulerEVC) // ethereumVaultConnector
        );

        vm.expectRevert();
        borrowLend = new OrigamiEulerV2BorrowAndLend(
            origamiMultisig, // initialOwner
            address(supplyToken), // supplyToken
            address(borrowToken), // borrowToken
            address(supplyVault), // supplyVault
            address(0), // borrowVault
            address(eulerEVC) // ethereumVaultConnector
        );

        vm.expectRevert();
        borrowLend = new OrigamiEulerV2BorrowAndLend(
            origamiMultisig, // initialOwner
            address(supplyToken), // supplyToken
            address(borrowToken), // borrowToken
            address(supplyVault), // supplyVault
            address(borrowVault), // borrowVault
            address(0) // ethereumVaultConnector
        );
    }

    function test_constructor_fail_vaultWithWrongAssets() public {
        // swapping supply and borrow vaults should fail
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(supplyVault)));
        borrowLend = new OrigamiEulerV2BorrowAndLend(
            origamiMultisig, // initialOwner
            address(supplyToken), // supplyToken
            address(borrowToken), // borrowToken
            address(borrowVault), // supplyVault
            address(supplyVault), // borrowVault
            address(eulerEVC) // ethereumVaultConnector
        );

        // same vault for both should also fail
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(supplyVault)));
        borrowLend = new OrigamiEulerV2BorrowAndLend(
            origamiMultisig, // initialOwner
            address(supplyToken), // supplyToken
            address(borrowToken), // borrowToken
            address(supplyVault), // supplyVault
            address(supplyVault), // borrowVault
            address(eulerEVC) // ethereumVaultConnector
        );
    }

    function test_constructor_fail_sameBorrowAndSupplyToken() public {
        // swapping supply and borrow vaults should fail
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(supplyToken)));
        borrowLend = new OrigamiEulerV2BorrowAndLend(
            origamiMultisig, // initialOwner
            address(supplyToken), // supplyToken
            address(supplyToken), // borrowToken
            address(supplyVault), // supplyVault
            address(borrowVault), // borrowVault
            address(eulerEVC) // ethereumVaultConnector
        );
    }

    function test_setPositionOwner_success() public {
        vm.prank(origamiMultisig);
        vm.expectEmit();
        emit IOrigamiBorrowAndLend.PositionOwnerSet(user);
        borrowLend.setPositionOwner(user);
        assertEq(borrowLend.positionOwner(), user);
    }

    function test_setPositionOwner_address0() public {
        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        borrowLend.setPositionOwner(address(0));
    }

    function test_setSwapper_success() public {
        vm.prank(origamiMultisig);
        vm.expectEmit();
        emit IOrigamiEulerV2BorrowAndLend.SwapperSet(user);
        borrowLend.setSwapper(user);
        assertEq(address(borrowLend.swapper()), user);
    }

    function test_setSwapper_address0() public {
        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        borrowLend.setSwapper(address(0));
    }

    function test_setSwapper_approvals() public {
        assertEq(supplyToken.allowance(address(borrowLend), address(swapper)), type(uint256).max);
        assertEq(borrowToken.allowance(address(borrowLend), address(swapper)), type(uint256).max);

        DummyLovTokenSwapper newSwapper = new DummyLovTokenSwapper();

        vm.prank(origamiMultisig);
        borrowLend.setSwapper(address(newSwapper));

        assertEq(supplyToken.allowance(address(borrowLend), address(swapper)), 0);
        assertEq(borrowToken.allowance(address(borrowLend), address(swapper)), 0);
        assertEq(supplyToken.allowance(address(borrowLend), address(newSwapper)), type(uint256).max);
        assertEq(borrowToken.allowance(address(borrowLend), address(newSwapper)), type(uint256).max);
    }

    function test_merklToggleOperator_access() public {
        expectElevatedAccess();
        borrowLend.merklToggleOperator(alice, alice);
    }

    function test_merklToggleOperator_success() public {
        MockMerklDistributor distributor = new MockMerklDistributor();
        assertEq(distributor.operators(address(borrowLend), alice), 0);
        vm.prank(origamiMultisig);
        borrowLend.merklToggleOperator(address(distributor), alice);
        assertEq(distributor.operators(address(borrowLend), alice), 1);
    }

    function test_merklSetClaimRecipient_access() public {
        expectElevatedAccess();
        borrowLend.merklSetClaimRecipient(alice, alice, alice);
    }

    function test_merklSetClaimRecipient_success() public {
        MockMerklDistributor distributor = new MockMerklDistributor();
        assertEq(distributor.claimRecipient(address(borrowLend), address(wstEth)), address(0));
        vm.prank(origamiMultisig);
        borrowLend.merklSetClaimRecipient(address(distributor), alice, address(wstEth));
        assertEq(distributor.claimRecipient(address(borrowLend), address(wstEth)), alice);
    }

    function test_recoverToken_success() public {
        uint256 donatedAmount = 1234e18;
        uint256 recoverAmount = 1000e18;
        deal(address(dai), address(borrowLend), donatedAmount);

        vm.prank(origamiMultisig);
        borrowLend.recoverToken(address(dai), randomUser, recoverAmount);
        assertEq(dai.balanceOf(randomUser), recoverAmount);
    }

    function test_recoverToken() public {
        // this also checks event is emitted
        check_recoverToken(address(borrowLend));
    }

    function test_recoverSupplyAndBorrowToken() public {
        // recovering supply/borrow tokens is fine because they are not meant to be in the contract (no surplus
        // management)
        uint256 donatedAmount = 1234e18;
        uint256 recoverAmount = 1000e18;

        deal(address(supplyToken), address(borrowLend), donatedAmount);
        vm.prank(origamiMultisig);
        borrowLend.recoverToken(address(supplyToken), randomUser, recoverAmount);
        assertEq(supplyToken.balanceOf(randomUser), recoverAmount);

        deal(address(borrowToken), address(borrowLend), donatedAmount);
        vm.prank(origamiMultisig);
        borrowLend.recoverToken(address(borrowToken), randomUser, recoverAmount);
        assertEq(borrowToken.balanceOf(randomUser), recoverAmount);
    }

    function test_recoverToken_recoveringVaultSharesIsForbidden() public {
        // user deposits collateral and donates the shares to borrowlend
        deal(address(supplyToken), user, 1000 ether);
        vm.startPrank(user);
        supplyToken.approve(address(supplyVault), type(uint256).max);
        supplyVault.deposit(1000 ether, user);
        // now we are transfering to the borrowLend the shares received in the deposit
        uint256 shares = supplyVault.balanceOf(user);
        supplyVault.transfer(address(borrowLend), shares);
        assertEq(supplyVault.balanceOf(address(borrowLend)), shares);
        vm.stopPrank();

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(supplyVault)));
        borrowLend.recoverToken(address(supplyVault), randomUser, shares);
    }
}

contract MaliciousCallerViaEVC is EVCUtil {
    OrigamiEulerV2BorrowAndLend borrowLendToAttack;

    constructor(address _evc, address _borrowLend) EVCUtil(_evc) {
        borrowLendToAttack = OrigamiEulerV2BorrowAndLend(_borrowLend);
    }

    function callOnlyElevatedAccessFunctionFromBorrowLend_increaseLeverage() public callThroughEVC {
        uint256 supplyAmount = 1 ether;
        bytes memory swapData = abi.encode(supplyAmount);
        borrowLendToAttack.increaseLeverage(supplyAmount, 0.5 ether, swapData, 0);
    }

    function callOnlyElevatedAccessFunctionFromBorrowLend_decreaseLeverage() public callThroughEVC {
        uint256 minBorrowTokensReceived = 1 ether;
        bytes memory swapData = abi.encode(minBorrowTokensReceived);
        borrowLendToAttack.decreaseLeverage(minBorrowTokensReceived, 0.5 ether, swapData, 0);
    }
}

contract OrigamiEulerBorrowAndLendTestAccess is OrigamiEulerV2BorrowAndLendTestBase {
    function setUp() public override {
        super.setUp();
        // The borrowLend needs to have tokens in balance before supplying/repaying can work.
        // the error thrown by EVault otherwise is a horrendous bytes 224 error from
        //  Permit2 that we would have to compose for every scenario
        deal(address(supplyToken), address(borrowLend), 10 ether);
        deal(address(borrowToken), address(borrowLend), 10 ether);
    }

    function test_access_setPositionOwner() public {
        expectElevatedAccess();
        borrowLend.setPositionOwner(alice);
    }

    function test_access_setSwapper() public {
        expectElevatedAccess();
        borrowLend.setSwapper(address(alice));
    }

    function test_access_recoverToken() public {
        expectElevatedAccess();
        borrowLend.recoverToken(address(borrowToken), alice, 100e18);
    }

    function test_access_supply() public {
        expectElevatedAccess();
        borrowLend.supply(5);

        vm.prank(posOwner);
        borrowLend.supply(5);

        vm.prank(origamiMultisig);
        borrowLend.supply(5);
    }

    function test_access_withdraw() public {
        expectElevatedAccess();
        borrowLend.withdraw(5, alice);

        vm.prank(posOwner);
        vm.expectRevert(E_InsufficientBalance.selector);
        borrowLend.withdraw(5, alice);

        vm.prank(origamiMultisig);
        vm.expectRevert(E_InsufficientBalance.selector);
        borrowLend.withdraw(5, alice);
    }

    function test_access_borrow() public {
        expectElevatedAccess();
        borrowLend.borrow(5, alice);

        vm.prank(posOwner);
        vm.expectRevert(E_AccountLiquidity.selector);
        borrowLend.borrow(5, alice);

        vm.prank(origamiMultisig);
        vm.expectRevert(E_AccountLiquidity.selector);
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
        vm.expectRevert(E_InsufficientBalance.selector);
        borrowLend.repayAndWithdraw(5, 5, alice);

        vm.prank(origamiMultisig);
        vm.expectRevert(E_InsufficientBalance.selector);
        borrowLend.repayAndWithdraw(5, 5, alice);
    }

    function test_access_supplyAndBorrow() public {
        expectElevatedAccess();
        borrowLend.supplyAndBorrow(5, 5, alice);

        vm.prank(posOwner);
        vm.expectRevert(E_AccountLiquidity.selector);
        borrowLend.supplyAndBorrow(5, 5, alice);

        vm.prank(origamiMultisig);
        vm.expectRevert(E_AccountLiquidity.selector);
        borrowLend.supplyAndBorrow(5, 5, alice);
    }

    function test_access_increaseLeverage() public {
        // this is an unauthorized user
        expectElevatedAccess();
        borrowLend.increaseLeverage(5, 5, "", 0);

        vm.prank(posOwner);
        vm.expectRevert(EVC_EmptyError.selector);
        borrowLend.increaseLeverage(5, 5, "", 0);

        vm.prank(origamiMultisig);
        vm.expectRevert(EVC_EmptyError.selector);
        borrowLend.increaseLeverage(5, 5, "", 0);

        // arbitrary calls from the eulerEVC are forbidden (unless initiated by elevatedAccess)
        vm.prank(address(eulerEVC));
        vm.expectRevert(EVC_OnBehalfOfAccountNotAuthenticated.selector);
        borrowLend.increaseLeverage(5, 5, "", 0);
    }

    function test_granted_access_increaseLeverage_with_selector() public {
        address leverageManager = makeAddr("leverageManager");
        assertFalse(borrowLend.explicitFunctionAccess(leverageManager, borrowLend.increaseLeverage.selector));

        IOrigamiElevatedAccess.ExplicitAccess[] memory access = new IOrigamiElevatedAccess.ExplicitAccess[](1);

        access[0] =
            IOrigamiElevatedAccess.ExplicitAccess({ fnSelector: borrowLend.increaseLeverage.selector, allowed: true });

        vm.prank(origamiMultisig);
        borrowLend.setExplicitAccess(leverageManager, access);
        // now this guy should have access to the increaseLeverage function
        assertTrue(borrowLend.explicitFunctionAccess(leverageManager, borrowLend.increaseLeverage.selector));

        // so the error should not be access-related, but another euler error
        vm.prank(leverageManager);
        vm.expectRevert(EVC_EmptyError.selector);
        borrowLend.increaseLeverage(5, 5, "", 0);
    }

    function test_callFromMaliciousContract_via_EVC() public {
        address attacker = makeAddr("attacker");
        vm.startPrank(attacker);
        MaliciousCallerViaEVC maliciousContract = new MaliciousCallerViaEVC(address(eulerEVC), address(borrowLend));

        vm.expectRevert(CommonEventsAndErrors.InvalidAccess.selector);
        maliciousContract.callOnlyElevatedAccessFunctionFromBorrowLend_increaseLeverage();

        vm.expectRevert(CommonEventsAndErrors.InvalidAccess.selector);
        maliciousContract.callOnlyElevatedAccessFunctionFromBorrowLend_decreaseLeverage();
    }

    function test_access_decreaseLeverage_euler() public {
        expectElevatedAccess();
        borrowLend.decreaseLeverage(5, 5, "", 0);

        vm.prank(posOwner);
        vm.expectRevert(E_InsufficientBalance.selector);
        borrowLend.decreaseLeverage(5, 5, "", 0);

        vm.prank(origamiMultisig);
        vm.expectRevert(E_InsufficientBalance.selector);
        borrowLend.decreaseLeverage(5, 5, "", 0);

        // arbitrary calls from the eulerEVC are forbidden (unless initiated by elevatedAccess)
        vm.prank(address(eulerEVC));
        vm.expectRevert(EVC_OnBehalfOfAccountNotAuthenticated.selector);
        borrowLend.decreaseLeverage(5, 5, "", 0);
    }

    function test_granted_access_decreaseLeverage_with_selector() public {
        address leverageManager = makeAddr("leverageManager");
        assertFalse(borrowLend.explicitFunctionAccess(leverageManager, borrowLend.decreaseLeverage.selector));

        IOrigamiElevatedAccess.ExplicitAccess[] memory access = new IOrigamiElevatedAccess.ExplicitAccess[](1);

        access[0] =
            IOrigamiElevatedAccess.ExplicitAccess({ fnSelector: borrowLend.decreaseLeverage.selector, allowed: true });

        vm.prank(origamiMultisig);
        borrowLend.setExplicitAccess(leverageManager, access);
        // now this guy should have access to the decreaseLeverage function
        assertTrue(borrowLend.explicitFunctionAccess(leverageManager, borrowLend.decreaseLeverage.selector));

        // so the error should not be access-related, but another euler error
        vm.prank(leverageManager);
        vm.expectRevert(E_InsufficientBalance.selector);
        borrowLend.decreaseLeverage(5, 5, "", 0);
    }
}

contract OrigamiEulerBorrowAndLendTestViews is OrigamiEulerV2BorrowAndLendTestBase {
    using AmountCapLib for AmountCap;

    function test_suppliedBalance_success() public {
        assertEq(borrowLend.suppliedBalance(), 0);
        uint256 suppliedAmount = 10 ether;

        posOwnerSupplies(suppliedAmount);
        assertApproxEqAbs(borrowLend.suppliedBalance(), suppliedAmount, 1);

        skip(30 days);

        // supplied balance increases as interests are accrued
        uint256 suppliedPlusInterests = borrowLend.suppliedBalance();
        assertGt(suppliedPlusInterests, suppliedAmount);

        uint256 withdrawnAmount = 1 ether;
        vm.prank(posOwner);
        borrowLend.withdraw(withdrawnAmount, posOwner);
        assertApproxEqAbs(borrowLend.suppliedBalance(), suppliedPlusInterests - withdrawnAmount, 1);
    }

    function test_suppliedBalance_withDonation_included() public {
        assertEq(borrowLend.suppliedBalance(), 0);

        uint256 suppliedAmount = 10 ether;
        posOwnerSupplies(suppliedAmount);
        assertApproxEqAbs(borrowLend.suppliedBalance(), suppliedAmount, 1);

        // donation from another address with the borrow lend as recipient
        deal(address(supplyToken), randomUser, suppliedAmount);
        vm.startPrank(randomUser);
        supplyToken.approve(address(supplyVault), type(uint256).max);
        supplyVault.deposit(suppliedAmount, address(borrowLend));
        vm.stopPrank();
        assertApproxEqAbs(borrowLend.suppliedBalance(), 2 * suppliedAmount, 1);

        // and the posOwner shoudl be able to withdraw all the deposited supplyToken
        uint256 balanceBefore = supplyToken.balanceOf(posOwner);
        vm.prank(posOwner);
        // we cant withdraw the exact amount because of the rounding issues
        borrowLend.withdraw(2 * suppliedAmount - 1, posOwner);
        assertApproxEqAbs(supplyToken.balanceOf(posOwner), balanceBefore + 2 * suppliedAmount, 1);
    }

    function test_withdrawMoreThanMaxWithdraw() public {
        assertEq(borrowLend.availableToWithdraw(), 0);

        uint256 suppliedAmount = 10 ether;
        posOwnerSupplies(suppliedAmount);

        uint256 maxWithdraw = borrowLend.availableToWithdraw();
        assertLe(maxWithdraw, suppliedAmount);

        vm.startPrank(posOwner);
        // we should be able to withdraw more than the max withdraw
        vm.expectRevert(E_InsufficientBalance.selector);
        borrowLend.withdraw(maxWithdraw + 1, address(borrowLend));

        // but we should be 100% able to withdraw maxWithdraw
        borrowLend.withdraw(maxWithdraw, address(borrowLend));
    }

    function test_fullWithdrawWithMaxUint256() public {
        uint256 suppliedAmount = 1.112341 ether;
        posOwnerSupplies(suppliedAmount);

        uint256 maxWithdraw = borrowLend.availableToWithdraw();
        assertApproxEqAbs(maxWithdraw, suppliedAmount, 1);

        uint256 balanceBefore = supplyToken.balanceOf(address(borrowLend));
        // use type(uint256).max for a full withdraw
        vm.startPrank(posOwner);
        borrowLend.withdraw(type(uint256).max, address(borrowLend));

        assertApproxEqAbs(borrowLend.suppliedBalance(), 0, 1);
        assertApproxEqAbs(supplyToken.balanceOf(address(borrowLend)), balanceBefore + suppliedAmount, 1);
    }

    function test_availableToWithdraw_euler() public {
        assertEq(borrowLend.availableToWithdraw(), 0);

        uint256 suppliedAmount = 10 ether;
        posOwnerSupplies(suppliedAmount);
        assertApproxEqAbs(borrowLend.availableToWithdraw(), suppliedAmount, 1);

        skip(30 days);

        // availableToWithdraw will increase a bit as the supplied amount accrues interests
        uint256 suppliedPlusInterests = borrowLend.availableToWithdraw();
        assertGt(suppliedPlusInterests, suppliedAmount);

        uint256 withdrawnAmount = 1 ether;
        vm.prank(posOwner);
        borrowLend.withdraw(withdrawnAmount, posOwner);
        assertApproxEqAbs(borrowLend.availableToWithdraw(), suppliedPlusInterests - withdrawnAmount, 1);
    }

    function test_availableToBorrow_withoutBorrowCapSet() public {
        posOwnerSupplies(100 ether);

        uint256 availableInVault = borrowVault.cash();
        uint256 borrowAmount = 10 ether;

        vm.prank(posOwner);
        borrowLend.borrow(borrowAmount, posOwner);

        assertEq(borrowLend.availableToBorrow(), availableInVault - borrowAmount);
    }

    function test_availableToBorrow_withBorrowCapGreaterThanCash() public {
        posOwnerSupplies(100 ether);

        uint256 availableInVault = borrowVault.cash();
        uint256 borrowAmount = 10 ether;

        uint16 cap = 90; // 1000000 ether in AmountCap terms

        vm.prank(borrowVault.governorAdmin());
        borrowVault.setCaps(0, cap);

        vm.prank(posOwner);
        borrowLend.borrow(borrowAmount, posOwner);

        assertEq(borrowLend.availableToBorrow(), availableInVault - borrowAmount);
    }

    function test_availableToBorrow_withMoreCashThanBorrowLimit() public {
        posOwnerSupplies(100 ether);

        uint256 borrowAmount = 12 ether;

        uint16 cap = 90; // 1000000 ether in AmountCap terms
        uint256 capUint256 = AmountCap.wrap(cap).resolve();

        vm.prank(borrowVault.governorAdmin());
        borrowVault.setCaps(0, cap);

        // now an angel deposits a ton of borrowtokens, making the cash > borrowLimit
        uint256 largeDeposit = capUint256 + 100 ether;
        deal(address(borrowToken), angel, largeDeposit);
        vm.prank(angel);
        borrowVault.deposit(largeDeposit, angel);

        (, uint16 bCap) = borrowVault.caps();
        assertEq(bCap, cap);
        assertEq(capUint256, AmountCap.wrap(bCap).resolve());

        vm.prank(posOwner);
        borrowLend.borrow(borrowAmount, posOwner);

        // lets make sure the vault has more cash than the borrow limit
        assertGt(borrowVault.cash(), capUint256);
        // and that therefore the limit is the borrowCap
        assertEq(borrowLend.availableToBorrow(), capUint256);
    }

    function test_dynamic_isSafeAlRatio_euler() public view {
        // >> 9100 in the arbitrum fork tests, which stands for 91%.
        // In origami's dps, this would be 0.91 ether
        // Converted to Oriami's ALratio ==> 1_098_901_098_901_098_901
        // uint256 forkedSafeLimit = 1_098_901_098_901_098_901;

        // >> 8500 in the mainnet fork tests, which stands for 85%
        // In origami's dps, this would be 0.85 ether
        // Converted to Oriami's ALratio ==> 1176470588235294117
        uint256 forkedSafeLimit = 1_176_470_588_235_294_117;

        uint16 eulerBorrowLtvLimit = borrowVault.LTVBorrow(address(supplyVault));
        assertEq(1e22 / eulerBorrowLtvLimit, forkedSafeLimit);

        assertFalse(borrowLend.isSafeAlRatio(forkedSafeLimit - 1));
        assertFalse(borrowLend.isSafeAlRatio(forkedSafeLimit));
        // this one fails because the the rounding up plus the strict greater-than
        // turns into two units higher
        assertFalse(borrowLend.isSafeAlRatio(forkedSafeLimit + 1));
        // but two units above makes it safe already
        assertTrue(borrowLend.isSafeAlRatio(forkedSafeLimit + 2));
    }

    function test_availableToSupply_euler() public {
        (uint16 _supplyCapFromVault,) = supplyVault.caps();
        (uint256 supplyCap, uint256 available) = borrowLend.availableToSupply();

        // This assertion is a bit pointless as we are only asserting a specific block and vault.
        // I leave it here more for documentation purposes
        assertGt(supplyCap, available);

        if (_supplyCapFromVault == 0) {
            assertEq(supplyCap, type(uint256).max);
        }

        // lets put the supply cap to the test
        deal(address(supplyToken), address(borrowLend), 100e18 + available);
        vm.startPrank(origamiMultisig);
        vm.expectRevert(E_AmountTooLargeToEncode.selector);
        borrowLend.supply(available + 2);

        // due to avaoiable being rounded down, the following does not revert
        // (neither it does when you attempt to supply available)
        borrowLend.supply(available + 1);
    }

    function test_supply_outputSuppliedAmount_convertShares(uint256 supplyAmount) public {
        assertEq(borrowLend.suppliedBalance(), 0);

        supplyAmount = bound(supplyAmount, 100_000, 1_000_000 ether);
        // uint256 supplyAmount = 1324123412341234177;
        vm.startPrank(posOwner);

        deal(address(supplyToken), address(borrowLend), supplyAmount);

        uint256 balanceBefore = supplyToken.balanceOf(address(borrowLend));
        borrowLend.supply(supplyAmount);
        uint256 supplied = balanceBefore - supplyToken.balanceOf(address(borrowLend));

        assertEq(supplied, supplyAmount);
    }

    function test_supplyAndDebtBalance_euler() public {
        assertEq(borrowLend.suppliedBalance(), 0);
        uint256 suppliedAmount = 10 ether;
        uint256 borrowAmount = 1 ether;
        uint256 repayAmount = borrowAmount - 0.1 ether; // repay almost everything to reduce the debt significantly
        uint256 withdrawAmount = 0.000001 ether;

        vm.startPrank(posOwner);

        // supply collateral
        deal(address(supplyToken), address(borrowLend), suppliedAmount);
        borrowLend.supply(suppliedAmount);
        assertApproxEqAbs(borrowLend.suppliedBalance(), suppliedAmount, 1, "incorrect suppliedAmount after borrowing");

        // borrow borrowable token
        borrowLend.borrow(borrowAmount, posOwner);
        assertEq(borrowLend.debtBalance(), borrowAmount, "incorrect debtBalance after borrowing");

        // Both debt and supplied amount increase due to interests after some time has passed
        // note using a longer time here, the oracles are not updated, and the withdraw function reverts
        skip(100);
        uint256 newDebt = borrowLend.debtBalance();
        uint256 newSupplyBalance = borrowLend.suppliedBalance();
        assertGe(newSupplyBalance, suppliedAmount, "deposited collateral should have accrued interests");
        assertGt(newDebt, borrowAmount, "debt should have accrued interests");

        // repay some debt
        deal(address(borrowToken), address(borrowLend), repayAmount);
        borrowLend.repay(repayAmount);
        assertEq(borrowLend.debtBalance(), newDebt - repayAmount, "incorrect debtBalance after repaying");
        assertApproxEqAbs(borrowLend.suppliedBalance(), newSupplyBalance, 1);

        // withdraw some collateral
        assertGt(borrowLend.availableToWithdraw(), withdrawAmount);
        uint256 balanceBefore = supplyToken.balanceOf(posOwner);
        borrowLend.withdraw(withdrawAmount, posOwner);
        assertEq(supplyToken.balanceOf(posOwner), balanceBefore + withdrawAmount, "incorrect balance after withdrawing");
        assertApproxEqAbs(
            borrowLend.suppliedBalance(),
            newSupplyBalance - withdrawAmount,
            1,
            "incorrect suppliedAmount after withdrawing"
        );
    }

    function test_availableToWithdraw_enoughCashInVault() public {
        // a basic case where the vault cash can easily covert the availableToWithdraw
        assertEq(borrowLend.suppliedBalance(), 0);

        // borrowLend supplies, someone else borrows, but the cash is still enough to withdraw all the supplied amount
        uint256 supplyAmount = 10 ether;
        deal(address(supplyToken), address(borrowLend), supplyAmount);

        vm.prank(posOwner);
        borrowLend.supply(supplyAmount);

        uint256 suppliedBalance = borrowLend.suppliedBalance();
        uint256 cash = borrowVault.cash();

        assertApproxEqAbs(suppliedBalance, supplyAmount, 1);
        assertGt(cash, supplyAmount);

        assertApproxEqAbs(borrowLend.availableToWithdraw(), supplyAmount, 1);
    }

    function test_availableToWithdraw_cashBelowSupplied() public {
        // a basic case where the vault cash can easily covert the availableToWithdraw
        assertEq(borrowLend.suppliedBalance(), 0);

        // borrowLend supplies, someone else borrows, but the cash is still enough to withdraw all the supplied amount
        uint256 supplyAmount = 100 ether;
        deal(address(supplyToken), address(borrowLend), supplyAmount);
        vm.prank(posOwner);
        borrowLend.supply(supplyAmount);

        // `angel` has supplied most of the assets of the supplyVault.
        // if he withdraws, the remaining assets supplied by borrowLend become kind of locked.
        supplyVault.convertToAssets(supplyVault.balanceOf(angel));
        vm.startPrank(angel);
        supplyVault.approve(address(supplyVault), type(uint256).max);
        supplyVault.redeem(supplyVault.balanceOf(angel), angel, angel);

        // this redemption leaves the vault with less cash than the supplied amount by borrowLend
        // and therefore the availableToWithdraw is less than the suppliedAmount
        assertLt(supplyVault.cash(), supplyAmount);
        assertEq(borrowLend.availableToWithdraw(), supplyVault.cash());
        assertLt(borrowLend.availableToWithdraw(), supplyAmount);
    }
}

contract OrigamiEulerBorrowAndLendTestSupply is OrigamiEulerV2BorrowAndLendTestBase {
    using AmountCapLib for AmountCap;

    error E_SupplyCapExceeded();

    function test_supply_success_euler() public {
        uint256 amount = 10 ether;
        deal(address(supplyToken), address(borrowLend), amount);

        uint256 balanceBefore = supplyToken.balanceOf(address(borrowLend));
        vm.prank(posOwner);
        borrowLend.supply(amount);

        assertApproxEqAbs(borrowLend.suppliedBalance(), amount, 1);
        assertApproxEqAbs(supplyVault.convertToAssets(supplyVault.balanceOf(address(borrowLend))), amount, 1);
        assertEq(balanceBefore, supplyToken.balanceOf(address(borrowLend)) + amount);
    }

    function test_supply_fail_insufficientBalance() public {
        deal(address(supplyToken), address(borrowLend), 5 ether);

        uint256 balanceBefore = supplyToken.balanceOf(address(borrowLend));
        vm.startPrank(posOwner);
        // error handling with Euler's contracts are a pain some times.
        vm.expectRevert();
        borrowLend.supply(balanceBefore + 1);
        // to make sure it is the `+1` that is failing, we check that this does not revert:
        borrowLend.supply(balanceBefore);
    }

    function test_withdraw_moreThanSuppliedFails() public {
        uint256 amount = 5 ether;
        posOwnerSupplies(amount);

        vm.startPrank(posOwner);
        vm.expectRevert(E_InsufficientBalance.selector);
        borrowLend.withdraw(amount + 1, alice);
    }

    function test_withdraw_success_euler() public {
        uint256 amount = 5 ether;

        // we deal the supplytokens in the posOwnerSupplies function
        assertEq(supplyToken.balanceOf(address(borrowLend)), 0);
        posOwnerSupplies(amount);
        assertEq(supplyToken.balanceOf(address(borrowLend)), 0);

        // due to rounding issues, the amount deposited cannot be withdrawn in full
        uint256 assetsToWithdraw = supplyVault.convertToAssets(supplyVault.balanceOf(address(borrowLend)));

        uint256 balanceBefore = supplyToken.balanceOf(address(borrowLend));
        vm.startPrank(posOwner);
        borrowLend.withdraw(assetsToWithdraw, address(borrowLend));

        assertEq(supplyToken.balanceOf(address(borrowLend)), balanceBefore + assetsToWithdraw);
    }

    function test_borrow_insufficientCollateral() public {
        assertEq(borrowLend.suppliedBalance(), 0);
        posOwnerSupplies(5 ether);

        // collateral and borrow token are WETH and stWETH here, so this borrow would be beyond safe LTV
        vm.startPrank(posOwner);
        vm.expectRevert(E_AccountLiquidity.selector);
        borrowLend.borrow(6 ether, alice);
    }

    function test_borrow_success_euler() public {
        assertEq(borrowToken.balanceOf(alice), 0);
        assertEq(borrowToken.balanceOf(address(borrowLend)), 0);
        assertEq(borrowToken.balanceOf(posOwner), 0);

        posOwnerSupplies(5 ether);
        assertApproxEqAbs(borrowLend.suppliedBalance(), 5 ether, 1);

        // collateral and borrow token are WETH and stWETH here, so this borrow would be beyond safe LTV
        vm.startPrank(posOwner);
        borrowLend.borrow(4 ether, alice);
        assertEq(borrowToken.balanceOf(alice), 4 ether);
        assertEq(borrowToken.balanceOf(address(borrowLend)), 0);
        assertEq(borrowToken.balanceOf(posOwner), 0);
    }

    function test_repay_moreThanOutstandingDebt_capsDebtRepaid() public {
        posOwnerSupplies(5 ether);
        vm.startPrank(posOwner);

        uint256 borrowAmount = 4 ether;
        uint256 excess = 1 ether;
        borrowLend.borrow(borrowAmount, alice);

        // give the borrowLend contract enough to repay the full debt
        deal(address(borrowToken), address(borrowLend), borrowAmount + excess);
        borrowLend.repay(borrowAmount + 10);

        assertEq(borrowLend.debtBalance(), 0);
        // check exactly only the borrowAmount was repaid
        assertEq(borrowToken.balanceOf(address(borrowLend)), excess);
    }

    function test_repay_fullOutstandingDebtSuccess() public {
        posOwnerSupplies(5 ether);

        uint256 borrowAmount = 3.12341234 ether;
        uint256 aliceBalanceBefore = borrowToken.balanceOf(alice);

        vm.prank(posOwner);
        borrowLend.borrow(borrowAmount, alice);
        assertEq(borrowLend.debtBalance(), borrowAmount);
        assertEq(borrowLend.debtBalance(), borrowVault.debtOf(address(borrowLend)));
        assertEq(borrowVault.debtOf(address(borrowLend)), borrowToken.balanceOf(alice));

        // give borrowLend extra borrow tokens to repay any outstanding debt
        deal(address(borrowToken), address(borrowLend), borrowAmount + 10 ether);
        uint256 repayAmount = type(uint256).max;
        vm.prank(posOwner);
        borrowLend.repay(repayAmount);
        assertEq(borrowLend.debtBalance(), 0);
        assertEq(borrowToken.balanceOf(alice), aliceBalanceBefore + borrowAmount);
    }

    function test_repay_partialSuccess() public {
        posOwnerSupplies(5 ether);
        vm.startPrank(posOwner);

        uint256 borrowAmount = 3.12341234 ether;
        uint256 aliceBalanceBefore = borrowToken.balanceOf(alice);

        borrowLend.borrow(borrowAmount, alice);
        assertEq(borrowLend.debtBalance(), borrowAmount);

        uint256 repayAmount = 2.1 ether;
        deal(address(borrowToken), address(borrowLend), repayAmount + 0.1 ether);

        uint256 borrowlendBalanceBeforeRepay = borrowToken.balanceOf(address(borrowLend));
        borrowLend.repay(repayAmount);
        assertEq(borrowLend.debtBalance(), borrowAmount - repayAmount);
        assertEq(borrowToken.balanceOf(alice), aliceBalanceBefore + borrowAmount);
        assertEq(borrowToken.balanceOf(address(borrowLend)), borrowlendBalanceBeforeRepay - repayAmount);
    }

    function test_supplyAndBorrow_success() public {
        assertEq(borrowToken.balanceOf(alice), 0);
        assertEq(borrowToken.balanceOf(address(borrowLend)), 0);
        assertEq(borrowToken.balanceOf(posOwner), 0);

        uint256 supplyAmount = 5 ether;
        uint256 borrowAmount = 3 ether;
        deal(address(supplyToken), address(borrowLend), supplyAmount);
        vm.startPrank(posOwner);
        borrowLend.supplyAndBorrow(supplyAmount, borrowAmount, alice);

        assertEq(borrowLend.debtBalance(), borrowAmount);
        assertApproxEqAbs(borrowLend.suppliedBalance(), supplyAmount, 1);
        assertEq(borrowToken.balanceOf(alice), borrowAmount);
        assertEq(borrowToken.balanceOf(address(borrowLend)), 0);
        assertEq(borrowToken.balanceOf(posOwner), 0);
    }

    function test_repayAndWithdraw_success_euler() public {
        uint256 supplyAmount = 5 ether;
        uint256 borrowAmount = 3 ether;
        deal(address(supplyToken), address(borrowLend), supplyAmount);
        vm.startPrank(posOwner);
        borrowLend.supplyAndBorrow(supplyAmount, borrowAmount, alice);

        uint256 repayAmount = 2 ether;
        uint256 withdrawAmount = 1 ether;
        deal(address(borrowToken), address(borrowLend), repayAmount);

        uint256 aliceBalanceBefore = supplyToken.balanceOf(alice);
        borrowLend.repayAndWithdraw(repayAmount, withdrawAmount, alice);

        assertEq(borrowLend.debtBalance(), borrowAmount - repayAmount);
        assertApproxEqAbs(borrowLend.suppliedBalance(), supplyAmount - withdrawAmount, 1);
        assertEq(borrowToken.balanceOf(alice), borrowAmount);
        assertEq(supplyToken.balanceOf(alice), aliceBalanceBefore + withdrawAmount);
        assertEq(borrowToken.balanceOf(address(borrowLend)), 0);
        assertEq(supplyToken.balanceOf(address(borrowLend)), 0);
    }

    function test_supplyAboveSupplyCapReverts() public {
        address governorAdmin = supplyVault.governorAdmin();
        vm.prank(governorAdmin);
        supplyVault.setCaps(10_000, 0); // 0.0156 ether as cap
        (uint16 wrappedSupplyCap,) = supplyVault.caps();
        assertEq(wrappedSupplyCap, 10_000);

        // now the borrowLend will have 1 ether in balance > 0.0156 supply cap
        // when supplying with type(uint256).max, it should revert
        deal(address(supplyToken), address(borrowLend), 1 ether);
        vm.prank(posOwner);
        vm.expectRevert(E_SupplyCapExceeded.selector);
        borrowLend.supply(type(uint256).max);
    }
}

contract OrigamiMorphoBorrowAndLendTestIncreaseLeverage is OrigamiEulerV2BorrowAndLendTestBase {
    using AmountCapLib for AmountCap;

    error E_SupplyCapExceeded();

    function test_increaseLeverage_success() public {
        uint256 supplyAmount = 5 ether;
        uint256 borrowAmount = 3 ether;

        // the dummy swapper assumes it is funded
        deal(address(supplyToken), address(swapper), supplyAmount);
        bytes memory swapData = abi.encode(supplyAmount);
        vm.prank(posOwner);
        uint256 collateralSupplied = borrowLend.increaseLeverage(supplyAmount, borrowAmount, swapData, 0);

        assertApproxEqAbs(collateralSupplied, supplyAmount, 1);
        assertEq(borrowLend.debtBalance(), borrowAmount);
        assertApproxEqAbs(borrowLend.suppliedBalance(), supplyAmount, 1);
        assertEq(borrowToken.balanceOf(address(borrowLend)), 0);
        assertEq(supplyToken.balanceOf(address(borrowLend)), 0);
    }

    function test_increaseLeverage_maxBorrowNotSupported() public {
        // This supplies all balance in the borrowLend, and borrows all cash in the vault

        // give the swapper (the borrowLend) enough collateral to borrow the entire cash
        uint256 vaultCash = borrowVault.cash();
        deal(address(supplyToken), address(swapper), 2 * vaultCash);

        // this collateral should be enough
        uint256 supplyAmount = 2 * vaultCash;
        uint256 borrowAmount = type(uint256).max;

        bytes memory swapData = abi.encode(2 * vaultCash);
        vm.prank(posOwner);
        vm.expectRevert(IOrigamiEulerV2BorrowAndLend.MaxBorrowNotSupported.selector);
        borrowLend.increaseLeverage(supplyAmount, borrowAmount, swapData, 0);
    }

    function test_increaseLeverage_maxSupplyNotSupported() public {
        // This supplies all balance in the borrowLend, and borrows all cash in the vault

        // give the swapper (the borrowLend) enough collateral to borrow the entire cash
        deal(address(supplyToken), address(swapper), 12 ether);

        // this collateral should be enough
        uint256 supplyAmount = type(uint256).max;
        uint256 borrowAmount = 10 ether;
        uint256 swapAmount = 12 ether;

        bytes memory swapData = abi.encode(swapAmount);
        vm.prank(posOwner);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, supplyAmount, swapAmount));
        borrowLend.increaseLeverage(supplyAmount, borrowAmount, swapData, 0);
    }

    function test_increaseLeverage_insufficientCollateral() public {
        uint256 supplyAmount = 5 ether;
        uint256 borrowAmount = 6 ether;

        // the dummy swapper assumes it is funded
        deal(address(supplyToken), address(swapper), supplyAmount);
        bytes memory swapData = abi.encode(supplyAmount);
        vm.startPrank(posOwner);
        vm.expectRevert(E_AccountLiquidity.selector);
        borrowLend.increaseLeverage(supplyAmount, borrowAmount, swapData, 0);
    }

    function test_increaseLeverage_failedSlippage() public {
        uint256 minSupplyAmount = 4 ether;
        uint256 borrowAmount = 3 ether;
        uint256 supplyAmountAfterSwap = 3.9 ether;

        // the dummy swapper assumes it is funded
        deal(address(supplyToken), address(swapper), minSupplyAmount);
        // we fake a swap that gets lower supply amount than the minimum
        bytes memory swapData = abi.encode(supplyAmountAfterSwap);

        vm.startPrank(posOwner);
        vm.expectRevert(
            abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, minSupplyAmount, supplyAmountAfterSwap)
        );
        borrowLend.increaseLeverage(minSupplyAmount, borrowAmount, swapData, 0);
    }

    function test_increaseLeverage_wrongSwapperContract() public {
        // set a wrong contract as swapper and try to increase leverage
        vm.prank(origamiMultisig);
        borrowLend.setSwapper(address(dai));

        uint256 supplyAmount = 5 ether;
        uint256 borrowAmount = 3 ether;
        bytes memory swapData = abi.encode(supplyAmount);
        vm.prank(posOwner);
        // this error is thrown by the EVC when the target contract reverts with no error (function not present for
        // instance)
        vm.expectRevert(EVC_EmptyError.selector);
        borrowLend.increaseLeverage(supplyAmount, borrowAmount, swapData, 0);

        // let's try now with an EOA instead of a contract
        vm.prank(origamiMultisig);
        borrowLend.setSwapper(alice);

        vm.prank(posOwner);
        vm.expectRevert(EVC_EmptyError.selector);
        borrowLend.increaseLeverage(supplyAmount, borrowAmount, swapData, 0);
    }

    function test_increaseLeverageReachesSupplyCap() public {
        address governorAdmin = supplyVault.governorAdmin();
        vm.prank(governorAdmin);
        supplyVault.setCaps(10_000, 0); // 0.0156 ether as cap
        (uint16 wrappedSupplyCap,) = supplyVault.caps();
        assertEq(wrappedSupplyCap, 10_000);

        uint256 minSupplyAmount = 4 ether;
        uint256 borrowAmount = 3 ether;
        deal(address(supplyToken), address(swapper), minSupplyAmount);
        bytes memory swapData = abi.encode(minSupplyAmount);

        vm.startPrank(posOwner);
        vm.expectRevert(E_SupplyCapExceeded.selector);
        borrowLend.increaseLeverage(minSupplyAmount, borrowAmount, swapData, 0);
    }
}

contract OrigamiEulerBorrowAndLendTestDecreaseLeverage is OrigamiEulerV2BorrowAndLendTestBase {
    function leveraged(uint256 supplyAmount, uint256 borrowAmount) internal {
        deal(address(supplyToken), address(swapper), supplyAmount);
        bytes memory swapData = abi.encode(supplyAmount);
        vm.prank(posOwner);
        borrowLend.increaseLeverage(supplyAmount, borrowAmount, swapData, 0);
    }

    function test_decreaseLeverageSuccess() public {
        uint256 supplyAmount = 6 ether;
        uint256 borrowAmount = 5 ether;
        leveraged(supplyAmount, borrowAmount);

        uint256 minRepayAmount = 2 ether;
        uint256 withdrawAmount = 1.5 ether;
        // the received borrowTokens are exact to repay what we intend to repay
        bytes memory swapData = abi.encode(minRepayAmount);
        // the dummy swapper needs to be funded in advance
        deal(address(borrowToken), address(swapper), minRepayAmount);

        vm.prank(posOwner);
        (uint256 debtRepaidAmount, uint256 surplusDebtRepaid) = borrowLend.decreaseLeverage(minRepayAmount, withdrawAmount, swapData, 0);
        assertEq(debtRepaidAmount, minRepayAmount);
        assertEq(surplusDebtRepaid, 0);

        assertEq(borrowLend.debtBalance(), borrowAmount - minRepayAmount);
        // delta of 2 wei due to rounding errors in supplied balance
        assertApproxEqAbs(borrowLend.suppliedBalance(), supplyAmount - withdrawAmount, 2);
        assertEq(borrowToken.balanceOf(address(borrowLend)), 0);
        assertEq(supplyToken.balanceOf(address(borrowLend)), 0);
    }

    function test_decreaseLeverage_fail_slippage() public {
        leveraged(6 ether, 5 ether);

        uint256 minRepayAmount = 2 ether;
        uint256 repayAmountAfterSwap = 1.9 ether;
        uint256 withdrawAmount = 1.5 ether;
        // the received borrowTokens are exact to repay what we intend to repay
        bytes memory swapData = abi.encode(repayAmountAfterSwap);
        // the dummy swapper needs to be funded in advance
        deal(address(borrowToken), address(swapper), minRepayAmount);

        vm.prank(posOwner);
        vm.expectRevert(
            abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, minRepayAmount, repayAmountAfterSwap)
        );
        borrowLend.decreaseLeverage(minRepayAmount, withdrawAmount, swapData, 0);
    }

    function test_fullDeleverage() public {
        uint256 supplyAmount = 3 ether;
        uint256 borrowAmount = 2 ether;

        leveraged(supplyAmount, borrowAmount);

        // we set the minimum debt to repay to the actual borrowed amount (outstanding debt)
        uint256 minBorrowTokensToRepay = borrowAmount;
        // the swap gives some extra, which will still be capped to the outstanting debt
        uint256 borrowTokensFromTheSwap = borrowAmount + 111;
        bytes memory swapData = abi.encode(borrowTokensFromTheSwap);
        deal(address(borrowToken), address(swapper), borrowTokensFromTheSwap);

        // withdraw and repay all
        assertGt(
            supplyVault.balanceOf(address(borrowLend)),
            0,
            "borrowLend should have some shares of the supplyVault, as we have suplied balance"
        );
        vm.prank(posOwner);
        borrowLend.decreaseLeverage(minBorrowTokensToRepay, type(uint256).max, swapData, 0);
        assertEq(
            supplyVault.balanceOf(address(borrowLend)),
            0,
            "borrowLend should no more shares anymore, as we have withdrawn all supplied tokens"
        );

        assertEq(borrowLend.debtBalance(), 0);
        assertEq(borrowLend.suppliedBalance(), 0);

        assertEq(
            borrowToken.balanceOf(address(borrowLend)),
            borrowTokensFromTheSwap - borrowAmount,
            "all debt should have been repaid, bt "
        );
        assertEq(
            supplyToken.balanceOf(address(borrowLend)),
            0,
            "we have withdrawn everything, and swapped for the debt tokens"
        );
    }
}

interface IEulerRouterOracle {
    function getQuote(uint256 inAmount, address base, address quote) external view returns (uint256);
}

contract MockWstEthOracle is IEulerRouterOracle {
    uint256 internal immutable price;

    constructor(uint256 _price) {
        price = _price;
    }

    function getQuote(uint256 inAmount, address base, address quote) external view returns (uint256) {
        // at the forked block, the output of the real oracle is 2764775662175262593515
        // we return half here to simulate a dramatic -unrealistic- price drop in one test
        inAmount;
        base;
        quote; // just to silence compiler warnings
        return price;
    }
}

contract OrigamiEulerBorrowAndLendTestViewsDebtAccountData is OrigamiEulerV2BorrowAndLendTestBase {
    uint256 internal WETH_USD_PRICE;
    uint256 internal WSTETH_USD_PRICE;
    address internal USD_DENOMINATION = 0x0000000000000000000000000000000000000348;

    uint256 internal vaultBorrowLtv;
    uint256 internal vaultLiquidationLtv;

    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp(); // forked at block number 20715366

        vaultBorrowLtv = borrowVault.LTVBorrow(address(supplyVault));
        vaultLiquidationLtv = borrowVault.LTVLiquidation(address(supplyVault));

        // only used to get the usd prices of WETH and wstETH in the forked block
        address wethOracle = borrowVault.oracle();
        address wstEthOracle = supplyVault.oracle();

        // 2352.580000000000000000 usd/WETH at that block
        WETH_USD_PRICE = IEulerRouterOracle(wethOracle).getQuote(1 ether, address(wETH), USD_DENOMINATION);
        // 2764.775662175262593515 usd/wstETH at that block
        WSTETH_USD_PRICE = IEulerRouterOracle(wstEthOracle).getQuote(1 ether, address(wstEth), USD_DENOMINATION);
    }

    function test_liquidationLTV_inForkedBlock() public view {
        // these are just to make sure we are in the correct block
        // These values match what we would see in the frontend in that block
        assertEq(vaultBorrowLtv, 8500);
        assertEq(vaultLiquidationLtv, 8700);
    }

    function test_debtAccountData_beforeAnyAction() public view {
        (
            uint256 supplied,
            uint256 borrowed,
            uint256 collateralValueInUsd,
            uint256 liabilityValueInUsd,
            uint256 currentLtv,
            uint256 liquidationLtv,
            uint256 healthFactor
        ) = borrowLend.debtAccountData();

        assertEq(supplied, 0);
        assertEq(borrowed, 0);
        assertEq(collateralValueInUsd, 0);
        assertEq(liabilityValueInUsd, 0);
        assertEq(currentLtv, 0); // nothing borrowed
        assertEq(liquidationLtv, vaultLiquidationLtv); // same as LTVliquidation() output
        assertEq(healthFactor, type(uint256).max); // nothing borrowed, so health factor is max
    }

    function test_debtAccountData_onlySupplied() public {
        uint256 supplyAmount = 1 ether;
        deal(address(supplyToken), address(borrowLend), supplyAmount);

        vm.prank(posOwner);
        borrowLend.supply(supplyAmount);
        (
            uint256 supplied, // 999999999999999999
            uint256 borrowed, // 0
            uint256 collateralValueInUsd, // 2764775662175262591167
            uint256 liabilityValueInUsd, // 0
            uint256 currentLtv, // 0
            uint256 liquidationLtv, // 8700
            uint256 healthFactor // type(uint256).max
        ) = borrowLend.debtAccountData();

        assertApproxEqAbs(supplied, supplyAmount, 1, "wrong supplied amount");
        assertEq(borrowed, 0);
        assertApproxEqRel(collateralValueInUsd, supplyAmount * WSTETH_USD_PRICE / 1e18, 1e6);
        assertEq(liabilityValueInUsd, 0); // nothing borrowed
        assertEq(currentLtv, 0); // nothing borrowed
        assertEq(liquidationLtv, vaultLiquidationLtv); // same as LTVliquidation() output
        assertEq(healthFactor, type(uint256).max); // nothing borrowed, so health factor is max
    }

    function test_fuzz_debtAccountData_onlySupplied(uint256 supplyAmount) public {
        supplyAmount = bound(supplyAmount, 0.0001 ether, 1000 ether);
        deal(address(supplyToken), address(borrowLend), supplyAmount);

        vm.prank(posOwner);
        borrowLend.supply(supplyAmount);
        (
            uint256 supplied,
            uint256 borrowed,
            uint256 collateralValueInUsd,
            uint256 liabilityValueInUsd,
            uint256 currentLtv,
            uint256 liquidationLtv,
            uint256 healthFactor
        ) = borrowLend.debtAccountData();

        assertApproxEqAbs(supplied, supplyAmount, 1, "wrong supplied amount");
        assertEq(borrowed, 0);
        assertApproxEqRel(collateralValueInUsd, supplyAmount * WSTETH_USD_PRICE / 1e18, 1e6);
        assertEq(liabilityValueInUsd, 0); // nothing borrowed
        assertEq(currentLtv, 0); // nothing borrowed
        assertEq(liquidationLtv, vaultLiquidationLtv); // same as LTVliquidation() output
        assertEq(healthFactor, type(uint256).max); // nothing borrowed, so health factor is max
    }

    function test_debtAccountData_supplyAndBorrow_basic() public {
        uint256 supplyAmount = 1 ether;
        uint256 supplyUsdValue = supplyAmount * WSTETH_USD_PRICE;
        uint256 borrowUsdValue = supplyUsdValue / 5; // 0.2 of supply value to yield a LTV=0.2 approx
        uint256 borrowAmount = borrowUsdValue / WETH_USD_PRICE;

        deal(address(supplyToken), address(borrowLend), supplyAmount);
        vm.startPrank(posOwner);
        borrowLend.supply(supplyAmount);
        borrowLend.borrow(borrowAmount, address(borrowLend));
        vm.stopPrank();

        (
            uint256 supplied, // 999999999999999999 wstETH
            uint256 borrowed, // 235042010233468157 WETH
            uint256 collateralValueInUsd, // 2764775662175262591167   usd
            uint256 liabilityValueInUsd, // 552955132435052516795    usd
            uint256 currentLtv, // 2000
            uint256 liquidationLtv, // 8700
            uint256 healthFactor // 4350000000000000000 = 8700/2000 = 4.35
        ) = borrowLend.debtAccountData();

        assertApproxEqAbs(supplied, supplyAmount, 1, "wrong supplied amount");
        assertEq(borrowed, borrowAmount, "wrong borrowed amount");
        assertApproxEqRel(collateralValueInUsd, supplyAmount * WSTETH_USD_PRICE / 1e18, 1e6);
        assertEq(liabilityValueInUsd, borrowAmount * WETH_USD_PRICE / 1e18, "wrong liabilitiesInUsd"); // nothing
            // borrowed
        assertEq(liquidationLtv, vaultLiquidationLtv); // same as LTVliquidation() output

        // the currentLTV inside debtAccountData uses the risk-adjusted collateralValueInUsd
        // So, even though the raw LTV would be 0.2/1 = 0.2,
        assertEq(currentLtv, 2000);
        assertEq(healthFactor, 1e18 * liquidationLtv / currentLtv);
    }

    function test_debtAccountData_suppliedAndBorrowedHealthy_borrowToOtherReceiver() public {
        // Same test as above, but borrowed tokens go directly to other receiver
        uint256 supplyAmount = 1 ether;
        uint256 supplyUsdValue = supplyAmount * WSTETH_USD_PRICE;
        uint256 borrowUsdValue = supplyUsdValue / 5; // 0.2 of supply value to yield a LTV=0.2 approx
        uint256 borrowAmount = borrowUsdValue / WETH_USD_PRICE;

        address receiver = makeAddr("receiver");
        deal(address(supplyToken), address(borrowLend), supplyAmount);

        vm.startPrank(posOwner);
        borrowLend.supply(supplyAmount);
        borrowLend.borrow(borrowAmount, receiver);
        vm.stopPrank();
        (
            uint256 supplied, // 999999999999999999 wstETH
            uint256 borrowed, // 235042010233468157 WETH
            uint256 collateralValueInUsd, // 2764775662175262591167   usd
            uint256 liabilityValueInUsd, // 552955132435052516795    usd
            , // currentLtv // 2000
            uint256 liquidationLtv, // 8700
                // healthFactor // 4350000000000000000 = 8700/2000 = 4.35
        ) = borrowLend.debtAccountData();

        assertApproxEqAbs(supplied, supplyAmount, 1, "wrong supplied amount");
        assertApproxEqRel(collateralValueInUsd, supplyAmount * WSTETH_USD_PRICE / 1e18, 1e6);
        assertEq(borrowed, borrowAmount, "wrong borrowed amount");
        assertEq(liabilityValueInUsd, borrowAmount * WETH_USD_PRICE / 1e18, "wrong liabilitiesInUsd"); // nothing
            // borrowed
        assertEq(liquidationLtv, vaultLiquidationLtv); // same as LTVliquidation() output
    }

    function test_edgeCase_supplyAndBorrow_rightAboveLiquidationLTV() public {
        uint256 supplyAmount = 1 ether;
        uint256 supplyUsdValue = supplyAmount * WSTETH_USD_PRICE;
        uint256 borrowUsdValue = supplyUsdValue * vaultLiquidationLtv / 1e4 + 1;
        uint256 borrowAmount = borrowUsdValue / WETH_USD_PRICE;

        deal(address(supplyToken), address(borrowLend), supplyAmount);
        vm.startPrank(posOwner);
        borrowLend.supply(supplyAmount);

        // we cannot borrow more than the equivalent for liquidation
        vm.expectRevert(E_AccountLiquidity.selector);
        borrowLend.borrow(borrowAmount, address(borrowLend));

        vm.stopPrank();
    }

    function test_debtAccountData_suppliedAndBorrowed_goesUnderWater() public {
        // borrowed possition is fine, and then oracle prices makes the possition liquidatable
        uint256 supplyAmount = 1 ether;
        uint256 supplyUsdValue = supplyAmount * WSTETH_USD_PRICE;
        uint256 borrowUsdValue = 4 * supplyUsdValue / 5; // 0.8 of supply value (not liquidatable yet)
        uint256 borrowAmount = borrowUsdValue / WETH_USD_PRICE;

        deal(address(supplyToken), address(borrowLend), supplyAmount);

        vm.startPrank(posOwner);
        borrowLend.supply(supplyAmount);
        borrowLend.borrow(borrowAmount, address(borrowLend));
        vm.stopPrank();

        // moved the oracle-faking logic to a separate function because of stack-too-deep
        uint256 new_WSTETH_USD_PRICE = WSTETH_USD_PRICE / 2;
        _fakeWstEthOraclePriceData(address(supplyVault.oracle()), new_WSTETH_USD_PRICE);
        // make sure the vault's new oracle is set and returns the new price
        assertEq(
            IEulerRouterOracle(address(supplyVault.oracle())).getQuote(1 ether, address(wstEth), USD_DENOMINATION),
            new_WSTETH_USD_PRICE,
            "failed the first call to oracle"
        );
        // also adjust the supplied usd value for later comparisons
        supplyUsdValue = supplyUsdValue / 2;

        (
            , // uint256 supplied = 999999999999999999 wstETH
            , // uint256 borrowed = 940168040933872631 WETH
            uint256 collateralValueInUsd, // 1382387831087631296756   usd
            uint256 liabilityValueInUsd, // 2211820529740210074237   usd (greater than collateral value)
            uint256 currentLtv, // 16000   greater than 10000 (greater than 100%) ==> liquidatable
            uint256 liquidationLtv, // 8700
            uint256 healthFactor // 0.4875 < 1 (unhealthy, liquidatable)
        ) = borrowLend.debtAccountData();

        assertEq(liabilityValueInUsd, borrowAmount * WETH_USD_PRICE / 1e18, "wrong liabilitiesInUsd"); // nothing
            // borrowed
        assertApproxEqRel(collateralValueInUsd, supplyAmount * new_WSTETH_USD_PRICE / 1e18, 1e6);
        assertEq(currentLtv, borrowUsdValue * 1e4 / supplyUsdValue);

        // the risk-adjusted collateralValueInUsd should now be greater than the liabilityUsdValue
        assertGt(liabilityValueInUsd, collateralValueInUsd);
        // The currentLtv should be greater than the liquidation Ltv because the value of the collateral has dropped
        assertGt(currentLtv, liquidationLtv);
        assertGt(currentLtv, 1e4);

        // health factor is under water now
        assertLt(healthFactor, 1e18);
        uint256 expectedHealthFactor = (1e18 * liquidationLtv) / currentLtv;
        assertEq(healthFactor, expectedHealthFactor, "wrong expectedHealthFactor");
    }

    function test_debtAccountData_suppliedAndBorrowed_goesSlightlyUnderWater() public {
        // same test as `test_debtAccountData_suppliedAndBorrowed_goesUnderWater()`
        // but this time, the collateral usd value places us between LTVBorrow and LTVLiquidation
        // so we can't borrow, but we are not liquidatable
        uint256 supplyAmount = 1 ether;
        uint256 supplyUsdValue = supplyAmount * WSTETH_USD_PRICE;
        uint256 borrowUsdValue = supplyUsdValue * 8499 / 1e4; // right below borrowLTV
        uint256 borrowAmount = borrowUsdValue / WETH_USD_PRICE;

        assertLt(1e4 * borrowUsdValue / supplyUsdValue, vaultBorrowLtv);

        deal(address(supplyToken), address(borrowLend), supplyAmount);

        vm.startPrank(posOwner);
        borrowLend.supply(supplyAmount);
        borrowLend.borrow(borrowAmount, address(borrowLend));
        vm.stopPrank();

        // moved the oracle-faking logic to a separate function because of stack-too-deep
        // wstEth price goes down 1 percent
        uint256 new_WSTETH_USD_PRICE = 0.99 ether * WSTETH_USD_PRICE / 1 ether;
        _fakeWstEthOraclePriceData(address(supplyVault.oracle()), new_WSTETH_USD_PRICE);
        // make sure the vault's new oracle is set and returns the new price
        assertEq(
            IEulerRouterOracle(address(supplyVault.oracle())).getQuote(1 ether, address(wstEth), USD_DENOMINATION),
            new_WSTETH_USD_PRICE,
            "failed the second call to oracle"
        );
        // also adjust the supplied usd value for later comparisons
        supplyUsdValue = 0.99 ether * supplyUsdValue / 1 ether;
        (
            , // uint256 supplied // 999999999999999999 wstETH
            , // uint256 borrowed // 998811022487122936 WETH
            uint256 collateralValueInUsd, // 2737127905553509967578   usd
            uint256 liabilityValueInUsd, // 2349782835282755676774   usd
            uint256 currentLtv, // 8585 // doesn't match the expected one because of the risk adjustment ...
            uint256 liquidationLtv, // 8700
            uint256 healthFactor //
        ) = borrowLend.debtAccountData();

        assertEq(liabilityValueInUsd, borrowAmount * WETH_USD_PRICE / 1e18, "wrong liabilitiesInUsd"); // nothing
            // borrowed
        assertApproxEqRel(collateralValueInUsd, supplyAmount * new_WSTETH_USD_PRICE / 1e18, 1e6);
        assertApproxEqAbs(currentLtv, borrowUsdValue * 1e4 / supplyUsdValue, 1);

        // the risk-adjusted collateralValueInUsd should still be lower than the liabilityUsdValue
        assertLt(liabilityValueInUsd, collateralValueInUsd);
        // The currentLtv should still be lower than the liquidation Ltv because the value of the collateral has dropped
        assertGt(currentLtv, vaultBorrowLtv);
        assertLt(currentLtv, liquidationLtv);
        assertLt(currentLtv, 1e4);

        // health factor should still be above 1
        assertGt(healthFactor, 1e18);
        uint256 expectedHealthFactor = (1e18 * liquidationLtv) / currentLtv;
        assertEq(healthFactor, expectedHealthFactor, "wrong expectedHealthFactor");
    }

    function _fakeWstEthOraclePriceData(address targetOracle, uint256 newPrice) internal {
        MockWstEthOracle mockWstEthOracle = new MockWstEthOracle(newPrice);
        uint256 newWstEthPrice =
            IEulerRouterOracle(mockWstEthOracle).getQuote(1 ether, address(wstEth), USD_DENOMINATION);
        assertEq(newWstEthPrice, newPrice);

        // This modifies the response form the supplyVault oracle
        // We fake here that the price of the collateral has dropped dramatically, and therefore the possition is
        // liquidatable
        stdstore.target(targetOracle).sig("getConfiguredOracle(address,address)").with_key(address(wstEth)).with_key(
            USD_DENOMINATION
        ).checked_write(address(mockWstEthOracle));
    }
}
