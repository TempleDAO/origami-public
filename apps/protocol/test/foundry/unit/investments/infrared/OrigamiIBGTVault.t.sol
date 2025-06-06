pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IInfraredVault } from "contracts/interfaces/external/infrared/IInfraredVault.sol";
import { IOrigamiErc4626 } from "contracts/interfaces/common/IOrigamiErc4626.sol";
import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";

import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiDelegated4626Vault } from "contracts/investments/OrigamiDelegated4626Vault.sol";
import { OrigamiInfraredVaultManager } from "contracts/investments/infrared/OrigamiInfraredVaultManager.sol";
import { OrigamiSwapperWithCallback } from "contracts/common/swappers/OrigamiSwapperWithCallback.sol";
import { DummyDexRouter } from "contracts/test/common/swappers/DummyDexRouter.sol";

contract OrigamiIBGTVaultTestBase is OrigamiTest {
    using OrigamiMath for uint256;
    using SafeERC20 for IERC20;

    event InKindFees(IOrigamiErc4626.FeeType feeType, uint256 feeBps, uint256 feeAmount);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    OrigamiDelegated4626Vault internal vault;
    OrigamiInfraredVaultManager internal manager;
    TokenPrices internal tokenPrices;

    IERC20 internal constant asset = IERC20(0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b);
    IERC20 internal constant wBeraToken = IERC20(0x6969696969696969696969696969696969696969);
    IERC20 internal constant honeyToken = IERC20(0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce);
    IInfraredVault internal iBgtVault = IInfraredVault(0x4EF0c533D065118907f68e6017467Eb05DBb2c8C);

    uint16 internal constant PERF_FEE_FOR_ORIGAMI = 100; // 1%

    uint256 internal constant DEPOSIT_FEE = 0;
    uint256 internal constant SEED_AMOUNT = 0.1e18;
    address internal swapper = makeAddr("swapper");

    function setUp() public virtual {
        fork("berachain_mainnet", 980_084);

        tokenPrices = new TokenPrices(30);
        vault = new OrigamiDelegated4626Vault(
            origamiMultisig, "Origami iBGT Auto-Compounding Vault", "oriBGT", asset, address(tokenPrices)
        );

        manager = new OrigamiInfraredVaultManager(
            origamiMultisig,
            address(vault),
            address(asset),
            address(iBgtVault),
            feeCollector,
            swapper,
            PERF_FEE_FOR_ORIGAMI
        );

        vm.startPrank(origamiMultisig);
        vault.setManager(address(manager));
        vm.stopPrank();

        seedDeposit(origamiMultisig, SEED_AMOUNT, type(uint256).max);
    }

    function seedDeposit(address account, uint256 amount, uint256 maxSupply) internal {
        vm.startPrank(account);
        deal(address(asset), account, amount);
        asset.approve(address(vault), amount);
        vault.seedDeposit(amount, account, maxSupply);
        vm.stopPrank();
    }

    function deposit(address user, uint256 amount) internal returns (uint256 shares) {
        deal(address(asset), user, amount);
        vm.startPrank(user);
        asset.approve(address(vault), amount);
        uint256 expectedShares = vault.previewDeposit(amount);

        vm.expectEmit(address(vault));
        emit Deposit(user, user, amount, expectedShares);
        shares = vault.deposit(amount, user);
        vm.stopPrank();

        assertEq(shares, expectedShares);
    }

    function mint(address user, uint256 shares) internal returns (uint256 assetsDeposited) {
        assetsDeposited = vault.previewMint(shares);
        deal(address(asset), user, assetsDeposited);
        vm.startPrank(user);
        asset.approve(address(vault), assetsDeposited);

        vm.expectEmit(address(vault));
        emit Deposit(user, user, assetsDeposited, shares);
        uint256 actualAssets = vault.mint(shares, user);
        vm.stopPrank();

        assertEq(actualAssets, assetsDeposited);
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

    /// @notice Simulates the manager receiving assets (either from donation or from rewards)
    function donateAndReinvest(uint256 amount) internal {
        doMint(asset, address(manager), amount);
        manager.reinvest();
        skip(10 minutes);
    }
}

contract OrigamiIBGTVaultTest_Admin is OrigamiIBGTVaultTestBase {
    event TokenPricesSet(address indexed tokenPrices);
    event ManagerSet(address indexed manager);

    function test_initialization() public view {
        assertEq(vault.owner(), origamiMultisig);
        assertEq(vault.name(), "Origami iBGT Auto-Compounding Vault");
        assertEq(vault.symbol(), "oriBGT");
        assertEq(vault.asset(), address(asset));
        assertEq(vault.decimals(), 18);
        assertEq(address(vault.manager()), address(manager));
        assertEq(address(vault.tokenPrices()), address(tokenPrices));
        assertEq(vault.performanceFeeBps(), PERF_FEE_FOR_ORIGAMI);
        assertEq(vault.maxTotalSupply(), type(uint256).max);
        assertEq(vault.totalSupply(), SEED_AMOUNT);
        assertEq(vault.totalAssets(), SEED_AMOUNT);
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

contract OrigamiIBGTVaultTest_Access is OrigamiIBGTVaultTestBase {
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

contract OrigamiIBGTVaultTest_Deposit is OrigamiIBGTVaultTestBase {
    function test_deposit_basic() public {
        uint256 expectedShares = OrigamiMath.subtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_DOWN);
        deposit(alice, 123e18);

        // alices assets are immediately staked
        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 0);

        // no fees are taken on deposit, full assets are available for withdraw
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), 123e18 + SEED_AMOUNT);
        assertEq(vault.totalAssets(), 123e18 + SEED_AMOUNT);
    }

    function test_deposit_beforeShareIncrease() public {
        uint256 shares = deposit(alice, 123e18);
        uint256 expectedShares = 123e18;
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(shares, expectedShares);

        uint256 assetsWithdrawable1 = vault.convertToAssets(shares);
        assertEq(assetsWithdrawable1, 123e18);
        assertEq(vault.totalAssets(), 123e18 + SEED_AMOUNT, "totalAssets");

        // after a donation the share price increases
        uint256 donationAmount = 100e18;
        doMint(asset, address(manager), donationAmount);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), donationAmount); // donation
        assertEq(manager.unallocatedAssets(), donationAmount - 1e18); // subject the perf fee

        // Donation doesn't immediately impact the share price
        assertEq(vault.totalAssets(), 123e18 + SEED_AMOUNT, "totalAssets");
        assertEq(vault.convertToAssets(shares), 123e18, "convertToAssets");

        // reinvest will now include the donation
        manager.reinvest();

        // Still no difference as those rewards get dripped in
        assertEq(vault.totalAssets(), 123e18 + SEED_AMOUNT, "totalAssets");
        assertEq(vault.convertToAssets(shares), 123e18, "convertToAssets");

        skip(10 minutes);

        // donation is subject to perf fees
        // alice can withdraw more assets than before the donation
        assertEq(vault.totalAssets(), 123e18 + SEED_AMOUNT + donationAmount - 1e18, "totalAssets");
        assertEq(vault.convertToAssets(shares), 221.919577579203899268e18, "convertToAssets");
    }

    function test_deposit_afterShareIncrease() public {
        uint256 bobShares = deposit(bob, 100e18);
        assertEq(bobShares, 100e18);

        uint256 donationAmount = 10e18;
        donateAndReinvest(donationAmount); // ~10% donation increases share price

        assertEq(vault.convertToShares(1e18), 0.91e18);
        assertEq(vault.convertToAssets(1e18), 1.098901098901098901e18);

        assertEq(vault.maxDeposit(alice), type(uint256).max);
        assertEq(vault.maxMint(alice), type(uint256).max);

        uint256 aliceShares = deposit(alice, 100e18);

        // alice gets less shares than bob because price has increased
        assertLt(aliceShares, bobShares);
        assertEq(vault.balanceOf(alice), 91e18, "balanceOf(alice)");
        assertEq(vault.totalSupply(), 191.1e18, "totalSupply");
        assertEq(vault.totalSupply(), aliceShares + bobShares + SEED_AMOUNT, "totalSupply"); 

        // total assets doesn't include iBGT reserved for fees
        assertEq(vault.totalAssets(), 100e18 + 100e18 + SEED_AMOUNT + donationAmount - 0.1e18, "totalAssets");
        assertEq(manager.stakedAssets(), 100e18 + 100e18 + SEED_AMOUNT + donationAmount - 0.1e18);

        // asset is immediately staked
        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 0);

        // Depositing doesn't change the price - rewards were already compounded
        assertEq(vault.convertToShares(1e18), 0.91e18);
        assertEq(vault.convertToAssets(1e18), 1.098901098901098901e18);
    }
}

contract OrigamiIBGTVaultTest_Mint is OrigamiIBGTVaultTestBase {
    function test_mint_basic() public {
        mint(alice, 123e18);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 0);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 123e18 + 0.1e18);
        assertEq(vault.totalAssets(), 123e18 + 0.1e18);
    }

    function test_mint_beforeShareIncrease() public {
        uint256 aliceDeposit = mint(alice, 123e18);

        donateAndReinvest(100e18);

        // alice's deposit + SEED_AMOUNT + 2% perf fee taken off donation
        uint256 expectedAssets = SEED_AMOUNT + aliceDeposit + 100e18 - 1e18;

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 0);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 123e18 + SEED_AMOUNT, "totalSupply");
        assertEq(vault.totalAssets(), expectedAssets, "totalAssets"); // 2% perf fee taken off donation
        assertEq(manager.stakedAssets(), expectedAssets);
        assertEq(vault.convertToShares(1e18), 0.554254840162089149e18);
        assertEq(vault.convertToAssets(1e18), 1.804224207961007311e18);
    }

    function test_mint_afterShareIncrease() public {
        uint256 bobDeposit = mint(bob, 100e18);

        uint256 donationAmount = 10e18;
        donateAndReinvest(donationAmount); // ~10% increase

        assertEq(vault.convertToShares(1e18), 0.91e18);
        assertEq(vault.convertToAssets(1e18), 1.098901098901098901e18);

        assertEq(vault.maxDeposit(alice), type(uint256).max);
        assertEq(vault.maxMint(alice), type(uint256).max);

        uint256 aliceDeposit = mint(alice, 100e18);
        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 0);
        assertEq(vault.balanceOf(alice), 100e18);

        // alice share + bob share + seed share
        assertEq(vault.totalSupply(), SEED_AMOUNT + 100e18 + 100e18, "totalSupply");
        assertEq(vault.totalAssets(), SEED_AMOUNT + bobDeposit + aliceDeposit + donationAmount - 0.1e18, "totalAssets");
        assertEq(manager.stakedAssets(), SEED_AMOUNT + bobDeposit + aliceDeposit + donationAmount - 0.1e18);
        assertGt(aliceDeposit, bobDeposit); // alice paid a higher share price
        assertEq(aliceDeposit, 109.890109890109890110e18);

        // Depositing causes reinvestment that pushes up the price
        assertEq(vault.convertToShares(1e18), 0.91e18 - 1); // rounding
        assertEq(vault.convertToAssets(1e18), 1.098901098901098901e18);
    }
}

contract OrigamiIBGTVaultTest_Withdraw is OrigamiIBGTVaultTestBase {
    function test_withdraw_basic() public {
        deposit(alice, 123e18);

        withdraw(alice, 50e18);

        uint256 expectedShares = 73e18;

        assertEq(asset.balanceOf(alice), 50e18);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 0);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares + 0.1e18);
        assertEq(vault.totalAssets(), 73e18 + 0.1e18);
    }

    function test_withdraw_beforeShareIncrease() public {
        deposit(alice, 123e18);
        withdraw(alice, 50e18);

        donateAndReinvest(100e18);

        assertEq(asset.balanceOf(alice), 50e18);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 0);

        uint256 sharesRemaining = 73e18;
        assertEq(vault.balanceOf(alice), sharesRemaining);
        assertEq(vault.totalSupply(), sharesRemaining + SEED_AMOUNT, "totalSupply");
        // 2% perf fee taken off donation
        assertEq(vault.totalAssets(), 73e18 + SEED_AMOUNT + 100e18 - 1e18, "totalAssets"); 
        assertEq(manager.stakedAssets(), 73e18 + SEED_AMOUNT + 100e18 - 1e18);
        assertEq(vault.convertToShares(1e18), 0.424753050552004648e18);
        assertEq(vault.convertToAssets(1e18), 2.354309165526675786e18);
    }

    function test_withdraw_afterShareIncrease() public {
        uint256 aliceShares = deposit(alice, 100e18);
        assertEq(aliceShares, 100e18);

        uint256 assetDonation = 10e18;
        donateAndReinvest(assetDonation); // ~10% increase less 2% perf fee
        assertEq(vault.convertToShares(1e18), 0.91e18);
        assertEq(vault.convertToAssets(1e18), 1.098901098901098901e18);

        // alice can withdraw more than she deposited
        assertEq(vault.maxWithdraw(alice), 109.890109890109890109e18);
        assertEq(vault.maxRedeem(alice), 100e18);

        withdraw(alice, 50e18);

        // withdraw causes donated amount to be reinvested
        assertEq(asset.balanceOf(alice), 50e18);
        assertEq(asset.balanceOf(feeCollector), 0.1e18);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 0); // amount in vault was staked

        assertEq(vault.balanceOf(alice), 54.499999999999999999e18);
        assertEq(vault.totalSupply(), 54.599999999999999999e18, "totalSupply");

        // all available assets are staked
        uint256 expectedAssets = SEED_AMOUNT + 100e18 + assetDonation - 0.1e18 - 50e18;
        assertEq(iBgtVault.balanceOf(address(manager)), expectedAssets, "stakedAmount");
        assertEq(vault.totalAssets(), expectedAssets, "totalAssets");
        assertEq(manager.stakedAssets(), expectedAssets);

        // Withdrawal fees continue to help the share price
        assertEq(vault.convertToShares(1e18), 0.91e18 - 1); // rounding
        assertEq(vault.convertToAssets(1e18), 1.098901098901098901e18);
    }
}

contract OrigamiIBGTVaultTest_Redeem is OrigamiIBGTVaultTestBase {
    function test_redeem_basic() public {
        deposit(alice, 123e18);

        redeem(alice, 50e18);

        uint256 expectedShares = OrigamiMath.subtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_DOWN) - 50e18;
        uint256 expectedAssets = 123e18 - 50e18;

        assertEq(asset.balanceOf(alice), 50e18);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 0);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares + 0.1e18);
        assertEq(vault.totalAssets(), expectedAssets + 0.1e18);
    }

    function test_redeem_beforeShareIncrease() public {
        deposit(alice, 123e18);
        redeem(alice, 50e18);
        donateAndReinvest(100e18);

        uint256 expectedAssets = SEED_AMOUNT + 123e18 + 100e18 - 1e18 - 50e18;

        assertEq(asset.balanceOf(alice), 50e18);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 0);

        assertEq(vault.balanceOf(alice), 123e18 - 50e18);
        assertEq(vault.totalSupply(), SEED_AMOUNT + 123e18 - 50e18, "totalSupply");
        assertEq(vault.totalAssets(), expectedAssets, "totalAssets");
        assertEq(manager.stakedAssets(), expectedAssets);
        assertEq(vault.convertToShares(1e18), 0.424753050552004648e18);
        assertEq(vault.convertToAssets(1e18), 2.354309165526675786e18);
    }

    function test_redeem_afterShareIncrease() public {
        deposit(alice, 100e18);

        assertEq(vault.convertToShares(1e18), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e18);

        donateAndReinvest(10e18); // 10% increase

        // changes price
        assertEq(vault.convertToShares(1e18), 0.91e18);
        assertEq(vault.convertToAssets(1e18), 1.098901098901098901e18);

        assertEq(vault.maxWithdraw(alice), 109.890109890109890109e18);
        assertEq(vault.maxRedeem(alice), 100e18);

        redeem(alice, 50e18);

        assertEq(asset.balanceOf(alice), 54.945054945054945054e18);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 0);
        assertEq(iBgtVault.balanceOf(address(manager)), 55.054945054945054946e18, "stakedAmount");

        assertEq(vault.balanceOf(alice), 100e18 - 50e18);
        assertEq(vault.totalSupply(), 50e18 + SEED_AMOUNT, "totalSupply");
        assertEq(vault.totalAssets(), 55.054945054945054946e18, "totalAssets");
        assertEq(manager.stakedAssets(), 55.054945054945054946e18);

        // Vault price is unaffected by redeem
        assertEq(vault.convertToShares(1e18), 0.91e18 - 1); // rounding
        assertEq(vault.convertToAssets(1e18), 1.098901098901098901e18);
    }
}

contract OrigamiIBGTVaultTest_Compound is OrigamiIBGTVaultTestBase {
    OrigamiSwapperWithCallback public compoundingSwapper;
    DummyDexRouter public router;

    function encode(
        uint256 sellAmount,
        uint256 requestedBuyAmount,
        uint256 buyTokenToReceiveAmount
    )
        internal
        view
        returns (bytes memory)
    {
        return abi.encode(IOrigamiSwapper.RouteDataWithCallback({
            minBuyAmount: requestedBuyAmount,
            router: address(router),
            receiver: address(manager),
            data: abi.encodeCall(DummyDexRouter.doExactSwap, (address(honeyToken), sellAmount, address(asset), buyTokenToReceiveAmount))
        }));
    }

    function setUp() public override {
        super.setUp();

        router = new DummyDexRouter();
        compoundingSwapper = new OrigamiSwapperWithCallback(origamiMultisig);

        vm.startPrank(origamiMultisig);
        manager.setSwapper(address(compoundingSwapper));
        compoundingSwapper.whitelistRouter(address(router), true);
        doMint(asset, address(router), 1_000_000e18);
    }

    function test_compoundingIncreasesSharePrice() public {
        // Initial deposit
        deposit(alice, 1000e18);

        uint256 initialSharePrice = vault.convertToAssets(1e18);
        assertEq(initialSharePrice, 1e18);

        // Skip time to accumulate rewards
        skip(1 weeks);

        // Harvest rewards which sends HONEY to the compounding swapper
        vm.startPrank(alice);
        manager.harvestRewards(alice);

        // share price has not changed until the rewards are swapped to the base asset
        uint256 newSharePrice = vault.convertToAssets(1e18);
        assertEq(newSharePrice, initialSharePrice);

        uint256 honeyRewards = 0.32958871989733209e18;

        assertEq(honeyToken.balanceOf(address(compoundingSwapper)), honeyRewards);

        // Simulate swapping HONEY rewards for 100 iBGT
        vm.startPrank(origamiMultisig);
        compoundingSwapper.execute(honeyToken, honeyRewards, asset, encode(honeyRewards, 100e18, 100e18));

        uint256 expectedPendingReserves = 100e18 - 1e18; // 2% perf fee taken off iBGT output
        uint256 expectedTotalAssets = 1000e18 + SEED_AMOUNT + expectedPendingReserves;

        {
            (uint256 vested, uint256 unvested, uint256 future) = manager.vestingStatus();
            assertEq(vested, 0);
            assertEq(unvested, expectedPendingReserves);
            assertEq(future, 0);
        }

        assertEq(iBgtVault.balanceOf(address(manager)), expectedTotalAssets); // The iBGT was staked
        assertEq(manager.stakedAssets(), expectedTotalAssets); // As above
        assertEq(manager.unallocatedAssets(), 0); // Assets immediately staked in the swap callback, nothing in the contract
        assertEq(manager.totalAssets(), 1000e18 + SEED_AMOUNT); // doesn't include the dripping in rewards yet
        assertEq(asset.balanceOf(address(manager)), 0); // No iBGT balance in the manager
        assertEq(asset.balanceOf(address(feeCollector)), 1e18); // fees are collected on the swap callback 

        assertEq(vault.convertToAssets(1e18), 1e18); // No change immediately - needs to drip in over time

        // Skip to the end of the drip duration
        skip(10 minutes);

        {
            (uint256 vested, uint256 unvested, uint256 future) = manager.vestingStatus();
            assertEq(vested, expectedPendingReserves);
            assertEq(unvested, 0);
            assertEq(future, 0);
        }

        // Verify share price increased
        newSharePrice = vault.convertToAssets(1e18);
        assertGt(newSharePrice, initialSharePrice);
        assertEq(newSharePrice, 1.098990100989901009e18);       
        assertEq(manager.totalAssets(), expectedTotalAssets); // total assets now includes the dripped in reserves

        // reinvesting rewards again causes no impact on the share price or total assets
        manager.reinvest();
        assertEq(vault.convertToAssets(1e18), newSharePrice);
    }

    function test_depositAndWithdrawDuringDrip() public {
        deposit(alice, 1000e18);
        assertEq(manager.stakedAssets(), 1000e18 + SEED_AMOUNT);
        assertEq(manager.totalAssets(), 1000e18 + SEED_AMOUNT);
        assertEq(vault.convertToAssets(1e18), 1e18);

        // Skip time to accumulate rewards
        skip(1 weeks);

        assertEq(vault.convertToAssets(1e18), 1e18);

        // Harvest rewards which sends HONEY to the compounding swapper
        // Mock that it's already received the iBGT tokens back form the swapper.
        deal(address(asset), address(manager), 100e18);
        vm.startPrank(alice);
        manager.harvestRewards(alice);

        skip(5 minutes); // Half way through the drip
        assertEq(manager.stakedAssets(), 1000e18 + SEED_AMOUNT + 99e18);
        assertEq(manager.totalAssets(), 1_049.6e18);
        assertEq(vault.convertToAssets(1e18), 1.049495050494950504e18);

        // Another deposit - gets staked and added to total assets immediately
        deposit(alice, 1000e18);
        assertEq(manager.stakedAssets(), 2000e18 + SEED_AMOUNT + 99e18);
        assertEq(manager.totalAssets(), 2_049.6e18);
        assertEq(vault.convertToAssets(1e18), 1.049495050494950504e18);

        // Alice withdraws all her shares and pockets her share of the increaseed yield.
        // She exited the period early though so effectively gave up 50% of that increase donating
        // it to remaining holders
        // exit fee is zero by default.
        vm.startPrank(alice);
        uint256 expectedAssets = 2_049.495050494950504949e18;
        assertEq(vault.redeem(vault.balanceOf(alice), alice, alice), expectedAssets);
        assertEq(manager.stakedAssets(), 2000e18 + SEED_AMOUNT + 99e18 - expectedAssets);
        assertEq(manager.totalAssets(), 2_049.6e18 - expectedAssets);
        assertEq(vault.convertToAssets(1e18), 1.049495050494950509e18); // up a little from rounding

        // past the end of the drip period
        skip(10 minutes);
        assertEq(vault.convertToAssets(1e18), 496.049495050494945559e18);
        assertEq(manager.totalAssets(), manager.stakedAssets());
        assertEq(manager.totalAssets(), 49.604949505049495051e18);

        // Origami multisig (the seedooor) pockets the yield that alice gave up by redeeming early.
        assertEq(vault.previewRedeem(vault.balanceOf(origamiMultisig)), 49.604949505049494555e18);
    }
}
