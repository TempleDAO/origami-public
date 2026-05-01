pragma solidity ^0.8.28;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/bundler/plugins/OrigamiBundlerPluginMorphoFlash.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IMorpho } from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";
import { IMorphoFlashLoanCallback } from "@morpho-org/morpho-blue/src/interfaces/IMorphoCallbacks.sol";
import { LibBytes } from "solady/utils/LibBytes.sol";

import {
    IOrigamiBundlerPluginMorphoFlash
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginMorphoFlash.sol";
import { OrigamiBundlerPluginMultiAccess } from "contracts/common/bundler/plugins/OrigamiBundlerPluginMultiAccess.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/// @title Origami Bundler - Plugin for Morpho Flashloans
contract OrigamiBundlerPluginMorphoFlash is OrigamiBundlerPluginMultiAccess, IOrigamiBundlerPluginMorphoFlash {
    using SafeERC20 for IERC20;

    /// @inheritdoc IOrigamiBundlerPluginMorphoFlash
    IMorpho public immutable override MORPHO;

    /// @inheritdoc IOrigamiBundlerPluginMorphoFlash
    uint256 public transient override flashloanTotalAmountT;

    /// @inheritdoc IOrigamiBundlerPluginMorphoFlash
    /// @dev Morpho does not have fees on flashloans
    uint256 public constant override flashloanFeeBps = 0;

    constructor(address _initialOwner, address _morpho) OrigamiBundlerPluginMultiAccess(_initialOwner) {
        MORPHO = IMorpho(_morpho);
    }

    /****** BUNDLER PLUGIN ACTIONS ******/

    /// @inheritdoc IOrigamiBundlerPluginMorphoFlash
    function flashLoan(address token, uint256 amount, bytes calldata params) external override withApprovedBundler {
        // Encode packed to avoid memory copies later.
        // `token` is fixed size of 20 bytes, so params always starts at index 20 (0x14)
        bytes memory paramsWithToken = abi.encodePacked(token, params);

        MORPHO.flashLoan(token, amount, paramsWithToken);
    }

    /****** MORPHO CALLBACKS ******/

    /// @inheritdoc IMorphoFlashLoanCallback
    function onMorphoFlashLoan(uint256 flashLoanAmount, bytes calldata params) external override {
        address _morpho = address(MORPHO);
        // Can only be called by the Morpho pool, and the FL can only ever be initiated by this contract.
        if (msg.sender != _morpho) revert CommonEventsAndErrors.InvalidAccess();

        // Token is the first 20 bytes
        IERC20 token = IERC20(address(bytes20(LibBytes.loadCalldata(params, 0x00))));
        // The reenterData is the remainer, using sliceCalldata. It correctly clamps to the
        // length of params, so no need for extra bounds check
        bytes calldata reenterData = LibBytes.sliceCalldata(params, 0x14);

        uint256 _prevAmount = flashloanTotalAmountT;
        flashloanTotalAmountT = flashLoanAmount;

        _reenterBundle(reenterData);

        if (token.balanceOf(address(this)) < flashLoanAmount) {
            revert CommonEventsAndErrors.InsufficientBalance(
                address(token), flashLoanAmount, token.balanceOf(address(this))
            );
        }

        flashloanTotalAmountT = _prevAmount;

        // Morpho's allowance is not reset to zero, as it is trusted from this plugin.
        if (token.allowance(address(this), _morpho) < flashLoanAmount) {
            token.forceApprove(_morpho, type(uint256).max);
        }
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
            || interfaceId == type(IMorphoFlashLoanCallback).interfaceId
            || interfaceId == type(IOrigamiBundlerPluginMorphoFlash).interfaceId;
    }
}
