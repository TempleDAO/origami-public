pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/sky/OrigamiSuperSavingsUsdsManager.sol)

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IOrigamiDelegated4626Vault } from "contracts/interfaces/investments/erc4626/IOrigamiDelegated4626Vault.sol";
import { IOrigamiDelegated4626VaultManager } from "contracts/interfaces/investments/erc4626/IOrigamiDelegated4626VaultManager.sol";

import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiManagerPausable } from "contracts/investments/util/OrigamiManagerPausable.sol";

contract DummyDelegated4626VaultManager is 
    IOrigamiDelegated4626VaultManager,
    OrigamiElevatedAccess,
    OrigamiManagerPausable
{
    using SafeERC20 for IERC20;
    using OrigamiMath for uint256;

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    IOrigamiDelegated4626Vault public immutable vault;

    /// @dev The Sky USDS contract. Use asset() for the getter    
    IERC20 private immutable _asset;

    /// @dev Used to deposit/withdraw max possible.
    uint256 private constant MAX_AMOUNT = type(uint256).max;

    uint48 public performanceFeeBps;

    address public feeCollector;
    

    constructor(
        address _initialOwner,
        address _vault,
        uint48 performanceFeeBps_,
        address feeCollector_
    ) 
        OrigamiElevatedAccess(_initialOwner)
    {
        vault = IOrigamiDelegated4626Vault(_vault);
        _asset = IERC20(vault.asset());

        if (performanceFeeBps_ > OrigamiMath.BASIS_POINTS_DIVISOR) revert CommonEventsAndErrors.InvalidParam();
        performanceFeeBps = performanceFeeBps_;
        feeCollector = feeCollector_;

    }

    function setPerformanceFee(uint48 feeBps) external onlyElevatedAccess {
        if (feeBps > OrigamiMath.BASIS_POINTS_DIVISOR) revert CommonEventsAndErrors.InvalidParam();

        // Note: Depending on the vault implementation, it may need to override in order
        // to collect fees up to now on the old performance fee, before updating to the new.
        emit PerformanceFeeSet(feeBps);
        performanceFeeBps = feeBps;
    }

    // /// @inheritdoc IOrigamiDelegated4626Vault
    // function setFeeCollector(address _feeCollector) external override onlyElevatedAccess {
    //     if (_feeCollector == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
    //     emit FeeCollectorSet(_feeCollector);
    //     feeCollector = _feeCollector;
    // }


    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function deposit(uint256 /*assetsAmount*/) external override view onlyVault returns (uint256 /*usdsDeposited*/) {
        if (_paused.investmentsPaused) revert CommonEventsAndErrors.IsPaused();
        return _asset.balanceOf(address(this)); // This is incorrect, but fine for dummy
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function withdraw(
        uint256 usdsAmount,
        address receiver
    ) external override onlyVault returns (uint256 /*usdsWithdrawn*/) {
        if (_paused.exitsPaused) revert CommonEventsAndErrors.IsPaused();

        _asset.safeTransfer(receiver, usdsAmount);
        return usdsAmount;
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function asset() external override view returns (address) {
        return address(_asset);
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function totalAssets() external override view returns (uint256 /*totalManagedAssets*/) {
        return _asset.balanceOf(address(this));
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function areDepositsPaused() external virtual override view returns (bool) {
        return _paused.investmentsPaused;
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function areWithdrawalsPaused() external virtual override view returns (bool) {
        return _paused.exitsPaused;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public override pure returns (bool) {
        return interfaceId == type(IOrigamiDelegated4626VaultManager).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    modifier onlyVault() {
        if (msg.sender != address(vault)) revert CommonEventsAndErrors.InvalidAccess();
        _;
    }
}
