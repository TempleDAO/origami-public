pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
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
import { OrigamiErc4626 } from "contracts/common/OrigamiErc4626.sol";

contract OrigamiErc4626TestBase is OrigamiTest {
    using OrigamiMath for uint256;

    DummyMintableToken public asset;
    MockErc4626VaultWithFees public vault;

    uint224 public constant MAX_TOTAL_SUPPLY = 100_000_000e18;
    uint16 public constant DEPOSIT_FEE = 50;
    uint16 public constant WITHDRAWAL_FEE = 200;
    uint256 public constant SEED_DEPOSIT_SIZE = 0.1e18;

    event InKindFees(IOrigamiErc4626.FeeType feeType, uint256 feeBps, uint256 feeAmount);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function setUp() public {
        asset = new DummyMintableToken(origamiMultisig, "UNDERLYING", "UDLY", 18);
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

        uint256 expectedFeeAmout = vault.convertToShares(amount) - expectedShares;
        if (expectedFeeAmout > 0) {
            vm.expectEmit(address(vault));
            emit InKindFees(
                IOrigamiErc4626.FeeType.DEPOSIT_FEE, 
                DEPOSIT_FEE, 
                expectedFeeAmout
            );
        }

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

contract OrigamiErc4626TestAdmin is OrigamiErc4626TestBase {
    event MaxTotalSupplySet(uint256 maxTotalSupply);

    function test_default_nofees() public {
        asset = new DummyMintableToken(origamiMultisig, "UNDERLYING", "UDLY", 18);
        vault = MockErc4626VaultWithFees(address(
            new OrigamiErc4626(
                origamiMultisig, 
                "VAULT",
                "VLT",
                asset
            )
        ));
        seedDeposit(origamiMultisig, SEED_DEPOSIT_SIZE, type(uint256).max);

        assertEq(vault.owner(), origamiMultisig);
        assertEq(vault.name(), "VAULT");
        assertEq(vault.symbol(), "VLT");
        assertEq(vault.asset(), address(asset));
        assertEq(vault.decimals(), 18);
        assertEq(vault.maxTotalSupply(), type(uint256).max);
        assertEq(vault.areDepositsPaused(), false);
        assertEq(vault.areWithdrawalsPaused(), false);
        assertEq(vault.totalSupply(), 0.1e18);
        assertEq(vault.totalAssets(), 0.1e18);
        assertEq(vault.convertToShares(1e18), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e18);
        assertEq(vault.maxDeposit(alice), type(uint256).max);
        assertEq(vault.maxMint(alice), type(uint256).max);
        assertEq(vault.maxWithdraw(alice), 0);
        assertEq(vault.maxRedeem(alice), 0);
        assertEq(vault.previewDeposit(1e18), 1e18);
        assertEq(vault.previewMint(1e18), 1e18);
        assertEq(vault.previewWithdraw(1e18), 1e18);
        assertEq(vault.previewRedeem(1e18), 1e18);
        // Dependent on the address, so changes
        assertEq(vault.DOMAIN_SEPARATOR(), bytes32(0xd2e843a44a91122d6c30863b00ef4f6cef005ce2bdfbe801e527b67fd3cc222c));
        assertEq(vault.areDepositsPaused(), false);
        assertEq(vault.areWithdrawalsPaused(), false);
    }

    function test_initialization() public {
        assertEq(vault.owner(), origamiMultisig);
        assertEq(vault.name(), "VAULT");
        assertEq(vault.symbol(), "VLT");
        assertEq(vault.asset(), address(asset));
        assertEq(vault.decimals(), 18);
        assertEq(vault.maxTotalSupply(), MAX_TOTAL_SUPPLY);
        assertEq(vault.areDepositsPaused(), false);
        assertEq(vault.areWithdrawalsPaused(), false);
        assertEq(vault.totalSupply(), 0.0995e18); // seed deposit minus fees
        assertEq(vault.totalAssets(), 0.1e18);
        assertEq(vault.convertToShares(1e18), 0.995e18);
        assertEq(vault.convertToAssets(1e18), 1.005025125628140703e18);

        // How many assets can be deposited to hit the total supply
        // so takes fees into consideration.
        assertEq(vault.maxDeposit(alice), 101_007_550.2138834877856366e18);
        assertEq(vault.maxMint(alice), 99_999_999.9005e18);
        assertEq(vault.maxWithdraw(alice), 0);
        assertEq(vault.maxRedeem(alice), 0);
        assertEq(vault.previewDeposit(1e18), 0.990025e18); // 50bps fee
        // 50 bps fee -- need to deposit more assets in order to get 1e18 shares
        assertEq(vault.previewMint(1e18), 1.010075503143860004e18);
        // 200 bps fee -- need to redeem more shares in order to get 1e18 assets
        assertEq(vault.previewWithdraw(1e18), 1.015306122448979593e18);
        assertEq(vault.previewRedeem(1e18), 0.984924623115577889e18); // 200bps fee

        assertEq(vault.DOMAIN_SEPARATOR(), bytes32(0xf07a1e21026e15847c4f454c9eb8f87a35787510bc37aee10796c2c8aa85ff16));
        assertEq(vault.areDepositsPaused(), false);
        assertEq(vault.areWithdrawalsPaused(), false);
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

    function test_setMaxTotalSupply_failure_zeroSupply() public {
        vault = new MockErc4626VaultWithFees(
            origamiMultisig, 
            "VAULT",
            "VLT",
            asset,
            0,
            0
        );
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        vault.setMaxTotalSupply(100e18);
    }

    function test_setMaxTotalSupply_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(vault));
        emit MaxTotalSupplySet(123_456e18);
        vault.setMaxTotalSupply(123_456e18);
        assertEq(vault.maxTotalSupply(), 123_456e18);
    }

    function test_setMaxTotalSupply_access() public {
        expectElevatedAccess();
        vault.setMaxTotalSupply(100e18);
    }

    function test_seedDeposit_failure_alreadySeeded() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        vault.seedDeposit(123e18, origamiMultisig, 123e18);
    }

    function test_seedDeposit_failure_maxTooLow() public {
        vault = new MockErc4626VaultWithFees(
            origamiMultisig, 
            "VAULT",
            "VLT",
            asset,
            0,
            0
        );
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiErc4626.ERC4626ExceededMaxDeposit.selector, origamiMultisig, 123e18, 1e18));
        vault.seedDeposit(123e18, origamiMultisig, 1e18);
    }

    function test_seedDeposit_success() public {
        vault = new MockErc4626VaultWithFees(
            origamiMultisig, 
            "VAULT",
            "VLT",
            asset,
            0,
            0
        );
        vm.startPrank(origamiMultisig);

        deal(address(asset), origamiMultisig, 123e18);
        asset.approve(address(vault), 123e18);

        vm.expectEmit(address(vault));
        emit MaxTotalSupplySet(123e18);
        assertEq(vault.seedDeposit(123e18, alice, 123e18), 123e18);
        assertEq(vault.totalSupply(), 123e18);
        assertEq(vault.totalAssets(), 123e18);
        assertEq(vault.balanceOf(alice), 123e18);
    }

    function test_withdraw_fullyUnwind() public {
        // Vaults will normally have the ability to turn off all withdrawal fees
        // Required to pull all funds out (incl the last depositor)
        // Can just use a non-fee vault to show here.
        vault = new MockErc4626VaultWithFees(
            origamiMultisig, 
            "VAULT",
            "VLT",
            asset,
            0,
            0
        );
        seedDeposit(origamiMultisig, SEED_DEPOSIT_SIZE, MAX_TOTAL_SUPPLY);
        
        assertEq(vault.balanceOf(origamiMultisig), 0.1e18);
        assertEq(vault.maxTotalSupply(), MAX_TOTAL_SUPPLY);

        vm.startPrank(origamiMultisig);
        
        assertEq(vault.redeem(vault.maxRedeem(origamiMultisig), origamiMultisig, origamiMultisig), 0.1e18);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(origamiMultisig), 0);
        assertEq(vault.maxTotalSupply(), 0); // Now back to zero like fresh

        assertEq(asset.balanceOf(origamiMultisig), 0.1e18);
    }

    function test_seedDeposit_access() public {
        expectElevatedAccess();
        vault.seedDeposit(100e18, alice, 100e18);
    }
}


contract OrigamiErc4626TestDeposit is OrigamiErc4626TestBase {
    function test_deposit_basic() public {
        deposit(alice, 123e18);

        uint256 expectedShares = 121.773075000000000005e18;

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 123e18 + 0.1e18);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), 121.872575000000000005e18);
        assertEq(vault.totalAssets(), 123e18 + 0.1e18);
    }

    function test_deposit_fail_zeroAssets() public {
        address user = alice;
        uint256 amount = 0;
        uint256 expectedShares = vault.previewDeposit(amount);

        assertEq(expectedShares, 0);
        assertEq(vault.deposit(amount, user), 0);
    }

    function test_deposit_fail_oneAssets() public {
        address user = alice;
        uint256 amount = 1;

        deal(address(asset), user, amount);
        vm.startPrank(user);
        asset.approve(address(vault), amount);
        uint256 expectedShares = vault.previewDeposit(amount);

        assertEq(expectedShares, 0);
        assertEq(vault.deposit(amount, user), 0);
    }

    function test_deposit_noFee() public {
        vault = new MockErc4626VaultWithFees(
            origamiMultisig, 
            "VAULT",
            "VLT",
            asset,
            0,
            0
        );
        seedDeposit(origamiMultisig, SEED_DEPOSIT_SIZE, MAX_TOTAL_SUPPLY);

        {
            address user = alice;
            uint256 amount = 123e18;
            deal(address(asset), user, amount);
            vm.startPrank(user);
            asset.approve(address(vault), amount);
            uint256 expectedShares = vault.previewDeposit(amount);

            vm.expectEmit(address(vault));
            emit Deposit(user, user, amount, expectedShares);
            uint256 actualShares = vault.deposit(amount, user);
            vm.stopPrank();

            assertEq(actualShares, expectedShares);
        }

        {
            assertEq(asset.balanceOf(alice), 0);
            assertEq(asset.balanceOf(address(vault)), 123e18 + 0.1e18);
            assertEq(vault.balanceOf(alice), 123e18);
            assertEq(vault.totalSupply(), 123e18 + 0.1e18);
            assertEq(vault.totalAssets(), 123e18 + 0.1e18);
        }
    }

    function test_deposit_beforeShareIncrease() public {
        deposit(alice, 123e18);

        addToSharePrice(100e18);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 223e18 + 0.1e18);
        assertEq(vault.balanceOf(alice), 121.773075e18 + 5);
        assertEq(vault.totalSupply(), 121.872575e18 + 5);
        assertEq(vault.totalAssets(), 223e18 + 0.1e18);
        assertEq(vault.convertToShares(1e18), 0.546268825638727028e18);
        assertEq(vault.convertToAssets(1e18), 1.830600526820738792e18);
    }

    function test_deposit_afterShareIncrease() public {
        deposit(bob, 100e18);

        addToSharePrice(10e18); // 10% increase
        assertEq(vault.convertToShares(1e18), 0.900108991825613079e18);
        assertEq(vault.convertToAssets(1e18), 1.110976569594962765e18);

        assertEq(vault.maxDeposit(alice), 111_655_825.989443494030216565e18);
        assertEq(vault.maxMint(alice), 99_999_900.897999999999999997e18);
        deposit(alice, 123e18);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 233e18 + 0.1e18);
        assertEq(vault.balanceOf(alice), 110.159838964577656678e18);
        assertEq(vault.totalSupply(), 209.261838964577656681e18);
        assertEq(vault.totalAssets(), 233e18 + 0.1e18);

        // Deposit fees continue to help the share price
        assertEq(vault.convertToShares(1e18), 0.897734186892225039e18);
        assertEq(vault.convertToAssets(1e18), 1.113915471417879952e18);

        deposit(alice, vault.maxDeposit(alice));
        assertEq(vault.maxDeposit(alice), 0);
    }
}

contract OrigamiErc4626TestMint is OrigamiErc4626TestBase {
    function test_mint_basic() public {
        mint(alice, 123e18);

        uint256 expectedAssets = 124.339286886694780429e18;

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), expectedAssets);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 123e18 + 0.0995e18);
        assertEq(vault.totalAssets(), expectedAssets);
    }

    function test_mint_fail_zeroShares() public {
        vault = new MockErc4626VaultWithFees(
            origamiMultisig, 
            "VAULT",
            "VLT",
            asset,
            0,
            0
        );
        seedDeposit(origamiMultisig, SEED_DEPOSIT_SIZE, MAX_TOTAL_SUPPLY);

        address user = alice;
        uint256 shares = 0;

        uint256 expectedAssets = vault.previewMint(shares);
        assertEq(expectedAssets, 0);

        assertEq(vault.mint(shares, user), 0);
    }

    function test_mint_success_oneShares() public {
        vault = new MockErc4626VaultWithFees(
            origamiMultisig, 
            "VAULT",
            "VLT",
            asset,
            0,
            0
        );
        seedDeposit(origamiMultisig, SEED_DEPOSIT_SIZE, MAX_TOTAL_SUPPLY);

        // OK as it gets rounded up.
        address user = alice;
        uint256 shares = 1;
        uint256 expectedAssets = vault.previewMint(shares);

        deal(address(asset), user, expectedAssets);
        vm.startPrank(user);
        asset.approve(address(vault), expectedAssets);

        assertEq(expectedAssets, 1);
        vault.mint(shares, user);
    }

    function test_mint_noFee() public {
        vault = new MockErc4626VaultWithFees(
            origamiMultisig, 
            "VAULT",
            "VLT",
            asset,
            0,
            0
        );
        seedDeposit(origamiMultisig, SEED_DEPOSIT_SIZE, MAX_TOTAL_SUPPLY);

        {
            address user = alice;
            uint256 shares = 123e18;
            uint256 expectedAssets = vault.previewMint(shares);
            deal(address(asset), user, expectedAssets);
            vm.startPrank(user);
            asset.approve(address(vault), expectedAssets);

            vm.expectEmit(address(vault));
            emit Deposit(user, user, expectedAssets, shares);
            uint256 actualAssets = vault.mint(shares, user);
            vm.stopPrank();

            assertEq(actualAssets, expectedAssets);
        }

        {
            uint256 expectedShares = 123e18;

            assertEq(asset.balanceOf(alice), 0);
            assertEq(asset.balanceOf(address(vault)), 123e18 + 0.1e18);
            assertEq(vault.balanceOf(alice), expectedShares);
            assertEq(vault.totalSupply(), expectedShares + 0.1e18);
            assertEq(vault.totalAssets(), 123e18 + 0.1e18);
        }
    }

    function test_mint_beforeShareIncrease() public {
        mint(alice, 123e18);

        addToSharePrice(100e18);

        uint256 expectedAssets = 224.339286886694780429e18;

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), expectedAssets);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 123e18 + 0.0995e18);
        assertEq(vault.totalAssets(), expectedAssets);
        assertEq(vault.convertToShares(1e18), 0.548720207273248860e18);
        assertEq(vault.convertToAssets(1e18), 1.822422405344414724e18);
    }

    function test_mint_afterShareIncrease() public {
        mint(bob, 100e18);

        addToSharePrice(10e18); // 10% increase
        assertEq(vault.convertToShares(1e18), 0.900924372076982977e18);
        assertEq(vault.convertToAssets(1e18), 1.109971081917352238e18);

        assertEq(vault.maxDeposit(alice), 111_554_770.938879305944932140e18);
        assertEq(vault.maxMint(alice), 99_999_899.9005e18);
        mint(alice, 123e18);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 248.320055918239593592e18);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 223e18 + 0.0995e18);

        // Deposit fees continue to help the share price
        assertEq(vault.convertToShares(1e18), 0.898435284153835862e18);
        assertEq(vault.convertToAssets(1e18), 1.113046223403636465e18);
    }
}

contract OrigamiErc4626TestWithdraw is OrigamiErc4626TestBase {
    function test_withdraw_basic() public {
        deposit(alice, 123e18);

        withdraw(alice, 50e18);

        assertEq(asset.balanceOf(alice), 50e18);
        assertEq(asset.balanceOf(address(vault)), 73e18 + 0.1e18);
        assertEq(vault.balanceOf(alice), 71.261389212768779325e18);
        assertEq(vault.totalSupply(), 71.360889212768779325e18);
        assertEq(vault.totalAssets(), 73e18 + 0.1e18);
    }

    function test_withdraw_fail_zeroAssets() public {
        vault = new MockErc4626VaultWithFees(
            origamiMultisig, 
            "VAULT",
            "VLT",
            asset,
            0,
            0
        );
        seedDeposit(origamiMultisig, SEED_DEPOSIT_SIZE, MAX_TOTAL_SUPPLY);

        deposit(alice, 1);
        assertEq(vault.balanceOf(alice), 1);

        address user = alice;
        uint256 assets = 0;

        vm.startPrank(user);
        uint256 expectedShares = vault.previewWithdraw(assets);
        assertEq(expectedShares, 0);

        assertEq(vault.withdraw(assets, user, user), 0);
    }

    function test_withdraw_success_oneAssets() public {
        vault = new MockErc4626VaultWithFees(
            origamiMultisig, 
            "VAULT",
            "VLT",
            asset,
            0,
            0
        );
        seedDeposit(origamiMultisig, SEED_DEPOSIT_SIZE, MAX_TOTAL_SUPPLY);

        deposit(alice, 1);
        assertEq(vault.balanceOf(alice), 1);

        address user = alice;
        uint256 assets = 1;

        vm.startPrank(user);
        uint256 expectedShares = vault.previewWithdraw(assets);
        assertEq(expectedShares, 1);

        vault.withdraw(assets, user, user);
    }

    function test_withdraw_noFee() public {
        vault = new MockErc4626VaultWithFees(
            origamiMultisig, 
            "VAULT",
            "VLT",
            asset,
            0,
            0
        );
        seedDeposit(origamiMultisig, SEED_DEPOSIT_SIZE, MAX_TOTAL_SUPPLY);

        {
            address user = alice;
            uint256 shares = 123e18;
            uint256 expectedAssets = vault.previewMint(shares);
            deal(address(asset), user, expectedAssets);
            vm.startPrank(user);
            asset.approve(address(vault), expectedAssets);
            vault.mint(shares, user);
            vm.stopPrank();
        }

        {
            address user = alice;
            uint256 assets = 50e18;

            vm.startPrank(user);
            uint256 expectedShares = vault.previewWithdraw(assets);

            vm.expectEmit(address(vault));
            emit Withdraw(user, user, user, assets, expectedShares);
            uint256 actualShares = vault.withdraw(assets, user, user);
            vm.stopPrank();

            assertEq(actualShares, expectedShares);
        }

        {
            assertEq(asset.balanceOf(alice), 50e18);
            assertEq(asset.balanceOf(address(vault)), 73e18 + 0.1e18);
            assertEq(vault.balanceOf(alice), 73e18);
            assertEq(vault.totalSupply(), 73e18 + 0.1e18);
            assertEq(vault.totalAssets(), 73e18 + 0.1e18);
        }
    }

    function test_withdraw_beforeShareIncrease() public {
        deposit(alice, 123e18);

        withdraw(alice, 50e18);
        addToSharePrice(100e18);

        assertEq(asset.balanceOf(alice), 50e18);
        assertEq(asset.balanceOf(address(vault)), 173e18 + 0.1e18);
        assertEq(vault.balanceOf(alice), 71.261389212768779325e18);
        assertEq(vault.totalSupply(), 71.360889212768779325e18);
        assertEq(vault.totalAssets(), 173e18 + 0.1e18);
        assertEq(vault.convertToShares(1e18), 0.412252392910276021e18);
        assertEq(vault.convertToAssets(1e18), 2.425698473065366336e18);
    }

    function test_withdraw_afterShareIncrease() public {
        deposit(alice, 100e18);

        addToSharePrice(10e18); // 10% increase
        assertEq(vault.convertToShares(1e18), 0.900108991825613079e18);
        assertEq(vault.convertToAssets(1e18), 1.110976569594962765e18);

        assertEq(vault.maxWithdraw(alice), 107.789668674698795179e18);
        assertEq(vault.maxRedeem(alice), 99.0025e18 + 3);
        withdraw(alice, 50e18);

        assertEq(asset.balanceOf(alice), 50e18);
        assertEq(asset.balanceOf(address(vault)), 60e18 + 0.1e18);
        assertEq(vault.balanceOf(alice), 53.078571845631985765e18);
        assertEq(vault.totalSupply(), 53.178071845631985765e18);
        assertEq(vault.totalAssets(), 60e18 + 0.1e18);

        // Withdrawal fees continue to help the share price
        assertEq(vault.convertToShares(1e18), 0.884826486616172808e18);
        assertEq(vault.convertToAssets(1e18), 1.130165083353554820e18);
    }

    function test_maxWithdraw_addressZero() public {
        // Default implementation has no constraints
        assertEq(vault.maxWithdraw(address(0)), type(uint256).max);
    }
}

contract OrigamiErc4626TestRedeem is OrigamiErc4626TestBase {
    function test_redeem_basic() public {
        deposit(alice, 123e18);

        redeem(alice, 50e18);

        assertEq(asset.balanceOf(alice), 49.493497614208939129e18);
        assertEq(asset.balanceOf(address(vault)), 73.606502385791060871e18);
        assertEq(vault.balanceOf(alice), 71.773075000000000005e18);
        assertEq(vault.totalSupply(), 71.872575000000000005e18);
        assertEq(vault.totalAssets(), 73.606502385791060871e18);
    }

    function test_redeem_ok_zeroShares() public {
        vault = new MockErc4626VaultWithFees(
            origamiMultisig, 
            "VAULT",
            "VLT",
            asset,
            0,
            WITHDRAWAL_FEE
        );
        seedDeposit(origamiMultisig, SEED_DEPOSIT_SIZE, MAX_TOTAL_SUPPLY);

        deposit(alice, 1);
        assertEq(vault.balanceOf(alice), 1);

        address user = alice;
        uint256 shares = 0;

        vm.startPrank(user);

        assertEq(vault.redeem(shares, user, user), 0);
    }

    function test_redeem_fail_oneShares() public {
        vault = new MockErc4626VaultWithFees(
            origamiMultisig, 
            "VAULT",
            "VLT",
            asset,
            0,
            WITHDRAWAL_FEE
        );
        seedDeposit(origamiMultisig, SEED_DEPOSIT_SIZE, MAX_TOTAL_SUPPLY);

        deposit(alice, 1);
        assertEq(vault.balanceOf(alice), 1);

        address user = alice;
        uint256 shares = 1;

        // Alice gets zero shares - but this is acceptable
        // There could be a valid scenario where redeeming dust gives zero assets.
        vm.startPrank(user);
        assertEq(vault.redeem(shares, user, user), 0);
    }

    function test_redeem_noFee() public {
        vault = new MockErc4626VaultWithFees(
            origamiMultisig, 
            "VAULT",
            "VLT",
            asset,
            0,
            0
        );
        seedDeposit(origamiMultisig, SEED_DEPOSIT_SIZE, MAX_TOTAL_SUPPLY);

        {
            address user = alice;
            uint256 shares = 123e18;
            uint256 expectedAssets = vault.previewMint(shares);
            deal(address(asset), user, expectedAssets);
            vm.startPrank(user);
            asset.approve(address(vault), expectedAssets);
            vault.mint(shares, user);
            vm.stopPrank();
        }

        {
            address user = alice;
            uint256 shares = 50e18;
            vm.startPrank(user);
            uint256 expectedAssets = vault.previewRedeem(shares);

            vm.expectEmit(address(vault));
            emit Withdraw(user, user, user, expectedAssets, shares);
            uint256 actualAssets = vault.redeem(shares, user, user);
            vm.stopPrank();

            assertEq(actualAssets, expectedAssets);
        }

        {
            assertEq(asset.balanceOf(alice), 50e18);
            assertEq(asset.balanceOf(address(vault)), 73e18 + 0.1e18);
            assertEq(vault.balanceOf(alice), 73e18);
            assertEq(vault.totalSupply(), 73e18 + 0.1e18);
            assertEq(vault.totalAssets(), 73e18 + 0.1e18);
        }
    }

    function test_redeem_beforeShareIncrease() public {
        deposit(alice, 123e18);

        redeem(alice, 50e18);
        addToSharePrice(100e18);

        assertEq(asset.balanceOf(alice), 49.493497614208939129e18);
        assertEq(asset.balanceOf(address(vault)), 173.606502385791060871e18);
        assertEq(vault.balanceOf(alice), 71.773075000000000005e18);
        assertEq(vault.totalSupply(), 71.872575000000000005e18);
        assertEq(vault.totalAssets(), 173.606502385791060871e18);
        assertEq(vault.convertToShares(1e18), 0.413997022071694351e18);
        assertEq(vault.convertToAssets(1e18), 2.415476311872658811e18);
    }

    function test_redeem_afterShareIncrease() public {
        deposit(alice, 100e18);

        addToSharePrice(10e18); // 10% increase
        assertEq(vault.convertToShares(1e18), 0.900108991825613079e18);
        assertEq(vault.convertToAssets(1e18), 1.110976569594962765e18);

        assertEq(vault.maxWithdraw(alice), 107.789668674698795179e18);
        assertEq(vault.maxRedeem(alice), 99.002500000000000003e18);
        redeem(alice, 50e18);

        assertEq(asset.balanceOf(alice), 54.437851910153175514e18);
        assertEq(asset.balanceOf(address(vault)), 55.662148089846824486e18);
        assertEq(vault.balanceOf(alice), 49.002500000000000003e18);
        assertEq(vault.totalSupply(), 49.102000000000000003e18);
        assertEq(vault.totalAssets(), 55.662148089846824486e18);

        // Withdrawal fees continue to help the share price
        assertEq(vault.convertToShares(1e18), 0.882143461670617009e18);
        assertEq(vault.convertToAssets(1e18), 1.133602462014720876e18);
    }

    function test_maxRedeem_addressZero() public {
        // Default implementation has no constraints
        assertEq(vault.maxRedeem(address(0)), type(uint256).max);
    }
}

contract OrigamiErc4626TestPermit is OrigamiErc4626TestBase {
    bytes32 private constant _TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function buildDomainSeparator() internal view returns (bytes32) {
        bytes32 _hashedName = keccak256(bytes(vault.name()));
        bytes32 _hashedVersion = keccak256(bytes("1"));
        return keccak256(abi.encode(_TYPE_HASH, _hashedName, _hashedVersion, block.chainid, address(vault)));
    }

    function signedPermit(
        address signer, 
        uint256 signerPk, 
        address spender, 
        uint256 amount, 
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 domainSeparator = buildDomainSeparator();
        bytes32 structHash = keccak256(abi.encode(_PERMIT_TYPEHASH, signer, spender, amount, vault.nonces(signer), deadline));
        bytes32 typedDataHash = ECDSA.toTypedDataHash(domainSeparator, structHash);
        return vm.sign(signerPk, typedDataHash);
    }

    function test_permit() public {
        (address signer, uint256 signerPk) = makeAddrAndKey("signer");
        address spender = makeAddr("spender");
        uint256 amount = 123;

        assertEq(vault.nonces(signer), 0);
        uint256 allowanceBefore = vault.allowance(signer, spender);

        // Check for expired deadlines
        uint256 deadline = block.timestamp-1;
        (uint8 v, bytes32 r, bytes32 s) = signedPermit(signer, signerPk, spender, amount, deadline);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiErc4626.ERC2612ExpiredSignature.selector, 99999999));

        vault.permit(signer, spender, amount, deadline, v, r, s);

        // Permit successfully increments the allowance
        deadline = block.timestamp + 3600;
        (v, r, s) = signedPermit(signer, signerPk, spender, amount, deadline);
        vault.permit(signer, spender, amount, deadline, v, r, s);
        assertEq(vault.allowance(signer, spender), allowanceBefore+amount);
        assertEq(vault.nonces(signer), 1);

        // Can't re-use the same signature for another permit (the nonce was incremented)
        address wrongRecoveryAddr = 0x600f8fed65c3a29D7854CB8366bA22a0e09Bdaba;
        vm.expectRevert(abi.encodeWithSelector(IOrigamiErc4626.ERC2612InvalidSigner.selector, wrongRecoveryAddr, signer));

        vault.permit(signer, spender, amount, deadline, v, r, s);
    }
}

contract OrigamiErc4626TestAttacksSB is OrigamiErc4626TestBase {
    function test_erc4626_failedInflationAttack_fees() public {
        asset = new DummyMintableToken(origamiMultisig, "UNDERLYING", "UDLY", 18);
        vault = new MockErc4626VaultWithFees(
            origamiMultisig, 
            "VAULT",
            "VLT",
            asset,
            DEPOSIT_FEE,
            0 // Remove withdraw fee
        );
        seedDeposit(origamiMultisig, SEED_DEPOSIT_SIZE, MAX_TOTAL_SUPPLY);

        vm.warp(100000000);

        // Bob deposits a small amount and gets 1 share
        {
            deposit(bob, 3);
            assertEq(vault.balanceOf(bob), 1);
        }
        
        // Bob donates to the vault
        {
            deal(address(asset), bob, 10000e18);
            vm.prank(bob);
            asset.transfer(address(vault), 10000e18);

            assertEq(vault.totalAssets(), 10_000e18 + 3 + 0.1e18); // 10000e18 + 3
            assertEq(vault.totalSupply(), 0.0995e18 + 1);  // 1 share for Bob
        }

        // Alice deposits
        {
            address user = alice;
            uint256 amount = 10_000e18;
            deal(address(asset), user, amount);
            vm.startPrank(user);
            asset.approve(address(vault), amount);

            assertEq(vault.deposit(amount, user), 0.099001509984900152e18);
        }

        // Bob redeems - but doing this leaves donation assets in the vault,
        // so he loses out.
        {
            vm.startPrank(bob);
            assertEq(vault.redeem(vault.balanceOf(bob), bob, bob), 100755);

            assertEq(vault.totalAssets(), 20_000.099999999999899248e18);
            assertEq(vault.totalSupply(), 0.198501509984900152e18);
        }
    }
}

contract OrigamiErc4626TestAttacksJP is OrigamiErc4626TestBase {
    function test_erc4626_donationAttack_withFees() public {
        // declarations
        address attacker = makeAddr("atacker");
        uint256 initialAttackerAssets = 25_000e18 + 3;

        // preparations & context
        deal(address(asset), alice, 10000e18);
        deal(address(asset), attacker, initialAttackerAssets);
        assertEq(vault.balanceOf(alice), 0);

        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(attacker);
        asset.approve(address(vault), type(uint256).max);

        // The attempted attack beings. The attacker must be the first depositor of the vault, 
        // so he must front-run the first depositor (alice) 
        vm.prank(attacker);
        vault.deposit(3, attacker);
        assertEq(vault.totalSupply(), 0.0995e18 + 1);
        assertEq(vault.totalAssets(), 0.1e18 + 3);
        assertEq(vault.convertToShares(3), 2);

        // right after the deposit, the attacker makes a donation of `asset` with the same amount as alice deposit
        // Share price decreases massively
        vm.prank(attacker);
        asset.transfer(address(vault), 10_000e18);
        assertEq(vault.convertToAssets(1), 100503);
        assertEq(vault.totalSupply(), 0.0995e18 + 1);
        assertEq(vault.balanceOf(attacker), vault.totalSupply() - 0.0995e18);

        // An honest depositor deposits the amount that the attacker front run him with (10000e18)
        vm.prank(alice);
        vault.deposit(10000e18, alice);
        assertEq(vault.balanceOf(alice), 0.099001509984900152e18);
        assertEq(vault.totalSupply(), 0.198501509984900153e18);

        assertEq(vault.maxWithdraw(attacker), 0);

        vm.startPrank(attacker);
        vault.redeem(vault.maxRedeem(attacker), attacker, attacker);
        assertEq(vault.totalSupply(), 0.198501509984900152e18);
        assertEq(vault.balanceOf(attacker), 0);
        assertEq(vault.totalAssets(), 20_000e18 + 0.1e18 + 3);
        assertEq(asset.balanceOf(attacker), 15_000e18);

        assertEq(vault.deposit(15000e18, attacker), 0.148131011171175883e18);

        assertEq(vault.totalSupply(), 0.346632521156076035e18);
        assertEq(vault.balanceOf(attacker), 0.148131011171175883e18);

        vm.startPrank(alice); 
        assertEq(vault.totalAssets(), 20_000e18 + 0.1e18 + 3 + 15_000e18);      
        assertEq(vault.maxWithdraw(alice), 9796.430765655325281390e18);
        assertEq(vault.redeem(vault.maxRedeem(alice), alice, alice), 9796.430765655325281390e18);

        vm.startPrank(attacker); 
        assertEq(vault.redeem(vault.maxRedeem(attacker), attacker, attacker), 14_775.112743048338451082e18);

        // Origami Multisig ends up with the donated amount!
        vm.startPrank(origamiMultisig);
        assertEq(vault.redeem(vault.maxRedeem(origamiMultisig), origamiMultisig, origamiMultisig), 10_219.985361470409439467e18);

        // Some fees left. On a real shutdown withdraw fees would be turned off
        assertEq(vault.totalAssets(), 208.571129825926828064e18);
        assertEq(asset.balanceOf(attacker), 14775.112743048338451082e18); // down bad
        assertEq(asset.balanceOf(alice), 9796.430765655325281390e18); // down a bit from fees
        assertEq(asset.balanceOf(origamiMultisig), 10_219.985361470409439467e18); // up big from donation + fees
        assertEq(vault.balanceOf(attacker), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.maxTotalSupply(), 0); // reset back to zero
    }

    function test_erc4626_donationAttack_noFees() public {
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
        uint256 initialAttackerAssets = 50_000e18;
        
        // preparations & context
        deal(address(asset), alice, 7000e18);
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
        assertEq(vault.totalSupply(), 0.1e18 + 1);
        assertEq(vault.totalAssets(), 0.1e18 + 1);
        assertEq(vault.convertToShares(1), 1);

        // right after the deposit, the attacker makes a big donation of `asset` 
        // to inflate the share price
        vm.prank(attacker);

        // The donation drives the share price down significantly
        asset.transfer(address(vault), 10_000e18);
        assertEq(vault.convertToAssets(1), 100000);
        assertEq(vault.totalSupply(), 0.1e18 + 1);
        assertEq(vault.balanceOf(attacker), vault.totalSupply() - 0.1e18);

        // An honest depositor deposits some amount of assets
        vm.startPrank(alice);
        assertEq(vault.deposit(3_000e18, alice), 0.02999970000299997e18);
        assertEq(vault.balanceOf(alice), 0.02999970000299997e18);
        assertEq(vault.balanceOf(attacker), 1);

        // Thanks to the inflation-attack-protection inside convertToAssets(), 
        // even though the attacker owns 100% of the shares, 
        // only a portion of them can be withdrawn. The attacker is currently at a loss.
        assertEq(vault.maxWithdraw(attacker), 100000);

        vm.startPrank(attacker);
        assertEq(vault.redeem(vault.maxRedeem(attacker), attacker, attacker), 100000);
        assertEq(vault.totalSupply(), 0.1e18 + 0.029999700002999970e18);
        assertEq(vault.balanceOf(alice), 0.02999970000299997e18);
        assertEq(vault.balanceOf(attacker), 0);

        // When the attacker redeems his shares, he IS AT A LOSS
        assertLt(asset.balanceOf(attacker), initialAttackerAssets);
        assertEq(asset.balanceOf(attacker), 40_000.000000000000099999e18);
    }
}
