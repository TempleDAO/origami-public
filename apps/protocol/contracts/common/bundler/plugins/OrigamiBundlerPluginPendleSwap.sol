pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/bundler/plugins/OrigamiBundlerPluginPendleSwap.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { LibCall } from "solady/utils/LibCall.sol";
import { PendleRouterScalingLib } from "pendle-router-scaling/src/PendleRouterScalingLib.sol";

import { OrigamiBundlerPluginMultiAccess } from "contracts/common/bundler/plugins/OrigamiBundlerPluginMultiAccess.sol";
import {
    IOrigamiBundlerPluginPendleSwap
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginPendleSwap.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

/// @title Origami Bundler - Plugin for swapping assets on Pendle
/// @dev This can handle scaling balances by a small amount at runtime.
contract OrigamiBundlerPluginPendleSwap is OrigamiBundlerPluginMultiAccess, IOrigamiBundlerPluginPendleSwap {
    using SafeERC20 for IERC20;
    using OrigamiMath for uint256;

    /// @inheritdoc IOrigamiBundlerPluginPendleSwap
    address public immutable override ROUTER;

    constructor(address _initialOwner, address _pendleRouter) OrigamiBundlerPluginMultiAccess(_initialOwner) {
        ROUTER = _pendleRouter;
    }

    /****** BUNDLER PLUGIN ACTIONS ******/

    /// @inheritdoc IOrigamiBundlerPluginPendleSwap
    function swap(address srcToken, bytes memory callData) external override withApprovedBundler {
        _callRouter(IERC20(srcToken), callData);
    }

    /// @inheritdoc IOrigamiBundlerPluginPendleSwap
    function swapBalance(address srcToken, bytes memory callData) external override withApprovedBundler {
        IERC20 _srcToken = IERC20(srcToken);

        // Scale the calldata by the current balance of srcToken
        uint256 newSrcAmount = _srcToken.balanceOf(address(this));

        // Nothing to do - it is left to the remainder of the bundle steps to check for min amounts
        if (newSrcAmount == 0) return;

        // Scale the calldata to the new amount - updated in place.
        // Note this will revert with UnsupportedSelector() if not supported.
        PendleRouterScalingLib.scaleCalldata(newSrcAmount, callData);
        _callRouter(_srcToken, callData);
    }

    /****** VIEWS ******/

    /// @inheritdoc IOrigamiBundlerPluginPendleSwap
    function scaleCalldata(uint256 newSrcAmount, bytes calldata callData)
        public
        pure
        override
        returns (bytes memory scaledCallData)
    {
        // Initial copy and then update in place
        scaledCallData = callData;
        PendleRouterScalingLib.scaleCalldata(newSrcAmount, scaledCallData);
    }

    /****** INTERNALS ******/

    function _callRouter(IERC20 srcToken, bytes memory callData) private {
        // Max approve the token -- the router is trusted, so doesnt need to be reset
        if (srcToken.allowance(address(this), ROUTER) < type(uint256).max) {
            srcToken.forceApprove(ROUTER, type(uint256).max);
        }

        LibCall.callContract(ROUTER, callData);
    }

    /****** VIEWS ******/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        pure
        virtual
        override(IERC165, OrigamiBundlerPluginMultiAccess)
        returns (bool)
    {
        return OrigamiBundlerPluginMultiAccess.supportsInterface(interfaceId)
            || interfaceId == type(IOrigamiBundlerPluginPendleSwap).interfaceId;
    }
}
