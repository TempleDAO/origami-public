pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { IOrigamiErc4626 } from "contracts/interfaces/common/IOrigamiErc4626.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { MockErc4626VaultWithFees } from "test/foundry/mocks/common/erc4626/MockErc4626VaultWithFees.m.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

contract OrigamiErc4626With6dpTestBase is OrigamiTest {
    using OrigamiMath for uint256;

    DummyMintableToken public asset;
    MockErc4626VaultWithFees public vault;

    uint224 public constant MAX_TOTAL_SUPPLY = 100_000_000e18;
    uint16 public constant DEPOSIT_FEE = 50;
    uint16 public constant WITHDRAWAL_FEE = 200;
    uint256 public constant SEED_DEPOSIT_SIZE = 0.1e6;

    event InKindFees(IOrigamiErc4626.FeeType feeType, uint256 feeBps, uint256 feeAmount);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function setUp() public {
        asset = new DummyMintableToken(origamiMultisig, "UNDERLYING", "UDLY", 6);
        vault = new MockErc4626VaultWithFees(
            origamiMultisig, 
            "VAULT",
            "VLT",
            asset,
            DEPOSIT_FEE,
            WITHDRAWAL_FEE
        );
        seedDeposit(origamiMultisig, SEED_DEPOSIT_SIZE, MAX_TOTAL_SUPPLY);

        vm.warp(100000000);
    }

    function seedDeposit(address account, uint256 amount, uint256 maxSupply) internal {
        vm.startPrank(account);
        deal(address(asset), account, amount);
        asset.approve(address(vault), amount);
        vault.seedDeposit(amount, account, maxSupply);
        vm.stopPrank();
    }

    function deposit(address user, uint256 amount) internal {
        deal(address(asset), user, amount);
        vm.startPrank(user);
        asset.approve(address(vault), amount);
        uint256 expectedShares = vault.previewDeposit(amount);

        vm.expectEmit(address(vault));
        emit InKindFees(
            IOrigamiErc4626.FeeType.DEPOSIT_FEE, 
            DEPOSIT_FEE, 
            expectedShares.inverseSubtractBps(DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_UP) - expectedShares
        );
        vm.expectEmit(address(vault));
        emit Deposit(user, user, amount, expectedShares);
        uint256 actualShares = vault.deposit(amount, user);
        vm.stopPrank();

        assertEq(actualShares, expectedShares);
    }

    function mint(address user, uint256 shares) internal {
        uint256 expectedAssets = vault.previewMint(shares);
        deal(address(asset), user, expectedAssets);
        vm.startPrank(user);
        asset.approve(address(vault), expectedAssets);

        vm.expectEmit(address(vault));
        emit InKindFees(
            IOrigamiErc4626.FeeType.DEPOSIT_FEE, 
            DEPOSIT_FEE, 
            shares.inverseSubtractBps(DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_UP) - shares
        );
        vm.expectEmit(address(vault));
        emit Deposit(user, user, expectedAssets, shares);
        uint256 actualAssets = vault.mint(shares, user);
        vm.stopPrank();

        assertEq(actualAssets, expectedAssets);
    }

    function withdraw(address user, uint256 assets) internal {
        vm.startPrank(user);
        uint256 expectedShares = vault.previewWithdraw(assets);

        vm.expectEmit(address(vault));
        emit InKindFees(
            IOrigamiErc4626.FeeType.WITHDRAWAL_FEE,
            WITHDRAWAL_FEE,
            expectedShares - expectedShares.subtractBps(WITHDRAWAL_FEE, OrigamiMath.Rounding.ROUND_DOWN)
        );
        vm.expectEmit(address(vault));
        emit Withdraw(user, user, user, assets, expectedShares);
        uint256 actualShares = vault.withdraw(assets, user, user);
        vm.stopPrank();

        assertEq(actualShares, expectedShares);
    }

    function redeem(address user, uint256 shares) internal {
        vm.startPrank(user);
        uint256 expectedAssets = vault.previewRedeem(shares);

        vm.expectEmit(address(vault));
        emit InKindFees(
            IOrigamiErc4626.FeeType.WITHDRAWAL_FEE,
            WITHDRAWAL_FEE,
            shares - shares.subtractBps(WITHDRAWAL_FEE, OrigamiMath.Rounding.ROUND_DOWN)
        );
        vm.expectEmit(address(vault));
        emit Withdraw(user, user, user, expectedAssets, shares);
        uint256 actualAssets = vault.redeem(shares, user, user);
        vm.stopPrank();

        assertEq(actualAssets, expectedAssets);
    }

    function addToSharePrice(uint256 amount) internal {
        deal(address(asset), address(vault), asset.balanceOf(address(vault)) + amount);
    }
}

contract OrigamiErc4626With6dpTestAdmin is OrigamiErc4626With6dpTestBase {
    function test_fail_constructor() public {
        asset = new DummyMintableToken(origamiMultisig, "UNDERLYING", "UDLY", 30);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(asset)));
        vault = new MockErc4626VaultWithFees(
            origamiMultisig, 
            "VAULT",
            "VLT",
            asset,
            DEPOSIT_FEE,
            WITHDRAWAL_FEE
        );
    }

    function test_initialization() public {
        assertEq(vault.owner(), origamiMultisig);
        assertEq(vault.name(), "VAULT");
        assertEq(vault.symbol(), "VLT");
        assertEq(vault.asset(), address(asset));
        assertEq(vault.decimals(), 18);
        assertEq(vault.maxTotalSupply(), MAX_TOTAL_SUPPLY);
        assertEq(vault.totalSupply(), 0.0995e18);
        assertEq(vault.totalAssets(), 0.1e6);
        assertEq(vault.convertToShares(1e6), 0.995000049999500004e18);
        assertEq(vault.convertToAssets(1e18), 1.005025e6);

        // How many assets can be deposited to hit the total supply
        // so takes fees into consideration.
        assertEq(vault.maxDeposit(alice), 101_007_545.138179e6);
        assertEq(vault.maxMint(alice), MAX_TOTAL_SUPPLY - 0.0995e18);
        assertEq(vault.maxWithdraw(alice), 0);
        assertEq(vault.maxRedeem(alice), 0);
        assertEq(vault.previewDeposit(1e6), 0.990025049749502503e18); // 50bps fee
        // 50 bps fee -- need to deposit more assets in order to get 1e18 shares
        assertEq(vault.previewMint(1e18), 1.010076e6);
        // 200 bps fee -- need to redeem more shares in order to get 1e18 assets
        assertEq(vault.previewWithdraw(1e6), 1.015306173468877557e18);
        assertEq(vault.previewRedeem(1e18), 0.984924e6); // 200bps fee

        assertEq(vault.DOMAIN_SEPARATOR(), bytes32(0xf07a1e21026e15847c4f454c9eb8f87a35787510bc37aee10796c2c8aa85ff16));
    }

    function test_supportsInterface() public {
        assertEq(vault.supportsInterface(type(IERC4626).interfaceId), true);
        assertEq(vault.supportsInterface(type(IERC20Permit).interfaceId), true);
        assertEq(vault.supportsInterface(type(EIP712).interfaceId), true);
        assertEq(vault.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(vault.supportsInterface(type(IOrigamiInvestment).interfaceId), false);
    }

    function test_recoverToken_failure() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(asset)));
        vault.recoverToken(address(asset), alice, 100e18);
    }

    function test_recoverToken_success() public {
        check_recoverToken(address(vault));
    }

    function test_recoverToken_access() public {
        expectElevatedAccess();
        vault.recoverToken(alice, alice, 100e18);
    }
}


contract OrigamiErc4626With6dpTestDeposit is OrigamiErc4626With6dpTestBase {
    using OrigamiMath for uint256;

    function test_deposit_basic() public {
        deposit(alice, 123e6);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 123e6 + 0.1e6);
        assertEq(vault.balanceOf(alice), 121.773081119188808110e18);
        assertEq(vault.totalSupply(), 121.872581119188808110e18);
        assertEq(vault.totalAssets(), 123e6 + 0.1e6);
    }

    function test_deposit_beforeShareIncrease() public {
        deposit(alice, 123e6);

        addToSharePrice(100e6);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 223e6 + 0.1e6);
        assertEq(vault.balanceOf(alice), 121.773081119188808110e18);
        assertEq(vault.totalSupply(), 121.872581119188808110e18);
        assertEq(vault.totalAssets(), 223e6 + 0.1e6);
        assertEq(vault.convertToShares(1e6), 0.546268855100492841e18);
        assertEq(vault.convertToAssets(1e18), 1.830600e6);
    }

    function test_deposit_afterShareIncrease() public {
        deposit(bob, 100e6);

        addToSharePrice(10e6); // 10% increase
        assertEq(vault.convertToShares(1e6), 0.900109037918630450e18);
        assertEq(vault.convertToAssets(1e18), 1.110976e6);

        assertEq(vault.maxDeposit(alice), 111_655_820.271738e6);
        assertEq(vault.maxMint(alice), 99_999_900.897995025049749504e18);
        deposit(alice, 123e6);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 233e6 + 0.1e6);
        assertEq(vault.balanceOf(alice), 110.159844605671587659e18);
        assertEq(vault.totalSupply(), 209.261849580621838155e18);
        assertEq(vault.totalAssets(), 233e6 + 0.1e6);

        // Deposit fees continue to help the share price
        assertEq(vault.convertToShares(1e6), 0.897734232873820700e18);
        assertEq(vault.convertToAssets(1e18), 1.113915e6);

        uint256 _max = vault.maxDeposit(alice);

        // Can't deposit more.
        {
            deal(address(asset), alice, _max+1);
            asset.approve(address(vault), _max+1);
            vm.expectRevert(abi.encodeWithSelector(IOrigamiErc4626.ERC4626ExceededMaxDeposit.selector, alice, _max+1, _max));
            vault.deposit(_max+1, alice);
        }

        deposit(alice, _max);
        assertEq(vault.maxDeposit(alice), 0);
    }

    function test_deposit_differentReceiver() public {
        uint256 amount = 100e6;

        deal(address(asset), alice, amount);
        vm.startPrank(alice);
        asset.approve(address(vault), amount);
        uint256 expectedShares = vault.previewDeposit(amount);

        vm.expectEmit(address(vault));
        emit InKindFees(
            IOrigamiErc4626.FeeType.DEPOSIT_FEE, 
            DEPOSIT_FEE, 
            expectedShares.inverseSubtractBps(DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_UP) - expectedShares
        );
        vm.expectEmit(address(vault));
        emit Deposit(alice, bob, amount, expectedShares);
        uint256 actualShares = vault.deposit(amount, bob);
        vm.stopPrank();

        assertEq(actualShares, expectedShares);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.balanceOf(bob), 99.002504974950250496e18);
    }
}

contract OrigamiErc4626With6dpTestMint is OrigamiErc4626With6dpTestBase {
    using OrigamiMath for uint256;

    function test_mint_basic() public {
        mint(alice, 123e18);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 124.339281e6);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 123e18 + 0.0995e18);
        assertEq(vault.totalAssets(), 124.339281e6);
    }

    function test_mint_beforeShareIncrease() public {
        mint(alice, 123e18);

        addToSharePrice(100e6);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 224.339281e6);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 123e18 + 0.0995e18);
        assertEq(vault.totalAssets(), 224.339281e6);
        assertEq(vault.convertToShares(1e6), 0.548720223683340486e18);
        assertEq(vault.convertToAssets(1e18), 1.822422e6);
    }

    function test_mint_afterShareIncrease() public {
        mint(bob, 100e18);

        addToSharePrice(10e6); // 10% increase
        assertEq(vault.convertToShares(1e6), 0.900924407952233883e18);
        assertEq(vault.convertToAssets(1e18), 1.109971e6);

        assertEq(vault.maxDeposit(alice), 111_554_766.496714e6);
        assertEq(vault.maxMint(alice), 99_999_899.9005e18);
        mint(alice, 123e18);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 248.320047e6);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 223e18 + 0.0995e18);

        // Deposit fees continue to help the share price
        assertEq(vault.convertToShares(1e6), 0.898435316829513499e18);
        assertEq(vault.convertToAssets(1e18), 1.113046e6);

        uint256 _max = vault.maxMint(alice);

        // Can't mint more.
        {
            uint256 expectedAssets = vault.previewMint(_max+1);
            deal(address(asset), alice, expectedAssets);
            asset.approve(address(vault), expectedAssets);
            vm.expectRevert(abi.encodeWithSelector(IOrigamiErc4626.ERC4626ExceededMaxMint.selector, alice, _max+1, _max));
            vault.mint(_max+1, alice);
        }

        mint(alice, _max);
        assertEq(vault.maxMint(alice), 0);
    }

    function test_mint_differentReceiver() public {
        uint256 shares = 100e18;

        uint256 expectedAssets = vault.previewMint(shares);
        deal(address(asset), alice, expectedAssets);
        vm.startPrank(alice);
        asset.approve(address(vault), expectedAssets);

        vm.expectEmit(address(vault));
        emit InKindFees(
            IOrigamiErc4626.FeeType.DEPOSIT_FEE, 
            DEPOSIT_FEE, 
            shares.inverseSubtractBps(DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_UP) - shares
        );
        vm.expectEmit(address(vault));
        emit Deposit(alice, bob, expectedAssets, shares);
        uint256 actualAssets = vault.mint(shares, bob);
        vm.stopPrank();

        assertEq(actualAssets, expectedAssets);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.balanceOf(bob), 100e18);
    }
}

contract OrigamiErc4626With6dpTestWithdraw is OrigamiErc4626With6dpTestBase {
    using OrigamiMath for uint256;

    function test_withdraw_basic() public {
        deposit(alice, 123e6);

        withdraw(alice, 50e6);

        assertEq(asset.balanceOf(alice), 50e6);
        assertEq(asset.balanceOf(address(vault)), 73e6 + 0.1e6);
        assertEq(vault.balanceOf(alice), 71.261392791647023228e18);
        assertEq(vault.totalSupply(), 71.360892791647023228e18);
        assertEq(vault.totalAssets(), 73e6 + 0.1e6);
    }

    function test_withdraw_beforeShareIncrease() public {
        deposit(alice, 123e6);

        withdraw(alice, 50e6);
        addToSharePrice(100e6);

        assertEq(asset.balanceOf(alice), 50e6);
        assertEq(asset.balanceOf(address(vault)), 173e6 + 0.1e6);
        assertEq(vault.balanceOf(alice), 71.261392791647023228e18);
        assertEq(vault.totalSupply(), 71.360892791647023228e18);
        assertEq(vault.totalAssets(), 173e6 + 0.1e6);
        assertEq(vault.convertToShares(1e6), 0.412252416980904715e18);
        assertEq(vault.convertToAssets(1e18), 2.425698e6);
    }

    function test_withdraw_afterShareIncrease() public {
        deposit(alice, 100e6);

        addToSharePrice(10e6); // 10% increase
        assertEq(vault.convertToShares(1e6), 0.900109037918630450e18);
        assertEq(vault.convertToAssets(1e18), 1.110976e6);

        assertEq(vault.maxWithdraw(alice), 107.789668e6);
        assertEq(vault.maxRedeem(alice), 99.002504974950250496e18);
        withdraw(alice, 50e6);

        assertEq(asset.balanceOf(alice), 50e6);
        assertEq(asset.balanceOf(address(vault)), 60e6 + 0.1e6);
        assertEq(vault.balanceOf(alice), 53.078574468897676501e18);
        assertEq(vault.totalSupply(), 53.178074468897676501e18);
        assertEq(vault.totalAssets(), 60e6 + 0.1e6);

        // Withdrawal fees continue to help the share price
        assertEq(vault.convertToShares(1e6), 0.884826532180884264e18);
        assertEq(vault.convertToAssets(1e18), 1.130165e6);

        // Check the maxWithdraw
        uint256 _max = vault.maxWithdraw(alice);
        assertEq(_max, 58.787797e6);

        // Can't withdraw more
        {
            vm.expectRevert(abi.encodeWithSelector(IOrigamiErc4626.ERC4626ExceededMaxWithdraw.selector, alice, _max+1, _max));
            vault.withdraw(_max+1, alice, alice);
        }

        // Because of the dp difference, there's (diminishing) dust on each maxWithdraw.
        // To get rid of the dust, should redeem rather than withdraw
        withdraw(alice, _max);
        assertEq(vault.maxWithdraw(alice), 5);
        withdraw(alice, 5);

        assertEq(vault.maxWithdraw(alice), 0);
    }

    function test_withdraw_differentReceiver() public {
        deposit(alice, 200e6);

        uint256 assets = 100e6;

        vm.startPrank(alice);
        uint256 expectedShares = vault.previewWithdraw(assets);

        vm.expectEmit(address(vault));
        emit InKindFees(
            IOrigamiErc4626.FeeType.WITHDRAWAL_FEE,
            WITHDRAWAL_FEE,
            expectedShares - expectedShares.subtractBps(WITHDRAWAL_FEE, OrigamiMath.Rounding.ROUND_DOWN)
        );
        vm.expectEmit(address(vault));
        emit Withdraw(alice, bob, alice, assets, expectedShares);
        uint256 actualShares = vault.withdraw(assets, bob, alice);
        vm.stopPrank();

        assertEq(actualShares, expectedShares);
        assertEq(vault.balanceOf(alice), 96.981791987517934642e18);
        assertEq(vault.balanceOf(bob), 0);
        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(bob), 100e6);
    }

    function test_withdraw_differentSender() public {
        deposit(alice, 200e6);

        uint256 assets = 100e6;
        uint256 expectedShares = vault.previewWithdraw(assets);

        // Bob can't withdraw with Alice's explicit approval
        {
            vm.startPrank(bob);
            vm.expectRevert("ERC20: insufficient allowance");
            vault.withdraw(assets, bob, alice);

            vm.startPrank(alice);
            vault.approve(bob, expectedShares);
            vm.startPrank(bob);
        }

        vm.expectEmit(address(vault));
        emit InKindFees(
            IOrigamiErc4626.FeeType.WITHDRAWAL_FEE,
            WITHDRAWAL_FEE,
            expectedShares - expectedShares.subtractBps(WITHDRAWAL_FEE, OrigamiMath.Rounding.ROUND_DOWN)
        );
        vm.expectEmit(address(vault));
        emit Withdraw(bob, bob, alice, assets, expectedShares);
        uint256 actualShares = vault.withdraw(assets, bob, alice);
        vm.stopPrank();

        assertEq(actualShares, expectedShares);
        assertEq(vault.balanceOf(alice), 96.981791987517934642e18);
        assertEq(vault.balanceOf(bob), 0);
        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(bob), 100e6);
    }
}

contract OrigamiErc4626With6dpTestRedeem is OrigamiErc4626With6dpTestBase {
    using OrigamiMath for uint256;

    function test_redeem_basic() public {
        deposit(alice, 123e6);

        redeem(alice, 50e18);

        assertEq(asset.balanceOf(alice), 49.493495e6);
        assertEq(asset.balanceOf(address(vault)), 73.606505e6);
        assertEq(vault.balanceOf(alice), 71.773081119188808110e18);
        assertEq(vault.totalSupply(), 71.872581119188808110e18);
        assertEq(vault.totalAssets(), 73.606505e6);
    }

    function test_redeem_beforeShareIncrease() public {
        deposit(alice, 123e6);

        redeem(alice, 50e18);
        addToSharePrice(100e6);

        assertEq(asset.balanceOf(alice), 49.493495e6);
        assertEq(asset.balanceOf(address(vault)), 173.606505e6);
        assertEq(vault.balanceOf(alice), 71.773081119188808110e18);
        assertEq(vault.totalSupply(), 71.872581119188808110e18);
        assertEq(vault.totalAssets(), 173.606505e6);
        assertEq(vault.convertToShares(1e6), 0.413997054460555804e18);
        assertEq(vault.convertToAssets(1e18), 2.415476e6);
    }

    function test_redeem_afterShareIncrease() public {
        deposit(alice, 100e6);

        addToSharePrice(10e6); // 10% increase
        assertEq(vault.convertToShares(1e6), 0.900109037918630450e18);
        assertEq(vault.convertToAssets(1e18), 1.110976e6);

        assertEq(vault.maxWithdraw(alice), 107.789668e6);
        assertEq(vault.maxRedeem(alice), 99.002504974950250496e18);
        redeem(alice, 50e18);

        assertEq(asset.balanceOf(alice), 54.437849e6);
        assertEq(asset.balanceOf(address(vault)), 55.662151e6);
        assertEq(vault.balanceOf(alice), 49.002504974950250496e18);
        assertEq(vault.totalSupply(), 49.102004974950250496e18);
        assertEq(vault.totalAssets(), 55.662151e6);

        // Withdrawal fees continue to help the share price
        assertEq(vault.convertToShares(1e6), 0.882143507044971069e18);
        assertEq(vault.convertToAssets(1e18), 1.133602e6);

        uint256 _max = vault.maxRedeem(alice);

        // Can't redeem more.
        {
            vm.expectRevert(abi.encodeWithSelector(IOrigamiErc4626.ERC4626ExceededMaxRedeem.selector, alice, _max+1, _max));
            vault.redeem(_max+1, alice, alice);
        }

        redeem(alice, _max);
        assertEq(vault.maxRedeem(alice), 0);
    }

    function test_redeem_differentReceiver() public {
        deposit(alice, 200e6);
        uint256 shares = 100e18;

        vm.startPrank(alice);
        uint256 expectedAssets = vault.previewRedeem(shares);

        vm.expectEmit(address(vault));
        emit InKindFees(
            IOrigamiErc4626.FeeType.WITHDRAWAL_FEE,
            WITHDRAWAL_FEE,
            shares - shares.subtractBps(WITHDRAWAL_FEE, OrigamiMath.Rounding.ROUND_DOWN)
        );
        vm.expectEmit(address(vault));
        emit Withdraw(alice, bob, alice, expectedAssets, shares);
        uint256 actualAssets = vault.redeem(shares, bob, alice);
        vm.stopPrank();

        assertEq(actualAssets, expectedAssets);

        assertEq(vault.balanceOf(alice), 98.005009949900500994e18);
        assertEq(vault.balanceOf(bob), 0);
        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(bob), 98.987145e6);
    }

    function test_redeem_differentSender() public {
        deposit(alice, 200e6);
        uint256 shares = 100e18;

        vm.startPrank(alice);
        uint256 expectedAssets = vault.previewRedeem(shares);

        // Bob can't redeem with Alice's explicit approval
        {
            vm.startPrank(bob);
            vm.expectRevert("ERC20: insufficient allowance");
            vault.redeem(shares, bob, alice);

            vm.startPrank(alice);
            vault.approve(bob, shares);
            vm.startPrank(bob);
        }

        vm.expectEmit(address(vault));
        emit InKindFees(
            IOrigamiErc4626.FeeType.WITHDRAWAL_FEE,
            WITHDRAWAL_FEE,
            shares - shares.subtractBps(WITHDRAWAL_FEE, OrigamiMath.Rounding.ROUND_DOWN)
        );
        vm.expectEmit(address(vault));
        emit Withdraw(bob, bob, alice, expectedAssets, shares);
        uint256 actualAssets = vault.redeem(shares, bob, alice);
        vm.stopPrank();

        assertEq(actualAssets, expectedAssets);

        assertEq(vault.balanceOf(alice), 98.005009949900500994e18);
        assertEq(vault.balanceOf(bob), 0);
        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(bob), 98.987145e6);
    }
}

contract OrigamiErc4626TestAttacksJP is OrigamiErc4626With6dpTestBase {
    function test_erc4626_donationAttack_noFees_6dp() public {
        vault = new MockErc4626VaultWithFees(
            origamiMultisig, 
            "VAULT",
            "VLT",
            asset,
            0, // DEPOSIT_FEE,
            0 // WITHDRAWAL_FEE
        );
        seedDeposit(origamiMultisig, SEED_DEPOSIT_SIZE, MAX_TOTAL_SUPPLY);
        vm.warp(100000000);

        // declarations
        address attacker = makeAddr("atacker");
        uint256 initialAttackerAssets = 50_000e6;
        
        // preparations & context
        deal(address(asset), alice, 7000e6);
        deal(address(asset), attacker, initialAttackerAssets);
        assertEq(vault.balanceOf(alice), 0);

        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(attacker);
        asset.approve(address(vault), type(uint256).max);

        // The attempted attack beings. The attacker must be the first depositor of the vault, 
        // so he must front-run the first depositor (alice)  
        vm.prank(attacker);
        vault.deposit(1, attacker);
        assertEq(vault.totalSupply(), 0.1e18 + 1e12);
        assertEq(vault.totalAssets(), 0.1e6 + 1);
        assertEq(vault.convertToShares(1), 1e12);

        // right after the deposit, the attacker makes a big donation of `asset` 
        // to inflate the share price
        vm.prank(attacker);

        // The donation drives the share price down significantly
        asset.transfer(address(vault), 10_000e6);
        assertEq(vault.convertToAssets(1e18), 0.000000099999000039e18);
        assertEq(vault.totalSupply(), 0.1e18 + 1e12);
        assertEq(vault.balanceOf(attacker), vault.totalSupply() - 0.1e18);

        // An honest depositor deposits some amount of assets
        vm.startPrank(alice);
        assertEq(vault.deposit(3_000e6, alice), 0.030000299991000030e18);
        assertEq(vault.balanceOf(alice), 0.030000299991000030e18);
        assertEq(vault.balanceOf(attacker), 1e12);

        // Thanks to the inflation-attack-protection inside convertToAssets(), 
        // even though the attacker owns 100% of the shares, 
        // only a portion of them can be withdrawn. The attacker is currently at a loss.
        assertEq(vault.maxWithdraw(attacker), 0.099999e6);

        vm.startPrank(attacker);
        assertEq(vault.redeem(vault.maxRedeem(attacker), attacker, attacker), 0.099999e6);
        assertEq(vault.totalSupply(), 0.130000299991000030e18);
        assertEq(vault.balanceOf(alice), 0.030000299991000030e18);
        assertEq(vault.balanceOf(attacker), 0);

        // When the attacker redeems his shares, he IS AT A LOSS
        assertLt(asset.balanceOf(attacker), initialAttackerAssets);
        assertEq(asset.balanceOf(attacker), 40_000.099998e6);

        // Alice gets her cash back.
        vm.startPrank(alice);
        assertEq(vault.balanceOf(alice), 0.030000299991000030e18);
        assertEq(vault.maxRedeem(alice), 0.030000299991000030e18);
        assertEq(vault.redeem(vault.balanceOf(alice), alice, alice), 3_000e6);
        assertEq(asset.balanceOf(alice), 7_000e6);
    }
}
