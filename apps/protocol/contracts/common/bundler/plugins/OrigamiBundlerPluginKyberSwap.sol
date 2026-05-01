pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/bundler/plugins/OrigamiBundlerPluginKyberSwap.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { LibCall } from "solady/utils/LibCall.sol";

import { OrigamiBundlerPluginMultiAccess } from "contracts/common/bundler/plugins/OrigamiBundlerPluginMultiAccess.sol";
import {
    IOrigamiBundlerPluginKyberSwap
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginKyberSwap.sol";
import { IKyberScalingHelper } from "contracts/interfaces/external/kyberswap/IKyberScalingHelper.sol";

/// @title Origami Bundler - Plugin for KyberSwap
/// @dev This can handle scaling balances by a small amount at runtime.
contract OrigamiBundlerPluginKyberSwap is OrigamiBundlerPluginMultiAccess, IOrigamiBundlerPluginKyberSwap {
    using SafeERC20 for IERC20;

    /// @inheritdoc IOrigamiBundlerPluginKyberSwap
    address public immutable override ROUTER;

    /// @inheritdoc IOrigamiBundlerPluginKyberSwap
    address public immutable override SCALING_HELPER;

    constructor(address _initialOwner, address _kyberRouter, address _kyberScalingHelper)
        OrigamiBundlerPluginMultiAccess(_initialOwner)
    {
        ROUTER = _kyberRouter;
        SCALING_HELPER = _kyberScalingHelper;
    }

    /****** BUNDLER PLUGIN ACTIONS ******/

    /// @inheritdoc IOrigamiBundlerPluginKyberSwap
    function swap(address srcToken, bytes memory callData) external override withApprovedBundler {
        _swap(IERC20(srcToken), callData);
    }

    /// @inheritdoc IOrigamiBundlerPluginKyberSwap
    function swapBalance(address srcToken, bytes memory callData) external override withApprovedBundler {
        IERC20 _srcToken = IERC20(srcToken);

        // Scale the calldata by the current balance of srcToken
        {
            uint256 newSrcAmount = _srcToken.balanceOf(address(this));

            // Nothing to do - it is left to the remainder of the bundle steps to check for min amounts
            if (newSrcAmount == 0) return;

            bool isSuccess;
            (isSuccess, callData) = IKyberScalingHelper(SCALING_HELPER).getScaledInputData(callData, newSrcAmount);

            // According to docs, if the scaling fails it may return with empty calldata
            // So also explicitly check for this case, as the Kyberswap router has a receive() function so wouldn't
            // revert
            if (!isSuccess || callData.length == 0) revert ScalingFailed();
        }

        _swap(_srcToken, callData);
    }

    function _swap(IERC20 srcToken, bytes memory callData) private {
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
            || interfaceId == type(IOrigamiBundlerPluginKyberSwap).interfaceId;
    }
}
