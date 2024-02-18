pragma solidity ^0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (test/foundry/investments/vesdt/OrigamiVeTetuProxy.t.sol)

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITetuRewardsDistributor} from "contracts/interfaces/external/tetu/ITetuRewardsDistributor.sol";
import {IVeTetu} from "contracts/interfaces/external/tetu/IVeTetu.sol";
import {ITetuVoter} from "contracts/interfaces/external/tetu/ITetuVoter.sol";
import {OrigamiVeTetuProxy} from "contracts/investments/vetetu/OrigamiVeTetuProxy.sol";
import {OrigamiTest} from "test/foundry/OrigamiTest.sol";
import {CommonEventsAndErrors} from "contracts/common/CommonEventsAndErrors.sol";
import {DummyDex} from "contracts/test/common/DummyDex.sol";
import {DummyNFT} from "contracts/test/common/DummyNFT.sol";
import {ITetuPlatformVoter} from "contracts/interfaces/external/tetu/ITetuPlatformVoter.sol";

contract OrigamiVeTetuProxyTest_Base is OrigamiTest {
    OrigamiVeTetuProxy proxy;

    IVeTetu veTetu = IVeTetu(0x6FB29DD17fa6E27BD112Bc3A2D0b8dae597AeDA4);
    address tetuUsdc8020 = 0xE2f706EF1f7240b803AAe877C9C762644bb808d8;
    address depositContract = 0x9FB2Eb86aE9DbEBf276A7A67DF1F2D48A49b95EC;
    address balancer = 0x9a71012B13CA4d3D0Cdc72A177DF3ef03b0E76A3;
    address tetuRewardsDistributor = 0xf8d97eC3a778028E84D4364bCd72bb3E2fb5D18e;
    address snapshotDelegator = 0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446;
    address tetuRewardToken = 0x255707B70BF90aa112006E1b07B9AeA6De021424;
    address tetuVoter = 0x4cdF28d6244c6B0560aa3eBcFB326e0C24fe8218;
    address platformVoter = 0x5576Fe01a9e6e0346c97E546919F5d15937Be92D;
    bytes32 constant snapshotId = bytes32("tetubal.eth");

    uint256 WEEK = 7 * 86400;

    event SnapshotDelegatorSet(address indexed _delegator);
    event TetuRewardsDistributorSet(address indexed _distributor);
    event TetuVoterSet(address indexed _voter);
    event TetuPlatformVoterSet(address indexed _platformVoter);
    event CreatedLock(address indexed _token, uint256 _value, uint256 _lockDuration);
    event IncreaseAmount(address indexed _token, uint256 indexed _tokenId, uint256 _value);
    event IncreaseUnlockTime(uint256 indexed _tokenId, uint256 _lockDuration);
    event Withdraw(address indexed _stakingToken, uint256 indexed _tokenId, uint256 _amount, address indexed _receiver);
    event WithdrawAll(uint256 indexed _tokenId, address indexed _receiver);
    event Merge(uint256 indexed _id1, uint256 indexed _id2);
    event Split(uint256 indexed _tokenId, uint256 _percent);
    event ClaimVeTetuRewards(uint256 indexed _tokenId, uint256 _amount);
    event ClaimManyVeTetuRewards(uint256[] _tokenIds);
    event VeTetuNFTReceived(uint256 indexed _tokenId);   
    event SetDelegate(address indexed _delegate);
    event ClearDelegate();
    event TokenTransferred(address indexed token, address indexed to, uint256 amount);
    event VeTetuTransferred(address indexed to, uint256 indexed tokenId);
    event Voted(uint256 indexed _tokenId);
    event ResetVote(uint256 indexed _tokenId);
    event Poke(uint256 indexed _tokenId);
    event PlatformVote(uint256 indexed _tokenId);
    event PlatformVoteBatch(uint256 indexed _tokenId);
    event PlatformVoteReset(uint256 indexed _tokenId);

    /// @dev Deploy the veTetu proxy
    function deployProxy() internal returns (OrigamiVeTetuProxy) {
        // Deploy the implementation
        OrigamiVeTetuProxy impl = new OrigamiVeTetuProxy(
            address(veTetu)
        );

        // Deploy the UUPS proxy wrapping the implementation.
        address uupsProxy = deployUUPSProxy(address(impl));

        return OrigamiVeTetuProxy(uupsProxy);
    }

    function setUp() public {
        fork("polygon", 38601140);
        proxy = deployProxy();
        proxy.initialize(
            gov,
            tetuRewardsDistributor,
            snapshotDelegator,
            tetuVoter,
            platformVoter
        );

        vm.prank(gov);
        proxy.addOperator(operator);
    }

    function createLock(address token, uint256 amount) public returns (uint256) {
        uint256 lockDuration = 10 * WEEK; // Duration is in Seconds
        deal(token, address(proxy), amount, true);
        return proxy.createLock(token, amount, lockDuration);
    }   
}

contract OrigamiVeTetuProxyTest_Initialize is OrigamiVeTetuProxyTest_Base {
    function test_initialize() public {
        proxy = deployProxy();
        proxy.initialize(
            gov,
            tetuRewardsDistributor,
            snapshotDelegator,
            tetuVoter,
            platformVoter
        );

        assertEq(address(proxy.veTetu()), address(veTetu));
        assertEq(address(proxy.tetuRewardsDistributor()), tetuRewardsDistributor);
        assertEq(address(proxy.snapshotDelegator()), snapshotDelegator);
        assertEq(address(proxy.tetuVoter()), tetuVoter);
        assertEq(address(proxy.tetuPlatformVoter()), platformVoter);
    }
}

contract OrigamiVeTetuProxyTest_Admin is OrigamiVeTetuProxyTest_Base {
    function test_addAndRemoveOperator() public {
        vm.startPrank(gov);
        check_addAndRemoveOperator(proxy);
    }

    function test_setSnapshotDelegator() public {
        vm.startPrank(gov);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        proxy.setSnapshotDelegator(address(0));

        vm.expectEmit(true, true, true, true);
        emit SnapshotDelegatorSet(alice);
        proxy.setSnapshotDelegator(alice);
        assertEq(address(proxy.snapshotDelegator()), alice);
    }

    function test_setTetuRewardsDistributor() public {
        vm.startPrank(gov);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        proxy.setTetuRewardsDistributor(address(0));

        vm.expectEmit(true, true, true, true);
        emit TetuRewardsDistributorSet(alice);
        proxy.setTetuRewardsDistributor(alice);
        assertEq(address(proxy.tetuRewardsDistributor()), alice);
    }

    function test_setTetuVoter() public {
        vm.startPrank(gov);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        proxy.setTetuVoter(address(0));

        vm.expectEmit(true, true, true, true);
        emit TetuVoterSet(alice);
        proxy.setTetuVoter(alice);
        assertEq(address(proxy.tetuVoter()), alice);
    }

    function test_setTetuPlatformVoter() public {
        vm.startPrank(gov);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        proxy.setTetuPlatformVoter(address(0));

        vm.expectEmit(true, true, true, true);
        emit TetuPlatformVoterSet(alice);
        proxy.setTetuPlatformVoter(alice);
        assertEq(address(proxy.tetuPlatformVoter()), alice);
    }
}

contract OrigamiVeTetuProxyTest_ExecuteAndRecovery is OrigamiVeTetuProxyTest_Base {
    function test_transferToken() public {
        vm.startPrank(operator);
        uint256 amount = 100 ether;
        deal(tetuUsdc8020, address(proxy), amount, true);

        vm.expectEmit(true, true, true, true);
        emit TokenTransferred(tetuUsdc8020, alice, amount);

        proxy.transferToken(tetuUsdc8020, alice, amount);
        assertEq(IERC20(tetuUsdc8020).balanceOf(alice), amount);
        assertEq(IERC20(tetuUsdc8020).balanceOf(address(proxy)), 0);
    }

    function test_increaseTokenAllowance() public {
        vm.startPrank(operator);
        uint256 amount = 100 ether;

        proxy.increaseTokenAllowance(tetuUsdc8020, alice, amount);
        assertEq(IERC20(tetuUsdc8020).allowance(address(proxy), alice), amount);
    }

    function test_decreaseTokenAllowance() public {
        vm.startPrank(operator);
        proxy.increaseTokenAllowance(tetuUsdc8020, alice, 100 ether);
        proxy.decreaseTokenAllowance(tetuUsdc8020, alice, 25 ether);
        assertEq(IERC20(tetuUsdc8020).allowance(address(proxy), alice), 75 ether);
    }

    function _addProxyToWhitelist() internal {
        address governance = 0xcc16d636dD05b52FF1D8B9CE09B09BC62b11412B;
        vm.startPrank(governance);
        veTetu.announceAction(IVeTetu.TimeLockType.WHITELIST_TRANSFER);
        // skip forward 1 day
        vm.warp(block.timestamp + 1 days);
        veTetu.whitelistTransferFor(address(proxy));
        vm.stopPrank();
    }

    function test_transferVeTetu() public {
        _addProxyToWhitelist();

        vm.startPrank(operator);
        uint256 id = createLock(tetuUsdc8020, 100 ether);

        proxy.transferVeTetu(alice, id);

        assertEq(veTetu.balanceOf(address(proxy)), 0);
        assertEq(veTetu.balanceOf(alice), 1);
        assertEq(veTetu.ownerOf(id), alice);

        // When alice transfers back, we get the received event.
        changePrank(alice);

        vm.expectEmit(true, false, false, false);
        emit VeTetuNFTReceived(id);

        veTetu.safeTransferFrom(address(alice), address(proxy), id);
        
        assertEq(veTetu.balanceOf(address(proxy)), 1);
        assertEq(veTetu.balanceOf(alice), 0);
        assertEq(veTetu.ownerOf(id), address(proxy));
    }

    function test_transferNonVeTetuReverts() public {
        DummyNFT otherNft = new DummyNFT();
        otherNft.safeMint(alice, 1);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(otherNft)));

        vm.prank(alice);
        otherNft.safeTransferFrom(alice, address(proxy), 1);
    }

    function test_approveVeTetu() public {
        vm.startPrank(operator);
        uint256 id = createLock(tetuUsdc8020, 100 ether);

        proxy.approveVeTetu(alice, id);
        assertEq(veTetu.getApproved(id), alice);
    }

    function test_setVeTetuApprovalForAll() public {
        vm.startPrank(operator);

        proxy.setVeTetuApprovalForAll(alice, true);
        assertEq(veTetu.isApprovedForAll(address(proxy), alice), true);

        proxy.setVeTetuApprovalForAll(alice, false);
        assertEq(veTetu.isApprovedForAll(address(proxy), alice), false);
    }

}

contract OrigamiVeTetuProxyTest_Access is OrigamiVeTetuProxyTest_Base {
    function test_tetuSetDelegatorAccess() public {
        expectOnlyGov();
        proxy.setSnapshotDelegator(alice);
    }

    function test_tetuSetRewardsAccess() public {
        expectOnlyGov();
        proxy.setTetuRewardsDistributor(alice);
    }

    function test_setTetuVoterAccess() public {
        expectOnlyGov();
        proxy.setTetuVoter(alice);
    }

    function test_tetuAddOperatorAccess() public {
        expectOnlyGov();
        proxy.addOperator(alice);
    }

    function test_tetuRemoveOperatorAccess() public {
        expectOnlyGov();
        proxy.removeOperator(alice);
    }

    function test_tetuCreateLockLockAccess() public {
        expectOnlyOperators();
        proxy.createLock(address(tetuUsdc8020), 1000000, WEEK);
    }

    function test_tetuIncreaseAmountAccess() public {
        expectOnlyOperators();
        proxy.increaseAmount(address(tetuUsdc8020), 8, WEEK);
    }

    function test_tetuIncreaseUnlockTimeAccess() public {
        expectOnlyOperators();
        proxy.increaseUnlockTime(8, WEEK);
    }

    function test_tetuWithdrawAccess() public {
        expectOnlyOperators();
        proxy.withdraw(address(tetuUsdc8020), 8, alice);
    }

    function test_tetuWithdrawAllAccess() public {
        expectOnlyOperators();
        proxy.withdrawAll(8, alice);
    }

    function test_tetuMergeAccess() public {
        expectOnlyOperators();
        proxy.merge(7, 8);
    }

    function test_tetuSplitAccess() public {
        expectOnlyOperators();
        proxy.split(8, 100);
    }

    function test_tetuClaimRewardsAccess() public {
        expectOnlyOperators();
        proxy.claimVeTetuRewards(8);
    }

    function test_tetuClaimManyRewardsAccess() public {
        expectOnlyOperators();
        uint256[] memory ids = new uint256[](0);
        proxy.claimManyVeTetuRewards(ids);
    }

    function test_tetuSetDelegateAccess() public {
        expectOnlyOperators();
        proxy.setDelegate(snapshotId, alice);
    }

    function test_tetuClearDelegateAccess() public {
        expectOnlyOperators();
        proxy.clearDelegate(snapshotId);
    }

    function test_tetuVoteAccess() public {
        expectOnlyOperators();
        address[] memory vaults = new address[](0);
        int256[] memory weights = new int256[](0);
        proxy.vote(1, vaults, weights);
    }

    function test_tetuResetVoteAccess() public {
        expectOnlyOperators();
        proxy.resetVote(1);
    }

    function test_tetuTransferTokenAccess() public {
        expectOnlyOperators();
        proxy.transferToken(tetuUsdc8020, alice, 100);
    }

    function test_tetuIncreaseTokenAllowanceAccess() public {
        expectOnlyOperators();
        proxy.increaseTokenAllowance(tetuUsdc8020, alice, 100);
    }

    function test_tetuDecreaseTokenAllowanceAccess() public {
        expectOnlyOperators();
        proxy.decreaseTokenAllowance(tetuUsdc8020, alice, 100);
    }

    function test_transferVeTetuAccess() public {
        expectOnlyOperators();
        proxy.transferVeTetu(alice, 100);
    }

    function test_approveVeTetuAccess() public {
        expectOnlyOperators();
        proxy.approveVeTetu(alice, 100);
    }

    function test_setVeTetuApprovalForAllAccess() public {
        expectOnlyOperators();
        proxy.setVeTetuApprovalForAll(alice, true);
    }
}

contract OrigamiVeTetuProxyTest_Locks is OrigamiVeTetuProxyTest_Base {
    function test_tetuCreateLock() public {
        vm.startPrank(operator);
        uint256 amount = 100 ether;
        uint256 lockDuration = 10 * WEEK; // Duration is in Seconds
        uint256 expectedUnlockDate = (block.timestamp + lockDuration) / WEEK * WEEK;
        
        block.timestamp + lockDuration;
        deal(tetuUsdc8020, address(proxy), amount, true);

        uint256 currentTokenId = IVeTetu(address(veTetu)).tokenId();
        vm.expectEmit(true, false, false, false);
        emit VeTetuNFTReceived(currentTokenId+1);

        uint256 id = proxy.createLock(tetuUsdc8020, amount, lockDuration);
        assertEq(veTetu.balanceOf(address(proxy)), 1);
        assertEq(id, currentTokenId+1);
        assertEq(veTetu.ownerOf(id), address(proxy));

        // Check veTetuLockedAmount
        assertEq(veTetu.lockedAmounts(id, tetuUsdc8020), amount);
        assertEq(proxy.veTetuLockedAmountOf(id, tetuUsdc8020), amount);
        assertEq(proxy.veTetuLockedAmount(tetuUsdc8020), amount);

        // Check veTetuLockedEnd
        assertEq(veTetu.lockedEnd(id), expectedUnlockDate);
        assertEq(proxy.veTetuLockedEnd(id), expectedUnlockDate);

        // Check veTetuVotingBalance
        uint256 vpower = IVeTetu(address(veTetu)).balanceOfNFTAt(id, block.timestamp);
        assertEq(proxy.veTetuVotingBalanceOf(id), vpower);
        assertEq(proxy.veTetuVotingBalance(), vpower);

        // Check totalVeTetuVotingSupply
        assertEq(proxy.totalVeTetuVotingSupply(), veTetu.totalSupplyAtT(block.timestamp));
    }

    function test_multipleLocks() public {
        vm.startPrank(operator);
        uint256 id1 = createLock(tetuUsdc8020, 100 ether);
        uint256 id2 = createLock(tetuUsdc8020, 50 ether);

        assertEq(veTetu.balanceOf(address(proxy)), 2);

        // Check the total locked amount
        assertEq(proxy.veTetuLockedAmount(tetuUsdc8020), 150 ether);

        // Check the total voting balance
        assertEq(
            proxy.veTetuVotingBalance(), 
            veTetu.balanceOfNFTAt(id1, block.timestamp) + veTetu.balanceOfNFTAt(id2, block.timestamp)
        );
    }

    function test_tetuAmountIncrease() public {
        vm.startPrank(operator);
        uint256 id = createLock(tetuUsdc8020, 100 ether);

        uint incAmount = 100 ether;
        deal(tetuUsdc8020, address(proxy), incAmount, true);

        vm.expectEmit(true, true, true, true);
        emit IncreaseAmount(tetuUsdc8020, id, incAmount);
        proxy.increaseAmount(tetuUsdc8020, id, incAmount);
        assertEq(veTetu.balanceOf(address(proxy)), 1); 
    }

    function test_increaseUnlockTime() public {
        vm.startPrank(operator);
        uint256 amount = 100 ether;
        uint256 lockDuration = 10 * WEEK; // Duration is in Seconds
        uint256 expectedUnlockDate = (block.timestamp + lockDuration) / WEEK * WEEK;
        
        deal(tetuUsdc8020, address(proxy), amount, true);
        uint256 id = proxy.createLock(tetuUsdc8020, amount, lockDuration);

        assertEq(veTetu.lockedEnd(id), expectedUnlockDate);
        assertEq(proxy.veTetuLockedEnd(id), expectedUnlockDate);

        uint256 lockDuration2 = 14 * WEEK;
        uint256 expectedUnlockDate2 = (block.timestamp + lockDuration2) / WEEK * WEEK;

        vm.expectEmit(true, true, true, true);
        emit IncreaseUnlockTime(id, lockDuration2);
        proxy.increaseUnlockTime(id, lockDuration2);

        assertEq(veTetu.lockedEnd(id), expectedUnlockDate2);
        assertEq(proxy.veTetuLockedEnd(id), expectedUnlockDate2);
    }

    function test_tetuWithdraw_toAlice() public {
        vm.startPrank(operator);
        uint256 locked = 100 ether;
        uint256 id = createLock(tetuUsdc8020, locked);
        uint256 lockEnd = proxy.veTetuLockedEnd(id);
        vm.warp(lockEnd+1);
        
        vm.expectEmit(true, true, true, true);
        emit Withdraw(tetuUsdc8020, id, locked, alice);
        uint256 unlocked = proxy.withdraw(tetuUsdc8020, id, alice);
        assertEq(IERC20(tetuUsdc8020).balanceOf(address(proxy)), 0);
        assertEq(IERC20(tetuUsdc8020).balanceOf(address(alice)), unlocked);
    }

    function test_tetuWithdraw_toProxy() public {
        vm.startPrank(operator);
        uint256 locked = 100 ether;
        uint256 id = createLock(tetuUsdc8020, locked);
        uint256 lockEnd = proxy.veTetuLockedEnd(id);
        vm.warp(lockEnd+1);
        
        vm.expectEmit(true, true, true, true);
        emit Withdraw(tetuUsdc8020, id, locked, address(proxy));
        uint256 unlocked = proxy.withdraw(tetuUsdc8020, id, address(proxy));
        assertEq(IERC20(tetuUsdc8020).balanceOf(address(proxy)), unlocked);
        assertEq(IERC20(tetuUsdc8020).balanceOf(address(alice)), 0);
        assertEq(proxy.veTetuLockedAmount(tetuUsdc8020), 0);
    }

    function test_tetuWithdrawAll_toAlice() public {
        vm.startPrank(operator);

        // Stake both bal and tetu tokens
        uint256 id = createLock(tetuUsdc8020, 100 ether);
        deal(tetuRewardToken, address(proxy), 50 ether, true);
        proxy.increaseAmount(tetuRewardToken, id, 50 ether);

        uint256 lockEnd = proxy.veTetuLockedEnd(id);
        vm.warp(lockEnd+1);

        vm.expectEmit(true, true, true, true);
        emit WithdrawAll(id, alice);

        uint256[] memory unlockAmounts = proxy.withdrawAll(id, alice);

        assertEq(unlockAmounts[0], 50 ether);
        assertEq(IERC20(tetuRewardToken).balanceOf(alice), 50 ether);
        assertEq(IERC20(tetuRewardToken).balanceOf(address(proxy)), 0);
        assertEq(proxy.veTetuLockedAmount(tetuRewardToken), 0);

        assertEq(unlockAmounts[1], 100 ether);
        assertEq(IERC20(tetuUsdc8020).balanceOf(alice), 100 ether);
        assertEq(IERC20(tetuUsdc8020).balanceOf(address(proxy)), 0);
        assertEq(proxy.veTetuLockedAmount(tetuUsdc8020), 0);
    }

    function test_tetuWithdrawAll_toProxy() public {
        vm.startPrank(operator);

        // Stake both bal and tetu tokens
        uint256 id = createLock(tetuUsdc8020, 100 ether);
        deal(tetuRewardToken, address(proxy), 50 ether, true);
        proxy.increaseAmount(tetuRewardToken, id, 50 ether);

        uint256 lockEnd = proxy.veTetuLockedEnd(id);
        vm.warp(lockEnd+1);

        vm.expectEmit(true, true, true, true);
        emit WithdrawAll(id, address(proxy));

        uint256[] memory unlockAmounts = proxy.withdrawAll(id, address(proxy));

        assertEq(unlockAmounts[0], 50 ether);
        assertEq(IERC20(tetuRewardToken).balanceOf(alice), 0);
        assertEq(IERC20(tetuRewardToken).balanceOf(address(proxy)), 50 ether);
        assertEq(proxy.veTetuLockedAmount(tetuRewardToken), 0);

        assertEq(unlockAmounts[1], 100 ether);
        assertEq(IERC20(tetuUsdc8020).balanceOf(alice), 0);
        assertEq(IERC20(tetuUsdc8020).balanceOf(address(proxy)), 100 ether);
        assertEq(proxy.veTetuLockedAmount(tetuUsdc8020), 0);
    }

    function test_tetuSplit() public {
        vm.startPrank(operator);
        uint256 id = createLock(tetuUsdc8020, 100 ether);

        vm.expectEmit(true, true, true, true);
        emit Split(id, 500);
        proxy.split(id, 500);
        assertEq(veTetu.balanceOf(address(proxy)), 2);
    }

    function test_tetuMerge() public {
        vm.startPrank(operator);
        uint256 id1 = createLock(tetuUsdc8020, 100 ether);
        uint256 id2 = createLock(tetuUsdc8020, 100 ether);
        assertEq(veTetu.balanceOf(address(proxy)), 2);

        vm.expectEmit(true, true, true, true);
        emit Merge(id1, id2);
        proxy.merge(id1, id2);
        assertEq(veTetu.balanceOf(address(proxy)), 1);
        assertEq(veTetu.ownerOf(id1), address(0));
        assertEq(veTetu.ownerOf(id2), address(proxy));
    }
}

contract OrigamiVeTetuProxyTest_Rewards is OrigamiVeTetuProxyTest_Base {

    // Send TETU rewards to the distributor and checkpoint
    // to set rewardsPerWeek
    function distributeRewards() internal {
        deal(tetuRewardToken, tetuRewardsDistributor, 100000 ether, true);
        ITetuRewardsDistributor(tetuRewardsDistributor).checkpoint();
    }

    function test_claimableRewards() public {
        vm.startPrank(operator);
        uint256 id = createLock(tetuUsdc8020, 100 ether);

        vm.warp(block.timestamp + 4 * WEEK);
        distributeRewards();

        uint256 claimable = proxy.claimableVeTetuRewards(id);
        assertGt(claimable, 0);
        assertEq(ITetuRewardsDistributor(tetuRewardsDistributor).claimable(id), claimable);
    }

    function test_claimRewards() public {
        vm.startPrank(operator);
        uint256 id = createLock(tetuUsdc8020, 100 ether);

        vm.warp(block.timestamp + 4 * WEEK);
        distributeRewards();

        uint256 claimable = proxy.claimableVeTetuRewards(id);

        vm.expectEmit(true, true, true, true);
        emit ClaimVeTetuRewards(id, claimable);
        uint256 claimed = proxy.claimVeTetuRewards(id);

        assertEq(claimed, claimable);
        assertGt(claimed, 0);

        // The TETU rewards get automatically locked into the NFT
        assertEq(proxy.veTetuLockedAmountOf(id, tetuRewardToken), claimed);
    }

    function test_claimManyVeTetuRewards() public {
        vm.startPrank(operator);
        uint256[] memory ids = new uint256[](2);
        ids[0] = createLock(tetuUsdc8020, 100 ether);
        ids[1] = createLock(tetuRewardToken, 200 ether);

        vm.warp(block.timestamp + 4 * WEEK);
        distributeRewards();

        uint256 claimable0 = proxy.claimableVeTetuRewards(ids[0]);
        uint256 claimable1 = proxy.claimableVeTetuRewards(ids[1]);

        vm.expectEmit(true, true, true, true);
        emit ClaimManyVeTetuRewards(ids);

        bool claimed = proxy.claimManyVeTetuRewards(ids);
        assertEq(claimed, true);

        // The TETU rewards get automatically locked into the NFT
        assertEq(proxy.veTetuLockedAmountOf(ids[0], tetuRewardToken), claimable0);
        assertEq(proxy.veTetuLockedAmountOf(ids[1], tetuRewardToken), 200 ether + claimable1);
    }
}

contract OrigamiVeTetuProxyTest_Voting is OrigamiVeTetuProxyTest_Base {
    function test_setDelegate() public {
        vm.startPrank(operator);
        vm.expectEmit(true, true, true, true);
        emit SetDelegate(alice);
        proxy.setDelegate(snapshotId, alice);
    }   

    function test_clearDelegate() public {
        vm.startPrank(operator);
        proxy.setDelegate(snapshotId, alice);

        vm.expectEmit(true, true, true, true);
        emit ClearDelegate();
        proxy.clearDelegate(snapshotId);
    }

    function doVote(uint256 id) internal returns (address) {
        address[] memory vaults = new address[](2);
        vaults[0] = ITetuVoter(tetuVoter).validVaults(0);
        vaults[1] = ITetuVoter(tetuVoter).validVaults(1);

        int256[] memory weights = new int256[](2);
        weights[0] = int256(1);
        weights[1] = int256(1);

        vm.expectEmit(true, false, false, false);
        emit Voted(id);

        proxy.vote(id, vaults, weights);
        return vaults[0];
    }
    
    function test_vote() public {
        vm.startPrank(operator);

        uint256 id = createLock(tetuUsdc8020, 100 ether);
        address vault0 = doVote(id);
        assertGt(ITetuVoter(tetuVoter).votes(id, vault0), 0);
    }

    function test_reset() public {
        vm.startPrank(operator);
        uint256 id = createLock(tetuUsdc8020, 100 ether);
        vm.expectEmit(true, true, true, true);
        emit ResetVote(id);
        proxy.resetVote(id);

        // Pass the vote delay
        vm.warp(block.timestamp + 1 weeks + 1);

        // Vote and then reset - should have 0 votes.
        address vault0 = doVote(id);

        vm.warp(block.timestamp + 1 weeks + 1);
        proxy.resetVote(id);
        assertEq(ITetuVoter(tetuVoter).votes(id, vault0), 0);
    }

    // Platform Voter //

    function test_tetuPlatformVote() public returns (uint256) {
        vm.startPrank(operator);
        uint256 id = createLock(tetuUsdc8020, 100 ether);

        ITetuPlatformVoter.AttributeType vType = ITetuPlatformVoter.AttributeType.INVEST_FUND_RATIO;
        uint256 value = 100_000;
        address target = address(0);

        // cast a vote
        vm.expectEmit(true, true, true, true);
        emit PlatformVote(id);
        proxy.platformVote(
            id,
            vType,
            value,
            target
        );

        ITetuPlatformVoter.Vote[] memory castVote = ITetuPlatformVoter(platformVoter).veVotes(id);
        assertEq(castVote.length, 1);
        require(castVote[0]._type == ITetuPlatformVoter.AttributeType.INVEST_FUND_RATIO);
        return id;
    }

    uint256[] types = [1]; // Corresponds to the enum type numbering (Invest Fund in this case)
    address[] addrs = [address(0)];
    function test_tetuPlatformReset() public {
        uint256 id = test_tetuPlatformVote();
        vm.warp(block.timestamp + WEEK + 1);
        vm.expectEmit(true, true, true, true);
        emit PlatformVoteReset(id);
        proxy.platformResetVote(
            id,
            types,
            addrs
        );

        ITetuPlatformVoter.Vote[] memory castVote = ITetuPlatformVoter(platformVoter).veVotes(id);
        assertEq(castVote.length, 0);
    }

    uint256[] batchValues = [50_000, 50_000];
    address[] batchTargets = [address(0), address(0)];
    ITetuPlatformVoter.AttributeType[] batchTypes = [
        ITetuPlatformVoter.AttributeType.INVEST_FUND_RATIO,
        ITetuPlatformVoter.AttributeType.GAUGE_RATIO
    ];
    function test_tetuPlatformVoteBatch() public {
        vm.startPrank(operator);
        uint256 id = createLock(tetuUsdc8020, 100 ether);
        vm.warp(block.timestamp + WEEK);
        proxy.platformVoteBatch(
            id,
            batchTypes,
            batchValues,
            batchTargets
        );
        
        ITetuPlatformVoter.Vote[] memory castVote = ITetuPlatformVoter(platformVoter).veVotes(id);
        assertEq(castVote.length, 2);
        require(castVote[0]._type == ITetuPlatformVoter.AttributeType.INVEST_FUND_RATIO);
        require(castVote[1]._type == ITetuPlatformVoter.AttributeType.GAUGE_RATIO);
    }

}
