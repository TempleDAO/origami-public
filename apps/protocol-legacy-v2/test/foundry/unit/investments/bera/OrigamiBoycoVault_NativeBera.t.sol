pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { OrigamiDelegated4626Vault } from "contracts/investments/OrigamiDelegated4626Vault.sol";
import { OrigamiBoycoUsdcManager } from "contracts/investments/bera/OrigamiBoycoUsdcManager.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

import { IBeraRewardsVault } from "contracts/interfaces/external/bera/IBeraRewardsVault.sol";
import { IBeraBgt } from "contracts/interfaces/external/bera/IBeraBgt.sol";

import { IBalancerVault } from "contracts/interfaces/external/balancer/IBalancerVault.sol";
import { IBalancerQueries } from "contracts/interfaces/external/balancer/IBalancerQueries.sol";
import { OrigamiBalancerComposableStablePoolHelper } from "contracts/common/balancer/OrigamiBalancerComposableStablePoolHelper.sol";
import { IBalancerBptToken } from "contracts/interfaces/external/balancer/IBalancerBptToken.sol";

import { IBeraRewardsVault } from "contracts/interfaces/external/bera/IBeraRewardsVault.sol";
import { OrigamiBeraRewardsVaultProxy } from "contracts/common/bera/OrigamiBeraRewardsVaultProxy.sol";
import { IBeraBgt } from "contracts/interfaces/external/bera/IBeraBgt.sol";
import { IOrigamiBoycoManager } from "contracts/interfaces/investments/bera/IOrigamiBoycoManager.sol";

contract OrigamiBoycoVaultTest_NativeBera_Base is OrigamiTest {

    IBeraBgt internal constant bgtToken = IBeraBgt(0x656b95E550C07a9ffe548bd4085c72418Ceb1dba);
    IBeraRewardsVault internal constant beraRewardsVault = IBeraRewardsVault(0xF99be47baf0c22B7eB5EAC42c8D91b9942Dc7e84);

    IBalancerBptToken internal constant lpToken = IBalancerBptToken(0xF961a8f6d8c69E7321e78d254ecAfBcc3A637621);

    IBalancerVault internal constant bexVault = IBalancerVault(0x4Be03f781C497A489E3cB0287833452cA9B9E80B);
    IBalancerQueries internal constant balancerQueries = IBalancerQueries(0x3C612e132624f4Bd500eE1495F54565F0bcc9b59);

    IERC20 internal constant asset = IERC20(0x549943e04f40284185054145c6E4e9568C1D3241); // USDC
    IERC20 internal constant honeyToken = IERC20(0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce);

    OrigamiDelegated4626Vault internal vault;
    OrigamiBoycoUsdcManager internal manager;
    TokenPrices internal tokenPrices;

    OrigamiBalancerComposableStablePoolHelper internal bexPoolHelper;

    OrigamiBeraRewardsVaultProxy internal beraRewardsVaultProxy;

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function setUp() public {
        fork("berachain_mainnet", 7692909);

        tokenPrices = new TokenPrices(30);
        vault = new OrigamiDelegated4626Vault(
            origamiMultisig, 
            "Origami HONEY", 
            "ovHONEY",
            asset,
            address(tokenPrices)
        );
        
        beraRewardsVaultProxy = new OrigamiBeraRewardsVaultProxy(origamiMultisig, address(beraRewardsVault));
        
        bexPoolHelper = new OrigamiBalancerComposableStablePoolHelper(
            origamiMultisig,
            address(bexVault),
            address(balancerQueries),
            lpToken.getPoolId()
        );
        
        manager = new OrigamiBoycoUsdcManager(
            origamiMultisig,
            address(vault),
            address(asset),
            address(bexPoolHelper),
            address(beraRewardsVaultProxy)
        );

        vm.startPrank(origamiMultisig);
        vault.setManager(address(manager), 0);
        setExplicitAccess(
            beraRewardsVaultProxy, 
            address(manager), 
            OrigamiBeraRewardsVaultProxy.stake.selector, 
            OrigamiBeraRewardsVaultProxy.withdraw.selector, 
            true
        );
        vm.stopPrank();

        seedDeposit(origamiMultisig, 0.1e6, type(uint256).max);
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

    function deployUsdc() internal {
        uint256 totalUsdc = 100_000e6;
        deposit(alice, totalUsdc);
        uint256 slippageBps = 50; // 0.5%

        vm.startPrank(origamiMultisig);

        (
            /* uint256 expectedLpAmount */,
            /* uint256 minLpAmount */,
            IBalancerVault.JoinPoolRequest memory requestData
        ) = manager.deployLiquidityQuote(address(asset), totalUsdc, slippageBps);

        manager.deployLiquidity(address(asset), totalUsdc, requestData);
    }
}

contract OrigamiBoycoVaultTest_NativeBera_Admin is OrigamiBoycoVaultTest_NativeBera_Base {
    event TokenPricesSet(address indexed tokenPrices);
    event ManagerSet(address indexed manager);

    function test_initialization() public view {
        assertEq(vault.owner(), origamiMultisig);
        assertEq(vault.name(), "Origami HONEY");
        assertEq(vault.symbol(), "ovHONEY");
        assertEq(vault.asset(), address(asset));
        assertEq(vault.decimals(), 18);
        assertEq(address(vault.manager()), address(manager));
        assertEq(address(vault.tokenPrices()), address(tokenPrices));
        assertEq(vault.performanceFeeBps(), 0);
        assertEq(vault.maxTotalSupply(), type(uint256).max);
        assertEq(vault.totalSupply(), 0.1e18);
        assertEq(vault.totalAssets(), 0.1e6);
        assertEq(vault.convertToShares(1e6), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e6);
        assertEq(vault.maxDeposit(alice), type(uint256).max);
        assertEq(vault.maxMint(alice), type(uint256).max);
        assertEq(vault.maxWithdraw(alice), 0);
        assertEq(vault.maxRedeem(alice), 0);
        assertEq(vault.previewDeposit(1e6), 1e18); // no fees
        assertEq(vault.previewMint(1e18), 1e6); // no fees
        assertEq(vault.previewWithdraw(1e6), 1e18); // no fees
        assertEq(vault.previewRedeem(1e18), 1e6); // no fees
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
        OrigamiBoycoUsdcManager newManager = new OrigamiBoycoUsdcManager(
            origamiMultisig,
            alice, // not vault
            address(asset),
            address(bexPoolHelper),
            address(beraRewardsVaultProxy)
        );

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(newManager)));
        vault.setManager(address(newManager), 0);
    }

    function test_setManager_success() public {
        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, 0.1e6);
        assertEq(manager.unallocatedAssets(), 0.1e6);

        OrigamiBoycoUsdcManager newManager = new OrigamiBoycoUsdcManager(
            origamiMultisig,
            address(vault),
            address(asset),
            address(bexPoolHelper),
            address(beraRewardsVaultProxy)
        );

        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(vault));
        emit ManagerSet(address(newManager));
        vault.setManager(address(newManager), totalAssets);
        assertEq(address(vault.manager()), address(newManager));

        assertEq(vault.totalAssets(), 0.1e6);
    }

    function test_setManager_fail_allAllocated() public {
        deployUsdc();
        
        assertEq(vault.totalAssets(), 100_000e6 + 0.1e6);
        assertEq(manager.unallocatedAssets(), 0.1e6); // wasn't deployed

        OrigamiBoycoUsdcManager newManager = new OrigamiBoycoUsdcManager(
            origamiMultisig,
            address(vault),
            address(asset),
            address(bexPoolHelper),
            address(beraRewardsVaultProxy)
        );

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBoycoManager.NotEnoughUsdc.selector, 0.1e6, 100_000e6 + 0.1e6));
        vault.setManager(address(newManager), 0);
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

    function test_recoverToken() public {
        check_recoverToken(address(vault));
    }
}

contract OrigamiBoycoVaultTest_NativeBera_Access is OrigamiBoycoVaultTest_NativeBera_Base {
    event PerformanceFeeSet(uint256 fee);
    
    function test_setManager_access() public {
        expectElevatedAccess();
        vault.setManager(alice, 0);
    }

    function test_setTokenPrices_access() public {
        expectElevatedAccess();
        vault.setTokenPrices(alice);
    }
}

contract OrigamiBoycoVaultTest_NativeBera_Deposit is OrigamiBoycoVaultTest_NativeBera_Base {
    function test_deposit_basic() public {
        deposit(alice, 123e6);

        uint256 expectedShares = 123e18;

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 123e6 + 0.1e6);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), 123e18 + 0.1e18);
        assertEq(vault.totalAssets(), 123e6 + 0.1e6);
    }

    function test_deposit_beforeShareIncrease() public {
        deposit(alice, 123e6);

        // Donations don't count
        addToSharePrice(100e6);

        uint256 expectedShares = 123e18;

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 100e6 + 123e6 + 0.1e6);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), 123e18 + 0.1e18);
        assertEq(vault.totalAssets(), 123e6 + 0.1e6);
        assertEq(vault.convertToShares(1e6), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e6);
    }

    function test_deposit_afterShareIncrease() public {
        deposit(bob, 100e6);

        addToSharePrice(10e6); // 10% increase
        assertEq(vault.convertToShares(1e6), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e6);

        assertEq(vault.maxDeposit(alice), type(uint256).max);
        assertEq(vault.maxMint(alice), type(uint256).max);
        deposit(alice, 123e6);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 100e6 + 10e6 + 123e6 + 0.1e6);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 223.1e18);
        assertEq(vault.totalAssets(), 223e6 + 0.1e6);

        assertEq(vault.convertToShares(1e6), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e6);
    }
}

contract OrigamiBoycoVaultTest_NativeBera_Mint is OrigamiBoycoVaultTest_NativeBera_Base {
    function test_mint_basic() public {
        mint(alice, 123e18);

        uint256 expectedAssets = 123e6;

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), expectedAssets + 0.1e6);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 123e18 + 0.1e18);
        assertEq(vault.totalAssets(), 123e6 + 0.1e6);
    }

    function test_mint_beforeShareIncrease() public {
        mint(alice, 123e18);

        addToSharePrice(100e6);

        uint256 expectedAssets = 100e6 + 123e6;

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), expectedAssets + 0.1e6);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 123e18 + 0.1e18);
        assertEq(vault.totalAssets(), 123e6 + 0.1e6);
        assertEq(vault.convertToShares(1e6), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e6);
    }

    function test_mint_afterShareIncrease() public {
        mint(bob, 100e18);

        addToSharePrice(10e6); // 10% increase
        assertEq(vault.convertToShares(1e6), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e6);

        assertEq(vault.maxDeposit(alice), type(uint256).max);
        assertEq(vault.maxMint(alice), type(uint256).max);
        mint(alice, 123e18);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 233.1e6);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 223e18 + 0.1e18);

        assertEq(vault.convertToShares(1e6), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e6);
    }
}

contract OrigamiBoycoVaultTest_NativeBera_Withdraw is OrigamiBoycoVaultTest_NativeBera_Base {
    function test_withdraw_basic() public {
        deposit(alice, 123e6);

        withdraw(alice, 50e6);

        uint256 expectedShares = 73e18;

        assertEq(asset.balanceOf(alice), 50e6);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 73e6 + 0.1e6);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares + 0.1e18);
        assertEq(vault.totalAssets(), 73e6 + 0.1e6);
    }

    function test_withdraw_beforeShareIncrease() public {
        deposit(alice, 123e6);

        withdraw(alice, 50e6);
        addToSharePrice(100e6);

        uint256 expectedShares = 73e18;

        assertEq(asset.balanceOf(alice), 50e6);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 100e6 + 73e6 + 0.1e6);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares + 0.1e18);
        assertEq(vault.totalAssets(), 73e6 + 0.1e6);
        assertEq(vault.convertToShares(1e6), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e6);
    }

    function test_withdraw_afterShareIncrease() public {
        deposit(alice, 100e6);

        addToSharePrice(10e6); // 10% increase
        assertEq(vault.convertToShares(1e6), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e6);

        assertEq(vault.maxWithdraw(alice), 100e6);
        assertEq(vault.maxRedeem(alice), 100e18);
        withdraw(alice, 50e6);

        assertEq(asset.balanceOf(alice), 50e6);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 10e6 + 50e6 + 0.1e6);
        assertEq(vault.balanceOf(alice), 50e18);
        assertEq(vault.totalSupply(), 50.1e18);
        assertEq(vault.totalAssets(), 50e6 + 0.1e6);

        assertEq(vault.convertToShares(1e6), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e6);
    }

    function test_maxWithdraw() public {
        deposit(alice, 100e6);
        deposit(bob, 299e6);
        assertEq(vault.maxWithdraw(alice), 100e6);
        assertEq(vault.maxWithdraw(bob), 299e6);

        vm.startPrank(origamiMultisig);

        // Simulate 50 being allocated and each of them still say they can get it all
        manager.recoverToken(address(asset), origamiMultisig, 50e6);
        assertEq(vault.maxWithdraw(alice), 100e6);
        assertEq(vault.maxWithdraw(bob), 299e6);

        manager.recoverToken(address(asset), origamiMultisig, 51e6);
        assertEq(vault.maxWithdraw(alice), 100e6);
        assertEq(vault.maxWithdraw(bob), 298e6 + 0.1e6); // includes the seed

        manager.recoverToken(address(asset), origamiMultisig, 250e6);
        assertEq(vault.maxWithdraw(alice), 48e6 + 0.1e6);
        assertEq(vault.maxWithdraw(bob), 48e6 + 0.1e6); // includes the seed

        // Simulate it being unallocated
        asset.transfer(address(manager), 351e6);
        assertEq(vault.maxWithdraw(alice), 100e6);
        assertEq(vault.maxWithdraw(bob), 299e6);
    }
}

contract OrigamiBoycoVaultTest_NativeBera_Redeem is OrigamiBoycoVaultTest_NativeBera_Base {
    function test_redeem_basic() public {
        deposit(alice, 123e6);

        redeem(alice, 50e18);

        uint256 expectedShares = 123e18 - 50e18;
        uint256 expectedAssets = 123e6 - 50e6;

        assertEq(asset.balanceOf(alice), 50e6);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), expectedAssets + 0.1e6);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares + 0.1e18);
        assertEq(vault.totalAssets(), expectedAssets + 0.1e6);
    }

    function test_redeem_beforeShareIncrease() public {
        deposit(alice, 123e6);

        redeem(alice, 50e18);
        addToSharePrice(100e6);

        uint256 expectedShares = 123e18 - 50e18;

        assertEq(asset.balanceOf(alice), 50e6);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 100e6 + 73e6 + 0.1e6);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares + 0.1e18);
        assertEq(vault.totalAssets(), 123e6 - 50e6 + 0.1e6);
        assertEq(vault.convertToShares(1e6), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e6);
    }

    function test_redeem_afterShareIncrease() public {
        deposit(alice, 100e6);

        addToSharePrice(10e6); // 10% increase
        assertEq(vault.convertToShares(1e6), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e6);

        assertEq(vault.maxWithdraw(alice), 100e6);
        assertEq(vault.maxRedeem(alice), 100e18);
        redeem(alice, 50e18);

        uint256 expectedShares = 100e18 - 50e18;

        assertEq(asset.balanceOf(alice), 50e6);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 10e6 + 50.1e6);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares + 0.1e18);
        assertEq(vault.totalAssets(), 50.1e6);

        assertEq(vault.convertToShares(1e6), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e6);
    }

    function test_maxRedeem() public {
        deposit(alice, 100e6);
        deposit(bob, 299e6);
        assertEq(vault.maxRedeem(alice), 100e18);
        assertEq(vault.maxRedeem(bob), 299e18);

        vm.startPrank(origamiMultisig);

        // Simulate 50 being allocated and each of them still say they can get it all
        manager.recoverToken(address(asset), origamiMultisig, 50e6);
        assertEq(vault.maxRedeem(alice), 100e18);
        assertEq(vault.maxRedeem(bob), 299e18);

        manager.recoverToken(address(asset), origamiMultisig, 51e6);
        assertEq(vault.maxRedeem(alice), 100e18);
        assertEq(vault.maxRedeem(bob), 298e18 + 0.1e18); // includes the seed

        manager.recoverToken(address(asset), origamiMultisig, 250e6);
        assertEq(vault.maxRedeem(alice), 48e18 + 0.1e18);
        assertEq(vault.maxRedeem(bob), 48e18 + 0.1e18); // includes the seed

        // Simulate it being unallocated
        asset.transfer(address(manager), 351e6);
        assertEq(vault.maxRedeem(alice), 100e18);
        assertEq(vault.maxRedeem(bob), 299e18);
    }
}