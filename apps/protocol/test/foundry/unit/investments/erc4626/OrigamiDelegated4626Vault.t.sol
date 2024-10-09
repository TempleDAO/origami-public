pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { DummyDelegated4626Vault } from "contracts/test/investments/erc4626/DummyDelegated4626Vault.sol";
import { DummyDelegated4626VaultManager } from "contracts/test/investments/erc4626/DummyDelegated4626VaultManager.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { IOrigamiErc4626 } from "contracts/interfaces/common/IOrigamiErc4626.sol";

contract OrigamiDelegated4626VaultTestBase is OrigamiTest {
    using OrigamiMath for uint256;

    DummyMintableToken public asset;
    DummyDelegated4626Vault public vault;
    DummyDelegated4626VaultManager public manager;
    TokenPrices public tokenPrices;

    uint48 public constant PERFORMANCE_FEE_BPS = 10; // 0.1%
    uint224 public constant MAX_TOTAL_SUPPLY = 100_000_000e18;
    uint16 public constant DEPOSIT_FEE = 50;
    uint16 public constant WITHDRAWAL_FEE = 200;

    event InKindFees(IOrigamiErc4626.FeeType feeType, uint256 feeBps, uint256 feeAmount);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function setUp() public {
        asset = new DummyMintableToken(origamiMultisig, "USDS", "USDS", 18);
        tokenPrices = new TokenPrices(30);
        vault = new DummyDelegated4626Vault(
            origamiMultisig, 
            "Origami sUSDS++", 
            "sUSDS++",
            asset,
            address(tokenPrices),
            MAX_TOTAL_SUPPLY
        );

        manager = new DummyDelegated4626VaultManager(
            origamiMultisig, 
            address(vault),
            PERFORMANCE_FEE_BPS,
            origamiMultisig
        );

        vm.startPrank(origamiMultisig);
        vault.setManager(address(manager));
        vault.setFeesBps(DEPOSIT_FEE, WITHDRAWAL_FEE);
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
        deal(address(asset), address(manager), asset.balanceOf(address(manager)) + amount);
    }
}

contract OrigamiDelegated4626VaultTestAdmin is OrigamiDelegated4626VaultTestBase {
    event TokenPricesSet(address indexed _tokenPrices);
    event PerformanceFeeSet(uint256 fee);
    event FeeCollectorSet(address indexed feeCollector);
    event MaxTotalSupplySet(uint256 maxTotalSupply);
    event ManagerSet(address indexed manager);

    function test_initialization() public {
        assertEq(vault.owner(), origamiMultisig);
        assertEq(vault.name(), "Origami sUSDS++");
        assertEq(vault.symbol(), "sUSDS++");
        assertEq(vault.asset(), address(asset));
        assertEq(vault.decimals(), 18);
        assertEq(address(vault.manager()), address(manager));
        assertEq(address(vault.tokenPrices()), address(tokenPrices));
        assertEq(vault.performanceFeeBps(), 10);
        assertEq(vault.maxTotalSupply(), MAX_TOTAL_SUPPLY);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.convertToShares(1e18), 1e18);
        assertEq(vault.convertToAssets(1e18), 1e18);
        // How many assets can be deposited to hit the total supply
        // so takes fees into consideration.
        assertEq(vault.maxDeposit(alice), 100_502_512.562814070351758794e18);
        assertEq(vault.maxMint(alice), MAX_TOTAL_SUPPLY);
        assertEq(vault.maxWithdraw(alice), 0);
        assertEq(vault.maxRedeem(alice), 0);
        assertEq(vault.previewDeposit(1e18), 0.995e18); // 50bps fee
        // 50 bps fee -- need to deposit more assets in order to get 1e18 shares
        assertEq(vault.previewMint(1e18), 1.005025125628140704e18);
        // 200 bps fee -- need to redeem more shares in order to get 1e18 assets
        assertEq(vault.previewWithdraw(1e18), 1.020408163265306123e18);
        assertEq(vault.previewRedeem(1e18), 0.98e18); // 200bps fee
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

    // function test_setPerformanceFee_fail() public {
    //     vm.startPrank(origamiMultisig);
    //     vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
    //     vault.setPerformanceFee(10_001);
    // }

    // function test_setPerformanceFee_success() public {
    //     vm.startPrank(origamiMultisig);
    //     vm.expectEmit(address(vault));
    //     emit PerformanceFeeSet(123);
    //     vault.setPerformanceFee(123);
    //     assertEq(vault.performanceFeeBps(), 123);
    // }

    function test_setMaxTotalSupply_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(vault));
        emit MaxTotalSupplySet(123e18);
        vault.setMaxTotalSupply(123e18);
        assertEq(vault.maxTotalSupply(), 123e18);
    }

    // function test_setFeeCollector_fail() public {
    //     vm.startPrank(origamiMultisig);
    //     vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
    //     vault.setFeeCollector(address(0));
    // }

    // function test_setFeeCollector_success() public {
    //     vm.startPrank(origamiMultisig);
    //     vm.expectEmit(address(vault));
    //     emit FeeCollectorSet(alice);
    //     vault.setFeeCollector(alice);
    //     assertEq(address(vault.feeCollector()), alice);
    // }

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

contract OrigamiDelegated4626VaultTestAccess is OrigamiDelegated4626VaultTestBase {
    function test_setManager_access() public {
        expectElevatedAccess();
        vault.setManager(alice);
    }

    // function test_setPerformanceFee_access() public {
    //     expectElevatedAccess();
    //     vault.setPerformanceFee(100);
    // }

    function test_setMaxTotalSupply_access() public {
        expectElevatedAccess();
        vault.setMaxTotalSupply(100);
    }

    // function test_setFeeCollector_access() public {
    //     expectElevatedAccess();
    //     vault.setFeeCollector(alice);
    // }

    function test_setTokenPrices_access() public {
        expectElevatedAccess();
        vault.setTokenPrices(alice);
    }
}

contract OrigamiDelegated4626VaultTestDeposit is OrigamiDelegated4626VaultTestBase {
    function test_deposit_basic() public {
        deposit(alice, 123e18);

        uint256 expectedShares = OrigamiMath.subtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_DOWN);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 123e18);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares);
        assertEq(vault.totalAssets(), 123e18);
    }

    function test_deposit_beforeShareIncrease() public {
        deposit(alice, 123e18);

        addToSharePrice(100e18);

        uint256 expectedShares = OrigamiMath.subtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_DOWN);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 223e18);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares);
        assertEq(vault.totalAssets(), 223e18);
        assertEq(vault.convertToShares(1e18), uint256(1e18)*expectedShares/223e18);
        assertEq(vault.convertToAssets(1e18), uint256(1e18)*223e18/expectedShares);
    }

    function test_deposit_afterShareIncrease() public {
        deposit(bob, 100e18);

        addToSharePrice(10e18); // 10% increase
        assertEq(vault.convertToShares(1e18), 0.904545454545454545e18);
        assertEq(vault.convertToAssets(1e18), 1.105527638190954773e18);

        assertEq(vault.maxDeposit(alice), 111_108_194.793060781293295092e18);
        assertEq(vault.maxMint(alice), 99_999_900.5e18);
        deposit(alice, 123e18);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 233e18);
        assertEq(vault.balanceOf(alice), 110.702795454545454545e18);
        assertEq(vault.totalSupply(), 210.202795454545454545e18);
        assertEq(vault.totalAssets(), 233e18);

        // Deposit fees continue to help the share price
        assertEq(vault.convertToShares(1e18), 0.902157920405774483e18);
        assertEq(vault.convertToAssets(1e18), 1.108453384248090291e18);
    }
}

contract OrigamiDelegated4626VaultTestMint is OrigamiDelegated4626VaultTestBase {
    function test_mint_basic() public {
        mint(alice, 123e18);

        uint256 expectedAssets = OrigamiMath.inverseSubtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_UP);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), expectedAssets);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 123e18);
        assertEq(vault.totalAssets(), expectedAssets);
    }

    function test_mint_beforeShareIncrease() public {
        mint(alice, 123e18);

        addToSharePrice(100e18);

        uint256 expectedAssets = 100e18 + OrigamiMath.inverseSubtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_UP);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), expectedAssets);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 123e18);
        assertEq(vault.totalAssets(), expectedAssets);
        assertEq(vault.convertToShares(1e18), uint256(1e18)*123e18/expectedAssets);
        assertEq(vault.convertToAssets(1e18), uint256(1e18)*expectedAssets/123e18);
    }

    function test_mint_afterShareIncrease() public {
        mint(bob, 100e18);

        addToSharePrice(10e18); // 10% increase
        assertEq(vault.convertToShares(1e18), 0.904956798544793087e18);
        assertEq(vault.convertToAssets(1e18), 1.105025125628140703e18);

        assertEq(vault.maxDeposit(alice), 111_057_690.512865836721431783e18);
        assertEq(vault.maxMint(alice), 99_999_900e18);
        mint(alice, 123e18);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 247.103608494734981441e18);
        assertEq(vault.balanceOf(alice), 123e18);
        assertEq(vault.totalSupply(), 223e18);

        // Deposit fees continue to help the share price
        assertEq(vault.convertToShares(1e18), 0.902455457281399614e18);
        assertEq(vault.convertToAssets(1e18), 1.108087930469663593e18);
    }
}

contract OrigamiDelegated4626VaultTestWithdraw is OrigamiDelegated4626VaultTestBase {
    function test_withdraw_basic() public {
        deposit(alice, 123e18);

        withdraw(alice, 50e18);

        uint256 expectedShares = 71.619693877551020407e18;

        assertEq(asset.balanceOf(alice), 50e18);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 73e18);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares);
        assertEq(vault.totalAssets(), 73e18);
    }

    function test_withdraw_beforeShareIncrease() public {
        deposit(alice, 123e18);

        withdraw(alice, 50e18);
        addToSharePrice(100e18);

        uint256 expectedShares = 71.619693877551020407e18;

        assertEq(asset.balanceOf(alice), 50e18);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 173e18);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares);
        assertEq(vault.totalAssets(), 173e18);
        assertEq(vault.convertToShares(1e18), 0.413986669812433643e18);
        assertEq(vault.convertToAssets(1e18), 2.415536713906931880e18);
    }

    function test_withdraw_afterShareIncrease() public {
        deposit(alice, 100e18);

        addToSharePrice(10e18); // 10% increase
        assertEq(vault.convertToShares(1e18), 0.904545454545454545e18);
        assertEq(vault.convertToAssets(1e18), 1.105527638190954773e18);

        assertEq(vault.maxWithdraw(alice), 107.799999999999999999e18);
        assertEq(vault.maxRedeem(alice), 99.5e18);
        withdraw(alice, 50e18);

        assertEq(asset.balanceOf(alice), 50e18);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), 60e18);
        assertEq(vault.balanceOf(alice), 53.349721706864564007e18);
        assertEq(vault.totalSupply(), 53.349721706864564007e18);
        assertEq(vault.totalAssets(), 60e18);

        // Withdrawal fees continue to help the share price
        assertEq(vault.convertToShares(1e18), 0.889162028447742733e18);
        assertEq(vault.convertToAssets(1e18), 1.124654413938203126e18);
    }
}

contract OrigamiDelegated4626VaultTestRedeem is OrigamiDelegated4626VaultTestBase {
    function test_redeem_basic() public {
        deposit(alice, 123e18);

        redeem(alice, 50e18);

        uint256 expectedShares = OrigamiMath.subtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_DOWN) - 50e18;
        uint256 expectedAssets = 123e18 - 49.246231155778894472e18;

        assertEq(asset.balanceOf(alice), 49.246231155778894472e18);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), expectedAssets);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares);
        assertEq(vault.totalAssets(), expectedAssets);
    }

    function test_redeem_beforeShareIncrease() public {
        deposit(alice, 123e18);

        redeem(alice, 50e18);
        addToSharePrice(100e18);

        uint256 expectedShares = OrigamiMath.subtractBps(123e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_DOWN) - 50e18;
        uint256 expectedAssets = 100e18 + 123e18 - 49.246231155778894472e18;

        assertEq(asset.balanceOf(alice), 49.246231155778894472e18);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), expectedAssets);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares);
        assertEq(vault.totalAssets(), expectedAssets);
        assertEq(vault.convertToShares(1e18), 0.416595280099488099e18);
        assertEq(vault.convertToAssets(1e18), 2.400411257086704504e18);
    }

    function test_redeem_afterShareIncrease() public {
        deposit(alice, 100e18);

        addToSharePrice(10e18); // 10% increase
        assertEq(vault.convertToShares(1e18), 0.904545454545454545e18);
        assertEq(vault.convertToAssets(1e18), 1.105527638190954773e18);

        assertEq(vault.maxWithdraw(alice), 107.799999999999999999e18);
        assertEq(vault.maxRedeem(alice), 99.5e18);
        redeem(alice, 50e18);

        uint256 expectedShares = OrigamiMath.subtractBps(100e18, DEPOSIT_FEE, OrigamiMath.Rounding.ROUND_DOWN) - 50e18;
        uint256 expectedAssets = 10e18 + 100e18 - 54.170854271356783919e18;

        assertEq(asset.balanceOf(alice), 54.170854271356783919e18);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(address(manager)), expectedAssets);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), expectedShares);
        assertEq(vault.totalAssets(), expectedAssets);

        // Withdrawal fees continue to help the share price
        assertEq(vault.convertToShares(1e18), 0.886633663366336633e18);
        assertEq(vault.convertToAssets(1e18), 1.127861529871580122e18);
    }
}