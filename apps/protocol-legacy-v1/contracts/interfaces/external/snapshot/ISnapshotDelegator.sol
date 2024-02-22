pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/snapshot/ISnapshotDelegator.sol)

interface ISnapshotDelegator {
    function setDelegate(bytes32 id, address delegate) external;
    function clearDelegate(bytes32 id) external;
    function delegation(address from, bytes32 id) external view returns (address);
}
