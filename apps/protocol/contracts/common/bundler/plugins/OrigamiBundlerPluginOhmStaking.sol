pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/bundler/plugins/OrigamiBundlerPluginOhmStaking.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

import { OrigamiBundlerPluginMultiAccess } from "contracts/common/bundler/plugins/OrigamiBundlerPluginMultiAccess.sol";
import { IOlympusStaking } from "contracts/interfaces/external/olympus/IOlympusStaking.sol";
import {
    IOrigamiBundlerPluginOhmStaking
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginOhmStaking.sol";
import { IGOHM } from "contracts/interfaces/external/olympus/IGOHM.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/// @title Origami Bundler - Plugin for OHM <--> gOHM
contract OrigamiBundlerPluginOhmStaking is OrigamiBundlerPluginMultiAccess, IOrigamiBundlerPluginOhmStaking {
    using SafeERC20 for IERC20;

    /// @inheritdoc IOrigamiBundlerPluginOhmStaking
    address public immutable override OLYMPUS_STAKING;

    /// @inheritdoc IOrigamiBundlerPluginOhmStaking
    address public immutable override OHM;

    /// @inheritdoc IOrigamiBundlerPluginOhmStaking
    address public immutable override GOHM;

    constructor(address _initialOwner, address _olympusStaking) OrigamiBundlerPluginMultiAccess(_initialOwner) {
        OLYMPUS_STAKING = _olympusStaking;
        OHM = IOlympusStaking(_olympusStaking).OHM();
        GOHM = IOlympusStaking(_olympusStaking).gOHM();

        IERC20(OHM).forceApprove(_olympusStaking, type(uint256).max);
        IERC20(GOHM).forceApprove(_olympusStaking, type(uint256).max);
    }

    /****** BUNDLER PLUGIN ACTIONS ******/

    /// @inheritdoc IOrigamiBundlerPluginOhmStaking
    function stakeToGOhm(uint256 ohmAmount, address receiver) external override withApprovedBundler {
        if (ohmAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        _stake(ohmAmount, receiver);
    }

    /// @inheritdoc IOrigamiBundlerPluginOhmStaking
    function stakeBalanceToGOhm(address receiver) external override withApprovedBundler {
        uint256 ohmAmount = IERC20(OHM).balanceOf(address(this));
        if (ohmAmount > 0) {
            _stake(ohmAmount, receiver);
        }
    }

    /// @inheritdoc IOrigamiBundlerPluginOhmStaking
    function unstakeToOhm(uint256 gOhmAmount, address receiver) external override withApprovedBundler {
        if (gOhmAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        _unstake(gOhmAmount, receiver);
    }

    /// @inheritdoc IOrigamiBundlerPluginOhmStaking
    function unstakeBalanceToOhm(address receiver) external override withApprovedBundler {
        uint256 gOhmAmount = IERC20(GOHM).balanceOf(address(this));
        if (gOhmAmount > 0) {
            _unstake(gOhmAmount, receiver);
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
            || interfaceId == type(IOrigamiBundlerPluginOhmStaking).interfaceId;
    }

    /// @inheritdoc IOrigamiBundlerPluginOhmStaking
    function stakeToGOhmQuote(uint256 ohmAmount) external view returns (uint256 gohmAmount) {
        return IGOHM(GOHM).balanceTo(ohmAmount);
    }

    /// @inheritdoc IOrigamiBundlerPluginOhmStaking
    function unstakeToOhmQuote(uint256 gOhmAmount) external view returns (uint256 ohmAmount) {
        return IGOHM(GOHM).balanceFrom(gOhmAmount);
    }

    /****** INTERNALS ******/

    function _stake(uint256 ohmAmount, address receiver) private {
        if (receiver == address(0)) revert CommonEventsAndErrors.InvalidAddress(receiver);

        // In order to stake, always use rebasing=false, claim=true
        IOlympusStaking(OLYMPUS_STAKING).stake(receiver, ohmAmount, false, true);
    }

    function _unstake(uint256 gOhmAmount, address receiver) private {
        if (receiver == address(0)) revert CommonEventsAndErrors.InvalidAddress(receiver);

        // In order to unstake, always use trigger=false, rebasing=false
        IOlympusStaking(OLYMPUS_STAKING).unstake(receiver, gOhmAmount, false, false);
    }
}
