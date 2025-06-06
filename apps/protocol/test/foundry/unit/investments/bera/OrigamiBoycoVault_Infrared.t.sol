// NOTE(chachlex): needs migration to bera mainnet or bepolia
// pragma solidity ^0.8.19;
// // SPDX-License-Identifier: AGPL-3.0-or-later

// import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
// import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// import { OrigamiBoycoVault } from "contracts/investments/bera/OrigamiBoycoVault.sol";
// import { OrigamiBoycoUsdcManager } from "contracts/investments/bera/OrigamiBoycoUsdcManager.sol";
// import { TokenPrices } from "contracts/common/TokenPrices.sol";
// import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

// import { IInfraredVault } from "contracts/interfaces/external/infrared/IInfraredVault.sol";
// import { IBeraBgt } from "contracts/interfaces/external/bera/IBeraBgt.sol";

// import { IBalancerVault } from "contracts/interfaces/external/balancer/IBalancerVault.sol";
// import { IBalancerQueries } from "contracts/interfaces/external/balancer/IBalancerQueries.sol";
// import { OrigamiBalancerComposableStablePoolHelper } from "contracts/common/balancer/OrigamiBalancerComposableStablePoolHelper.sol";
// import { IBalancerBptToken } from "contracts/interfaces/external/balancer/IBalancerBptToken.sol";

// import { OrigamiInfraredVaultProxy } from "contracts/common/bera/infrared/OrigamiInfraredVaultProxy.sol";
// import { IBeraBgt } from "contracts/interfaces/external/bera/IBeraBgt.sol";


// contract OrigamiBoycoVaultTest_Infrared_Base is OrigamiTest {

//     IBeraBgt internal constant bgtToken = IBeraBgt(0x289274787bAF083C15A45a174b7a8e44F0720660);
//     IInfraredVault internal constant infraredVault = IInfraredVault(0x380605d60386682Ef8a0e79F4eC0b45A08bce171);

//     IBalancerBptToken internal constant lpToken = IBalancerBptToken(0xF7F214A9543c1153eF5DF2edCd839074615F248c);

//     IBalancerVault internal constant bexVault = IBalancerVault(0x9C8a5c82e797e074Fe3f121B326b140CEC4bcb33);
//     IBalancerQueries internal constant balancerQueries = IBalancerQueries(0xf3F2d2D5706543Dc17584835647A98C34cE54cc3);

//     IERC20 internal constant asset = IERC20(0x015fd589F4f1A33ce4487E12714e1B15129c9329); // USDC
//     IERC20 internal constant honeyToken = IERC20(0xd137593CDB341CcC78426c54Fb98435C60Da193c);

//     OrigamiBoycoVault internal vault;
//     OrigamiBoycoUsdcManager internal manager;
//     TokenPrices internal tokenPrices;

//     OrigamiBalancerComposableStablePoolHelper internal bexPoolHelper;

//     OrigamiInfraredVaultProxy internal infraredVaultProxy;

//     event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
//     event Withdraw(
//         address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
//     );

//     function setUp() public {
//         fork("berachain_cartio_testnet", 4048000);

//         tokenPrices = new TokenPrices(30);
//         vault = new OrigamiBoycoVault(
//             origamiMultisig, 
//             "Origami HONEY", 
//             "ovHONEY",
//             asset,
//             address(tokenPrices)
//         );
        
//         infraredVaultProxy = new OrigamiInfraredVaultProxy(origamiMultisig, address(infraredVault));
        
//         bexPoolHelper = new OrigamiBalancerComposableStablePoolHelper(
//             origamiMultisig,
//             address(bexVault),
//             address(balancerQueries),
//             lpToken.getPoolId()
//         );
        
//         manager = new OrigamiBoycoUsdcManager(
//             origamiMultisig,
//             address(vault),
//             address(asset),
//             address(bexPoolHelper),
//             address(infraredVaultProxy)
//         );

//         vm.startPrank(origamiMultisig);
//         vault.setManager(address(manager));
//         setExplicitAccess(
//             infraredVaultProxy, 
//             address(manager), 
//             OrigamiInfraredVaultProxy.stake.selector, 
//             OrigamiInfraredVaultProxy.withdraw.selector, 
//             true
//         );
//         vm.stopPrank();

//         seedDeposit(origamiMultisig, 0.1e6, type(uint256).max);
//     }

//     function seedDeposit(address account, uint256 amount, uint256 maxSupply) internal {
//         vm.startPrank(account);
//         deal(address(asset), account, amount);
//         asset.approve(address(vault), amount);
//         vault.seedDeposit(amount, account, maxSupply);
//         vm.stopPrank();
//     }

//     function deposit(address user, uint256 amount) internal {
//         deal(address(asset), user, amount);
//         vm.startPrank(user);
//         asset.approve(address(vault), amount);
//         uint256 expectedShares = vault.previewDeposit(amount);

//         vm.expectEmit(address(vault));
//         emit Deposit(user, user, amount, expectedShares);
//         uint256 actualShares = vault.deposit(amount, user);
//         vm.stopPrank();

//         assertEq(actualShares, expectedShares);
//     }

//     function mint(address user, uint256 shares) internal {
//         uint256 expectedAssets = vault.previewMint(shares);
//         deal(address(asset), user, expectedAssets);
//         vm.startPrank(user);
//         asset.approve(address(vault), expectedAssets);

//         vm.expectEmit(address(vault));
//         emit Deposit(user, user, expectedAssets, shares);
//         uint256 actualAssets = vault.mint(shares, user);
//         vm.stopPrank();

//         assertEq(actualAssets, expectedAssets);
//     }

//     function withdraw(address user, uint256 assets) internal {
//         vm.startPrank(user);
//         uint256 expectedShares = vault.previewWithdraw(assets);

//         vm.expectEmit(address(vault));
//         emit Withdraw(user, user, user, assets, expectedShares);
//         uint256 actualShares = vault.withdraw(assets, user, user);
//         vm.stopPrank();

//         assertEq(actualShares, expectedShares);
//     }

//     function redeem(address user, uint256 shares) internal {
//         vm.startPrank(user);
//         uint256 expectedAssets = vault.previewRedeem(shares);

//         vm.expectEmit(address(vault));
//         emit Withdraw(user, user, user, expectedAssets, shares);
//         uint256 actualAssets = vault.redeem(shares, user, user);
//         vm.stopPrank();

//         assertEq(actualAssets, expectedAssets);
//     }

//     function addToSharePrice(uint256 amount) internal {
//         deal(address(asset), address(manager), asset.balanceOf(address(manager)) + amount);
//     }
// }

// contract OrigamiBoycoVaultTest_Infrared_Admin is OrigamiBoycoVaultTest_Infrared_Base {
//     event TokenPricesSet(address indexed tokenPrices);
//     event ManagerSet(address indexed manager);

//     function test_initialization() public view {
//         assertEq(vault.owner(), origamiMultisig);
//         assertEq(vault.name(), "Origami HONEY");
//         assertEq(vault.symbol(), "ovHONEY");
//         assertEq(vault.asset(), address(asset));
//         assertEq(vault.decimals(), 18);
//         assertEq(address(vault.manager()), address(manager));
//         assertEq(address(vault.tokenPrices()), address(tokenPrices));
//         assertEq(vault.performanceFeeBps(), 0);
//         assertEq(vault.maxTotalSupply(), type(uint256).max);
//         assertEq(vault.totalSupply(), 0.1e18);
//         assertEq(vault.totalAssets(), 0.1e6);
//         assertEq(vault.convertToShares(1e6), 1e18);
//         assertEq(vault.convertToAssets(1e18), 1e6);
//         assertEq(vault.maxDeposit(alice), type(uint256).max);
//         assertEq(vault.maxMint(alice), type(uint256).max);
//         assertEq(vault.maxWithdraw(alice), 0);
//         assertEq(vault.maxRedeem(alice), 0);
//         assertEq(vault.previewDeposit(1e6), 1e18); // no fees
//         assertEq(vault.previewMint(1e18), 1e6); // no fees
//         assertEq(vault.previewWithdraw(1e6), 1e18); // no fees
//         assertEq(vault.previewRedeem(1e18), 1e6); // no fees
//         assertEq(vault.areDepositsPaused(), false);
//         assertEq(vault.areWithdrawalsPaused(), false);
//     }

//     function test_setManager_fail() public {
//         vm.startPrank(origamiMultisig);
//         vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
//         vault.setManager(address(0));
//     }

//     function test_setManager_success() public {
//         vm.startPrank(origamiMultisig);
//         vm.expectEmit(address(vault));
//         emit ManagerSet(alice);
//         vault.setManager(alice);
//         assertEq(address(vault.manager()), alice);
//     }

//     function test_setTokenPrices_fail() public {
//         vm.startPrank(origamiMultisig);
//         vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
//         vault.setTokenPrices(address(0));
//     }

//     function test_setTokenPrices_success() public {
//         vm.startPrank(origamiMultisig);
//         vm.expectEmit(address(vault));
//         emit TokenPricesSet(alice);
//         vault.setTokenPrices(alice);
//         assertEq(address(vault.tokenPrices()), alice);
//     }

//     function test_recoverToken() public {
//         check_recoverToken(address(vault));
//     }
// }

// contract OrigamiBoycoVaultTest_Infrared_Access is OrigamiBoycoVaultTest_Infrared_Base {
//     event PerformanceFeeSet(uint256 fee);
    
//     function test_setManager_access() public {
//         expectElevatedAccess();
//         vault.setManager(alice);
//     }

//     function test_setTokenPrices_access() public {
//         expectElevatedAccess();
//         vault.setTokenPrices(alice);
//     }
// }

// contract OrigamiBoycoVaultTest_Infrared_Deposit is OrigamiBoycoVaultTest_Infrared_Base {
//     function test_deposit_basic() public {
//         deposit(alice, 123e6);

//         uint256 expectedShares = 123e18;

//         assertEq(asset.balanceOf(alice), 0);
//         assertEq(asset.balanceOf(address(vault)), 0);
//         assertEq(asset.balanceOf(address(manager)), 123e6 + 0.1e6);
//         assertEq(vault.balanceOf(alice), expectedShares);
//         assertEq(vault.totalSupply(), 123e18 + 0.1e18);
//         assertEq(vault.totalAssets(), 123e6 + 0.1e6);
//     }

//     function test_deposit_beforeShareIncrease() public {
//         deposit(alice, 123e6);

//         // Donations don't count
//         addToSharePrice(100e6);

//         uint256 expectedShares = 123e18;

//         assertEq(asset.balanceOf(alice), 0);
//         assertEq(asset.balanceOf(address(vault)), 0);
//         assertEq(asset.balanceOf(address(manager)), 100e6 + 123e6 + 0.1e6);
//         assertEq(vault.balanceOf(alice), expectedShares);
//         assertEq(vault.totalSupply(), 123e18 + 0.1e18);
//         assertEq(vault.totalAssets(), 123e6 + 0.1e6);
//         assertEq(vault.convertToShares(1e6), 1e18);
//         assertEq(vault.convertToAssets(1e18), 1e6);
//     }

//     function test_deposit_afterShareIncrease() public {
//         deposit(bob, 100e6);

//         addToSharePrice(10e6); // 10% increase
//         assertEq(vault.convertToShares(1e6), 1e18);
//         assertEq(vault.convertToAssets(1e18), 1e6);

//         assertEq(vault.maxDeposit(alice), type(uint256).max);
//         assertEq(vault.maxMint(alice), type(uint256).max);
//         deposit(alice, 123e6);

//         assertEq(asset.balanceOf(alice), 0);
//         assertEq(asset.balanceOf(address(vault)), 0);
//         assertEq(asset.balanceOf(address(manager)), 100e6 + 10e6 + 123e6 + 0.1e6);
//         assertEq(vault.balanceOf(alice), 123e18);
//         assertEq(vault.totalSupply(), 223.1e18);
//         assertEq(vault.totalAssets(), 223e6 + 0.1e6);

//         assertEq(vault.convertToShares(1e6), 1e18);
//         assertEq(vault.convertToAssets(1e18), 1e6);
//     }
// }

// contract OrigamiBoycoVaultTest_Infrared_Mint is OrigamiBoycoVaultTest_Infrared_Base {
//     function test_mint_basic() public {
//         mint(alice, 123e18);

//         uint256 expectedAssets = 123e6;

//         assertEq(asset.balanceOf(alice), 0);
//         assertEq(asset.balanceOf(address(vault)), 0);
//         assertEq(asset.balanceOf(address(manager)), expectedAssets + 0.1e6);
//         assertEq(vault.balanceOf(alice), 123e18);
//         assertEq(vault.totalSupply(), 123e18 + 0.1e18);
//         assertEq(vault.totalAssets(), 123e6 + 0.1e6);
//     }

//     function test_mint_beforeShareIncrease() public {
//         mint(alice, 123e18);

//         addToSharePrice(100e6);

//         uint256 expectedAssets = 100e6 + 123e6;

//         assertEq(asset.balanceOf(alice), 0);
//         assertEq(asset.balanceOf(address(vault)), 0);
//         assertEq(asset.balanceOf(address(manager)), expectedAssets + 0.1e6);
//         assertEq(vault.balanceOf(alice), 123e18);
//         assertEq(vault.totalSupply(), 123e18 + 0.1e18);
//         assertEq(vault.totalAssets(), 123e6 + 0.1e6);
//         assertEq(vault.convertToShares(1e6), 1e18);
//         assertEq(vault.convertToAssets(1e18), 1e6);
//     }

//     function test_mint_afterShareIncrease() public {
//         mint(bob, 100e18);

//         addToSharePrice(10e6); // 10% increase
//         assertEq(vault.convertToShares(1e6), 1e18);
//         assertEq(vault.convertToAssets(1e18), 1e6);

//         assertEq(vault.maxDeposit(alice), type(uint256).max);
//         assertEq(vault.maxMint(alice), type(uint256).max);
//         mint(alice, 123e18);

//         assertEq(asset.balanceOf(alice), 0);
//         assertEq(asset.balanceOf(address(vault)), 0);
//         assertEq(asset.balanceOf(address(manager)), 233.1e6);
//         assertEq(vault.balanceOf(alice), 123e18);
//         assertEq(vault.totalSupply(), 223e18 + 0.1e18);

//         assertEq(vault.convertToShares(1e6), 1e18);
//         assertEq(vault.convertToAssets(1e18), 1e6);
//     }
// }

// contract OrigamiBoycoVaultTest_Infrared_Withdraw is OrigamiBoycoVaultTest_Infrared_Base {
//     function test_withdraw_basic() public {
//         deposit(alice, 123e6);

//         withdraw(alice, 50e6);

//         uint256 expectedShares = 73e18;

//         assertEq(asset.balanceOf(alice), 50e6);
//         assertEq(asset.balanceOf(address(vault)), 0);
//         assertEq(asset.balanceOf(address(manager)), 73e6 + 0.1e6);
//         assertEq(vault.balanceOf(alice), expectedShares);
//         assertEq(vault.totalSupply(), expectedShares + 0.1e18);
//         assertEq(vault.totalAssets(), 73e6 + 0.1e6);
//     }

//     function test_withdraw_beforeShareIncrease() public {
//         deposit(alice, 123e6);

//         withdraw(alice, 50e6);
//         addToSharePrice(100e6);

//         uint256 expectedShares = 73e18;

//         assertEq(asset.balanceOf(alice), 50e6);
//         assertEq(asset.balanceOf(address(vault)), 0);
//         assertEq(asset.balanceOf(address(manager)), 100e6 + 73e6 + 0.1e6);
//         assertEq(vault.balanceOf(alice), expectedShares);
//         assertEq(vault.totalSupply(), expectedShares + 0.1e18);
//         assertEq(vault.totalAssets(), 73e6 + 0.1e6);
//         assertEq(vault.convertToShares(1e6), 1e18);
//         assertEq(vault.convertToAssets(1e18), 1e6);
//     }

//     function test_withdraw_afterShareIncrease() public {
//         deposit(alice, 100e6);

//         addToSharePrice(10e6); // 10% increase
//         assertEq(vault.convertToShares(1e6), 1e18);
//         assertEq(vault.convertToAssets(1e18), 1e6);

//         assertEq(vault.maxWithdraw(alice), 100e6);
//         assertEq(vault.maxRedeem(alice), 100e18);
//         withdraw(alice, 50e6);

//         assertEq(asset.balanceOf(alice), 50e6);
//         assertEq(asset.balanceOf(address(vault)), 0);
//         assertEq(asset.balanceOf(address(manager)), 10e6 + 50e6 + 0.1e6);
//         assertEq(vault.balanceOf(alice), 50e18);
//         assertEq(vault.totalSupply(), 50.1e18);
//         assertEq(vault.totalAssets(), 50e6 + 0.1e6);

//         assertEq(vault.convertToShares(1e6), 1e18);
//         assertEq(vault.convertToAssets(1e18), 1e6);
//     }

//     function test_maxWithdraw() public {
//         deposit(alice, 100e6);
//         deposit(bob, 299e6);
//         assertEq(vault.maxWithdraw(alice), 100e6);
//         assertEq(vault.maxWithdraw(bob), 299e6);

//         vm.startPrank(origamiMultisig);

//         // Simulate 50 being allocated and each of them still say they can get it all
//         manager.recoverToken(address(asset), origamiMultisig, 50e6);
//         assertEq(vault.maxWithdraw(alice), 100e6);
//         assertEq(vault.maxWithdraw(bob), 299e6);

//         manager.recoverToken(address(asset), origamiMultisig, 51e6);
//         assertEq(vault.maxWithdraw(alice), 100e6);
//         assertEq(vault.maxWithdraw(bob), 298e6 + 0.1e6); // includes the seed

//         manager.recoverToken(address(asset), origamiMultisig, 250e6);
//         assertEq(vault.maxWithdraw(alice), 48e6 + 0.1e6);
//         assertEq(vault.maxWithdraw(bob), 48e6 + 0.1e6); // includes the seed

//         // Simulate it being unallocated
//         asset.transfer(address(manager), 351e6);
//         assertEq(vault.maxWithdraw(alice), 100e6);
//         assertEq(vault.maxWithdraw(bob), 299e6);
//     }
// }

// contract OrigamiBoycoVaultTest_Infrared_Redeem is OrigamiBoycoVaultTest_Infrared_Base {
//     function test_redeem_basic() public {
//         deposit(alice, 123e6);

//         redeem(alice, 50e18);

//         uint256 expectedShares = 123e18 - 50e18;
//         uint256 expectedAssets = 123e6 - 50e6;

//         assertEq(asset.balanceOf(alice), 50e6);
//         assertEq(asset.balanceOf(address(vault)), 0);
//         assertEq(asset.balanceOf(address(manager)), expectedAssets + 0.1e6);
//         assertEq(vault.balanceOf(alice), expectedShares);
//         assertEq(vault.totalSupply(), expectedShares + 0.1e18);
//         assertEq(vault.totalAssets(), expectedAssets + 0.1e6);
//     }

//     function test_redeem_beforeShareIncrease() public {
//         deposit(alice, 123e6);

//         redeem(alice, 50e18);
//         addToSharePrice(100e6);

//         uint256 expectedShares = 123e18 - 50e18;

//         assertEq(asset.balanceOf(alice), 50e6);
//         assertEq(asset.balanceOf(address(vault)), 0);
//         assertEq(asset.balanceOf(address(manager)), 100e6 + 73e6 + 0.1e6);
//         assertEq(vault.balanceOf(alice), expectedShares);
//         assertEq(vault.totalSupply(), expectedShares + 0.1e18);
//         assertEq(vault.totalAssets(), 123e6 - 50e6 + 0.1e6);
//         assertEq(vault.convertToShares(1e6), 1e18);
//         assertEq(vault.convertToAssets(1e18), 1e6);
//     }

//     function test_redeem_afterShareIncrease() public {
//         deposit(alice, 100e6);

//         addToSharePrice(10e6); // 10% increase
//         assertEq(vault.convertToShares(1e6), 1e18);
//         assertEq(vault.convertToAssets(1e18), 1e6);

//         assertEq(vault.maxWithdraw(alice), 100e6);
//         assertEq(vault.maxRedeem(alice), 100e18);
//         redeem(alice, 50e18);

//         uint256 expectedShares = 100e18 - 50e18;

//         assertEq(asset.balanceOf(alice), 50e6);
//         assertEq(asset.balanceOf(address(vault)), 0);
//         assertEq(asset.balanceOf(address(manager)), 10e6 + 50.1e6);
//         assertEq(vault.balanceOf(alice), expectedShares);
//         assertEq(vault.totalSupply(), expectedShares + 0.1e18);
//         assertEq(vault.totalAssets(), 50.1e6);

//         assertEq(vault.convertToShares(1e6), 1e18);
//         assertEq(vault.convertToAssets(1e18), 1e6);
//     }

//     function test_maxRedeem() public {
//         deposit(alice, 100e6);
//         deposit(bob, 299e6);
//         assertEq(vault.maxRedeem(alice), 100e18);
//         assertEq(vault.maxRedeem(bob), 299e18);

//         vm.startPrank(origamiMultisig);

//         // Simulate 50 being allocated and each of them still say they can get it all
//         manager.recoverToken(address(asset), origamiMultisig, 50e6);
//         assertEq(vault.maxRedeem(alice), 100e18);
//         assertEq(vault.maxRedeem(bob), 299e18);

//         manager.recoverToken(address(asset), origamiMultisig, 51e6);
//         assertEq(vault.maxRedeem(alice), 100e18);
//         assertEq(vault.maxRedeem(bob), 298e18 + 0.1e18); // includes the seed

//         manager.recoverToken(address(asset), origamiMultisig, 250e6);
//         assertEq(vault.maxRedeem(alice), 48e18 + 0.1e18);
//         assertEq(vault.maxRedeem(bob), 48e18 + 0.1e18); // includes the seed

//         // Simulate it being unallocated
//         asset.transfer(address(manager), 351e6);
//         assertEq(vault.maxRedeem(alice), 100e18);
//         assertEq(vault.maxRedeem(bob), 299e18);
//     }
// }