pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISkyLockstakeEngine } from "contracts/interfaces/external/sky/ISkyLockstakeEngine.sol";

import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiDelegated4626Vault } from "contracts/investments/OrigamiDelegated4626Vault.sol";
import { OrigamiSuperSkyManager } from "contracts/investments/sky/OrigamiSuperSkyManager.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { IOrigamiErc4626 } from "contracts/interfaces/common/IOrigamiErc4626.sol";
import { LSE_WITH_FEE } from "test/foundry/unit/investments/sky/LseWithFee.t.sol";

contract OrigamiSuperSkyVaultTestBase is OrigamiTest {
    using OrigamiMath for uint256;

    IERC20 internal constant SKY = IERC20(0x56072C95FAA701256059aa122697B133aDEd9279);
    IERC20 internal constant LSSKY = IERC20(0xf9A9cfD3229E985B91F99Bc866d42938044FFa1C);
    ISkyLockstakeEngine internal constant LOCKSTAKE_ENGINE = ISkyLockstakeEngine(0xCe01C90dE7FD1bcFa39e237FE6D8D9F569e8A6a3);
    address internal URN_ADDRESS;

    OrigamiDelegated4626Vault public vault;
    OrigamiSuperSkyManager public manager;

    TokenPrices public tokenPrices;
    address public swapper = makeAddr("swapper");

    uint32 public constant SWITCH_FARM_COOLDOWN = 1 days;
    uint16 public constant PERF_FEE_FOR_CALLER = 100; // 1%
    uint16 public constant PERF_FEE_FOR_ORIGAMI = 400; // 4%

    uint256 public constant DEPOSIT_FEE = 0;

    event InKindFees(IOrigamiErc4626.FeeType feeType, uint256 feeBps, uint256 feeAmount);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function setUp() public virtual {
        fork("mainnet", 22694300);

        tokenPrices = new TokenPrices(30);
        vault = new OrigamiDelegated4626Vault(
            origamiMultisig, 
            "Origami SKY Auto-Compounder", 
            "SKY+",
            SKY,
            address(tokenPrices)
        );

        manager = new OrigamiSuperSkyManager(
            origamiMultisig,
            address(vault),
            address(LOCKSTAKE_ENGINE),
            SWITCH_FARM_COOLDOWN,
            swapper,
            feeCollector,
            PERF_FEE_FOR_CALLER,
            PERF_FEE_FOR_ORIGAMI
        );
        URN_ADDRESS = manager.URN_ADDRESS();

        vm.startPrank(origamiMultisig);
        vault.setManager(address(manager), 0);
        vm.stopPrank();

        seedDeposit(origamiMultisig, 0.1e18, type(uint256).max);
    }

    function seedDeposit(address account, uint256 amount, uint256 maxSupply) internal {
        vm.startPrank(account);
        deal(address(SKY), account, amount, true);
        SKY.approve(address(vault), amount);
        vault.seedDeposit(amount, account, maxSupply);
        vm.stopPrank();
    }

    function deposit(address user, uint256 amount) internal {
        deal(address(SKY), user, amount);
        vm.startPrank(user);
        SKY.approve(address(vault), amount);
        uint256 expectedShares = vault.previewDeposit(amount);

        vm.expectEmit(address(vault));
        emit Deposit(user, user, amount, expectedShares);
        uint256 actualShares = vault.deposit(amount, user);
        vm.stopPrank();

        assertEq(actualShares, expectedShares);
    }

    function mint(address user, uint256 shares) internal {
        uint256 expectedAssets = vault.previewMint(shares);
        deal(address(SKY), user, expectedAssets);
        vm.startPrank(user);
        SKY.approve(address(vault), expectedAssets);

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
        deal(address(SKY), address(manager), SKY.balanceOf(address(manager)) + amount, true);
    }
}

contract OrigamiSuperSkyVaultTestAdmin is OrigamiSuperSkyVaultTestBase {
    event TokenPricesSet(address indexed tokenPrices);
    event ManagerSet(address indexed manager);

    function test_initialization() public view {
        assertEq(vault.owner(), origamiMultisig);
        assertEq(vault.name(), "Origami SKY Auto-Compounder");
        assertEq(vault.symbol(), "SKY+");
        assertEq(vault.asset(), address(SKY));
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

    function test_setManager_fail_zero() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        vault.setManager(address(0), 0);
    }

    function test_setManager_fail_notWedToVault() public {
        vm.startPrank(origamiMultisig);
        OrigamiSuperSkyManager newManager = new OrigamiSuperSkyManager(
            origamiMultisig,
            alice, // not vault
            address(LOCKSTAKE_ENGINE),
            SWITCH_FARM_COOLDOWN,
            swapper,
            feeCollector,
            PERF_FEE_FOR_CALLER,
            PERF_FEE_FOR_ORIGAMI
        );

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(newManager)));
        vault.setManager(address(newManager), 0);
    }

    function test_setManager_success() public {
        deposit(alice, 100e18);
        uint256 totalAssets = vault.totalAssets();
        assertEq(vault.totalAssets(), 100e18 + 0.1e18);
        assertEq(vault.convertToAssets(1e18), 1e18);
        assertEq(manager.unallocatedAssets(), 0);

        OrigamiSuperSkyManager newManager = new OrigamiSuperSkyManager(
            origamiMultisig,
            address(vault),
            address(LOCKSTAKE_ENGINE),
            SWITCH_FARM_COOLDOWN,
            swapper,
            feeCollector,
            PERF_FEE_FOR_CALLER,
            PERF_FEE_FOR_ORIGAMI
        );
       
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(vault));
        emit ManagerSet(address(newManager));
        vault.setManager(address(newManager), totalAssets);
        assertEq(address(vault.manager()), address(newManager));

        assertEq(vault.totalAssets(), 100e18 + 0.1e18);
        assertEq(vault.convertToAssets(1e18), 1e18);
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

contract OrigamiSuperSkyVaultTestAccess is OrigamiSuperSkyVaultTestBase {
    event PerformanceFeeSet(uint256 fee);
    
    function test_setManager_access() public {
        expectElevatedAccess();
        vault.setManager(alice, 0);
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

contract OrigamiSuperSkyVaultTestDeposit is OrigamiSuperSkyVaultTestBase {
    function test_deposit_basic() public {
        deposit(alice, 123e18);

        uint256 expectedShares = OrigamiMath.subtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_DOWN);

        assertEq(SKY.balanceOf(alice), 0);
        assertEq(SKY.balanceOf(address(vault)), 0);
        assertEq(SKY.balanceOf(address(manager)), 0);
        assertEq(LSSKY.balanceOf(URN_ADDRESS), 123e18 + 0.1e18);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), 123e18 + 0.1e18);
        assertEq(vault.totalAssets(), 123e18 + 0.1e18);
    }

    function test_deposit_beforeShareIncrease() public {
        deposit(alice, 123e18);

        addToSharePrice(100e18);

        uint256 expectedShares = OrigamiMath.subtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_DOWN);

        assertEq(SKY.balanceOf(alice), 0);
        assertEq(SKY.balanceOf(address(vault)), 0);
        assertEq(SKY.balanceOf(address(manager)), 100e18); // donation doesn't affect share price
        assertEq(LSSKY.balanceOf(URN_ADDRESS), 123e18 + 0.1e18);
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

        assertEq(SKY.balanceOf(alice), 0);
        assertEq(SKY.balanceOf(address(vault)), 0);
        assertEq(SKY.balanceOf(address(manager)), 10e18); // donation was added into sUSDS
        assertEq(LSSKY.balanceOf(URN_ADDRESS), 223e18 + 0.1e18);
        assertEq(vault.balanceOf(alice), 111.828337874659400545e18);
        assertEq(vault.totalSupply(), 211.928337874659400545e18);
        assertEq(vault.totalAssets(), 233e18 + 0.1e18);

        // Deposit fees continue to help the share price
        assertEq(vault.convertToShares(1e18), 0.909173478655767484e18);
        assertEq(vault.convertToAssets(1e18), 1.099900099900099900e18);
    }
}

contract OrigamiSuperSkyVaultTestMint is OrigamiSuperSkyVaultTestBase {
    function test_mint_basic() public {
        mint(alice, 123e18);

        uint256 expectedAssets = OrigamiMath.inverseSubtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_UP);

        assertEq(SKY.balanceOf(alice), 0);
        assertEq(SKY.balanceOf(address(vault)), 0);
        assertEq(SKY.balanceOf(address(manager)), 0);
        assertEq(LSSKY.balanceOf(URN_ADDRESS), expectedAssets + 0.1e18);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 123e18 + 0.1e18);
        assertEq(vault.totalAssets(), 123e18 + 0.1e18);
    }

    function test_mint_beforeShareIncrease() public {
        mint(alice, 123e18);

        addToSharePrice(100e18);

        uint256 expectedAssets = 100e18 + OrigamiMath.inverseSubtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_UP);

        assertEq(SKY.balanceOf(alice), 0);
        assertEq(SKY.balanceOf(address(vault)), 0);
        assertEq(SKY.balanceOf(address(manager)), 100e18);
        assertEq(LSSKY.balanceOf(URN_ADDRESS), expectedAssets - 100e18 + 0.1e18);
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

        assertEq(SKY.balanceOf(alice), 0);
        assertEq(SKY.balanceOf(address(vault)), 0);
        assertEq(SKY.balanceOf(address(manager)), 10e18);
        assertEq(LSSKY.balanceOf(URN_ADDRESS), 235.387712287712287713e18);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 223e18 + 0.1e18);

        // Deposit fees continue to help the share price
        assertEq(vault.convertToShares(1e18), 0.909173478655767484e18);
        assertEq(vault.convertToAssets(1e18), 1.099900099900099900e18);
    }
}

contract OrigamiSuperSkyVaultTestWithdraw is OrigamiSuperSkyVaultTestBase {
    function test_withdraw_basic() public {
        deposit(alice, 123e18);

        withdraw(alice, 50e18);

        uint256 expectedShares = 73e18;

        assertEq(SKY.balanceOf(alice), 50e18);
        assertEq(SKY.balanceOf(address(vault)), 0);
        assertEq(SKY.balanceOf(address(manager)), 0);
        assertEq(LSSKY.balanceOf(URN_ADDRESS), 73e18 + 0.1e18);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares + 0.1e18);
        assertEq(vault.totalAssets(), 73e18 + 0.1e18);
    }

    function test_withdraw_beforeShareIncrease() public {
        deposit(alice, 123e18);

        withdraw(alice, 50e18);
        addToSharePrice(100e18);

        uint256 expectedShares = 73e18;

        assertEq(SKY.balanceOf(alice), 50e18);
        assertEq(SKY.balanceOf(address(vault)), 0);
        assertEq(SKY.balanceOf(address(manager)), 100e18);
        assertEq(LSSKY.balanceOf(URN_ADDRESS), 73e18 + 0.1e18);
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

        assertEq(SKY.balanceOf(alice), 50e18);
        assertEq(SKY.balanceOf(address(vault)), 0);
        assertEq(SKY.balanceOf(address(manager)), 10e18);
        assertEq(LSSKY.balanceOf(URN_ADDRESS), 50e18 + 0.1e18);
        assertEq(vault.balanceOf(alice), 54.541326067211625794e18);
        assertEq(vault.totalSupply(), 54.641326067211625794e18);
        assertEq(vault.totalAssets(), 60e18 + 0.1e18);

        // Withdrawal fees continue to help the share price
        assertEq(vault.convertToShares(1e18), 0.909173478655767484e18);
        assertEq(vault.convertToAssets(1e18), 1.099900099900099900e18);
    }
}

contract OrigamiSuperSkyVaultTestRedeem is OrigamiSuperSkyVaultTestBase {
    function test_redeem_basic() public {
        deposit(alice, 123e18);

        redeem(alice, 50e18);

        uint256 expectedShares = OrigamiMath.subtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_DOWN) - 50e18;
        uint256 expectedAssets = 123e18 - 50e18;

        assertEq(SKY.balanceOf(alice), 50e18);
        assertEq(SKY.balanceOf(address(vault)), 0);
        assertEq(SKY.balanceOf(address(manager)), 0);
        assertEq(LSSKY.balanceOf(URN_ADDRESS), expectedAssets + 0.1e18);
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

        assertEq(SKY.balanceOf(alice), 50e18);
        assertEq(SKY.balanceOf(address(vault)), 0);
        assertEq(SKY.balanceOf(address(manager)), 100e18);
        assertEq(LSSKY.balanceOf(URN_ADDRESS), 73e18 + 0.1e18);
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

        assertEq(SKY.balanceOf(alice), 54.995004995004995004e18);
        assertEq(SKY.balanceOf(address(vault)), 0);
        assertEq(SKY.balanceOf(address(manager)), 10e18);
        assertEq(LSSKY.balanceOf(URN_ADDRESS), 45.104995004995004996e18);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares + 0.1e18);
        assertEq(vault.totalAssets(), 55.104995004995004996e18);

        // Withdrawal fees continue to help the share price
        assertEq(vault.convertToShares(1e18), 0.909173478655767484e18);
        assertEq(vault.convertToAssets(1e18), 1.099900099900099900e18);
    }
}

contract OrigamiSuperSkyVaultTestWithFee is OrigamiSuperSkyVaultTestBase {
    event Free(address indexed owner, uint256 indexed index, address to, uint256 wad, uint256 freed);

    uint256 public constant UPDATED_FEE = 0.012345e18;

    function setUp() public override {
        super.setUp();

        // Etch a new lockstake engine, one with a fee of 0.012345e18
        vm.etch(address(LOCKSTAKE_ENGINE), LSE_WITH_FEE);
    }

    function test_fees() public view {
        assertEq(vault.depositFeeBps(), 0);

        // Rounded up to the nearest basis point
        assertEq(vault.withdrawalFeeBps(), 124);
    }

    function test_withdraw_partial() public {
        assertEq(vault.convertToAssets(1e18), 1e18);
        assertEq(vault.totalAssets(), 0.1e18);
        assertEq(vault.totalSupply(), 0.1e18);
        assertEq(vault.previewRedeem(1e18), 0.9876e18); // 1 - feeBps
        assertEq(vault.previewWithdraw(1e18), 1.012555690562980964e18); // 1/(1-feeBps)

        deposit(alice, 100e18);
        assertEq(vault.convertToAssets(1e18), 1e18);
        assertEq(vault.totalAssets(), 100e18 + 0.1e18);
        assertEq(vault.totalSupply(), 100e18 + 0.1e18);
        assertEq(vault.previewRedeem(1e18), 0.9876e18);
        assertEq(vault.previewWithdraw(1e18), 1.012555690562980964e18);

        withdraw(alice, 10e18);

        // to WAD precision
        uint256 expectedSkyFee = 10e18 * 1e18 / (1e18 - UPDATED_FEE) - 10e18;

        // to basis points precision but rounded up
        uint256 expectedOrigamiFee = (10e18 * uint256(10_000) / (10_000 - 124)) - 10e18 + 1;

        // Because Origami is in basis points rounded up, the share price increases slightly.
        // ie Alice has a slightly higher fee than if she withdrew herself (but to the benefit of existing holders)
        assertEq(vault.convertToAssets(1e18), 1.000006266963630245e18);
        assertEq(vault.totalAssets(), 100e18 + 0.1e18 - 10e18 - expectedSkyFee);
        assertEq(vault.totalSupply(), 100e18 + 0.1e18 - 10e18 - expectedOrigamiFee);
        assertEq(vault.previewRedeem(1e18), 0.987606189253281230e18);
        assertEq(vault.previewWithdraw(1e18), 1.012549344953062315e18);

        uint256 expectedShares = 89.874443094370190360e18;
        assertEq(SKY.balanceOf(alice), 10e18);
        assertEq(SKY.balanceOf(address(vault)), 0);
        assertEq(SKY.balanceOf(address(manager)), 0);
        assertEq(LSSKY.balanceOf(URN_ADDRESS), 89.875006960932714359e18 + 0.1e18);
        assertEq(vault.balanceOf(alice), expectedShares);
    }

    function test_withdraw_all_fullImpact() public {
        deposit(alice, 100e18);

        // Multisig withdraws everything, so only alice is left holding the bag
        uint256 withdrawAmt1 = 0.09876e18;
        withdraw(origamiMultisig, withdrawAmt1);

        uint256 expectedSkyFee1 = withdrawAmt1 * 1e18 / (1e18 - UPDATED_FEE) - withdrawAmt1;
        uint256 expectedOrigamiFee1 = (withdrawAmt1 * uint256(10_000) / (10_000 - 124)) - withdrawAmt1;
        uint256 expectedTotalAssets1 = 100e18 + 0.1e18 - withdrawAmt1 - expectedSkyFee1;
        uint256 expectedTotalSupply1 = 100e18 + 0.1e18 - withdrawAmt1 - expectedOrigamiFee1;

        assertEq(vault.totalAssets(), expectedTotalAssets1);
        assertEq(vault.totalSupply(), expectedTotalSupply1);
        assertEq(vault.convertToAssets(1e18), 1.000000055687461714e18);

        uint256 withdrawAmt2 = 98.760005499693718961e18;
        assertEq(vault.maxWithdraw(alice), withdrawAmt2);
        withdraw(alice, withdrawAmt2);

        // Some dust is left even though there's no supply, for 2 reasons:
        //  1/ vanilla ERC4626 leaves some dust in there anyway by design becuase of rounding agains the user
        //  2/ The origami fee on shares rounds slightly higher than the SKY fee on assets
        assertEq(vault.totalAssets(), 0.005568746481596347e18);
        assertEq(vault.totalSupply(), 0);
        // It leads to a very skewed share price, basically writing off the usefulness of the 
        // vault now. But that's accepted -- if the vault becomes empty then it wont be used again
        assertEq(vault.convertToAssets(1e18), 5_568_746_481_596_348e18);

        assertEq(SKY.balanceOf(origamiMultisig), withdrawAmt1);
        assertEq(vault.balanceOf(origamiMultisig), 0);
        assertEq(SKY.balanceOf(alice), withdrawAmt2);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_withdraw_all_minImpact() public {
        deposit(alice, 100e18);

        // Multisig withdraws everything, so only alice is left holding the bag
        uint256 withdrawAmt1 = 0.09876e18;
        withdraw(origamiMultisig, withdrawAmt1);

        // Almost all of it first, then the remainder as a second step
        uint256 withdrawAmt2 = 98.76e18;
        withdraw(alice, withdrawAmt2);
        withdraw(alice, vault.maxWithdraw(alice));

        // Far less dust left now, but still a very skewed share price
        assertEq(vault.totalAssets(), 0.000000310419450490e18);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.convertToAssets(1e18), 310_419_450_491e18);

        assertEq(SKY.balanceOf(origamiMultisig), withdrawAmt1);
        assertEq(vault.balanceOf(origamiMultisig), 0);
        assertEq(SKY.balanceOf(alice), 98.765505193412677629e18);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_redeem_partial() public {
        assertEq(vault.convertToAssets(1e18), 1e18);
        assertEq(vault.totalAssets(), 0.1e18);
        assertEq(vault.totalSupply(), 0.1e18);
        assertEq(vault.previewRedeem(1e18), 0.9876e18); // 1 - feeBps
        assertEq(vault.previewWithdraw(1e18), 1.012555690562980964e18); // 1/(1-feeBps)

        deposit(alice, 100e18);
        assertEq(vault.convertToAssets(1e18), 1e18);
        assertEq(vault.totalAssets(), 100e18 + 0.1e18);
        assertEq(vault.totalSupply(), 100e18 + 0.1e18);
        assertEq(vault.previewRedeem(1e18), 0.9876e18);
        assertEq(vault.previewWithdraw(1e18), 1.012555690562980964e18);

        redeem(alice, 10e18);

        // to WAD precision
        uint256 withdrawAmt1 = 9.876e18;
        uint256 expectedSkyFee = withdrawAmt1 * 1e18 / (1e18 - UPDATED_FEE) - withdrawAmt1;

        // to basis points precision but rounded up
        uint256 expectedOrigamiFee = (withdrawAmt1 * uint256(10_000) / (10_000 - 124)) - withdrawAmt1;

        // Because Origami is in basis points rounded up, the share price increases slightly.
        // ie Alice has a slightly higher fee than if she withdrew herself (but to the benefit of existing holders)
        assertEq(vault.convertToAssets(1e18), 1.000006180628381228e18);
        assertEq(vault.totalAssets(), 100e18 + 0.1e18 - withdrawAmt1 - expectedSkyFee);
        assertEq(vault.totalSupply(), 100e18 + 0.1e18 - withdrawAmt1 - expectedOrigamiFee);
        assertEq(vault.previewRedeem(1e18), 0.987606103988589301e18);
        assertEq(vault.previewWithdraw(1e18), 1.012549432371221854e18);

        assertEq(SKY.balanceOf(alice), 9.876e18);
        assertEq(SKY.balanceOf(address(vault)), 0);
        assertEq(SKY.balanceOf(address(manager)), 0);
        assertEq(LSSKY.balanceOf(URN_ADDRESS), 90.000556874617148701e18 + 0.1e18);
        assertEq(vault.balanceOf(alice), 90e18);
    }

    function test_redeem_all() public {
        deposit(alice, 100e18);

        // Multisig withdraws everything, so only alice is left holding the bag
        uint256 withdrawAmt1 = 0.09876e18;
        redeem(origamiMultisig, 0.1e18);

        uint256 expectedSkyFee1 = withdrawAmt1 * 1e18 / (1e18 - UPDATED_FEE) - withdrawAmt1;
        uint256 expectedOrigamiFee1 = (withdrawAmt1 * uint256(10_000) / (10_000 - 124)) - withdrawAmt1;
        uint256 expectedTotalAssets1 = 100e18 + 0.1e18 - withdrawAmt1 - expectedSkyFee1;
        uint256 expectedTotalSupply1 = 100e18 + 0.1e18 - withdrawAmt1 - expectedOrigamiFee1;

        assertEq(vault.totalAssets(), expectedTotalAssets1);
        assertEq(vault.totalSupply(), expectedTotalSupply1);
        assertEq(vault.convertToAssets(1e18), 1.000000055687461714e18);

        uint256 withdrawAmt2 = 98.760005499693718961e18;
        assertEq(vault.maxRedeem(alice), 100e18);
        redeem(alice, 100e18);

        // Some dust is left even though there's no supply,
        // since the max Withdraw calc rounds in favour of vault
        assertEq(vault.totalAssets(), 0.005568746481596347e18);
        assertEq(vault.totalSupply(), 0);
        // It leads to a very skewed share price, basically writing off the usefulness of the 
        // vault now. But that's accepted -- if the vault becomes empty then it wont be used again
        assertEq(vault.convertToAssets(1e18), 5_568_746_481_596_348e18);

        assertEq(SKY.balanceOf(origamiMultisig), withdrawAmt1);
        assertEq(vault.balanceOf(origamiMultisig), 0);
        assertEq(SKY.balanceOf(alice), withdrawAmt2);
        assertEq(vault.balanceOf(alice), 0);
    }
}
