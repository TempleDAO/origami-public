pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (contracts/factories/staking/OrigamiAutoStakingFactory.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IOrigamiAutoStakingFactory } from "contracts/interfaces/factories/infrared/autostaking/IOrigamiAutoStakingFactory.sol";
import { IOrigamiAutoStaking } from "contracts/interfaces/investments/staking/IOrigamiAutoStaking.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";

import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiAutoStakingToErc4626Deployer } from "contracts/factories/staking/OrigamiAutoStakingToErc4626Deployer.sol";
import { OrigamiAutoStakingToErc4626 } from "contracts/investments/staking/OrigamiAutoStakingToErc4626.sol";
import { OrigamiSwapperWithCallbackDeployer } from "contracts/factories/swappers/OrigamiSwapperWithCallbackDeployer.sol";
import { OrigamiSwapperWithCallback } from "contracts/common/swappers/OrigamiSwapperWithCallback.sol";

/// @title Origami Infrared Auto Staking Factory
/// @notice Provides core functionalities for registering new Auto Staking vaults
contract OrigamiAutoStakingFactory is IOrigamiAutoStakingFactory, OrigamiElevatedAccess {
    using SafeERC20 for IERC20;

    /// @dev Mapping of staking token to a set of vault versions
    /// The first vault starts at index 0 in the list, and only increases if migrateVault()
    /// needs to be called.
    /// The versions are maintained on-chain in order for dapps to iterate through all past
    /// and current versions, since there may be passive TVL still in old vaults.
    mapping(address asset => address[] vaultVersions) internal _vaultRegistry;

    /// @inheritdoc IOrigamiAutoStakingFactory
    address public override feeCollector;

    /// @inheritdoc IOrigamiAutoStakingFactory
    uint96 public override rewardsDuration;

    /// @inheritdoc IOrigamiAutoStakingFactory
    address public override vaultDeployer;

    /// @inheritdoc IOrigamiAutoStakingFactory
    address public override swapperDeployer;

    constructor(
        address initialOwner_,
        address vaultDeployer_,
        address feeCollector_,
        uint96 rewardsDuration_,
        address swapperDeployer_
    ) OrigamiElevatedAccess(initialOwner_) {
        _updateRewardsDuration(rewardsDuration_);
        _updateFeeCollector(feeCollector_);
        vaultDeployer = vaultDeployer_;
        swapperDeployer = swapperDeployer_;
    }

    /// @inheritdoc IOrigamiAutoStakingFactory
    function registerVault(
        address asset_,
        address rewardsVault_,
        uint256 performanceFeeBps_,
        address overlord_,
        address[] calldata expectedSwapRouters_
    ) external override onlyElevatedAccess returns (IOrigamiAutoStaking deployedVault) {
        _validateNewVault(asset_, rewardsVault_);

        // If the swapper deployer is set, then deploy a new one
        address _swapperDeployer = swapperDeployer;
        OrigamiSwapperWithCallback swapper = (_swapperDeployer == address(0))
            ? OrigamiSwapperWithCallback(address(0))
            : OrigamiSwapperWithCallbackDeployer(_swapperDeployer).deploy(
                address(this)
            );

        // NB Any deployer could be used for the vault or swapper, as long as the interface to deploy()
        // remains the same as this.
        // If for whatever chance a different interface is required, a vault can be created externally
        // and registered manually via `manualRegistration()` below.
        OrigamiAutoStakingToErc4626 vault = OrigamiAutoStakingToErc4626Deployer(vaultDeployer).deploy({
            owner: address(this),
            stakingToken: asset_,
            rewardsVault: rewardsVault_,
            performanceFeeBps: performanceFeeBps_,
            feeCollector: feeCollector,
            rewardsDuration: rewardsDuration,
            swapper: address(swapper)
        });

        _vaultRegistry[asset_].push(address(vault));

        if (address(swapper) != address(0)) {
            IOrigamiElevatedAccess.ExplicitAccess[] memory access = new IOrigamiElevatedAccess.ExplicitAccess[](1);
            access[0] = IOrigamiElevatedAccess.ExplicitAccess(OrigamiSwapperWithCallback.execute.selector, true);
            swapper.setExplicitAccess(overlord_, access);
    
            for (uint256 i; i < expectedSwapRouters_.length; ++i) {
                swapper.whitelistRouter(expectedSwapRouters_[i], true);
            }
            swapper.proposeNewOwner(owner);
        }

        vault.proposeNewOwner(owner);
        emit VaultCreated(address(vault), asset_, address(swapper));
        return vault;
    }

    /// @inheritdoc IOrigamiAutoStakingFactory
    function manualRegisterVault(address asset, address vault) external override onlyElevatedAccess {
        _validateNewVault(asset, vault);
        if (IOrigamiAutoStaking(vault).stakingToken() != asset) revert CommonEventsAndErrors.InvalidToken(asset);

        _vaultRegistry[asset].push(vault);
        emit VaultCreated(address(vault), asset, IOrigamiAutoStaking(vault).swapper());
    }

    /// @inheritdoc IOrigamiAutoStakingFactory
    function migrateVault(address asset, address newVault) external override onlyElevatedAccess {
        (address oldVault, uint256 oldVersion) = currentVaultForAsset(asset);

        if (oldVersion == 0) revert NotRegistered();
        if (newVault == oldVault) revert CommonEventsAndErrors.InvalidAddress(newVault);
        if (IOrigamiAutoStaking(newVault).stakingToken() != asset) revert CommonEventsAndErrors.InvalidToken(asset);

        _vaultRegistry[asset].push(newVault);
        emit VaultMigrated(oldVault, newVault, asset);
    }

    /// @inheritdoc IOrigamiAutoStakingFactory
    function setVaultDeployer(address deployer) external onlyElevatedAccess {
        emit VaultDeployerSet(deployer);
        vaultDeployer = deployer;
    }

    /// @inheritdoc IOrigamiAutoStakingFactory
    function setSwapperDeployer(address deployer) external onlyElevatedAccess {
        emit SwapperDeployerSet(deployer);
        swapperDeployer = deployer;
    }

    /// @inheritdoc IOrigamiAutoStakingFactory
    function updateRewardsDuration(uint96 _rewardsDuration) external override onlyElevatedAccess {
        _updateRewardsDuration(_rewardsDuration);
    }

    /// @inheritdoc IOrigamiAutoStakingFactory
    function updateFeeCollector(address _feeCollector) external override onlyElevatedAccess {
        _updateFeeCollector(_feeCollector);
    }

    /// @inheritdoc IOrigamiAutoStakingFactory
    function recoverToken(address token, address to, uint256 amount) external override onlyElevatedAccess {
        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc IOrigamiAutoStakingFactory
    function proposeNewOwner(address _contract, address _account) external override onlyElevatedAccess {
        IOrigamiElevatedAccess(_contract).proposeNewOwner(_account);
    }
    
    /// @inheritdoc IOrigamiAutoStakingFactory
    function currentVaultForAsset(address asset) public override view returns (address vault, uint256 version) {
        address[] storage vaultVersions = _vaultRegistry[asset];

        // An invalid version (an unmapped asset) will have version=0
        // So the first valid version is 1
        version = vaultVersions.length;
        if (version != 0) {
            vault = vaultVersions[version-1];
        }
    }

    /// @inheritdoc IOrigamiAutoStakingFactory
    function allVaultsForAsset(address asset) external override view returns (address[] memory vaultVersions) {
        return _vaultRegistry[asset];
    }

    function _updateRewardsDuration(uint96 _rewardsDuration) private {
        if (_rewardsDuration == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(_rewardsDuration);
    }

    function _updateFeeCollector(address _feeCollector) private {
        if (_feeCollector == address(0)) revert CommonEventsAndErrors.InvalidAddress(_feeCollector);
        feeCollector = _feeCollector;
        emit FeeCollectorSet(_feeCollector);
    }

    function _validateNewVault(
        address asset_,
        address rewardsVault_
    ) internal view {
        if (asset_ == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        if (rewardsVault_ == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));

        // Check for duplicate staking asset address
        (, uint256 version) = currentVaultForAsset(asset_);
        if (version != 0) revert AlreadyRegistered();
    }
}
