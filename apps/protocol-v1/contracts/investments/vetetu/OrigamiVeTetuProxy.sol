pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/vetetu/OrigamiVeTetuProxy.sol)

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC721ReceiverUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IVeTetu} from "contracts/interfaces/external/tetu/IVeTetu.sol";
import {ITetuVoter} from "contracts/interfaces/external/tetu/ITetuVoter.sol";
import {ITetuPlatformVoter} from "contracts/interfaces/external/tetu/ITetuPlatformVoter.sol";
import {ITetuRewardsDistributor} from "contracts/interfaces/external/tetu/ITetuRewardsDistributor.sol";
import {ISnapshotDelegator} from "contracts/interfaces/external/snapshot/ISnapshotDelegator.sol";

import {Operators} from "contracts/common/access/Operators.sol";
import {CommonEventsAndErrors} from "contracts/common/CommonEventsAndErrors.sol";
import {GovernableUpgradeable} from "../../common/access/GovernableUpgradeable.sol";

/**
  * @title Origami veTETU Proxy
  * @notice 
  *    - Lock tokens to veTetu contract (which mints a veTetu NFT)
  *    - Claim rewards from veTetu (which compounds into veTetu)
  *    - Vote for Tetu vaults
  *    - Delegate snapshot voting for governance
  */
contract OrigamiVeTetuProxy is Initializable, GovernableUpgradeable, Operators, UUPSUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @dev The underlying veTetu contract is locking into
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IVeTetu public immutable veTetu;

    /// @dev Claim locked veTetu yield
    ITetuRewardsDistributor public tetuRewardsDistributor;

    /// @dev Ability to delegate veTetu snapshot voting to an eoa
    ISnapshotDelegator public snapshotDelegator;

    /// @dev Use voting power to vote for vaults
    ITetuVoter public tetuVoter;

    /// @dev Use the voting power for tetu platform votes.
    ITetuPlatformVoter public tetuPlatformVoter;

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
    event PlatformVote(uint256 indexed _tokenId);
    event PlatformVoteBatch(uint256 indexed _tokenId);
    event PlatformVoteReset(uint256 indexed _tokenId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address _veTetu
    ) {
        _disableInitializers();
        
        veTetu = IVeTetu(_veTetu);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyGov
        override
    {}

    function initialize(
        address _initialGov, 
        address _tetuRewardsDistributor,
        address _snapshotDelegator,
        address _tetuVoter,
        address _tetuPlatformVoter
    ) public initializer {
        __Governable_init(_initialGov);
        __UUPSUpgradeable_init();

        tetuRewardsDistributor = ITetuRewardsDistributor(_tetuRewardsDistributor);
        snapshotDelegator = ISnapshotDelegator(_snapshotDelegator);
        tetuVoter = ITetuVoter(_tetuVoter);
        tetuPlatformVoter = ITetuPlatformVoter(_tetuPlatformVoter);
    }

    // **************** //
    // Setter Functions //
    // **************** //

    /// @notice Set the snapshot delegate registry address
    function setSnapshotDelegator(address _delegator) external onlyGov {
        if (_delegator == address(0)) revert CommonEventsAndErrors.InvalidAddress(_delegator);
        snapshotDelegator = ISnapshotDelegator(_delegator);
        emit SnapshotDelegatorSet(_delegator);
    }

    /// @notice Set the TETU rewards distributor address
    function setTetuRewardsDistributor(address _distributor) external onlyGov {
        if (_distributor == address(0)) revert CommonEventsAndErrors.InvalidAddress(_distributor);
        tetuRewardsDistributor = ITetuRewardsDistributor(_distributor);
        emit TetuRewardsDistributorSet(_distributor);
    }

    /// @notice Set the TETU Voter address
    function setTetuVoter(address _tetuVoter) external onlyGov {
        if (_tetuVoter == address(0)) revert CommonEventsAndErrors.InvalidAddress(_tetuVoter);
        tetuVoter = ITetuVoter(_tetuVoter);
        emit TetuVoterSet(_tetuVoter);
    }

    /// @notice Set the TETU Platform Voter address
    function setTetuPlatformVoter(address _tetuPlatformVoter) external onlyGov {
        if (_tetuPlatformVoter == address(0)) revert CommonEventsAndErrors.InvalidAddress(_tetuPlatformVoter);
        tetuPlatformVoter = ITetuPlatformVoter(_tetuPlatformVoter);
        emit TetuPlatformVoterSet(_tetuPlatformVoter);
    }

    function addOperator(address _address) external override onlyGov {
        _addOperator(_address);
    }

    function removeOperator(address _address) external override onlyGov {
        _removeOperator(_address);
    }

    // *********** //
    //    veTetu   //
    // *********** // 

    /// @notice Deposit tokens into veTetu and receive an NFT
    /// @dev Staking tokens should first be sent to this address
    function createLock(address _token, uint256 _value, uint256 _lockDuration) external onlyOperators returns (uint256) {
        emit CreatedLock(_token, _value, _lockDuration);
        IERC20Upgradeable(_token).safeIncreaseAllowance(address(veTetu), _value);
        return veTetu.createLock(_token, _value, _lockDuration);
    }

    /// @notice Increase the staked tokens for a given veTetu id
    /// @dev Staking tokens should first be sent to this address
    function increaseAmount(address _token, uint256 _tokenId, uint256 _value) external onlyOperators {
        emit IncreaseAmount(_token, _tokenId, _value);
        IERC20Upgradeable(_token).safeIncreaseAllowance(address(veTetu), _value);
        veTetu.increaseAmount(_token, _tokenId, _value);
    }

    /// @notice Increase the unlock time for a given veTetu. 
    /// @dev This will increase voting power
    function increaseUnlockTime(uint256 _tokenId, uint256 _lockDuration) external onlyOperators {
        emit IncreaseUnlockTime(_tokenId, _lockDuration);
        veTetu.increaseUnlockTime(_tokenId, _lockDuration);
    }

    /// @notice Withdraw staking tokens from an expired veTetu token
    /// @dev Sends the tokens to receiver
    function withdraw(address _stakingToken, uint256 _tokenId, address _receiver) external onlyOperators returns (uint256) {
        uint256 lockedAmount = veTetu.lockedAmounts(_tokenId, _stakingToken);
        emit Withdraw(_stakingToken, _tokenId, lockedAmount, _receiver);
        veTetu.withdraw(_stakingToken, _tokenId);

        if (_receiver != address(this)) {
            IERC20Upgradeable(_stakingToken).safeTransfer(_receiver, lockedAmount);
        }

        return lockedAmount;
    }

    /// @notice Withdraw all staking tokens from an expired veTetu token
    /// @dev Sends the tokens to receiver
    function withdrawAll(uint256 _tokenId, address _receiver) external onlyOperators returns (uint256[] memory) {
        emit WithdrawAll(_tokenId, _receiver);

        // Get the balances of the existing locks
        uint256 tokensLength = veTetu.tokensLength();
        uint256[] memory lockedAmounts = new uint256[](tokensLength);
        address[] memory tokens = new address[](tokensLength);
        uint256 i;
        for (; i < tokensLength; ++i) {
            tokens[i] = veTetu.tokens(i);
            lockedAmounts[i] = veTetu.lockedAmounts(_tokenId, tokens[i]);
        }

        // Do the withdrawal
        veTetu.withdrawAll(_tokenId);

        // Send to the receiver
        if (_receiver != address(this)) {
            for (i=0; i < tokensLength; ++i) {
                IERC20Upgradeable(tokens[i]).safeTransfer(_receiver, lockedAmounts[i]);
            }
        }

        return lockedAmounts;
    }

    /// @notice Merge `_id1` veTetu NFT into `_id2`
    function merge(uint256 _id1, uint256 _id2) external onlyOperators {
        emit Merge(_id1, _id2);
        veTetu.merge(_id1, _id2);
    }

    /// @notice Split a veTetu into two
    function split(uint256 _tokenId, uint256 _percent) external onlyOperators {
        emit Split(_tokenId, _percent);
        veTetu.split(_tokenId, _percent);
    }

    /// @notice The amount locked of `_stakingToken` for a given `_tokenId`
    function veTetuLockedAmountOf(uint256 _tokenId, address _stakingToken) external view returns (uint256) {
        return veTetu.lockedAmounts(_tokenId, _stakingToken);
    }
    
    /// @notice Get the current total locked amount across all veTetu tokens this proxy owns
    function veTetuLockedAmount(address _stakingToken) external view returns (uint256) {
        uint256 amount;
        uint256 numTokens = IERC20Upgradeable(address(veTetu)).balanceOf(address(this));
        uint256 tokenId;
        for (uint256 i; i < numTokens; ++i) {
            tokenId = veTetu.tokenOfOwnerByIndex(address(this), i);
            amount += veTetu.lockedAmounts(tokenId, _stakingToken);
        }

        return amount;
    }

    /// @notice The unlock date for a `_tokenId`
    function veTetuLockedEnd(uint256 _tokenId) external view returns (uint256) {
        return veTetu.lockedEnd(_tokenId);
    }

    /// @notice Get the current veTetu voting balance across a particular token id
    function veTetuVotingBalanceOf(uint256 _tokenId) external view returns (uint256) {
        return veTetu.balanceOfNFTAt(_tokenId, block.timestamp);
    }

    /// @notice Get the current total veTetu voting balance across all NFS this proxy owns
    function veTetuVotingBalance() external view returns (uint256) {
        uint256 totalVotingPower;
        uint256 numTokens = IERC20Upgradeable(address(veTetu)).balanceOf(address(this));
        uint256 tokenId;
        for (uint256 i; i < numTokens; ++i) {
            tokenId = veTetu.tokenOfOwnerByIndex(address(this), i);
            totalVotingPower += veTetu.balanceOfNFTAt(tokenId, block.timestamp);
        }

        return totalVotingPower;
    }

    /// @notice Calculate total veTetu voting supply, as of now.
    function totalVeTetuVotingSupply() external view returns (uint256) {
        return veTetu.totalSupplyAtT(block.timestamp);
    }

    // ************** //
    // veTetu Rewards //
    // ************** //

    /// @notice Claim rewards for a veTetu token. 
    /// @dev Reward tokens are automatically staked back into the veTetu
    function claimVeTetuRewards(uint256 _tokenId) external onlyOperators returns (uint256 amount) {
        amount = tetuRewardsDistributor.claim(_tokenId);
        emit ClaimVeTetuRewards(_tokenId, amount);
    }

    /// @notice Claim rewards for a set of veTetu tokens. 
    /// @dev Reward tokens are automatically staked back into the veTetu
    function claimManyVeTetuRewards(uint256[] memory _tokenIds) external onlyOperators returns (bool) {
        emit ClaimManyVeTetuRewards(_tokenIds);
        return tetuRewardsDistributor.claimMany(_tokenIds);
    }

    /// @notice The current claimable rewards from a veTetu token
    /// @dev Note may be stale if vetetu.checkpoint() hasn't been called recently.
    function claimableVeTetuRewards(uint256 _tokenId) external view returns (uint256) {
        return tetuRewardsDistributor.claimable(_tokenId);
    }

    // ****************** //
    //   veTetu Voting   //
    // ***************** //

    /// @notice Set the delegate for snapshot governance voting.
    /// @dev Governance voting happens on snapshot offchain, which can be delegated to another contract/EOA
    function setDelegate(bytes32 _id, address _delegate) external onlyOperators {
        emit SetDelegate(_delegate);
        snapshotDelegator.setDelegate(_id, _delegate);
    }

    /// @notice Clear the delegate for snapshot governance voting.
    function clearDelegate(bytes32 _id) external onlyOperators {
        emit ClearDelegate();
        snapshotDelegator.clearDelegate(_id);
    } 

    /// @notice Use voting power to vote for a particular TETU vault
    function vote(uint256 tokenId, address[] calldata _vaultVotes, int256[] calldata _weights) external onlyOperators {
        emit Voted(tokenId);
        tetuVoter.vote(tokenId, _vaultVotes, _weights);
    }

    /// @notice Revoke the vote for a particular veTetu token.
    function resetVote(uint256 tokenId) external onlyOperators {
        emit ResetVote(tokenId);
        tetuVoter.reset(tokenId);
    }

    // ********************* //
    // veTetu Platform Voter //
    // ********************* //

    /// @dev Vote for multiple attributes in one call.
    function platformVoteBatch(
        uint256 _tokenId,
        ITetuPlatformVoter.AttributeType[] calldata _types,
        uint256[] calldata _values,
        address[] calldata _targets
    ) external onlyOperators {
        emit PlatformVoteBatch(_tokenId);
        tetuPlatformVoter.voteBatch(
            _tokenId,
            _types,
            _values,
            _targets
        );
    }

    /// @dev Vote for given parameter using a vote power of given tokenId. Reset previous vote.
    function platformVote(uint256 _tokenId, ITetuPlatformVoter.AttributeType _type, uint256 _value, address _target) external onlyOperators {
        emit PlatformVote(_tokenId);
        tetuPlatformVoter.vote(_tokenId, _type, _value, _target);
    }

    /// @dev Remove all votes for given tokenId.
    function platformResetVote(uint256 _tokenId, uint256[] memory _types, address[] memory _targets) external onlyOperators {
        emit PlatformVoteReset(_tokenId);
        tetuPlatformVoter.reset(_tokenId, _types, _targets);
    }

    // **************** //
    //   Admin Control  //
    // **************** //

    /// @notice Transfer a token to a designated address.
    /// @dev This can be used to recover tokens, but also to transfer staked $sdToken gauge tokens, reward tokens to the DAO/another address/HW/etc
    function transferToken(address _token, address _to, uint256 _amount) external onlyOperators {
        emit TokenTransferred(_token, _to, _amount);
        IERC20Upgradeable(_token).safeTransfer(_to, _amount);
    }

    /// @notice Increase an allowance such that a spender can pull a token. 
    /// @dev Required for future integration such that contracts can pull the staked $sdToken gauge tokens, reward tokens, etc.
    function increaseTokenAllowance(address _token, address _spender, uint256 _amount) external onlyOperators {
        IERC20Upgradeable(_token).safeIncreaseAllowance(_spender, _amount);
    }

    /// @notice Decrease an allowance.
    function decreaseTokenAllowance(address _token, address _spender, uint256 _amount) external onlyOperators {
        IERC20Upgradeable(_token).safeDecreaseAllowance(_spender, _amount);
    }

    /// @notice Transfer an NFT tokenId to a designated address.
    /// @dev Required to transfer veTetu NFTs DAO/another address/HW/etc
    function transferVeTetu(address _to, uint256 _tokenId) external onlyOperators {
        emit VeTetuTransferred(_to, _tokenId);
        veTetu.safeTransferFrom(address(this), _to, _tokenId);
    }

    /// @notice Gives permission to to to transfer tokenId NFT to another account. The approval is cleared when the token is transferred.
    /// @dev Required for future integration such that contracts can pull the veTetu NFTs
    function approveVeTetu(address _spender, uint256 _tokenId) external onlyOperators {
        veTetu.approve(_spender, _tokenId);
    }

    /// @notice Approve or remove operator as an operator for the caller for all token id's
    /// @dev Required for future integration such that contracts can pull the veTetu NFTs
    function setVeTetuApprovalForAll(address _spender, bool _approved) external onlyOperators {
        veTetu.setApprovalForAll(_spender, _approved);
    }

    /// @notice Callback to receive veTETU ERC721's
    /// @dev Will reject any other ERC721's
    function onERC721Received(address /*operator*/, address /*from*/, uint256 tokenId, bytes calldata /*data*/) external returns (bytes4) {
        if (msg.sender != address(veTetu)) revert CommonEventsAndErrors.InvalidToken(msg.sender);
        emit VeTetuNFTReceived(tokenId);
        return IERC721ReceiverUpgradeable.onERC721Received.selector;
    }
}
