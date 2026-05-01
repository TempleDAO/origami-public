pragma solidity ^0.8.28;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/bundler/plugins/OrigamiBundlerPluginAaveV3Flash.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { IFlashLoanReceiver } from "@aave/core-v3/contracts/misc/flashloan/interfaces/IFlashLoanReceiver.sol";
import { DataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

import {
    IOrigamiBundlerPluginAaveV3Flash
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginAaveV3Flash.sol";
import { OrigamiBundlerPluginMultiAccess } from "contracts/common/bundler/plugins/OrigamiBundlerPluginMultiAccess.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/// @title Origami Bundler - Plugin for Aave V3 Flashloans
contract OrigamiBundlerPluginAaveV3Flash is OrigamiBundlerPluginMultiAccess, IOrigamiBundlerPluginAaveV3Flash {
    using SafeERC20 for IERC20;

    /// @inheritdoc IFlashLoanReceiver
    IPoolAddressesProvider public immutable override ADDRESSES_PROVIDER;

    /// @inheritdoc IOrigamiBundlerPluginAaveV3Flash
    uint256 public transient override flashloanTotalAmountT;

    constructor(address _initialOwner, address _aavePoolAddressProvider)
        OrigamiBundlerPluginMultiAccess(_initialOwner)
    {
        ADDRESSES_PROVIDER = IPoolAddressesProvider(_aavePoolAddressProvider);
    }

    /****** BUNDLER PLUGIN ACTIONS ******/

    /// @inheritdoc IOrigamiBundlerPluginAaveV3Flash
    function flashLoan(address token, uint256 amount, uint16 referralCode, bytes calldata params)
        external
        override
        withApprovedBundler
    {
        if (amount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        address[] memory tokens = new address[](1);
        tokens[0] = token;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        uint256[] memory modes = new uint256[](1);
        // Never opens a borrow position immediately after the FL, always repay it immediately
        modes[0] = uint256(DataTypes.InterestRateMode.NONE);

        POOL().flashLoan(address(this), tokens, amounts, modes, address(this), params, referralCode);
    }

    /****** AAVE CALLBACKS ******/

    /// @inheritdoc IFlashLoanReceiver
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata fees,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        // Can only be called by the Aave POOL, and the flashloan can only ever be initiated by this contract.
        address _pool = address(POOL());
        if (msg.sender != _pool) revert CommonEventsAndErrors.InvalidAccess();
        if (initiator != address(this)) revert CommonEventsAndErrors.InvalidAddress(initiator);
        if (assets.length != 1 || amounts.length != 1 || fees.length != 1) {
            revert CommonEventsAndErrors.InvalidLength();
        }

        uint256 requiredToRepay = amounts[0] + fees[0];

        // Utilise transient storage to set the flashloan amount and fee
        // such that reentered calls know what needs to be repaid to satisfy the flashloan
        // before execution ends.
        uint256 _prevTotalAmount = flashloanTotalAmountT;
        flashloanTotalAmountT = requiredToRepay;

        _reenterBundle(params);

        IERC20 asset = IERC20(assets[0]);
        if (asset.balanceOf(address(this)) < requiredToRepay) {
            revert CommonEventsAndErrors.InsufficientBalance(
                address(asset), requiredToRepay, asset.balanceOf(address(this))
            );
        }

        flashloanTotalAmountT = _prevTotalAmount;

        // Aave's allowance is not reset to zero, as it is trusted from this plugin.
        if (asset.allowance(address(this), _pool) < requiredToRepay) {
            asset.forceApprove(_pool, type(uint256).max);
        }

        return true;
    }

    /****** VIEWS ******/

    /// @inheritdoc IFlashLoanReceiver
    function POOL() public view override returns (IPool) {
        return IPool(ADDRESSES_PROVIDER.getPool());
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        pure
        virtual
        override(IERC165, OrigamiBundlerPluginMultiAccess)
        returns (bool)
    {
        return OrigamiBundlerPluginMultiAccess.supportsInterface(interfaceId)
            || interfaceId == type(IOrigamiBundlerPluginAaveV3Flash).interfaceId;
    }

    /// @inheritdoc IOrigamiBundlerPluginAaveV3Flash
    function flashloanFeeBps() external view returns (uint256) {
        return POOL().FLASHLOAN_PREMIUM_TOTAL();
    }
}
