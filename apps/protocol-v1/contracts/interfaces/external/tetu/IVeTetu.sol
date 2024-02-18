pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/tetu/IVeTetu.sol)

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IVeTetu is IERC721 {
    // Lock
    function createLock(address _token, uint256 _value, uint256 _lockDuration) external returns (uint256);
    function increaseAmount(address _token, uint256 _tokenId, uint256 _value) external;
    function increaseUnlockTime(uint256 _tokenId, uint256 _lockDuration) external;
    function merge(uint256 _from, uint256 _to) external;
    function split(uint256 _tokenId, uint256 percent) external;
    function withdraw(address stakingToken, uint256 _tokenId) external;
    function withdrawAll(uint256 _tokenId) external;

    // Voting
    function voting(uint256 _tokenId) external;
    function abstain(uint256 _tokenId) external;

    /// @dev Current count of token
    function tokenId() external view returns (uint256);

    /// @dev veId => stakingToken => Locked amount
    function lockedAmounts(uint256 _tokenId, address _stakingToken) external view returns (uint256);

    /// @dev veId => Amount based on weights aka power
    function lockedDerivedAmount(uint256 _tokenId) external view returns (uint256);

    /// @dev veId => Lock end timestamp
    function lockedEnd(uint256 _tokenId) external view returns (uint256);

    /// @notice Get the current voting power for `_tokenId`
    function balanceOfNFTAt(uint256 _tokenId, uint256 _t) external view returns (uint256);

    /// @notice Calculate total voting power
    function totalSupplyAtT(uint256 t) external view returns (uint256);

    /// @dev Get token by index
    function tokenOfOwnerByIndex(address _owner, uint256 _tokenIndex) external view returns (uint256);

    /// @dev Whitelist address for transfers. Removing from whitelist should be forbidden.
    function whitelistTransferFor(address value) external;

    enum TimeLockType {
        UNKNOWN,
        ADD_TOKEN,
        WHITELIST_TRANSFER
    }
    function announceAction(TimeLockType _type) external;

    /// @dev Underlying staking tokens
    function tokens(uint256 i) external returns (address);

    /// @dev Return length of staking tokens.
    function tokensLength() external view returns (uint256);

    function isApprovedOrOwner(address _spender, uint _tokenId) external view returns (bool);

    function userPointEpoch(uint256 _tokenId) external view returns (uint256);

    /// @notice Record global data to checkpoint
    function checkpoint() external;

    /// @notice Get the timestamp for checkpoint `_idx` for `_tokenId`
    function userPointHistoryTs(uint _tokenId, uint _idx) external view returns (uint256);

}