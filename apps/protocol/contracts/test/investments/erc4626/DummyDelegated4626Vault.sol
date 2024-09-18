pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/erc4626/OrigamiDelegated4626Vault.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IOrigamiErc4626 } from "contracts/interfaces/common/IOrigamiErc4626.sol";
import { OrigamiErc4626 } from "contracts/common/OrigamiErc4626.sol";
import { IOrigamiDelegated4626Vault } from "contracts/interfaces/investments/erc4626/IOrigamiDelegated4626Vault.sol";
import { DummyDelegated4626VaultManager } from "contracts/test/investments/erc4626/DummyDelegated4626VaultManager.sol";

import { ITokenPrices } from "contracts/interfaces/common/ITokenPrices.sol";

import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

/**
 * @title Origami Delegated ERC-4626 Vault
 * @notice The logic to utilize the underlying asset on deposits/exits 
 * is delegated to a manager.
 */
contract DummyDelegated4626Vault is 
    OrigamiErc4626,
    IOrigamiDelegated4626Vault
{
    using SafeERC20 for IERC20;

    DummyDelegated4626VaultManager private _manager;

    /// @inheritdoc IOrigamiDelegated4626Vault
    ITokenPrices public override tokenPrices;

    uint16 private _depositFeeBps;

    uint16 private _withdrawalFeeBps;

    uint224 private _maxTotalSupply;

    constructor(
        address initialOwner_,
        string memory name_,
        string memory symbol_,
        IERC20 asset_,
        address tokenPrices_,
        uint224 maxTotalSupply_
    ) 
        OrigamiErc4626(initialOwner_, name_, symbol_, asset_)
    {
        tokenPrices = ITokenPrices(tokenPrices_);
        _maxTotalSupply = maxTotalSupply_;
    }

    /// @inheritdoc IOrigamiDelegated4626Vault
    function setManager(address newManager) external override onlyElevatedAccess {
        if (newManager == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        emit ManagerSet(newManager);
        _manager = DummyDelegated4626VaultManager(newManager);
    }

    function setMaxTotalSupply(uint224 maxTotalSupply_) external onlyElevatedAccess {
        _maxTotalSupply = maxTotalSupply_;
        emit MaxTotalSupplySet(maxTotalSupply_);
    }

    /// @inheritdoc IOrigamiDelegated4626Vault
    function setTokenPrices(address _tokenPrices) external override onlyElevatedAccess {
        if (_tokenPrices == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        emit TokenPricesSet(_tokenPrices);
        tokenPrices = ITokenPrices(_tokenPrices);
    }

    function setFeesBps(
        uint16 depositFeeBps_, 
        uint16 withdrawalFeeBps_
    ) external onlyElevatedAccess {
        if (depositFeeBps_ > OrigamiMath.BASIS_POINTS_DIVISOR) revert CommonEventsAndErrors.InvalidParam();
        if (withdrawalFeeBps_ > OrigamiMath.BASIS_POINTS_DIVISOR) revert CommonEventsAndErrors.InvalidParam();
        emit FeeBpsSet(FeeType.DEPOSIT_FEE, depositFeeBps_);
        _depositFeeBps = depositFeeBps_;
        emit FeeBpsSet(FeeType.WITHDRAWAL_FEE, withdrawalFeeBps_);
        _withdrawalFeeBps = withdrawalFeeBps_;
    }

    /// @inheritdoc IOrigamiDelegated4626Vault
    function manager() external override view returns (address) {
        return address(_manager);
    }

    /// @inheritdoc IOrigamiDelegated4626Vault
    function performanceFeeBps() external override view returns (uint48) {
        return _manager.performanceFeeBps();
    }

    /// @inheritdoc IOrigamiErc4626
    function depositFeeBps() public override(IOrigamiErc4626, OrigamiErc4626) view returns (uint256) {
        return _depositFeeBps;
    }

    /// @inheritdoc IOrigamiErc4626
    function withdrawalFeeBps() public override(IOrigamiErc4626, OrigamiErc4626) view returns (uint256) {
        return _withdrawalFeeBps;
    }

    /// @inheritdoc IOrigamiErc4626
    function maxTotalSupply() public override(IOrigamiErc4626, OrigamiErc4626) view returns (uint256) {
        return _maxTotalSupply;
    }

    /// @inheritdoc IERC4626
    function totalAssets() public view override(IERC4626, OrigamiErc4626) returns (uint256) {
        return _manager.totalAssets();
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public override(IERC165, OrigamiErc4626) pure returns (bool) {
        return interfaceId == type(IOrigamiDelegated4626Vault).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /// @dev Pull freshly deposited sUSDS and deposit into the manager
    function _depositHook(address caller, uint256 assets) internal override {
        SafeERC20.safeTransferFrom(_asset, caller, address(_manager), assets);
        _manager.deposit(type(uint256).max);
    }

    /// @dev Pull sUSDS from the manager which also sends to the receiver
    function _withdrawHook(
        uint256 assets,
        address receiver
    ) internal override {
        _manager.withdraw(assets, receiver);
    }
}
