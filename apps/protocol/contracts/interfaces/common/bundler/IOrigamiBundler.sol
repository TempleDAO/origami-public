pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/bundler/IOrigamiBundler.sol)

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

/// @notice Struct containing all the data needed to make a call.
/// @notice The call target is `to`, the calldata is `data` with value `value`.
/// @notice If `skipRevert` is true, other planned calls will continue executing even if this call reverts. `skipRevert`
/// will ignore all reverts. Use with caution -- see below for exceptions to this behaviour.
/// @notice If the call will trigger a reenter, the callbackHash should be set to the hash of the reenter bundle data.
struct Call {
    /// @dev The address to call
    address to;

    /// @dev The function selector and calldata, empty is allowed (to send 'native' assets eg ETH)
    bytes data;

    /// @dev Any optional 'native' assets to send to `to`
    uint256 value;

    /// @dev If set to true and the call fails, it will not revert the whole transaction.
    /// There are some exceptions to this where it will always revert regardless of this flag:
    ///   - If the `to` is address(0) it will revert with `InvalidPlugin(to)`
    ///   - If the `to` is not 'approved' in the bundler implementation it will revert with `InvalidPlugin(to)`
    ///   - If there is a reentered call stack where:
    ///       - The inner reentered call reverts and has `skipRevert=false` (so the inner revert bubbles up)
    ///       - The outer call which called reenter has `skipRevert=true`
    ///     In this case the entire transaction will still revert with `MissingExpectedReenter()`
    ///     since the transient `reenterHashT` is not reset to bytes32(0)
    bool skipRevert;

    /// @dev The hash of any expected reentered call as part of this.
    /// Should be set to `keccak256(abi.encode(Call[] callbackBundle))`
    /// If no callback, set to bytes32(0)
    bytes32 callbackHash;
}

/// @title Origami Bundler
/// @notice Batch-execute a sequence of arbitrary calls atomically
/// @dev It carries specific features to be able to perform actions that require authorizations, and handle callbacks.
/// Credit to Morpho for their bundler3:
/// https://github.com/morpho-org/bundler3/tree/263f75d3662f38133d5fba1b08c7b07847abfb2a
interface IOrigamiBundler is IERC165 {
    error AlreadyInitiated();
    error EmptyBundle();
    error MissingExpectedReenter();
    error IncorrectReenterHash();
    error InvalidPlugin(address plugin);

    /// @notice The bundler implementation can optionally whitelist which addresses can be
    /// called in each multicall step.
    function isApprovedPlugin(address plugin) external view returns (bool);

    /// @notice Executes a sequence of calls.
    /// @dev
    ///   - Locks the initiator so that the sender can be identified by other contracts.
    ///   - There are some exceptions to skip reverting if a call's `skipRevert=true`.
    ///     See the natspec within the Call struct definition for details.
    /// @param bundle The ordered array of calldata to execute.
    function multicall(Call[] calldata bundle) external payable;

    /// @notice Executes a sequence of calls.
    /// @dev Useful during callbacks.
    /// @dev Can only be called by the last unreturned callee with known data.
    /// @param bundle The ordered array of calldata to execute.
    function reenter(Call[] calldata bundle) external;

    /****** TRANSIENT VIEWS ******/

    /// @notice The initiator of the multicall transaction.
    /// @dev transient
    function initiatorT() external view returns (address);

    /// @notice Hash of the concatenation of the sender and the hash of the calldata of the next call to `reenter`.
    /// @dev transient
    function reenterHashT() external view returns (bytes32);
}
