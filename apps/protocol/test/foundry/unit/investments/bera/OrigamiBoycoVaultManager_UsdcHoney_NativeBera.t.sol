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
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { IOrigamiManagerPausable } from "contracts/interfaces/investments/util/IOrigamiManagerPausable.sol";
import { IOrigamiBalancerPoolHelper } from "contracts/interfaces/common/balancer/IOrigamiBalancerPoolHelper.sol";

import { IBalancerVault } from "contracts/interfaces/external/balancer/IBalancerVault.sol";
import { IBalancerQueries } from "contracts/interfaces/external/balancer/IBalancerQueries.sol";
import { OrigamiBalancerComposableStablePoolHelper } from "contracts/common/balancer/OrigamiBalancerComposableStablePoolHelper.sol";
import { IBalancerBptToken } from "contracts/interfaces/external/balancer/IBalancerBptToken.sol";

import { IBeraRewardsVault } from "contracts/interfaces/external/bera/IBeraRewardsVault.sol";
import { OrigamiBeraRewardsVaultProxy } from "contracts/common/bera/OrigamiBeraRewardsVaultProxy.sol";
import { IBeraBgt } from "contracts/interfaces/external/bera/IBeraBgt.sol";

contract OrigamiBoycoUsdcManagerTest_UsdcHoney_NativeBera_Base is OrigamiTest {

    IBeraBgt internal constant bgtToken = IBeraBgt(0x656b95E550C07a9ffe548bd4085c72418Ceb1dba);
    IBeraRewardsVault internal beraRewardsVault = IBeraRewardsVault(0xF99be47baf0c22B7eB5EAC42c8D91b9942Dc7e84);

    IBalancerBptToken internal lpToken = IBalancerBptToken(0xF961a8f6d8c69E7321e78d254ecAfBcc3A637621);

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
    event BexPoolHelperSet(address bexPoolHelper);
    event BeraRewardsVaultProxySet(address beraRewardsVaultProxy);

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
    }

    function _changeToTripool() internal {
        // USDC.e | USDT0 | HONEY
        // https://hub.berachain.com/pools/0x976ef125c739b5d2f7bb8d59045b14367ec6d44400000000000000000000003a/details/
        address tripoolLp = 0x976eF125c739b5d2F7Bb8d59045B14367eC6d444;
        address tripoolRewardsVault = 0x3e7bB9E2D991146481C0DAf87044B66daAbc1FD7;

        // Deploy new helpers/proxies
        vm.startPrank(origamiMultisig);
        {
            lpToken = IBalancerBptToken(tripoolLp);
            beraRewardsVault = IBeraRewardsVault(tripoolRewardsVault);
            bexPoolHelper = new OrigamiBalancerComposableStablePoolHelper(
                origamiMultisig,
                address(bexVault),
                address(balancerQueries),
                lpToken.getPoolId()
            );
            beraRewardsVaultProxy = new OrigamiBeraRewardsVaultProxy(origamiMultisig, address(beraRewardsVault));
            setExplicitAccess(
                beraRewardsVaultProxy, 
                address(manager), 
                OrigamiBeraRewardsVaultProxy.stake.selector, 
                OrigamiBeraRewardsVaultProxy.withdraw.selector, 
                true
            );
        }

        // Update manager to use new pools
        {
            vm.expectEmit(address(manager));
            emit BexPoolHelperSet(address(bexPoolHelper));
            manager.setBexPoolHelper(address(bexPoolHelper));

            vm.expectEmit(address(manager));
            emit BeraRewardsVaultProxySet(address(beraRewardsVaultProxy));
            manager.setBeraRewardsVaultProxy(address(beraRewardsVaultProxy));
        }

        vm.stopPrank();

        assertEq(address(manager.bexPoolHelper()), address(bexPoolHelper));
        assertEq(address(manager.bexLpToken()), tripoolLp);
        assertEq(address(manager.beraRewardsVaultProxy()), address(beraRewardsVaultProxy));
    }
}

contract OrigamiBoycoUsdcManagerTest_UsdcHoney_NativeBera_Admin is OrigamiBoycoUsdcManagerTest_UsdcHoney_NativeBera_Base {

    function test_initialization() public view {
        assertEq(manager.owner(), origamiMultisig);
        assertEq(address(manager.vault()), address(vault));
        assertEq(manager.asset(), address(asset));
        assertEq(address(manager.usdcToken()), address(asset));
        assertEq(manager.totalAssets(), 0);
        assertEq(address(manager.bexPoolHelper()), address(bexPoolHelper));
        assertEq(address(manager.bexLpToken()), address(lpToken));
        assertEq(address(manager.beraRewardsVaultProxy()), address(beraRewardsVaultProxy));
    }

    function test_initialization_fail_wrongUsdcToken() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        new OrigamiBoycoUsdcManager(
            origamiMultisig,
            address(vault),
            address(alice), // should be USDC token
            address(bexPoolHelper),
            address(beraRewardsVaultProxy)
        );
    }

    function test_initialization_fail_poolWithoutUsdc() public {
        // https://hub.berachain.com/pools/0xde04c469ad658163e2a5e860a03a86b52f6fa8c8000000000000000000000000/details/
        // BYUSD/HONEY pool
        IBalancerBptToken bptUsdtHoney = IBalancerBptToken(0xdE04c469Ad658163e2a5E860a03A86B52f6FA8C8);

        OrigamiBalancerComposableStablePoolHelper nonUsdcPoolHelper = new OrigamiBalancerComposableStablePoolHelper(
            origamiMultisig,
            address(bexVault),
            address(balancerQueries),
            bptUsdtHoney.getPoolId()
        );

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        new OrigamiBoycoUsdcManager(
            origamiMultisig,
            address(vault),
            address(asset), // is the USDC token
            address(nonUsdcPoolHelper), // this pool cannot be farmed directly with USDC
            address(beraRewardsVaultProxy)
        );
    }

    function test_setBexPoolHelper_successSamePool() public {
        OrigamiBalancerComposableStablePoolHelper bexPoolHelper2 = new OrigamiBalancerComposableStablePoolHelper(
            origamiMultisig,
            address(bexVault),
            address(balancerQueries),
            lpToken.getPoolId()
        );
        
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit BexPoolHelperSet(address(bexPoolHelper2));
        manager.setBexPoolHelper(address(bexPoolHelper2));
        assertEq(address(manager.bexPoolHelper()), address(bexPoolHelper2));
    }

    function test_setBexPoolHelper_failBadPool() public {
        IBalancerBptToken bptUsdtHoney = IBalancerBptToken(0xdE04c469Ad658163e2a5E860a03A86B52f6FA8C8);

        OrigamiBalancerComposableStablePoolHelper bexPoolHelper2 = new OrigamiBalancerComposableStablePoolHelper(
            origamiMultisig,
            address(bexVault),
            address(balancerQueries),
            bptUsdtHoney.getPoolId()
        );
        
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        manager.setBexPoolHelper(address(bexPoolHelper2));
    }

    function test_setBexPoolHelper_successDifferentUsdcPool() public {
        _changeToTripool();
    }

    function test_setBeraRewardsVaultProxy() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit BeraRewardsVaultProxySet(alice);
        manager.setBeraRewardsVaultProxy(alice);
        assertEq(address(manager.beraRewardsVaultProxy()), alice);
    }

    function test_recoverToken_success() public {
        check_recoverToken(address(manager));
    }
}

contract OrigamiBoycoUsdcManagerTest_UsdcHoney_NativeBera_Access is OrigamiBoycoUsdcManagerTest_UsdcHoney_NativeBera_Base {
    function test_setBeraRewardsVaultProxy_access() public {
        expectElevatedAccess();
        manager.setBeraRewardsVaultProxy(alice);
    }

    function test_setBexPoolHelper_access() public {
        expectElevatedAccess();
        manager.setBexPoolHelper(alice);
    }

    // NB: Anyone can call deposit, but only the vault can withdraw
    function test_withdraw_access() public {
        expectElevatedAccess();
        manager.withdraw(100, alice);

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        manager.withdraw(100, alice);
    }

    function test_deployUsdc_access() public {
        expectElevatedAccess();
        IBalancerVault.JoinPoolRequest memory requestData;
        manager.deployLiquidity(address(asset), 100, requestData);
    }

    function test_recallLiquidity_access() public {
        expectElevatedAccess();
        IBalancerVault.ExitPoolRequest memory requestData;
        manager.recallLiquidity(100, address(asset), requestData);
    }

    function test_setPauser_access() public {
        expectElevatedAccess();
        manager.setPauser(alice, true);
    }

    function test_setPaused_access() public {
        expectElevatedAccess();
        manager.setPaused(IOrigamiManagerPausable.Paused(true, false));
    }

    function test_recoverToken_access() public {
        expectElevatedAccess();
        manager.recoverToken(alice, alice, 100e18);
    }
}

contract OrigamiBoycoUsdcManagerTest_UsdcHoney_NativeBera_Deposit is OrigamiBoycoUsdcManagerTest_UsdcHoney_NativeBera_Base {
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
        deal(address(asset), address(manager), 100e6);
        assertEq(manager.deposit(25e6), 25e6);
        // effectively a donation of 75
        assertEq(asset.balanceOf(address(manager)), 100e6);
        assertEq(manager.totalAssets(), 25e6);
    }
}

contract OrigamiBoycoUsdcManagerTest_UsdcHoney_NativeBera_Withdraw is OrigamiBoycoUsdcManagerTest_UsdcHoney_NativeBera_Base {

    function test_withdraw_pausedOK() public {
        vm.startPrank(address(vault));
        deal(address(asset), address(manager), 333e6);
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
        deal(address(asset), address(manager), 333e6);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBoycoManager.NotEnoughUsdc.selector, 333e6, 555e6));
        manager.withdraw(555e6, alice);
    }

    function test_withdraw_success_underMax_success() public {
        vm.startPrank(address(vault));
        deal(address(asset), address(manager), 333e6);
        assertEq(manager.deposit(333e6), 333e6);
        assertEq(manager.withdraw(111e6, alice), 111e6);
        assertEq(asset.balanceOf(address(manager)), 222e6);
        assertEq(asset.balanceOf(address(alice)), 111e6);
        assertEq(manager.totalAssets(), 222e6);
    }
}

contract OrigamiBoycoUsdcManagerTest_UsdcHoney_NativeBera_Deploy is OrigamiBoycoUsdcManagerTest_UsdcHoney_NativeBera_Base {
    using OrigamiMath for uint256;

    event LiquidityDeployed(uint256 vaultAssetAmount, address depositToken, uint256 depositTokenAmount, uint256 lpAmount);
    event LiquidityRecalled(uint256 vaultAssetAmount, address exitToken, uint256 exitTokenAmount, uint256 lpAmount);

    function deployUsdc() internal {
        uint256 totalUsdc = 100_000e6;
        uint256 slippageBps = 50; // 0.5%

        vm.startPrank(origamiMultisig);
        deal(address(asset), address(manager), totalUsdc);

        (
            /* uint256 expectedLpAmount */,
            /* uint256 minLpAmount */,
            IBalancerVault.JoinPoolRequest memory requestData
        ) = manager.deployLiquidityQuote(address(asset), totalUsdc, slippageBps);

        manager.deployLiquidity(address(asset), totalUsdc, requestData);
    }

    function test_deployLiquidityQuote_success() public {
        uint256 totalUsdc = 100_000e6;
        uint256 slippageBps = 50; // 0.5%

        (
            uint256 expectedLp,
            uint256 minLpAmount,
            IBalancerVault.JoinPoolRequest memory requestData
        ) = manager.deployLiquidityQuote(address(asset), totalUsdc, slippageBps);

        assertEq(requestData.assets[0], address(asset));
        assertEq(requestData.assets[1], address(lpToken));
        assertEq(requestData.assets[2], address(honeyToken));
        assertEq(requestData.maxAmountsIn[0], totalUsdc);
        assertEq(requestData.maxAmountsIn[1], 0); // nothing for BPT
        assertEq(requestData.maxAmountsIn[2], 0);
        (uint256 jtype, uint256[] memory amountsIn, uint256 minBpt) = abi.decode(requestData.userData, (uint256, uint256[], uint256));
        assertEq(jtype, 1);
        assertEq(amountsIn.length, 2);
        assertEq(amountsIn[0], totalUsdc);
        assertEq(amountsIn[1], 0);
        assertEq(expectedLp, 99_906.648421046927100404e18);
        assertEq(minBpt, OrigamiMath.subtractBps(expectedLp, slippageBps, OrigamiMath.Rounding.ROUND_DOWN));
        assertEq(minLpAmount, minBpt);
    }
    
    function test_deployUsdcQuote_failUsdcIndex() public {
        address[] memory addresses = bexPoolHelper.poolTokens();
        for (uint256 i; i < addresses.length; ++i) {
            addresses[i] = alice;
        }
        vm.mockCall(
            address(bexPoolHelper),
            abi.encodeWithSelector(IOrigamiBalancerPoolHelper.poolTokens.selector),
            abi.encode(addresses)
        );
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        manager.deployLiquidityQuote(address(asset), 123, 50);
    }

    function test_deployUsdc_success() public {
        uint256 totalUsdc = 100_000e6;
        uint256 slippageBps = 50; // 0.5%

        vm.startPrank(origamiMultisig);
        deal(address(asset), address(manager), totalUsdc);

        (
            /* uint256 expectedLpAmount */,
            /* uint256 minLpAmount */,
            IBalancerVault.JoinPoolRequest memory requestData
        ) = manager.deployLiquidityQuote(address(asset), totalUsdc, slippageBps);

        vm.expectEmit(address(manager));
        emit LiquidityDeployed(totalUsdc, address(asset), totalUsdc, 99_906.648421046927100404e18);
        manager.deployLiquidity(address(asset), totalUsdc, requestData);

        assertEq(asset.balanceOf(address(manager)), 0); // fully deploys USDC
        assertEq(asset.balanceOf(address(bexPoolHelper)), 0);
        assertEq(asset.balanceOf(address(beraRewardsVaultProxy)), 0);

        assertEq(honeyToken.balanceOf(address(manager)), 0);
        assertEq(honeyToken.balanceOf(address(bexPoolHelper)), 0);
        assertEq(honeyToken.balanceOf(address(beraRewardsVaultProxy)), 0);

        assertEq(lpToken.balanceOf(address(manager)), 0);
        assertEq(lpToken.balanceOf(address(bexPoolHelper)), 0);
        assertEq(lpToken.balanceOf(address(beraRewardsVaultProxy)), 0);

        assertEq(beraRewardsVault.balanceOf(address(beraRewardsVaultProxy)), 99_906.648421046927100404e18);
        assertEq(beraRewardsVault.earned(address(beraRewardsVaultProxy)), 0);

        skip(30 days);
        uint256 expectedBgt = 2.033193745098793005e18;
        assertEq(beraRewardsVault.earned(address(beraRewardsVaultProxy)), expectedBgt);

        beraRewardsVaultProxy.getReward(origamiMultisig);
        assertEq(bgtToken.balanceOf(origamiMultisig), expectedBgt);
    }

   function test_deployWrongToken_fail() public {
        vm.startPrank(origamiMultisig);
        deal(address(honeyToken), address(manager), 100);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(honeyToken)));
        manager.deployLiquidityQuote(address(honeyToken), 100, 0);

        IBalancerVault.JoinPoolRequest memory requestData;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(honeyToken)));
        manager.deployLiquidity(address(honeyToken), 100, requestData);
    }

    function test_deployUsdc_updatedPool() public {
        _changeToTripool();

        uint256 totalUsdc = 100_000e6;
        uint256 slippageBps = 50; // 0.5%

        vm.startPrank(origamiMultisig);
        deal(address(asset), address(manager), totalUsdc);

        (
            /* uint256 expectedLpAmount */,
            /* uint256 minLpAmount */,
            IBalancerVault.JoinPoolRequest memory requestData
        ) = manager.deployLiquidityQuote(address(asset), totalUsdc, slippageBps);

        vm.expectEmit(address(manager));
        emit LiquidityDeployed(totalUsdc, address(asset), totalUsdc, 69_714.190223401197236756e18);
        manager.deployLiquidity(address(asset), totalUsdc, requestData);

        assertEq(asset.balanceOf(address(manager)), 0); // fully deploys USDC
        assertEq(asset.balanceOf(address(bexPoolHelper)), 0);
        assertEq(asset.balanceOf(address(beraRewardsVaultProxy)), 0);

        assertEq(honeyToken.balanceOf(address(manager)), 0);
        assertEq(honeyToken.balanceOf(address(bexPoolHelper)), 0);
        assertEq(honeyToken.balanceOf(address(beraRewardsVaultProxy)), 0);

        assertEq(lpToken.balanceOf(address(manager)), 0);
        assertEq(lpToken.balanceOf(address(bexPoolHelper)), 0);
        assertEq(lpToken.balanceOf(address(beraRewardsVaultProxy)), 0);

        assertEq(beraRewardsVault.balanceOf(address(beraRewardsVaultProxy)), 69_714.190223401197236756e18);
        assertEq(beraRewardsVault.earned(address(beraRewardsVaultProxy)), 0);

        // This pool isn't whitelisted for BGT
        skip(30 days);
        uint256 expectedBgt = 0;
        assertEq(beraRewardsVault.earned(address(beraRewardsVaultProxy)), expectedBgt);

        beraRewardsVaultProxy.getReward(origamiMultisig);
        assertEq(bgtToken.balanceOf(origamiMultisig), expectedBgt);
    }

    function test_recallLiquidityQuote_failUsdcIndex() public {
        address[] memory addresses = bexPoolHelper.poolTokens();
        for (uint256 i; i < addresses.length; ++i) {
            addresses[i] = alice;
        }
        vm.mockCall(
            address(bexPoolHelper),
            abi.encodeWithSelector(IOrigamiBalancerPoolHelper.poolTokens.selector),
            abi.encode(addresses)
        );
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        manager.recallLiquidityQuote(123, address(asset), 50);
    }

    function test_recallUsdc_success() public {
        deployUsdc();
        assertEq(beraRewardsVault.balanceOf(address(beraRewardsVaultProxy)), 99_906.648421046927100404e18);

        uint256 stakedLp = beraRewardsVault.balanceOf(address(beraRewardsVaultProxy));
        uint256 slippageBps = 1; // 0.01%

        (
            uint256[] memory expectedTokenAmounts,
            /* uint256[] memory minTokenAmounts */,
            IBalancerVault.ExitPoolRequest memory requestData
        ) = manager.recallLiquidityQuote(stakedLp, address(asset), slippageBps);

        vm.expectEmit(address(manager));
        emit LiquidityRecalled(99_986.170139e6, address(asset), 99_986.170139e6, stakedLp);
        manager.recallLiquidity(stakedLp, address(asset), requestData);


        // Started with 100k, and ended up with 10 less lost to balancer fees
        assertEq(asset.balanceOf(address(manager)), 99_986.170139e6);
        assertEq(asset.balanceOf(address(bexPoolHelper)), 0);
        assertEq(asset.balanceOf(address(beraRewardsVaultProxy)), 0);

        assertEq(expectedTokenAmounts[0], 99_986.170139e6);
        assertEq(expectedTokenAmounts[1], 0);
        assertEq(expectedTokenAmounts[2], 0);

        assertEq(honeyToken.balanceOf(address(manager)), 0);
        assertEq(honeyToken.balanceOf(address(bexPoolHelper)), 0);
        assertEq(honeyToken.balanceOf(address(beraRewardsVaultProxy)), 0);

        assertEq(lpToken.balanceOf(address(manager)), 0);
        assertEq(lpToken.balanceOf(address(bexPoolHelper)), 0);
        assertEq(lpToken.balanceOf(address(beraRewardsVaultProxy)), 0);

        assertEq(beraRewardsVault.balanceOf(address(beraRewardsVaultProxy)), 0);
        assertEq(beraRewardsVault.earned(address(beraRewardsVaultProxy)), 0);
    }    
    
    function test_recallWrongToken_fail() public {
        deployUsdc();

        uint256 lpAmount = manager.lpBalanceStaked();

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(honeyToken)));
        manager.recallLiquidityQuote(lpAmount, address(honeyToken), 0);

        IBalancerVault.ExitPoolRequest memory requestData;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(honeyToken)));
        manager.recallLiquidity(lpAmount, address(honeyToken), requestData);
    }
}

contract OrigamiBoycoUsdcManagerTest_UsdcHoney_NativeBera_Views is OrigamiBoycoUsdcManagerTest_UsdcHoney_NativeBera_Base {

    event LiquidityDeployed(uint256 vaultAssetAmount, address depositToken, uint256 depositTokenAmount, uint256 lpAmount);

    function test_supportsInterface() public view {
        assertEq(manager.supportsInterface(type(IOrigamiBoycoManager).interfaceId), true);
        assertEq(manager.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(manager.supportsInterface(type(IOrigamiManagerPausable).interfaceId), false);
    }

    function test_lpBalanceStaked() public {
        uint256 totalUsdc = 100_000e6;
        uint256 slippageBps = 50; // 0.5%

        vm.startPrank(origamiMultisig);
        deal(address(asset), address(manager), totalUsdc);

        (
            /* uint256 expectedLpAmount */,
            /* uint256 minLpAmount */,
            IBalancerVault.JoinPoolRequest memory requestData
        ) = manager.deployLiquidityQuote(address(asset), totalUsdc, slippageBps);
        manager.deployLiquidity(address(asset), totalUsdc, requestData);

        assertEq(manager.lpBalanceStaked(), 99_906.648421046927100404e18);
    }

    function test_totalAssets_halfDeployed() public {
        uint256 totalUsdc = 100_000e6;
        uint256 slippageBps = 50; // 0.5%

        vm.startPrank(origamiMultisig);
        deal(address(asset), origamiMultisig, totalUsdc);
        asset.approve(address(vault), totalUsdc);
        uint256 msigShares = vault.seedDeposit(totalUsdc, origamiMultisig, 100_000_000e18);
        assertEq(msigShares, 100_000e18);
        
        assertEq(manager.totalAssets(), totalUsdc);
        assertEq(vault.totalSupply(), 100_000e18);
        assertEq(vault.convertToShares(1e6), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e6);

        uint256 deployAmount = totalUsdc / 2;
        (
            /* uint256 expectedLpAmount */,
            /* uint256 minLpAmount */,
            IBalancerVault.JoinPoolRequest memory requestData
        ) = manager.deployLiquidityQuote(address(asset), deployAmount, slippageBps);

        vm.expectEmit(address(manager));
        emit LiquidityDeployed(deployAmount, address(asset), deployAmount, 49_953.744905641071321560e18);
        manager.deployLiquidity(address(asset), deployAmount, requestData);

        assertEq(manager.unallocatedAssets(), 50_000e6);
        assertEq(manager.totalAssets(), 100_000e6);
        assertEq(vault.convertToShares(1e6), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e6);
    }

    function test_totalAssets_fullDeployed() public {
        uint256 totalUsdc = 100_000e6;
        uint256 slippageBps = 50; // 0.5%

        vm.startPrank(origamiMultisig);
        deal(address(asset), origamiMultisig, totalUsdc);
        asset.approve(address(vault), totalUsdc);
        uint256 msigShares = vault.seedDeposit(totalUsdc, origamiMultisig, 100_000_000e18);
        assertEq(msigShares, 100_000e18);
        
        assertEq(manager.totalAssets(), totalUsdc);
        assertEq(vault.totalSupply(), 100_000e18);
        assertEq(vault.convertToShares(1e6), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e6);

        (
            uint256 expectedLpAmount,
            uint256 minLpAmount,
            IBalancerVault.JoinPoolRequest memory requestData
        ) = manager.deployLiquidityQuote(address(asset), totalUsdc, slippageBps);
        
        vm.expectEmit(address(manager));
        emit LiquidityDeployed(totalUsdc, address(asset), totalUsdc, 99_906.648421046927100404e18);
        manager.deployLiquidity(address(asset), totalUsdc, requestData);

        assertEq(expectedLpAmount, 99_906.648421046927100404e18);
        assertEq(minLpAmount, OrigamiMath.subtractBps(expectedLpAmount, slippageBps, OrigamiMath.Rounding.ROUND_DOWN));

        uint256[] memory tokens = bexPoolHelper.tokenAmountsForLpTokens(99_906.648421046927100404e18);
        assertEq(tokens[0], 31_112.752228e6); // USDC
        assertEq(tokens[2], 68_917.366789043476530326e18); // HONEY

        uint256[] memory balances = manager.bexTokenBalances();
        assertEq(balances[0], 31_112.752228e6); // USDC
        assertEq(balances[2], 68_917.366789043476530326e18); // HONEY

        assertEq(manager.unallocatedAssets(), 0); // fully allocated

        assertEq(manager.totalAssets(), 100_000e6);
        assertEq(vault.convertToShares(1e6), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e6);
    }
}
