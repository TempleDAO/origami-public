pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiDelegated4626Vault } from "contracts/investments/OrigamiDelegated4626Vault.sol";
import { OrigamiErc4626WithRewardsManager } from "contracts/investments/erc4626/OrigamiErc4626WithRewardsManager.sol";
import { IOrigamiErc4626WithRewardsManager } from "contracts/interfaces/investments/erc4626/IOrigamiErc4626WithRewardsManager.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { IOrigamiManagerPausable } from "contracts/interfaces/investments/util/IOrigamiManagerPausable.sol";
import { stdError } from "forge-std/StdError.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IMerklDistributor } from "contracts/interfaces/external/merkl/IMerklDistributor.sol";
import { IMorphoUniversalRewardsDistributor } from "contracts/interfaces/external/morpho/IMorphoUniversalRewardsDistributor.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { IOrigamiDelegated4626VaultManager } from "contracts/interfaces/investments/erc4626/IOrigamiDelegated4626VaultManager.sol";
import { IOrigamiCompoundingVaultManager } from "contracts/interfaces/investments/IOrigamiCompoundingVaultManager.sol";

contract MockMerklDistributor is IMerklDistributor {
    using SafeERC20 for IERC20;

    event OperatorToggled(address indexed user, address indexed operator, bool isWhitelisted);
    event Claimed(address indexed user, address indexed token, uint256 amount);

    /// @notice User -> Operator -> authorisation to claim on behalf of the user
    mapping(address => mapping(address => uint256)) public operators;

    /// @notice Toggles whitelisting for a given user and a given operator
    /// @dev When an operator is whitelisted for a user, the operator can claim rewards on behalf of the user
    function toggleOperator(address user, address operator) external override {
        uint256 oldValue = operators[user][operator];
        operators[user][operator] = 1 - oldValue;
        emit OperatorToggled(user, operator, oldValue == 0);
    }

    function setClaimRecipient(address /*recipient*/, address /*token*/) external pure override {
        revert("UNIMPLEMENTED");
    }

    // Just assumes is asked for is given
    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata /*proofs*/
    ) external override {
        address user;
        address token;
        uint256 amount;
        for (uint256 i; i < users.length; ++i) {
            user = users[i];
            token = tokens[i];
            amount = amounts[i];
            IERC20(token).safeTransfer(user, amount);
            emit Claimed(user, token, amount);
        }
    }

    function claimWithRecipient(
        address[] calldata /*users*/,
        address[] calldata /*tokens*/,
        uint256[] calldata /*amounts*/,
        bytes32[][] calldata /*proofs*/,
        address[] calldata /*recipients*/,
        bytes[] memory /*datas*/
    ) external pure override {
        revert("UNIMPLEMENTED");
    }
}

contract MockMorphoDistributor is IMorphoUniversalRewardsDistributor {
    using SafeERC20 for IERC20;

    // Just assumes is asked for is given
    function claim(
        address account,
        address token,
        uint256 claimable,
        bytes32[] calldata /*proof*/
    ) external returns (uint256 amount) {
        IERC20(token).safeTransfer(account, claimable);
        return claimable;
    }
}

contract OrigamiErc4626WithRewardsManagerTestBase is OrigamiTest {
    using OrigamiMath for uint256;

    IERC20 internal constant USDS = IERC20(0xdC035D45d973E3EC169d2276DDab16f1e407384F);
    IERC4626 internal constant IMF_USDS_VAULT = IERC4626(0xdef1Fce2df6270Fdf7E1214343BeBbaB8583D43d);
    IERC20 internal constant IMF = IERC20(0x05BE1d4c307C19450A6Fd7cE7307cE72a3829A60);

    OrigamiDelegated4626Vault internal vault;
    OrigamiErc4626WithRewardsManager internal manager;

    TokenPrices internal tokenPrices;
    address internal swapper = makeAddr("swapper");

    MockMerklDistributor internal merklRewardsDistributor;
    MockMorphoDistributor internal morphoRewardsDistributor;

    uint16 internal constant PERF_FEE_FOR_ORIGAMI = 100; // 1%
    uint256 internal constant DEPOSIT_FEE = 0;

    uint48 internal constant VESTING_DURATION = 1 days;

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function setUp() public {
        fork("mainnet", 22914300);

        tokenPrices = new TokenPrices(30);
        vault = new OrigamiDelegated4626Vault(
            origamiMultisig, 
            "Origami Morpho IMF-USDS Auto-Compounder", 
            "oAC-MOR-IMF-USDS",
            USDS,
            address(tokenPrices)
        );

        merklRewardsDistributor = new MockMerklDistributor();
        deal(address(IMF), address(merklRewardsDistributor), 1_000_000e18);
        morphoRewardsDistributor = new MockMorphoDistributor();
        deal(address(IMF), address(morphoRewardsDistributor), 1_000_000e18);

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

        address[] memory newRewardTokens = new address[](1);
        newRewardTokens[0] = address(IMF);
        manager.setRewardTokens(newRewardTokens);

        vm.stopPrank();
    }

    function deposit(uint256 amount) internal returns (uint256 amountOut) {
        deal(address(USDS), address(manager), amount);
        vm.startPrank(address(vault));
        amountOut = manager.deposit(amount);
        vm.stopPrank();
    }

}

contract OrigamiErc4626WithRewardsManagerTestAdmin is OrigamiErc4626WithRewardsManagerTestBase {
    event RewardTokensSet();
    event MerklRewardsDistributorSet(address indexed distributor);
    event MorphoRewardsDistributorSet(address indexed distributor);
    event FeeCollectorSet(address indexed feeCollector);
    event SwapperSet(address indexed newSwapper);
    event FeeBpsSet(uint16 depositFeeBps, uint16 withdrawalFeeBps);
    event ReservesVestingDurationSet(uint48 durationInSeconds);
    event OperatorToggled(address indexed user, address indexed operator, bool isWhitelisted);
    event PerformanceFeeSet(uint256 fee);
    event ClaimedReward(
        address indexed rewardToken, 
        uint256 amountForCaller,
        uint256 amountForOrigami,
        uint256 amountForVault
    );

    function test_bad_constructor() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        new OrigamiErc4626WithRewardsManager(
            origamiMultisig,
            address(vault),
            address(IMF_USDS_VAULT),
            feeCollector,
            swapper,
            10_001,
            7 days,
            address(merklRewardsDistributor),
            address(morphoRewardsDistributor)
        );
        
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        new OrigamiErc4626WithRewardsManager(
            origamiMultisig,
            address(vault),
            address(IMF_USDS_VAULT),
            feeCollector,
            swapper,
            10_000,
            7 days + 1,
            address(merklRewardsDistributor),
            address(morphoRewardsDistributor)
        );
    }

    function test_initialization() public view {
        assertEq(manager.owner(), origamiMultisig);
        assertEq(address(manager.vault()), address(vault));
        assertEq(manager.asset(), address(USDS));
        assertEq(address(manager.underlyingVault()), address(IMF_USDS_VAULT));
        assertEq(manager.depositFeeBps(), 0);
        assertEq(manager.withdrawalFeeBps(), 0);
        assertEq(manager.MAX_WITHDRAWAL_FEE_BPS(), 330);
        assertEq(manager.swapper(), swapper);
        assertEq(manager.feeCollector(), feeCollector);
        assertEq(address(manager.merklRewardsDistributor()), address(merklRewardsDistributor));
        assertEq(address(manager.morphoRewardsDistributor()), address(morphoRewardsDistributor));

        address[] memory rewardTokens = manager.getAllRewardTokens();
        assertEq(rewardTokens.length, 1);
        assertEq(rewardTokens[0], address(IMF));

        assertEq(manager.reservesVestingDuration(), 1 days);
        assertEq(manager.lastVestingCheckpoint(), 0);
        assertEq(manager.vestingReserves(), 0);
        assertEq(manager.futureVestingReserves(), 0);
        (
            uint256 currentPeriodVested,
            uint256 currentPeriodUnvested,
            uint256 futurePeriodUnvested
        ) = manager.vestingStatus();
        assertEq(currentPeriodVested, 0);
        assertEq(currentPeriodUnvested, 0);
        assertEq(futurePeriodUnvested, 0);

        assertEq(manager.totalAssets(), 0);
        assertEq(manager.unallocatedAssets(), 0);
        (uint16 forCaller, uint16 forOrigami) = manager.performanceFeeBps();
        assertEq(forCaller, 0);
        assertEq(forOrigami, 100);

        // Max approval set for USDS => underlying vault
        assertEq(USDS.allowance(address(manager), address(IMF_USDS_VAULT)), type(uint256).max);
    }

    function test_setReservesVestingDuration_failRange() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));        
        manager.setReservesVestingDuration(0);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));        
        manager.setReservesVestingDuration(7 days + 1);
    }

    function test_setReservesVestingDuration_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit ReservesVestingDurationSet(7 days);
        manager.setReservesVestingDuration(7 days);
        assertEq(manager.reservesVestingDuration(), 7 days);
    }

    function test_setRewardTokens() public {
        vm.startPrank(origamiMultisig);

        address[] memory newRewardTokens = new address[](2);
        newRewardTokens[0] = address(USDS);
        newRewardTokens[1] = address(IMF);

        vm.expectEmit(address(manager));
        emit RewardTokensSet();
        manager.setRewardTokens(newRewardTokens);
        address[] memory actualRewardTokens = manager.getAllRewardTokens();
        assertEq(actualRewardTokens.length, 2);
        assertEq(actualRewardTokens[0], address(USDS));
        assertEq(actualRewardTokens[1], address(IMF));

        newRewardTokens = new address[](0);
        vm.expectEmit(address(manager));
        emit RewardTokensSet();
        manager.setRewardTokens(newRewardTokens);
        actualRewardTokens = manager.getAllRewardTokens();
        assertEq(actualRewardTokens.length, 0);
    }

    function test_setMerklRewardsDistributor() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit MerklRewardsDistributorSet(alice);
        manager.setMerklRewardsDistributor(alice);
        assertEq(address(manager.merklRewardsDistributor()), alice);
        
        vm.expectEmit(address(manager));
        emit MerklRewardsDistributorSet(address(0));
        manager.setMerklRewardsDistributor(address(0));
        assertEq(address(manager.merklRewardsDistributor()), address(0));
    }

    function test_setMorphoRewardsDistributor() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit MorphoRewardsDistributorSet(alice);
        manager.setMorphoRewardsDistributor(alice);
        assertEq(address(manager.morphoRewardsDistributor()), alice);
        
        vm.expectEmit(address(manager));
        emit MorphoRewardsDistributorSet(address(0));
        manager.setMorphoRewardsDistributor(address(0));
        assertEq(address(manager.morphoRewardsDistributor()), address(0));
    }

    function test_merklToggleOperator() public {
        vm.startPrank(origamiMultisig);

        assertEq(merklRewardsDistributor.operators(address(manager), alice), 0);

        vm.expectEmit(address(merklRewardsDistributor));
        emit OperatorToggled(address(manager), alice, true);
        manager.merklToggleOperator(alice);
        assertEq(merklRewardsDistributor.operators(address(manager), alice), 1);

        vm.expectEmit(address(merklRewardsDistributor));
        emit OperatorToggled(address(manager), alice, false);
        manager.merklToggleOperator(alice);
        assertEq(merklRewardsDistributor.operators(address(manager), alice), 0);
    }

    function test_setFeeCollector_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        manager.setFeeCollector(address(0));
    }

    function test_setFeeCollector_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit FeeCollectorSet(alice);
        manager.setFeeCollector(alice);
        assertEq(address(manager.feeCollector()), alice);
    }

    function test_setSwapper_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        manager.setSwapper(address(0));
    }

    function test_setSwapper_success() public {
        vm.startPrank(origamiMultisig);

        vm.expectEmit(address(manager));
        emit SwapperSet(alice);
        manager.setSwapper(alice);
        assertEq(address(manager.swapper()), alice);
    }

    function test_setWithdrawalFee_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        manager.setWithdrawalFee(uint16(331));

        assertEq(manager.withdrawalFeeBps(), 0);
    }

    function test_setWithdrawalFee_success() public {
        vm.startPrank(origamiMultisig);

        vm.expectEmit(address(manager));
        emit FeeBpsSet(0, 330);
        manager.setWithdrawalFee(uint16(330));

        assertEq(manager.withdrawalFeeBps(), 330);
    }

    function test_setPerformanceFees_tooHigh() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        manager.setPerformanceFees(1_001);
    }

    function test_setPerformanceFees_success() public {
        vm.startPrank(origamiMultisig);

        // It's emitted from the vault
        vm.expectEmit(address(vault));
        emit PerformanceFeeSet(1_000);
        manager.setPerformanceFees(1_000);
        (uint16 forCaller, uint16 forOrigami) = manager.performanceFeeBps();
        assertEq(forCaller, 0);
        assertEq(forOrigami, 1_000);
    }

    function test_setPerformanceFees_withHarvest() public {
        assertEq(deposit(100e18), 100e18);
        assertEq(manager.totalAssets(), 100e18 - 1);

        // Will get sent to the swapper
        deal(address(IMF), address(manager), 100e18);
        // Will get reinvested (minus fees)
        deal(address(USDS), address(manager), 100e18);

        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit ClaimedReward(address(vault), 0, 1e18, 99e18);
        vm.expectEmit(address(vault));
        emit PerformanceFeeSet(50);
        manager.setPerformanceFees(50);
        (uint16 forCaller, uint16 forOrigami) = manager.performanceFeeBps();
        assertEq(forCaller, 0);
        assertEq(forOrigami, 50);

        assertEq(IMF.balanceOf(address(swapper)), 100e18);

        // The extra 100e18 USDS gets dripped in, so nothing at the start
        assertEq(manager.totalAssets(), 100e18 - 2);
        skip(7 days);

        // All vested in, and interest from the ERC4626
        assertEq(manager.totalAssets(), 200.490151661506562745e18);
    }

    function test_recoverToken_failure() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(USDS)));
        manager.recoverToken(address(USDS), alice, 100e18);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(IMF_USDS_VAULT)));
        manager.recoverToken(address(IMF_USDS_VAULT), alice, 100e18);
    }

    function test_recoverToken_success() public {
        check_recoverToken(address(manager));
    }
}

contract OrigamiErc4626WithRewardsManagerTestAccess is OrigamiErc4626WithRewardsManagerTestBase {
    function test_setReservesVestingDuration_access() public {
        expectElevatedAccess();
        manager.setReservesVestingDuration(123);
    }

    function test_setRewardTokens_access() public {
        expectElevatedAccess();
        manager.setRewardTokens(new address[](0));
    }

    function test_setMerklRewardsDistributor_access() public {
        expectElevatedAccess();
        manager.setMerklRewardsDistributor(alice);
    }

    function test_setMorphoRewardsDistributor_access() public {
        expectElevatedAccess();
        manager.setMorphoRewardsDistributor(alice);
    }

    function test_merklToggleOperator_access() public {
        expectElevatedAccess();
        manager.merklToggleOperator(alice);
    }

    function test_setFeeCollector_access() public {
        expectElevatedAccess();
        manager.setFeeCollector(alice);
    }

    function test_setSwapper_access() public {
        expectElevatedAccess();
        manager.setSwapper(alice);
    }

    function test_setWithdrawalFee_access() public {
        expectElevatedAccess();
        manager.setWithdrawalFee(123);
    }

    function test_setPerformanceFees_access() public {
        expectElevatedAccess();
        manager.setPerformanceFees(123);
    }

    function test_recoverToken_access() public {
        expectElevatedAccess();
        manager.recoverToken(alice, alice, 100e18);
    }

    function test_deposit_access() public {
        expectElevatedAccess();
        manager.deposit(100);

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        manager.deposit(100);
    }

    function test_withdraw_access() public {
        expectElevatedAccess();
        manager.withdraw(100, alice);

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        manager.withdraw(100, alice);
    }

    function test_setPauser_access() public {
        expectElevatedAccess();
        manager.setPauser(alice, true);
    }

    function test_setPaused_access() public {
        expectElevatedAccess();
        manager.setPaused(IOrigamiManagerPausable.Paused(true, false));
    }
}

contract OrigamiErc4626WithRewardsManagerTestDeposit is OrigamiErc4626WithRewardsManagerTestBase {
    event AssetStaked(uint256 amount);

    function test_deposit_pausedOK() public {
        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(true, false));

        assertEq(manager.areDepositsPaused(), true);
        assertEq(manager.areWithdrawalsPaused(), false);

        // The manager itself doesn't pause - it's checked within the OrigamiERC4626
        assertEq(deposit(0), 0);
    }

    function test_deposit_successNothing() public {
        assertEq(deposit(0), 0);
    }

    function test_deposit_fail_tooMuch() public {
        vm.startPrank(address(vault));
        vm.expectRevert("Usds/insufficient-balance");
        manager.deposit(100e18);
    }

    function test_deposit_successLimitedUSDS() public {
        vm.startPrank(address(vault));
        deal(address(USDS), address(manager), 100e18);
        vm.expectEmit(address(manager));
        emit AssetStaked(25e18);
        vm.expectEmit(address(IMF_USDS_VAULT));
        emit Deposit(address(manager), address(manager), 25e18, 24.347137513268786146e18);
        assertEq(manager.deposit(25e18), 25e18);
        assertEq(IMF_USDS_VAULT.balanceOf(address(manager)), 24.347137513268786146e18);
        assertEq(USDS.balanceOf(address(manager)), 75e18);
        assertEq(manager.totalAssets(), 25e18 - 1);
        assertEq(manager.unallocatedAssets(), 75e18*99/100);
        assertEq(manager.vestingReserves(), 0);
        assertEq(manager.futureVestingReserves(), 0);
    }

    function test_deposit_successMaxUSDS() public {
        vm.startPrank(origamiMultisig);
        assertEq(deposit(100e18), 100e18);
        assertEq(IMF_USDS_VAULT.balanceOf(address(manager)), 97.388550053075144587e18);
        assertEq(USDS.balanceOf(address(manager)), 0);
        assertEq(manager.totalAssets(), 100e18 - 1);
        assertEq(manager.vestingReserves(), 0);
        assertEq(manager.futureVestingReserves(), 0);
    }
}

contract OrigamiErc4626WithRewardsManagerTestWithdraw is OrigamiErc4626WithRewardsManagerTestBase {
    event AssetWithdrawn(uint256 amount);
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

    function test_withdraw_pausedOK() public {
        assertEq(deposit(100e18), 100e18);

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
        vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientBalance.selector, address(manager), 0, 97.388550053075144588e18));
        assertEq(manager.withdraw(100e18, alice), 0);
    }

    function test_withdraw_successSome() public {
        assertEq(deposit(100e18), 100e18);

        vm.startPrank(address(vault));
        vm.expectEmit(address(manager));
        emit AssetWithdrawn(100e18-1);
        assertEq(manager.withdraw(manager.totalAssets(), alice), 100e18-1);
        assertEq(USDS.balanceOf(alice), 100e18-1);

        assertEq(IMF_USDS_VAULT.balanceOf(address(manager)), 0);
        assertEq(USDS.balanceOf(address(manager)), 0);
        assertEq(manager.totalAssets(), 0);
        assertEq(manager.vestingReserves(), 0);
        assertEq(manager.futureVestingReserves(), 0);
    }

    function test_withdraw_successSameReceiver() public {
        assertEq(deposit(100e18), 100e18);
        assertEq(manager.totalAssets(), 100e18-1);

        vm.startPrank(address(vault));
        assertEq(manager.withdraw(50e18, address(manager)), 50e18);
        assertEq(manager.totalAssets(), 50e18-1);
        assertEq(manager.unallocatedAssets(), 50e18*99/100);
        assertEq(manager.vestingReserves(), 0);
    }
}

contract OrigamiErc4626WithRewardsManagerTestRewards is OrigamiErc4626WithRewardsManagerTestBase {
    event ClaimedReward(
        address indexed rewardToken, 
        uint256 amountForCaller,
        uint256 amountForOrigami,
        uint256 amountForVault
    );
    event AssetStaked(uint256 amount);

    function test_merklClaim_no_inputs() public {
        manager.merklClaim(new address[](0), new uint256[](0), new bytes32[][](0));
    }

    function test_merklClaim_withClaimAndReinvest() public {
        deposit(100e18);
        assertEq(manager.totalAssets(), 100e18-1);

        address[] memory tokens = new address[](1);
        tokens[0] = address(IMF);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 123e18;
        manager.merklClaim(tokens, amounts, new bytes32[][](0));

        assertEq(IMF.balanceOf(address(swapper)), 123e18);
        assertEq(manager.totalAssets(), 100e18 - 1);
    }

    function test_merklClaim_withNonRewardTokens() public {
        deposit(100e18);
        assertEq(manager.totalAssets(), 100e18-1);

        DummyMintableToken fakeToken = new DummyMintableToken(origamiMultisig, "fake", "fake", 18);
        deal(address(fakeToken), address(merklRewardsDistributor), 1_000e18);

        address[] memory tokens = new address[](2);
        tokens[0] = address(fakeToken);
        tokens[1] = address(IMF);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 123e18;
        amounts[1] = 123e18;
        manager.merklClaim(tokens, amounts, new bytes32[][](0));

        // Non reward tokens are left in the manager (can be rescued)
        assertEq(fakeToken.balanceOf(address(manager)), 123e18);
        assertEq(fakeToken.balanceOf(address(swapper)), 0);
        assertEq(IMF.balanceOf(address(swapper)), 123e18);
        assertEq(manager.totalAssets(), 100e18 - 1);
    }

    function test_merklClaim_withExtraVaultTokens() public {
        deposit(100e18);
        assertEq(manager.totalAssets(), 100e18-1);

        {
            deal(address(USDS), origamiMultisig, 1_000e18);
            vm.startPrank(origamiMultisig);
            USDS.approve(address(IMF_USDS_VAULT), 1_000e18);
            IMF_USDS_VAULT.deposit(1_000e18, address(merklRewardsDistributor));
            deal(address(USDS), address(merklRewardsDistributor), 1_000e18);
        }

        address[] memory tokens = new address[](3);
        tokens[0] = address(IMF_USDS_VAULT);
        tokens[1] = address(USDS);
        tokens[2] = address(IMF);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 123e18;
        amounts[1] = 123e18;
        amounts[2] = 123e18;
        manager.merklClaim(tokens, amounts, new bytes32[][](0));

        // vault shares dont have fees applied but they hit the total assets
        // The USDS got reinvested (fees were taken)
        assertEq(IMF_USDS_VAULT.balanceOf(address(manager)), 100e18 - 1 + 238.978587452704748152e18);
        assertEq(USDS.balanceOf(address(manager)), 0);
        assertEq(IMF_USDS_VAULT.balanceOf(address(swapper)), 0);
        assertEq(IMF.balanceOf(address(swapper)), 123e18);

        // 100e18 from deposit + 123e18*99/100 from USDS + 123e18 IMF-USDS shares -> USDS
        assertEq(manager.depositedAssets(), 348.068214659697715959e18);

        (
            uint256 currentPeriodVested,
            uint256 currentPeriodUnvested,
            uint256 futurePeriodUnvested
        ) = manager.vestingStatus();
        assertEq(currentPeriodVested, 0);
        assertEq(currentPeriodUnvested, (123e18 * 99/100));
        assertEq(futurePeriodUnvested, 0);

        assertEq(manager.totalAssets(), 348.068214659697715959e18 - (123e18 * 99/100));
    }

    function test_externalMerklClaim() public {
        address[] memory users = new address[](1);
        users[0] = address(manager);
        address[] memory tokens = new address[](1);
        tokens[0] = address(IMF);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 123e18;
        merklRewardsDistributor.claim(users, tokens, amounts, new bytes32[][](0));

        assertEq(IMF.balanceOf(address(manager)), 123e18);
        manager.reinvest();
        assertEq(IMF.balanceOf(address(swapper)), 123e18);
    }
    
    function test_morphoClaim_no_inputs() public {
        manager.morphoClaim(new address[](0), new uint256[](0), new bytes32[][](0));
    }

    function test_morphoClaim_withClaimAndReinvest() public {
        deposit(100e18);
        assertEq(manager.totalAssets(), 100e18-1);

        address[] memory tokens = new address[](1);
        tokens[0] = address(IMF);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 123e18;
        manager.morphoClaim(tokens, amounts, new bytes32[][](1));

        assertEq(IMF.balanceOf(address(swapper)), 123e18);
        assertEq(manager.totalAssets(), 100e18 - 1);
    }

    function test_morphoClaim_withNonRewardTokens() public {
        deposit(100e18);
        assertEq(manager.totalAssets(), 100e18-1);

        DummyMintableToken fakeToken = new DummyMintableToken(origamiMultisig, "fake", "fake", 18);
        deal(address(fakeToken), address(morphoRewardsDistributor), 1_000e18);

        address[] memory tokens = new address[](2);
        tokens[0] = address(fakeToken);
        tokens[1] = address(IMF);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 123e18;
        amounts[1] = 123e18;
        manager.morphoClaim(tokens, amounts, new bytes32[][](2));

        // Non reward tokens are left in the manager (can be rescued)
        assertEq(fakeToken.balanceOf(address(manager)), 123e18);
        assertEq(fakeToken.balanceOf(address(swapper)), 0);
        assertEq(IMF.balanceOf(address(swapper)), 123e18);
        assertEq(manager.totalAssets(), 100e18 - 1);
    }

    function test_morphoClaim_withExtraVaultTokens() public {
        deposit(100e18);
        assertEq(manager.totalAssets(), 100e18-1);

        {
            deal(address(USDS), origamiMultisig, 1_000e18);
            vm.startPrank(origamiMultisig);
            USDS.approve(address(IMF_USDS_VAULT), 1_000e18);
            IMF_USDS_VAULT.deposit(1_000e18, address(morphoRewardsDistributor));
            deal(address(USDS), address(morphoRewardsDistributor), 1_000e18);
        }

        address[] memory tokens = new address[](3);
        tokens[0] = address(IMF_USDS_VAULT);
        tokens[1] = address(USDS);
        tokens[2] = address(IMF);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 123e18;
        amounts[1] = 123e18;
        amounts[2] = 123e18;
        manager.morphoClaim(tokens, amounts, new bytes32[][](3));

        // vault shares dont have fees applied but they hit the total assets
        // The USDS got reinvested (fees were taken)
        assertEq(IMF_USDS_VAULT.balanceOf(address(manager)), 100e18 - 1 + 238.978587452704748152e18);
        assertEq(USDS.balanceOf(address(manager)), 0);
        assertEq(IMF_USDS_VAULT.balanceOf(address(swapper)), 0);
        assertEq(IMF.balanceOf(address(swapper)), 123e18);

        // 100e18 from deposit + 123e18*99/100 from USDS + 123e18 IMF-USDS shares -> USDS
        assertEq(manager.depositedAssets(), 348.068214659697715959e18);

        (
            uint256 currentPeriodVested,
            uint256 currentPeriodUnvested,
            uint256 futurePeriodUnvested
        ) = manager.vestingStatus();
        assertEq(currentPeriodVested, 0);
        assertEq(currentPeriodUnvested, (123e18 * 99/100));
        assertEq(futurePeriodUnvested, 0);

        assertEq(manager.totalAssets(), 348.068214659697715959e18 - (123e18 * 99/100));
    }

    function test_externalMorphoClaim() public {
        address[] memory users = new address[](1);
        users[0] = address(manager);
        address[] memory tokens = new address[](1);
        tokens[0] = address(IMF);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 123e18;
        morphoRewardsDistributor.claim(address(manager), address(IMF), 123e18, new bytes32[](0));

        assertEq(IMF.balanceOf(address(manager)), 123e18);
        manager.reinvest();
        assertEq(IMF.balanceOf(address(swapper)), 123e18);
    }

    function test_reinvest_nothing() public {
        deposit(100e18);
        assertEq(manager.totalAssets(), 100e18-1);
        manager.reinvest();
        assertEq(manager.totalAssets(), 100e18-1);
    }

    function test_reinvest_withFees() public {
        deposit(100e18);
        assertEq(manager.totalAssets(), 100e18-1);

        // Will get sent to the swapper
        deal(address(IMF), address(manager), 100e18);
        // Will get reinvested (minus fees)
        deal(address(USDS), address(manager), 100e18);

        vm.expectEmit(address(manager));
        emit AssetStaked(99e18);
        vm.expectEmit(address(manager));
        emit ClaimedReward(address(vault), 0, 1e18, 99e18);
        manager.reinvest();

        assertEq(IMF.balanceOf(address(swapper)), 100e18);

        // The extra 100e18 USDS gets dripped in, so nothing at the start
        assertEq(manager.totalAssets(), 100e18 - 2);
        skip(7 days);

        // All vested in, and interest from the ERC4626
        assertEq(manager.totalAssets(), 200.490151661506562745e18);

        // Fees
        assertEq(USDS.balanceOf(feeCollector), 1e18);
    }

    function test_harvestRewards() public {
        deposit(100e18);
        assertEq(manager.totalAssets(), 100e18-1);

        // Will get sent to the swapper
        deal(address(IMF), address(manager), 100e18);
        // Will get reinvested (minus fees)
        deal(address(USDS), address(manager), 100e18);

        vm.expectEmit(address(manager));
        emit AssetStaked(99e18);
        vm.expectEmit(address(manager));
        emit ClaimedReward(address(vault), 0, 1e18, 99e18);
        manager.harvestRewards(alice);

        assertEq(IMF.balanceOf(address(swapper)), 100e18);

        // The extra 100e18 USDS gets dripped in, so nothing at the start
        assertEq(manager.totalAssets(), 100e18 - 2);
        skip(7 days);

        // All vested in, and interest from the ERC4626
        assertEq(manager.totalAssets(), 200.490151661506562745e18);

        // Fees
        assertEq(USDS.balanceOf(feeCollector), 1e18);
    }

    function test_swapCallback() public {
        deposit(100e18);
        assertEq(manager.totalAssets(), 100e18-1);

        // Will get sent to the swapper
        deal(address(IMF), address(manager), 100e18);
        // Will get reinvested (minus fees)
        deal(address(USDS), address(manager), 100e18);

        vm.expectEmit(address(manager));
        emit AssetStaked(99e18);
        vm.expectEmit(address(manager));
        emit ClaimedReward(address(vault), 0, 1e18, 99e18);
        manager.swapCallback();

        assertEq(IMF.balanceOf(address(swapper)), 100e18);

        // The extra 100e18 USDS gets dripped in, so nothing at the start
        assertEq(manager.totalAssets(), 100e18 - 2);
        skip(7 days);

        // All vested in, and interest from the ERC4626
        assertEq(manager.totalAssets(), 200.490151661506562745e18);

        // Fees
        assertEq(USDS.balanceOf(feeCollector), 1e18);
    }

    function test_reinvest_allFees() public {
        {
            manager = new OrigamiErc4626WithRewardsManager(
                origamiMultisig,
                address(vault),
                address(IMF_USDS_VAULT),
                feeCollector,
                swapper,
                1_000,
                VESTING_DURATION,
                address(merklRewardsDistributor),
                address(morphoRewardsDistributor)
            );

            vm.startPrank(origamiMultisig);
            vault.setManager(address(manager), 0);

            address[] memory newRewardTokens = new address[](1);
            newRewardTokens[0] = address(IMF);
            manager.setRewardTokens(newRewardTokens);

            vm.stopPrank();
        }

        deposit(100e18);
        assertEq(manager.totalAssets(), 100e18-1);

        // Will get sent to the swapper
        deal(address(IMF), address(manager), 100e18);
        // Will get reinvested (minus fees)
        deal(address(USDS), address(manager), 1);

        vm.expectEmit(address(manager));
        emit ClaimedReward(address(vault), 0, 1, 0);
        manager.reinvest();

        assertEq(IMF.balanceOf(address(swapper)), 100e18);

        // The extra 100e18 USDS gets dripped in, so nothing at the start
        assertEq(manager.totalAssets(), 100e18 - 1);
        skip(7 days);

        // All vested in, and interest from the ERC4626
        assertEq(manager.totalAssets(), 100.748820898439609701e18);

        // Fees
        assertEq(USDS.balanceOf(feeCollector), 1);
    }

    function test_reinvest_noFees() public {
        vm.startPrank(origamiMultisig);
        manager.setPerformanceFees(0);
        
        deposit(100e18);
        assertEq(manager.totalAssets(), 100e18-1);

        // Will get sent to the swapper
        deal(address(IMF), address(manager), 100e18);
        // Will get reinvested (minus fees)
        deal(address(USDS), address(manager), 100e18);

        vm.expectEmit(address(manager));
        emit AssetStaked(100e18);
        vm.expectEmit(address(manager));
        emit ClaimedReward(address(vault), 0, 0, 100e18);
        manager.reinvest();

        assertEq(IMF.balanceOf(address(swapper)), 100e18);

        // The extra 100e18 USDS gets dripped in, so nothing at the start
        assertEq(manager.totalAssets(), 100e18 - 2);
        skip(7 days);

        // All vested in, and interest from the ERC4626
        assertEq(manager.totalAssets(), 201.497639841254392840e18);

        // Fees
        assertEq(USDS.balanceOf(feeCollector), 0);
    }
}

contract OrigamiErc4626WithRewardsManagerTestViews is OrigamiErc4626WithRewardsManagerTestBase {
    function test_supportsInterface() public view {
        assertEq(manager.supportsInterface(type(IOrigamiDelegated4626VaultManager).interfaceId), true);
        assertEq(manager.supportsInterface(type(IOrigamiErc4626WithRewardsManager).interfaceId), true);
        assertEq(manager.supportsInterface(type(IOrigamiCompoundingVaultManager).interfaceId), true);
        assertEq(manager.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(manager.supportsInterface(type(IOrigamiManagerPausable).interfaceId), false);
    }
}
