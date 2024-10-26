pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { MockSDaiToken } from "contracts/test/external/maker/MockSDaiToken.m.sol";
import { OrigamiSuperSavingsUsdsVault } from "contracts/investments/sky/OrigamiSuperSavingsUsdsVault.sol";
import { OrigamiSuperSavingsUsdsManager } from "contracts/investments/sky/OrigamiSuperSavingsUsdsManager.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { IOrigamiErc4626 } from "contracts/interfaces/common/IOrigamiErc4626.sol";

contract OrigamiSuperSavingsUsdsVaultTestBase is OrigamiTest {
    using OrigamiMath for uint256;

    DummyMintableToken public asset;
    MockSDaiToken public sUSDS; 
    OrigamiSuperSavingsUsdsVault public vault;
    OrigamiSuperSavingsUsdsManager public manager;
    TokenPrices public tokenPrices;
    address public swapper = makeAddr("swapper");

    uint96 public constant SUSDS_INTEREST_RATE = 0.05e18;
    uint32 public constant SWITCH_FARM_COOLDOWN = 1 days;
    uint16 public constant PERF_FEE_FOR_CALLER = 100; // 1%
    uint16 public constant PERF_FEE_FOR_ORIGAMI = 400; // 4%

    uint256 public constant DEPOSIT_FEE = 0;
    uint256 public constant BOOTSTRAPPED_USDS_AMOUNT = 100_000_000e18;

    event InKindFees(IOrigamiErc4626.FeeType feeType, uint256 feeBps, uint256 feeAmount);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function setUp() public {
        asset = new DummyMintableToken(origamiMultisig, "USDS", "USDS", 18);
        sUSDS = new MockSDaiToken(asset);
        sUSDS.setInterestRate(SUSDS_INTEREST_RATE);
        doMint(asset, address(sUSDS), BOOTSTRAPPED_USDS_AMOUNT);

        tokenPrices = new TokenPrices(30);
        vault = new OrigamiSuperSavingsUsdsVault(
            origamiMultisig, 
            "Origami sUSDS+s", 
            "sUSDS+s",
            asset,
            address(tokenPrices)
        );

        manager = new OrigamiSuperSavingsUsdsManager(
            origamiMultisig,
            address(vault),
            address(sUSDS),
            SWITCH_FARM_COOLDOWN,
            swapper,
            feeCollector,
            PERF_FEE_FOR_CALLER,
            PERF_FEE_FOR_ORIGAMI
        );

        vm.startPrank(origamiMultisig);
        vault.setManager(address(manager));
        vm.stopPrank();

        seedDeposit(origamiMultisig, 0.1e18, type(uint256).max);
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
        emit Deposit(user, user, expectedAssets, shares);
        uint256 actualAssets = vault.mint(shares, user);
        vm.stopPrank();

        assertEq(actualAssets, expectedAssets);
    }

    function withdraw(address user, uint256 assets) internal {
        vm.startPrank(user);
        uint256 expectedShares = vault.previewWithdraw(assets);

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
        emit Withdraw(user, user, user, expectedAssets, shares);
        uint256 actualAssets = vault.redeem(shares, user, user);
        vm.stopPrank();

        assertEq(actualAssets, expectedAssets);
    }

    function addToSharePrice(uint256 amount) internal {
        deal(address(asset), address(manager), asset.balanceOf(address(manager)) + amount);
    }
}

contract OrigamiSuperSavingsUsdsVaultTestAdmin is OrigamiSuperSavingsUsdsVaultTestBase {
    event TokenPricesSet(address indexed tokenPrices);
    event ManagerSet(address indexed manager);

    function test_initialization() public {
        assertEq(vault.owner(), origamiMultisig);
        assertEq(vault.name(), "Origami sUSDS+s");
        assertEq(vault.symbol(), "sUSDS+s");
        assertEq(vault.asset(), address(asset));
        assertEq(vault.decimals(), 18);
        assertEq(address(vault.manager()), address(manager));
        assertEq(address(vault.tokenPrices()), address(tokenPrices));
        assertEq(vault.performanceFeeBps(), 500);
        assertEq(vault.maxTotalSupply(), type(uint256).max);
        assertEq(vault.totalSupply(), 0.1e18);
        assertEq(vault.totalAssets(), 0.1e18);
        assertEq(vault.convertToShares(1e18), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e18);
        assertEq(vault.maxDeposit(alice), type(uint256).max);
        assertEq(vault.maxMint(alice), type(uint256).max);
        assertEq(vault.maxWithdraw(alice), 0);
        assertEq(vault.maxRedeem(alice), 0);
        assertEq(vault.previewDeposit(1e18), 1e18); // no fees
        assertEq(vault.previewMint(1e18), 1e18); // no fees
        assertEq(vault.previewWithdraw(1e18), 1e18); // no fees
        assertEq(vault.previewRedeem(1e18), 1e18); // no fees
        assertEq(vault.areDepositsPaused(), false);
        assertEq(vault.areWithdrawalsPaused(), false);
    }

    function test_setManager_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        vault.setManager(address(0));
    }

    function test_setManager_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(vault));
        emit ManagerSet(alice);
        vault.setManager(alice);
        assertEq(address(vault.manager()), alice);
    }

    function test_setTokenPrices_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        vault.setTokenPrices(address(0));
    }

    function test_setTokenPrices_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(vault));
        emit TokenPricesSet(alice);
        vault.setTokenPrices(alice);
        assertEq(address(vault.tokenPrices()), alice);
    }
}

contract OrigamiSuperSavingsUsdsVaultTestAccess is OrigamiSuperSavingsUsdsVaultTestBase {
    event PerformanceFeeSet(uint256 fee);
    
    function test_setManager_access() public {
        expectElevatedAccess();
        vault.setManager(alice);
    }

    function test_setTokenPrices_access() public {
        expectElevatedAccess();
        vault.setTokenPrices(alice);
    }

    function test_logPerformanceFeesSet_access() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        vault.logPerformanceFeesSet(123);

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        vault.logPerformanceFeesSet(123);

        vm.startPrank(address(manager));
        vm.expectEmit(address(vault));
        emit PerformanceFeeSet(123);
        vault.logPerformanceFeesSet(123);
    }
}

contract OrigamiSuperSavingsUsdsVaultTestDeposit is OrigamiSuperSavingsUsdsVaultTestBase {
    function test_deposit_basic() public {
        deposit(alice, 123e18);

        uint256 expectedShares = OrigamiMath.subtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_DOWN);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 0);
        assertEq(asset.balanceOf(address(sUSDS)), BOOTSTRAPPED_USDS_AMOUNT + 123e18 + 0.1e18);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), 123e18 + 0.1e18);
        assertEq(vault.totalAssets(), 123e18 + 0.1e18);
    }

    function test_deposit_beforeShareIncrease() public {
        deposit(alice, 123e18);

        addToSharePrice(100e18);

        uint256 expectedShares = OrigamiMath.subtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_DOWN);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 100e18); // donation
        assertEq(asset.balanceOf(address(sUSDS)), BOOTSTRAPPED_USDS_AMOUNT + 123e18 + 0.1e18);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), 123e18 + 0.1e18);
        assertEq(vault.totalAssets(), 100e18 + 123e18 + 0.1e18);
        assertEq(vault.convertToShares(1e18), 0.551770506499327655e18);
        assertEq(vault.convertToAssets(1e18), 1.812347684809098294e18);
    }

    function test_deposit_afterShareIncrease() public {
        deposit(bob, 100e18);

        addToSharePrice(10e18); // 10% increase
        assertEq(vault.convertToShares(1e18), 0.909173478655767484e18);
        assertEq(vault.convertToAssets(1e18), 1.099900099900099900e18);

        assertEq(vault.maxDeposit(alice), type(uint256).max);
        assertEq(vault.maxMint(alice), type(uint256).max);
        deposit(alice, 123e18);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 0); // donation was added into sUSDS
        assertEq(asset.balanceOf(address(sUSDS)), BOOTSTRAPPED_USDS_AMOUNT + 233e18 + 0.1e18);
        assertEq(vault.balanceOf(alice), 111.828337874659400545e18);
        assertEq(vault.totalSupply(), 211.928337874659400545e18);
        assertEq(vault.totalAssets(), 233e18 + 0.1e18);

        // Deposit fees continue to help the share price
        assertEq(vault.convertToShares(1e18), 0.909173478655767484e18);
        assertEq(vault.convertToAssets(1e18), 1.099900099900099900e18);
    }
}

contract OrigamiSuperSavingsUsdsVaultTestMint is OrigamiSuperSavingsUsdsVaultTestBase {
    function test_mint_basic() public {
        mint(alice, 123e18);

        uint256 expectedAssets = OrigamiMath.inverseSubtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_UP);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 0);
        assertEq(asset.balanceOf(address(sUSDS)), BOOTSTRAPPED_USDS_AMOUNT + expectedAssets + 0.1e18);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 123e18 + 0.1e18);
        assertEq(vault.totalAssets(), 123e18 + 0.1e18);
    }

    function test_mint_beforeShareIncrease() public {
        mint(alice, 123e18);

        addToSharePrice(100e18);

        uint256 expectedAssets = 100e18 + OrigamiMath.inverseSubtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_UP);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 100e18);
        assertEq(asset.balanceOf(address(sUSDS)), BOOTSTRAPPED_USDS_AMOUNT + expectedAssets - 100e18 + 0.1e18);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 123e18 + 0.1e18);
        assertEq(vault.totalAssets(), expectedAssets + 0.1e18);
        assertEq(vault.convertToShares(1e18), 0.551770506499327655e18);
        assertEq(vault.convertToAssets(1e18), 1.812347684809098294e18);
    }

    function test_mint_afterShareIncrease() public {
        mint(bob, 100e18);

        addToSharePrice(10e18); // 10% increase
        assertEq(vault.convertToShares(1e18), 0.909173478655767484e18);
        assertEq(vault.convertToAssets(1e18), 1.099900099900099900e18);

        assertEq(vault.maxDeposit(alice), type(uint256).max);
        assertEq(vault.maxMint(alice), type(uint256).max);
        mint(alice, 123e18);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 0);
        assertEq(asset.balanceOf(address(sUSDS)), BOOTSTRAPPED_USDS_AMOUNT + 245.387712287712287713e18);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 223e18 + 0.1e18);

        // Deposit fees continue to help the share price
        assertEq(vault.convertToShares(1e18), 0.909173478655767484e18);
        assertEq(vault.convertToAssets(1e18), 1.099900099900099900e18);
    }
}

contract OrigamiSuperSavingsUsdsVaultTestWithdraw is OrigamiSuperSavingsUsdsVaultTestBase {
    function test_withdraw_basic() public {
        deposit(alice, 123e18);

        withdraw(alice, 50e18);

        uint256 expectedShares = 73e18;

        assertEq(asset.balanceOf(alice), 50e18);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 0);
        assertEq(asset.balanceOf(address(sUSDS)), BOOTSTRAPPED_USDS_AMOUNT + 73e18 + 0.1e18);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares + 0.1e18);
        assertEq(vault.totalAssets(), 73e18 + 0.1e18);
    }

    function test_withdraw_beforeShareIncrease() public {
        deposit(alice, 123e18);

        withdraw(alice, 50e18);
        addToSharePrice(100e18);

        uint256 expectedShares = 73e18;

        assertEq(asset.balanceOf(alice), 50e18);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 100e18);
        assertEq(asset.balanceOf(address(sUSDS)), BOOTSTRAPPED_USDS_AMOUNT + 73e18 + 0.1e18);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares + 0.1e18);
        assertEq(vault.totalAssets(), 173e18 + 0.1e18);
        assertEq(vault.convertToShares(1e18), 0.422299248989023685e18);
        assertEq(vault.convertToAssets(1e18), 2.367989056087551299e18);
    }

    function test_withdraw_afterShareIncrease() public {
        deposit(alice, 100e18);

        addToSharePrice(10e18); // 10% increase
        assertEq(vault.convertToShares(1e18), 0.909173478655767484e18);
        assertEq(vault.convertToAssets(1e18), 1.099900099900099900e18);

        assertEq(vault.maxWithdraw(alice), 109.990009990009990009e18);
        assertEq(vault.maxRedeem(alice), 100e18);
        withdraw(alice, 50e18);

        assertEq(asset.balanceOf(alice), 50e18);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 10e18);
        assertEq(asset.balanceOf(address(sUSDS)), BOOTSTRAPPED_USDS_AMOUNT + 50e18 + 0.1e18);
        assertEq(vault.balanceOf(alice), 54.541326067211625794e18);
        assertEq(vault.totalSupply(), 54.641326067211625794e18);
        assertEq(vault.totalAssets(), 60e18 + 0.1e18);

        // Withdrawal fees continue to help the share price
        assertEq(vault.convertToShares(1e18), 0.909173478655767484e18);
        assertEq(vault.convertToAssets(1e18), 1.099900099900099900e18);
    }
}

contract OrigamiSuperSavingsUsdsVaultTestRedeem is OrigamiSuperSavingsUsdsVaultTestBase {
    function test_redeem_basic() public {
        deposit(alice, 123e18);

        redeem(alice, 50e18);

        uint256 expectedShares = OrigamiMath.subtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_DOWN) - 50e18;
        uint256 expectedAssets = 123e18 - 50e18;

        assertEq(asset.balanceOf(alice), 50e18);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 0);
        assertEq(asset.balanceOf(address(sUSDS)), BOOTSTRAPPED_USDS_AMOUNT + expectedAssets + 0.1e18);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares + 0.1e18);
        assertEq(vault.totalAssets(), expectedAssets + 0.1e18);
    }

    function test_redeem_beforeShareIncrease() public {
        deposit(alice, 123e18);

        redeem(alice, 50e18);
        addToSharePrice(100e18);

        uint256 expectedShares = OrigamiMath.subtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_DOWN) - 50e18;
        uint256 expectedAssets = 100e18 + 123e18 - 50e18;

        assertEq(asset.balanceOf(alice), 50e18);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 100e18);
        assertEq(asset.balanceOf(address(sUSDS)), BOOTSTRAPPED_USDS_AMOUNT + 73e18 + 0.1e18);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares + 0.1e18);
        assertEq(vault.totalAssets(), expectedAssets + 0.1e18);
        assertEq(vault.convertToShares(1e18), 0.422299248989023685e18);
        assertEq(vault.convertToAssets(1e18), 2.367989056087551299e18);
    }

    function test_redeem_afterShareIncrease() public {
        deposit(alice, 100e18);

        addToSharePrice(10e18); // 10% increase
        assertEq(vault.convertToShares(1e18), 0.909173478655767484e18);
        assertEq(vault.convertToAssets(1e18), 1.099900099900099900e18);

        assertEq(vault.maxWithdraw(alice), 109.990009990009990009e18);
        assertEq(vault.maxRedeem(alice), 100e18);
        redeem(alice, 50e18);

        uint256 expectedShares = OrigamiMath.subtractBps(100e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_DOWN) - 50e18;

        assertEq(asset.balanceOf(alice), 54.995004995004995004e18);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 10e18);
        assertEq(asset.balanceOf(address(sUSDS)), BOOTSTRAPPED_USDS_AMOUNT + 45.104995004995004996e18);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares + 0.1e18);
        assertEq(vault.totalAssets(), 55.104995004995004996e18);

        // Withdrawal fees continue to help the share price
        assertEq(vault.convertToShares(1e18), 0.909173478655767484e18);
        assertEq(vault.convertToAssets(1e18), 1.099900099900099900e18);
    }
}