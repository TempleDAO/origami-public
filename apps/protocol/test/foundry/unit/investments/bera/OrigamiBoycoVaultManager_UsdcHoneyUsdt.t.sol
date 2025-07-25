pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { stdError } from "forge-std/StdError.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";

import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiDelegated4626Vault } from "contracts/investments/OrigamiDelegated4626Vault.sol";
import { OrigamiBoycoUsdcManager } from "contracts/investments/bera/OrigamiBoycoUsdcManager.sol";
import { IOrigamiBoycoManager } from "contracts/interfaces/investments/bera/IOrigamiBoycoManager.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { IOrigamiManagerPausable } from "contracts/interfaces/investments/util/IOrigamiManagerPausable.sol";

import { IBalancerVault } from "contracts/interfaces/external/balancer/IBalancerVault.sol";
import { IBalancerQueries } from "contracts/interfaces/external/balancer/IBalancerQueries.sol";
import { OrigamiBalancerComposableStablePoolHelper } from "contracts/common/balancer/OrigamiBalancerComposableStablePoolHelper.sol";
import { IBalancerBptToken } from "contracts/interfaces/external/balancer/IBalancerBptToken.sol";

import { IBeraRewardsVault } from "contracts/interfaces/external/bera/IBeraRewardsVault.sol";
import { OrigamiBeraRewardsVaultProxy } from "contracts/common/bera/OrigamiBeraRewardsVaultProxy.sol";
import { IBeraBgt } from "contracts/interfaces/external/bera/IBeraBgt.sol";

contract OrigamiBoycoUsdcManagerTestBase_UsdcHoneyUsdt is OrigamiTest {

    IBeraBgt internal constant bgtToken = IBeraBgt(0x656b95E550C07a9ffe548bd4085c72418Ceb1dba);
    IBeraRewardsVault internal constant beraRewardsVault = IBeraRewardsVault(0x3e7bB9E2D991146481C0DAf87044B66daAbc1FD7);

    // Balancer v2 ComposableStablePool with token ordering [USDC.e, USD₮0, BPT, HONEY]
    IBalancerBptToken internal constant lpToken = IBalancerBptToken(0x976eF125c739b5d2F7Bb8d59045B14367eC6d444);

    IBalancerVault internal constant bexVault = IBalancerVault(0x4Be03f781C497A489E3cB0287833452cA9B9E80B);
    IBalancerQueries internal constant balancerQueries = IBalancerQueries(0x3C612e132624f4Bd500eE1495F54565F0bcc9b59);

    IERC20 internal constant usdcToken = IERC20(0x549943e04f40284185054145c6E4e9568C1D3241); // USDC
    IERC20 internal constant usdtToken = IERC20(0x779Ded0c9e1022225f8E0630b35a9b54bE713736); // USD₮0
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
            usdcToken,
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
            address(usdcToken),
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
    }
}

contract OrigamiBoycoUsdcManagerTestDeposit is OrigamiBoycoUsdcManagerTestBase_UsdcHoneyUsdt {
    function test_deposit_pausedOK() public {
        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(true, false));

        vm.startPrank(address(vault));
        assertEq(manager.areDepositsPaused(), true);
        assertEq(manager.areWithdrawalsPaused(), false);

        // The manager itself doesn't pause - it's checked within the OrigamiERC4626
        assertEq(manager.deposit(123), 123);
    }

    function test_deposit_successNothing() public {
        vm.startPrank(address(vault));
        assertEq(manager.deposit(0), 0);
    }

    function test_deposit_success_underMax() public {
        vm.startPrank(address(vault));
        deal(address(usdcToken), address(manager), 100e6);
        assertEq(manager.deposit(25e6), 25e6);
        // effectively a donation of 75
        assertEq(usdcToken.balanceOf(address(manager)), 100e6);
        assertEq(manager.totalAssets(), 25e6);
    }
}

contract OrigamiBoycoUsdcManagerTestWithdraw is OrigamiBoycoUsdcManagerTestBase_UsdcHoneyUsdt {
    function test_withdraw_pausedOK() public {
        vm.startPrank(address(vault));
        deal(address(usdcToken), address(manager), 333e6);
        assertEq(manager.deposit(333e6), 333e6);

        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(false, true));

        assertEq(manager.areDepositsPaused(), false);
        assertEq(manager.areWithdrawalsPaused(), true);
        vm.startPrank(address(vault));

        // The manager itself doesn't pause - it's checked within the OrigamiERC4626
        assertEq(manager.withdraw(100, alice), 100);
    }

    function test_withdraw_successNothing() public {
        vm.startPrank(address(vault));
        assertEq(manager.withdraw(0, alice), 0);
    }

    function test_withdraw_failNotEnough() public {
        vm.startPrank(address(vault));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBoycoManager.NotEnoughUsdc.selector, 0, 100e6));
        assertEq(manager.withdraw(100e6, alice), 0);
    }

    function test_withdraw_success_underMax_fail() public {
        vm.startPrank(address(vault));
        deal(address(usdcToken), address(manager), 333e6);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBoycoManager.NotEnoughUsdc.selector, 333e6, 555e6));
        manager.withdraw(555e6, alice);
    }

    function test_withdraw_success_underMax_success() public {
        vm.startPrank(address(vault));
        deal(address(usdcToken), address(manager), 333e6);
        assertEq(manager.deposit(333e6), 333e6);
        assertEq(manager.withdraw(111e6, alice), 111e6);
        assertEq(usdcToken.balanceOf(address(manager)), 222e6);
        assertEq(usdcToken.balanceOf(address(alice)), 111e6);
        assertEq(manager.totalAssets(), 222e6);
    }
}

contract OrigamiBoycoUsdcManagerTestDeploy is OrigamiBoycoUsdcManagerTestBase_UsdcHoneyUsdt {
    using OrigamiMath for uint256;

    event LiquidityDeployed(uint256 vaultAssetAmount, address depositToken, uint256 depositTokenAmount, uint256 lpAmount);
    event LiquidityRecalled(uint256 vaultAssetAmount, address exitToken, uint256 exitTokenAmount, uint256 lpAmount);

    function deployUsdc() internal {
        uint256 totalUsdc = 100_000e6;
        uint256 slippageBps = 50; // 0.5%

        vm.startPrank(origamiMultisig);
        deal(address(usdcToken), address(manager), totalUsdc);

        (
            /* uint256 expectedLpAmount */,
            /* uint256 minLpAmount */,
            IBalancerVault.JoinPoolRequest memory requestData
        ) = manager.deployLiquidityQuote(address(usdcToken), totalUsdc, slippageBps);

        manager.deployLiquidity(address(usdcToken), totalUsdc, requestData);
    }

    function test_deployLiquidityQuote_success() public {
        uint256 totalUsdc = 100_000e6;
        uint256 slippageBps = 50; // 0.5%

        (
            uint256 expectedLpAmount,
            uint256 minLpAmount,
            IBalancerVault.JoinPoolRequest memory requestData
        ) = manager.deployLiquidityQuote(address(usdcToken), totalUsdc, slippageBps);

        assertEq(requestData.assets[0], address(usdcToken));
        assertEq(requestData.assets[1], address(usdtToken));
        assertEq(requestData.assets[2], address(lpToken));
        assertEq(requestData.assets[3], address(honeyToken));
        assertEq(requestData.maxAmountsIn[0], totalUsdc);
        assertEq(requestData.maxAmountsIn[1], 0);
        assertEq(requestData.maxAmountsIn[2], 0); // nothing for BPT
        assertEq(requestData.maxAmountsIn[3], 0);
        (uint256 jtype, uint256[] memory amountsIn, uint256 minBpt) = abi.decode(requestData.userData, (uint256, uint256[], uint256));
        assertEq(jtype, 1);
        assertEq(amountsIn.length, 3);
        assertEq(amountsIn[0], totalUsdc);
        assertEq(amountsIn[1], 0);
        assertEq(amountsIn[2], 0);
        assertEq(expectedLpAmount, 69_714.190223401197236756e18);
        assertEq(minLpAmount, OrigamiMath.subtractBps(expectedLpAmount, slippageBps, OrigamiMath.Rounding.ROUND_DOWN));
        assertEq(minBpt, minLpAmount);
    }

    function test_deployUsdc_success() public {
        uint256 totalUsdc = 100_000e6;
        uint256 slippageBps = 50; // 0.5%

        vm.startPrank(origamiMultisig);
        deal(address(usdcToken), address(manager), totalUsdc);

        (
            /* uint256 expectedLpAmount */,
            /* uint256 minLpAmount */,
            IBalancerVault.JoinPoolRequest memory requestData
        ) = manager.deployLiquidityQuote(address(usdcToken), totalUsdc, slippageBps);

        vm.expectEmit(address(manager));
        emit LiquidityDeployed(totalUsdc, address(usdcToken), totalUsdc, 69_714.190223401197236756e18);
        manager.deployLiquidity(address(usdcToken), totalUsdc, requestData);

        assertEq(usdcToken.balanceOf(address(manager)), 0); // fully deploys USDC
        assertEq(usdcToken.balanceOf(address(bexPoolHelper)), 0);
        assertEq(usdcToken.balanceOf(address(beraRewardsVaultProxy)), 0);

        assertEq(usdtToken.balanceOf(address(manager)), 0);
        assertEq(usdtToken.balanceOf(address(bexPoolHelper)), 0);
        assertEq(usdtToken.balanceOf(address(beraRewardsVaultProxy)), 0);

        assertEq(honeyToken.balanceOf(address(manager)), 0);
        assertEq(honeyToken.balanceOf(address(bexPoolHelper)), 0);
        assertEq(honeyToken.balanceOf(address(beraRewardsVaultProxy)), 0);

        assertEq(lpToken.balanceOf(address(manager)), 0);
        assertEq(lpToken.balanceOf(address(bexPoolHelper)), 0);
        assertEq(lpToken.balanceOf(address(beraRewardsVaultProxy)), 0);

        // reward vault not whitelisted
        assertEq(beraRewardsVault.balanceOf(address(beraRewardsVaultProxy)), 69_714.190223401197236756e18);
        assertEq(beraRewardsVault.earned(address(beraRewardsVaultProxy)), 0);

        skip(30 days);
        uint256 expectedBgt = 0;
        assertEq(beraRewardsVault.earned(address(beraRewardsVaultProxy)), expectedBgt);

        beraRewardsVaultProxy.getReward(origamiMultisig);
        assertEq(bgtToken.balanceOf(origamiMultisig), expectedBgt);
    }

    function test_recallUsdc_success() public {
        deployUsdc();
        assertEq(beraRewardsVault.balanceOf(address(beraRewardsVaultProxy)), 69_714.190223401197236756e18);

        uint256 stakedLp = beraRewardsVault.balanceOf(address(beraRewardsVaultProxy));
        uint256 slippageBps = 1; // 0.01%

        (
            uint256[] memory expectedTokenAmounts,
            ,// uint256[] memory minimumTokenAmounts,
            IBalancerVault.ExitPoolRequest memory requestData
        ) = manager.recallLiquidityQuote(stakedLp, address(usdcToken), slippageBps);

        vm.expectEmit(address(manager));
        emit LiquidityRecalled(99_989.978031e6, address(usdcToken), 99_989.978031e6, stakedLp);
        manager.recallLiquidity(stakedLp, address(usdcToken), requestData);

        // Started with 100k, and ended up with 67 less lost to balancer fees
        assertEq(expectedTokenAmounts[0], 99_989.978031e6);
        assertEq(usdcToken.balanceOf(address(manager)), expectedTokenAmounts[0]);
        assertEq(usdcToken.balanceOf(address(bexPoolHelper)), 0);
        assertEq(usdcToken.balanceOf(address(beraRewardsVaultProxy)), 0);

        assertEq(usdtToken.balanceOf(address(manager)), 0);
        assertEq(usdtToken.balanceOf(address(bexPoolHelper)), 0);
        assertEq(usdtToken.balanceOf(address(beraRewardsVaultProxy)), 0);

        assertEq(honeyToken.balanceOf(address(manager)), 0);
        assertEq(honeyToken.balanceOf(address(bexPoolHelper)), 0);
        assertEq(honeyToken.balanceOf(address(beraRewardsVaultProxy)), 0);

        assertEq(lpToken.balanceOf(address(manager)), 0);
        assertEq(lpToken.balanceOf(address(bexPoolHelper)), 0);
        assertEq(lpToken.balanceOf(address(beraRewardsVaultProxy)), 0);

        assertEq(beraRewardsVault.balanceOf(address(beraRewardsVaultProxy)), 0);
        assertEq(beraRewardsVault.earned(address(beraRewardsVaultProxy)), 0);
    }
}

contract OrigamiBoycoUsdcManagerTestViews is OrigamiBoycoUsdcManagerTestBase_UsdcHoneyUsdt {

    event LiquidityDeployed(uint256 vaultAssetAmount, address depositToken, uint256 depositTokenAmount, uint256 lpAmount);
    event LiquidityRecalled(uint256 vaultAssetAmount, address exitToken, uint256 exitTokenAmount, uint256 lpAmount);

    function test_supportsInterface() public view {
        assertEq(manager.supportsInterface(type(IOrigamiBoycoManager).interfaceId), true);
        assertEq(manager.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(manager.supportsInterface(type(IOrigamiManagerPausable).interfaceId), false);
    }

    function test_lpBalanceStaked() public {
        uint256 totalUsdc = 100_000e6;
        uint256 slippageBps = 50; // 0.5%

        vm.startPrank(origamiMultisig);
        deal(address(usdcToken), address(manager), totalUsdc);

        (
            uint256 expectedLpAmount,
            ,//uint256 minLpAmount,
            IBalancerVault.JoinPoolRequest memory requestData
        ) = manager.deployLiquidityQuote(address(usdcToken), totalUsdc, slippageBps);
        manager.deployLiquidity(address(usdcToken), totalUsdc, requestData);

        assertEq(expectedLpAmount, 69_714.190223401197236756e18);
        assertEq(manager.lpBalanceStaked(), expectedLpAmount);
    }

    function test_totalAssets_halfDeployed() public {
        uint256 totalUsdc = 100_000e6;
        uint256 slippageBps = 50; // 0.5%

        vm.startPrank(origamiMultisig);
        deal(address(usdcToken), origamiMultisig, totalUsdc);
        usdcToken.approve(address(vault), totalUsdc);
        uint256 msigShares = vault.seedDeposit(totalUsdc, origamiMultisig, 100_000_000e18);
        assertEq(msigShares, 100_000e18);
        
        assertEq(manager.totalAssets(), totalUsdc);
        assertEq(vault.totalSupply(), 100_000e18);
        assertEq(vault.convertToShares(1e6), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e6);

        (
            uint256 expectedLp,
            ,//uint256 minLp,
            IBalancerVault.JoinPoolRequest memory requestData
        ) = manager.deployLiquidityQuote(address(usdcToken), totalUsdc/2, slippageBps);

        vm.expectEmit(address(manager));
        emit LiquidityDeployed(50_000e6, address(usdcToken), 50_000e6, expectedLp);
        manager.deployLiquidity(address(usdcToken), totalUsdc/2, requestData);

        assertEq(manager.totalAssets(), 100_000e6);
        assertEq(vault.convertToShares(1e6), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e6);
    }

    function test_totalAssets_fullDeployed() public {
        uint256 totalUsdc = 100_000e6;
        uint256 slippageBps = 50; // 0.5%

        vm.startPrank(origamiMultisig);
        deal(address(usdcToken), origamiMultisig, totalUsdc);
        usdcToken.approve(address(vault), totalUsdc);
        uint256 msigShares = vault.seedDeposit(totalUsdc, origamiMultisig, 100_000_000e18);
        assertEq(msigShares, 100_000e18);
        
        assertEq(manager.totalAssets(), totalUsdc);
        assertEq(vault.totalSupply(), 100_000e18);
        assertEq(vault.convertToShares(1e6), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e6);

        (
            uint256 expectedLp,
            uint256 minLp,
            IBalancerVault.JoinPoolRequest memory requestData
        ) = manager.deployLiquidityQuote(address(usdcToken), totalUsdc, slippageBps);

        assertEq(expectedLp, 69_714.190223401197236756e18);
        assertEq(minLp, OrigamiMath.subtractBps(expectedLp, slippageBps, OrigamiMath.Rounding.ROUND_DOWN));
        
        vm.expectEmit(address(manager));
        emit LiquidityDeployed(100_000e6, address(usdcToken), 100_000e6, expectedLp);
        manager.deployLiquidity(address(usdcToken), totalUsdc, requestData);

        assertEq(manager.totalAssets(), 100_000e6);
        assertEq(vault.convertToShares(1e6), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e6);
    }
}
