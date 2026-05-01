pragma solidity ^0.8.28;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/bundler/OrigamiBundler.sol)

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { LibCall } from "solady/utils/LibCall.sol";
import { EfficientHashLib } from "solady/utils/EfficientHashLib.sol";

import { Call, IOrigamiBundler } from "contracts/interfaces/common/bundler/IOrigamiBundler.sol";

/// @title Origami Bundler
/// @notice Batch-execute a sequence of arbitrary calls atomically
/// @dev It carries specific features to be able to perform actions that require authorizations, and handle callbacks.
/// Credit to Morpho for their bundler3:
/// https://github.com/morpho-org/bundler3/tree/263f75d3662f38133d5fba1b08c7b07847abfb2a
contract OrigamiBundler is IOrigamiBundler {
    /// @inheritdoc IOrigamiBundler
    address public transient override initiatorT;

    /// @inheritdoc IOrigamiBundler
    bytes32 public transient override reenterHashT;

    /// @inheritdoc IOrigamiBundler
    function isApprovedPlugin(
        address /*plugin*/
    )
        public
        view
        virtual
        override
        returns (bool)
    {
        // By default, any plugin is allowed
        return true;
    }

    /// @inheritdoc IOrigamiBundler
    function multicall(Call[] calldata bundle) public payable virtual {
        if (initiatorT != address(0)) revert AlreadyInitiated();

        initiatorT = msg.sender;

        _multicall(bundle);

        initiatorT = address(0);
    }

    /// @inheritdoc IOrigamiBundler
    function reenter(Call[] calldata bundle) external {
        if (
            reenterHashT
                != EfficientHashLib.hash(
                    bytes32(uint256(uint160(msg.sender))), EfficientHashLib.hashCalldata(msg.data, 4)
                )
        ) {
            revert IncorrectReenterHash();
        }

        _multicall(bundle);
        // After _multicall the value of reenterHashT is bytes32(0).
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure virtual override returns (bool) {
        return interfaceId == type(IOrigamiBundler).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /// @dev Executes a sequence of calls.
    function _multicall(Call[] calldata bundle) internal {
        if (bundle.length == 0) revert EmptyBundle();

        for (uint256 i; i < bundle.length; ++i) {
            address to = bundle[i].to;
            if (to == address(0) || !isApprovedPlugin(to)) revert InvalidPlugin(to);
            bytes32 callbackHash = bundle[i].callbackHash;

            reenterHashT = (callbackHash == bytes32(0))
                ? bytes32(0)
                : EfficientHashLib.hash(bytes32(uint256(uint160(to))), callbackHash);

            (bool success, bytes memory returnData) = to.call{ value: bundle[i].value }(bundle[i].data);
            if (!success && !bundle[i].skipRevert) {
                LibCall.bubbleUpRevert(returnData);
            }

            if (reenterHashT != bytes32(0)) revert MissingExpectedReenter();
        }
    }
}
