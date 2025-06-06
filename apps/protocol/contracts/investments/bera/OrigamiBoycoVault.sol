pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/bera/OrigamiBoycoVault.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { OrigamiDelegated4626Vault } from "contracts/investments/OrigamiDelegated4626Vault.sol";
import { OrigamiErc4626 } from "contracts/common/OrigamiErc4626.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

/**
 * @title Origami Boyco Vault
 * @notice The logic to allocate the assets is delegated to a manager
 */
contract OrigamiBoycoVault is OrigamiDelegated4626Vault
{
    using SafeERC20 for IERC20;

    constructor(
        address initialOwner_,
        string memory name_,
        string memory symbol_,
        IERC20 asset_,
        address tokenPrices_
    ) 
        OrigamiDelegated4626Vault(initialOwner_, name_, symbol_, asset_, tokenPrices_)
    {
    }

    /// @dev Send new deposits into the manager
    function _depositHook(address caller, uint256 assets) internal override {
        SafeERC20.safeTransferFrom(_asset, caller, address(_manager), assets);
        _manager.deposit(assets);
    }

    /// @inheritdoc OrigamiErc4626
    function _maxWithdraw(
        address sharesOwner, 
        uint256 feeBps
    ) internal override view returns (uint256 maxAssets) {
        uint256 userAvailableAssets = super._maxWithdraw(sharesOwner, feeBps);

        // Cap the amount available to the actual assets available in the manager as of now.
        uint256 globalAvailableAssets = _manager.unallocatedAssets();
        maxAssets = userAvailableAssets < globalAvailableAssets ? userAvailableAssets : globalAvailableAssets;
    }

    /// @inheritdoc OrigamiErc4626
    function _maxRedeem(
        address sharesOwner
    ) internal override view returns (uint256 maxShares) {
        uint256 userAvailableShares = super._maxRedeem(sharesOwner);

        // Cap the amount of shares available based on the actual assets available in the manager as of now.
        // Fees for this vault are always zero so no need to account for them.
        // Round up - since previewRedeem rounds that number of shares down into the assets.
        uint256 globalAvailableShares = _convertToShares(_manager.unallocatedAssets(), OrigamiMath.Rounding.ROUND_UP);
        maxShares = userAvailableShares < globalAvailableShares ? userAvailableShares : globalAvailableShares;
    }
     
    /// @inheritdoc OrigamiErc4626
    function recoverToken(address token, address to, uint256 amount) external override onlyElevatedAccess {
        // The asset token is sent straight to the manager on deposit/withdraw - so it's acceptable to recover from here.
        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }
}
