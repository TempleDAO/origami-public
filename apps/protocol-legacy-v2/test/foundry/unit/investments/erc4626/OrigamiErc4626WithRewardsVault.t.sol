pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiDelegated4626Vault } from "contracts/investments/OrigamiDelegated4626Vault.sol";
import { OrigamiErc4626WithRewardsManager } from "contracts/investments/erc4626/OrigamiErc4626WithRewardsManager.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

contract OrigamiErc4626WithRewardsVaultTestBase is OrigamiTest {
    using OrigamiMath for uint256;

    IERC20 internal constant USDS = IERC20(0xdC035D45d973E3EC169d2276DDab16f1e407384F);
    IERC4626 internal constant IMF_USDS_VAULT = IERC4626(0xdef1Fce2df6270Fdf7E1214343BeBbaB8583D43d);

    OrigamiDelegated4626Vault internal vault;
    OrigamiErc4626WithRewardsManager internal manager;

    TokenPrices internal tokenPrices;
    address internal swapper = makeAddr("swapper");

    address internal merklRewardsDistributor = makeAddr("merklDist");
    address internal morphoRewardsDistributor = makeAddr("morphoDist");

    uint16 internal constant PERF_FEE_FOR_ORIGAMI = 100; // 1%
    uint256 internal constant DEPOSIT_FEE = 0;
    uint48 internal constant VESTING_DURATION = 1 days;

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function setUp() public virtual {
        fork("mainnet", 22914300);

        tokenPrices = new TokenPrices(30);
        vault = new OrigamiDelegated4626Vault(
            origamiMultisig, 
            "Origami Morpho IMF-USDS Auto-Compounder", 
            "oAC-MOR-IMF-USDS",
            USDS,
            address(tokenPrices)
        );

        manager = new OrigamiErc4626WithRewardsManager(
            origamiMultisig,
            address(vault),
            address(IMF_USDS_VAULT),
            feeCollector,
            swapper,
            PERF_FEE_FOR_ORIGAMI,
            VESTING_DURATION,
            address(merklRewardsDistributor),
            address(morphoRewardsDistributor)
        );

        vm.startPrank(origamiMultisig);
        vault.setManager(address(manager), 0);
        vm.stopPrank();

        seedDeposit(origamiMultisig, 0.1e18, type(uint256).max);
    }

    function seedDeposit(address account, uint256 amount, uint256 maxSupply) internal {
        vm.startPrank(account);
        deal(address(USDS), account, amount, true);
        USDS.approve(address(vault), amount);
        vault.seedDeposit(amount, account, maxSupply);
        vm.stopPrank();
    }

    function deposit(address user, uint256 amount) internal {
        deal(address(USDS), user, amount);
        vm.startPrank(user);
        USDS.approve(address(vault), amount);
        uint256 expectedShares = vault.previewDeposit(amount);

        vm.expectEmit(address(vault));
        emit Deposit(user, user, amount, expectedShares);
        uint256 actualShares = vault.deposit(amount, user);
        vm.stopPrank();

        assertEq(actualShares, expectedShares);
    }

    function mint(address user, uint256 shares) internal {
        uint256 expectedAssets = vault.previewMint(shares);
        deal(address(USDS), user, expectedAssets);
        vm.startPrank(user);
        USDS.approve(address(vault), expectedAssets);

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
        deal(address(USDS), address(manager), USDS.balanceOf(address(manager)) + amount, true);
        manager.reinvest();
        skip(VESTING_DURATION);
    }
}

contract OrigamiErc4626WithRewardsVaultTestAdmin is OrigamiErc4626WithRewardsVaultTestBase {
    event TokenPricesSet(address indexed tokenPrices);
    event ManagerSet(address indexed manager);

    function test_initialization() public view {
        assertEq(vault.owner(), origamiMultisig);
        assertEq(vault.name(), "Origami Morpho IMF-USDS Auto-Compounder");
        assertEq(vault.symbol(), "oAC-MOR-IMF-USDS");
        assertEq(vault.asset(), address(USDS));
        assertEq(vault.decimals(), 18);
        assertEq(address(vault.manager()), address(manager));
        assertEq(address(vault.tokenPrices()), address(tokenPrices));
        assertEq(vault.performanceFeeBps(), 100);
        assertEq(vault.maxTotalSupply(), type(uint256).max);
        assertEq(vault.totalSupply(), 0.1e18);
        // slight rounding on underlying erc4626 deposit in seed
        assertEq(vault.totalAssets(), 0.1e18 - 1);
        assertEq(vault.convertToShares(1e18), 1e18 + 10);
        assertEq(vault.convertToAssets(1e18), 1e18 - 10);
        // underlying IMF-USDS erc4626 deposit caps
        assertEq(vault.maxDeposit(alice), 986_496_157.829767843095147185e18);
        assertEq(vault.maxMint(alice), 986_496_157.829767852960108763e18);
        assertEq(vault.maxWithdraw(alice), 0);
        assertEq(vault.maxRedeem(alice), 0);
        assertEq(vault.maxWithdraw(address(0)), 0.1e18 - 1);
        assertEq(vault.maxRedeem(address(0)), 0.1e18);
        assertEq(vault.previewDeposit(1e18), 1e18 + 10); // no fees
        assertEq(vault.previewMint(1e18), 1e18 - 9); // no fees
        assertEq(vault.previewWithdraw(1e18), 1e18 + 10); // no fees
        assertEq(vault.previewRedeem(1e18), 1e18 - 10); // no fees
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
        OrigamiErc4626WithRewardsManager newManager = new OrigamiErc4626WithRewardsManager(
            origamiMultisig,
            alice, // not vault
            address(IMF_USDS_VAULT),
            feeCollector,
            swapper,
            PERF_FEE_FOR_ORIGAMI,
            VESTING_DURATION,
            address(merklRewardsDistributor),
            address(morphoRewardsDistributor)
        );

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(newManager)));
        vault.setManager(address(newManager), 0);
    }

    function test_setManager_fail_slippage() public {
        deposit(alice, 100e18);
        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, 100e18 + 0.1e18 - 2);

        OrigamiErc4626WithRewardsManager newManager = new OrigamiErc4626WithRewardsManager(
            origamiMultisig,
            address(vault),
            address(IMF_USDS_VAULT),
            feeCollector,
            swapper,
            PERF_FEE_FOR_ORIGAMI,
            VESTING_DURATION,
            address(merklRewardsDistributor),
            address(morphoRewardsDistributor)
        );
      
        vm.startPrank(origamiMultisig);

        // loses an extra 1 wei from erc4626 rounding
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, totalAssets, totalAssets-1));
        vault.setManager(address(newManager), totalAssets);
    }

    function test_setManager_success() public {
        deposit(alice, 100e18);
        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, 100e18 + 0.1e18 - 2);
        assertEq(vault.convertToAssets(1e18), 1e18 - 11);
        assertEq(manager.unallocatedAssets(), 0);

        OrigamiErc4626WithRewardsManager newManager = new OrigamiErc4626WithRewardsManager(
            origamiMultisig,
            address(vault),
            address(IMF_USDS_VAULT),
            feeCollector,
            swapper,
            PERF_FEE_FOR_ORIGAMI,
            VESTING_DURATION,
            address(merklRewardsDistributor),
            address(morphoRewardsDistributor)
        );
       
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(vault));
        emit ManagerSet(address(newManager));

        // loses an extra 1 wei from erc4626 rounding
        vault.setManager(address(newManager), totalAssets - 1);
        assertEq(address(vault.manager()), address(newManager));

        assertEq(vault.totalAssets(), 100e18 + 0.1e18 - 3);
        assertEq(vault.convertToAssets(1e18), 1e18 - 11);
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

contract OrigamiErc4626WithRewardsVaultTestAccess is OrigamiErc4626WithRewardsVaultTestBase {
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

contract OrigamiErc4626WithRewardsVaultTestDeposit is OrigamiErc4626WithRewardsVaultTestBase {
    function test_deposit_basic() public {
        deposit(alice, 123e18);

        uint256 expectedShares = OrigamiMath.subtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_DOWN);

        assertEq(USDS.balanceOf(alice), 0);
        assertEq(USDS.balanceOf(address(vault)), 0);
        assertEq(USDS.balanceOf(address(manager)), 0);
        assertEq(IMF_USDS_VAULT.maxWithdraw(address(manager)), 123e18 + 0.1e18 - 1);
        assertEq(vault.balanceOf(alice), expectedShares + 1230);
        assertEq(vault.totalSupply(), 123e18 + 0.1e18 + 1230);
        assertEq(vault.totalAssets(), 123e18 + 0.1e18 - 1);
    }

    function test_deposit_beforeShareIncrease() public {
        deposit(alice, 123e18);

        // 1% of this donation will be fees
        addToSharePrice(100e18);

        uint256 expectedShares = OrigamiMath.subtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_DOWN);

        assertEq(USDS.balanceOf(alice), 0);
        assertEq(USDS.balanceOf(address(vault)), 0);
        assertEq(USDS.balanceOf(address(manager)), 0);
        assertEq(IMF_USDS_VAULT.maxWithdraw(address(manager)), 222.248401685165072069e18);
        assertEq(vault.balanceOf(alice), expectedShares + 1230);
        assertEq(vault.totalSupply(), 123e18 + 0.1e18 + 1230);
        assertEq(vault.totalAssets(), 222.248401685165072069e18);
        assertEq(vault.convertToShares(1e18), 0.553884748176422280e18);
        assertEq(vault.convertToAssets(1e18), 1.805429745614663443e18);
    }

    function test_deposit_afterShareIncrease() public {
        deposit(bob, 100e18);

        // 1% of this donation will be fees
        addToSharePrice(10e18); // 10% increase
        assertEq(manager.totalAssets(), 110.073499366337725645e18);
        (
            uint256 currentPeriodVested,
            uint256 currentPeriodUnvested,
            uint256 futurePeriodUnvested
        ) = manager.vestingStatus();
        assertEq(currentPeriodVested, 9.9e18);
        assertEq(currentPeriodUnvested, 0);
        assertEq(futurePeriodUnvested, 0);

        assertEq(vault.convertToShares(1e18), 0.909392365794197838e18);
        assertEq(vault.convertToAssets(1e18), 1.099635358305072173e18);

        // Limited by the underlying erc4626
        assertEq(vault.maxDeposit(alice), 986_495_251.146712522616478497e18);
        assertEq(vault.maxMint(alice), 897_111_250.285050259195689443e18);
        deposit(alice, 123e18);

        assertEq(USDS.balanceOf(alice), 0);
        assertEq(USDS.balanceOf(address(vault)), 0);
        assertEq(USDS.balanceOf(address(manager)), 0);
        assertEq(IMF_USDS_VAULT.maxWithdraw(address(manager)), 233.073499366337725644e18);
        assertEq(vault.balanceOf(alice), 111.855260992686334151e18);
        assertEq(vault.totalSupply(), 211.955260992686335151e18);
        assertEq(vault.totalAssets(), 233.073499366337725644e18);

        assertEq(vault.convertToShares(1e18), 0.909392365794197838e18);
        assertEq(vault.convertToAssets(1e18), 1.099635358305072173e18);
    }
}

contract OrigamiErc4626WithRewardsVaultTestMint is OrigamiErc4626WithRewardsVaultTestBase {
    function test_mint_basic() public {
        mint(alice, 123e18);

        uint256 expectedAssets = OrigamiMath.inverseSubtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_UP);

        assertEq(USDS.balanceOf(alice), 0);
        assertEq(USDS.balanceOf(address(vault)), 0);
        assertEq(USDS.balanceOf(address(manager)), 0);
        assertEq(IMF_USDS_VAULT.maxWithdraw(address(manager)), expectedAssets + 0.1e18 - 1230);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 123e18 + 0.1e18);
        assertEq(vault.totalAssets(), 123e18 + 0.1e18 - 1230);
    }

    function test_mint_beforeShareIncrease() public {
        mint(alice, 123e18);

        // 1% of this donation will be fees
        addToSharePrice(100e18);

        assertEq(USDS.balanceOf(alice), 0);
        assertEq(USDS.balanceOf(address(vault)), 0);
        assertEq(USDS.balanceOf(address(manager)), 0);
        assertEq(IMF_USDS_VAULT.maxWithdraw(address(manager)), 222.248401685165070839e18);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 123e18 + 0.1e18);
        assertEq(vault.totalAssets(), 222.248401685165070839e18);
        assertEq(vault.convertToShares(1e18), 0.553884748176422278e18);
        assertEq(vault.convertToAssets(1e18), 1.805429745614663451e18);
    }

    function test_mint_afterShareIncrease() public {
        mint(bob, 100e18);

        addToSharePrice(10e18); // 10% increase
        assertEq(vault.convertToShares(1e18), 0.909392365794197837e18);
        assertEq(vault.convertToAssets(1e18), 1.099635358305072174e18);

        // Limited by the underlying erc4626
        assertEq(vault.maxDeposit(alice), 986_495_251.146712522616479496e18);
        assertEq(vault.maxMint(alice), 897_111_250.285050258383651111e18);
        mint(alice, 123e18);

        assertEq(USDS.balanceOf(alice), 0);
        assertEq(USDS.balanceOf(address(vault)), 0);
        assertEq(USDS.balanceOf(address(manager)), 0);
        assertEq(IMF_USDS_VAULT.maxWithdraw(address(manager)), 245.328648437861602081e18);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 223e18 + 0.1e18);

        // Share price remains the same
        assertEq(vault.convertToShares(1e18), 0.909392365794197837e18);
        assertEq(vault.convertToAssets(1e18), 1.099635358305072174e18);
    }
}

contract OrigamiErc4626WithRewardsVaultTestWithdraw is OrigamiErc4626WithRewardsVaultTestBase {
    function test_withdraw_basic() public {
        deposit(alice, 123e18);

        withdraw(alice, 50e18);

        uint256 expectedShares = 73e18;

        assertEq(USDS.balanceOf(alice), 50e18);
        assertEq(USDS.balanceOf(address(vault)), 0);
        assertEq(USDS.balanceOf(address(manager)), 0);
        assertEq(IMF_USDS_VAULT.maxWithdraw(address(manager)), 73e18 + 0.1e18 - 1);
        assertEq(vault.balanceOf(alice), expectedShares + 730);
        assertEq(vault.totalSupply(), expectedShares + 0.1e18 + 730);
        assertEq(vault.totalAssets(), 73e18 + 0.1e18 - 1);
    }

    function test_withdraw_beforeShareIncrease() public {
        deposit(alice, 123e18);

        withdraw(alice, 50e18);
        addToSharePrice(100e18);

        uint256 expectedShares = 73e18;

        assertEq(USDS.balanceOf(alice), 50e18);
        assertEq(USDS.balanceOf(address(vault)), 0);
        assertEq(USDS.balanceOf(address(manager)), 0);
        assertEq(IMF_USDS_VAULT.maxWithdraw(address(manager)), 172.214993006267315746e18);
        assertEq(vault.balanceOf(alice), expectedShares + 730);
        assertEq(vault.totalSupply(), expectedShares + 0.1e18 + 730);
        assertEq(vault.totalAssets(), 172.214993006267315746e18);
        assertEq(vault.convertToShares(1e18), 0.424469430471362715e18);
        assertEq(vault.convertToAssets(1e18), 2.355882257267678714e18);
    }

    function test_withdraw_afterShareIncrease() public {
        deposit(alice, 100e18);

        addToSharePrice(10e18); // 10% increase
        assertEq(vault.convertToShares(1e18), 0.909392365794197838e18);
        assertEq(vault.convertToAssets(1e18), 1.099635358305072173e18);

        assertEq(vault.maxWithdraw(alice), 109.963535830507218427e18);
        assertEq(vault.maxRedeem(alice), 100.000000000000001000e18);
        withdraw(alice, 50e18);

        assertEq(USDS.balanceOf(alice), 50e18);
        assertEq(USDS.balanceOf(address(vault)), 0);
        assertEq(USDS.balanceOf(address(manager)), 0);
        assertEq(IMF_USDS_VAULT.maxWithdraw(address(manager)), 60.073499366337725644e18);
        assertEq(vault.balanceOf(alice), 54.530381710290109068e18);
        assertEq(vault.totalSupply(), 54.630381710290109068e18);
        assertEq(vault.totalAssets(), 60.073499366337725644e18);

        // Share price remains the same
        assertEq(vault.convertToShares(1e18), 0.909392365794197838e18);
        assertEq(vault.convertToAssets(1e18), 1.099635358305072173e18);
    }
}

contract OrigamiErc4626WithRewardsVaultTestRedeem is OrigamiErc4626WithRewardsVaultTestBase {
    function test_redeem_basic() public {
        deposit(alice, 123e18);

        redeem(alice, 50e18);

        uint256 expectedShares = OrigamiMath.subtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_DOWN) - 50e18;
        uint256 expectedAssets = 123e18 - 50e18;

        assertEq(USDS.balanceOf(alice), 50e18 - 500);
        assertEq(USDS.balanceOf(address(vault)), 0);
        assertEq(USDS.balanceOf(address(manager)), 0);
        assertEq(IMF_USDS_VAULT.maxWithdraw(address(manager)), expectedAssets + 0.1e18 + 499);
        assertEq(vault.balanceOf(alice), expectedShares + 1230);
        assertEq(vault.totalSupply(), expectedShares + 0.1e18 + 1230);
        assertEq(vault.totalAssets(), expectedAssets + 0.1e18 + 499);
    }

    function test_redeem_beforeShareIncrease() public {
        deposit(alice, 123e18);

        redeem(alice, 50e18);
        addToSharePrice(100e18);

        uint256 expectedShares = OrigamiMath.subtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_DOWN) - 50e18;

        assertEq(USDS.balanceOf(alice), 50e18 - 500);
        assertEq(USDS.balanceOf(address(vault)), 0);
        assertEq(USDS.balanceOf(address(manager)), 0);
        assertEq(IMF_USDS_VAULT.maxWithdraw(address(manager)), 172.214993006267316246e18);
        assertEq(vault.balanceOf(alice), expectedShares + 1230);
        assertEq(vault.totalSupply(), expectedShares + 0.1e18 + 1230);
        assertEq(vault.totalAssets(), 172.214993006267316246e18);
        assertEq(vault.convertToShares(1e18), 0.424469430471362717e18);
        assertEq(vault.convertToAssets(1e18), 2.355882257267678705e18);
    }

    function test_redeem_afterShareIncrease() public {
        deposit(alice, 100e18);

        addToSharePrice(10e18); // 10% increase
        assertEq(vault.convertToShares(1e18), 0.909392365794197838e18);
        assertEq(vault.convertToAssets(1e18), 1.099635358305072173e18);

        assertEq(vault.maxWithdraw(alice), 109.963535830507218427e18);
        assertEq(vault.maxRedeem(alice), 100.000000000000001000e18);
        redeem(alice, 50e18);

        uint256 expectedShares = OrigamiMath.subtractBps(100e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_DOWN) - 50e18;

        assertEq(USDS.balanceOf(alice), 54.981767915253608663e18);
        assertEq(USDS.balanceOf(address(vault)), 0);
        assertEq(USDS.balanceOf(address(manager)), 0);
        assertEq(IMF_USDS_VAULT.maxWithdraw(address(manager)), 55.091731451084116982e18);
        assertEq(vault.balanceOf(alice), expectedShares + 1000);
        assertEq(vault.totalSupply(), expectedShares + 0.1e18 + 1000);
        assertEq(vault.totalAssets(), 55.091731451084116982e18);

        // Withdrawal fees continue to help the share price
        assertEq(vault.convertToShares(1e18), 0.909392365794197838e18);
        assertEq(vault.convertToAssets(1e18), 1.099635358305072173e18);
    }
}

contract OrigamiErc4626WithRewardsVaultTestDonations is OrigamiErc4626WithRewardsVaultTestBase {
    function test_sharePriceDropOnDeposit_ifAssetsInBalance() public {
        // normal deposit by a normal user
        deposit(alice, 100e18);

        // price pre-donation is 999999999999999989
        {
            assertEq(vault.convertToAssets(1e18), 0.999999999999999989e18);
            assertEq(manager.unallocatedAssets(), 0);
            assertEq(manager.depositedAssets(), 100.099999999999999998e18);
            (
                uint256 currentPeriodVested,
                uint256 currentPeriodUnvested,
                uint256 futurePeriodUnvested
            ) = manager.vestingStatus();
            assertEq(currentPeriodVested, 0);
            assertEq(currentPeriodUnvested, 0);
            assertEq(futurePeriodUnvested, 0);
            assertEq(manager.totalAssets(), 100.099999999999999998e18);
        }

        // Upon donation, the share price remains the same
        uint256 donatedAmount = 10e18;
        deal(address(USDS), address(manager), donatedAmount, true);

        {
            assertEq(vault.convertToAssets(1e18), 0.999999999999999989e18);
            assertEq(manager.unallocatedAssets(), 9.900000000000000000e18); // donated amount minus fees
            assertEq(manager.depositedAssets(), 100.099999999999999998e18);
            (
                uint256 currentPeriodVested,
                uint256 currentPeriodUnvested,
                uint256 futurePeriodUnvested
            ) = manager.vestingStatus();
            assertEq(currentPeriodVested, 0);
            assertEq(currentPeriodUnvested, 0);
            assertEq(futurePeriodUnvested, 0);
            assertEq(manager.totalAssets(), 100.099999999999999998e18);
        }

        // On reinvest the donation will start vesting. 0 added to totalAssets to start
        manager.reinvest();
        {
            assertEq(vault.convertToAssets(1e18), 0.999999999999999989e18);
            assertEq(manager.unallocatedAssets(), 0);
            assertEq(manager.depositedAssets(), 109.999999999999999998e18);
            (
                uint256 currentPeriodVested,
                uint256 currentPeriodUnvested,
                uint256 futurePeriodUnvested
            ) = manager.vestingStatus();
            assertEq(currentPeriodVested, 0);
            assertEq(currentPeriodUnvested, 9.900000000000000000e18);
            assertEq(futurePeriodUnvested, 0);
            assertEq(manager.totalAssets(), 100.099999999999999998e18);
        }
        
        // After 100% vested, the share price increases
        skip(VESTING_DURATION);

        {
            assertEq(vault.convertToAssets(1e18), 1.099635358305072173e18);
            assertEq(manager.unallocatedAssets(), 0);
            assertEq(manager.depositedAssets(), 110.073499366337725645e18);
            (
                uint256 currentPeriodVested,
                uint256 currentPeriodUnvested,
                uint256 futurePeriodUnvested
            ) = manager.vestingStatus();
            assertEq(currentPeriodVested, 9.900000000000000000e18);
            assertEq(currentPeriodUnvested, 0);
            assertEq(futurePeriodUnvested, 0);
            assertEq(manager.totalAssets(), 110.073499366337725645e18);
        }
    }
}
