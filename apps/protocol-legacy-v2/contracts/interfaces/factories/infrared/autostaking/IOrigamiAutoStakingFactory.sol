pragma solidity ^0.8.0;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/factories/infrared/autostaking/IOrigamiAutoStakingFactory.sol)

import { IOrigamiAutoStaking } from "contracts/interfaces/investments/staking/IOrigamiAutoStaking.sol";

/// @title Origami Auto Staking Factory
/// @notice Provides core functionalities for registering new Auto Staking vaults
interface IOrigamiAutoStakingFactory {
    error NotRegistered();
    error AlreadyRegistered();

    /**
     * @notice Emitted when a new vault is registered
     */
    event VaultCreated(
        address indexed vault,
        address indexed asset,
        address swapper
    );

    /**
     * @notice Emiited when a new vault is registered, replacing an oldVault for the same asset
     */
    event VaultMigrated(
        address indexed oldVault,
        address indexed newVault,
        address indexed asset
    );

    /**
     * @notice Emitted when the rewards duration is updated
     */
    event RewardsDurationUpdated(uint96 rewardsDuration);

    /**
     * @notice Emitted when the fee collector is updated
     */
    event FeeCollectorSet(address indexed feeCollector);

    /**
     * @notice Emitted when the vault deployer is updated
     */
    event VaultDeployerSet(address indexed deployer);

    /**
     * @notice Emitted when the swapper deployer is updated
     */
    event SwapperDeployerSet(address indexed deployer);

    /**
     * @notice Registers a new vault for a given asset
     */
    function registerVault(
        address asset_,
        address rewardsVault_,
        uint256 performanceFeeBps_,
        address overlord_,
        address[] calldata expectedSwapRouters_
    ) external returns (IOrigamiAutoStaking vault);

    /**
     * @notice Manually register an already deployed vault for a given asset
     * @dev Provided in case a variation of the deployed vault is required
     * which doesn't fit the above registration.
     */
    function manualRegisterVault(address asset, address vault) external;

    /**
     * @notice Migrate the registration for a vault for a given staking `asset` to a new vault.
     * @dev The `asset` must be registered to a vault.
     */
    function migrateVault(address asset, address newVault) external;

    /**
     * @notice Set the vault deployer for future created vaults
     */
    function setVaultDeployer(address deployer) external;

    /**
     * @notice Set the swapper deployer for future created vaults
     */
    function setSwapperDeployer(address deployer) external;

    /**
     * @notice Sets the new duration for reward distributions in rewards vault
     * @param _rewardsDuration The new reward duration period, in seconds
     * @dev Only callable by elevated acceess
     */
    function updateRewardsDuration(uint96 _rewardsDuration) external;

    /**
     * @notice Sets the new feeCollector for newly registered vaults
     * @dev Only callable by governance
     */
    function updateFeeCollector(address _feeCollector) external;

    /**
     * @notice Recovers ERC20 tokens sent accidentally to the contract
     */
    function recoverToken(address token, address to, uint256 amount) external;

    /**
     * @notice Propose a new owner for a registered vault or swapper,
     * if it wasn't initially claimed as expected after registration.
     */
    function proposeNewOwner(address _contract, address _account) external;

    /**
     * @notice Returns the latest active version of the Origami rewards vault address for a 
     * given staking token.
     * @dev If a vault has not been registered for this asset, then vault will be address(0)
     * and version will be 0
     * The first valid version = 1
     * @param asset The address of the staking asset
     */
    function currentVaultForAsset(address asset) external view returns (
        address vault,
        uint256 version
    );

    /**
     * @notice Returns all versions of vaults for a given staking token.
     * @param asset The address of the staking asset
     */
    function allVaultsForAsset(address asset) external view returns (
        address[] memory vaultVersions
    );

    /**
     * @notice Vault fees collector
     */
    function feeCollector() external view returns (address);

    /**
     * @notice The rewards duration
     * @dev Used as gloabl variabel to set the rewards duration for all new reward tokens on InfraredVaults
     * @return uint256 The reward duration period, in seconds
     */
    function rewardsDuration() external view returns (uint96);

    /**
     * @notice @notice The deployer for the vault
     */
    function vaultDeployer() external view returns (address);

    /**
     * @notice @notice The deployer for the swapper
     */
    function swapperDeployer() external view returns (address);
}
