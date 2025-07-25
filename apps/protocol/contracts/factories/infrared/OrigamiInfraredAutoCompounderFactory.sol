pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (factories/infrared/OrigamiInfraredAutoCompounderFactory.sol)

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IInfraredVault } from "contracts/interfaces/external/infrared/IInfraredVault.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";
import { OrigamiDelegated4626Vault } from "contracts/investments/OrigamiDelegated4626Vault.sol";
import { OrigamiInfraredVaultManager } from "contracts/investments/infrared/OrigamiInfraredVaultManager.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { OrigamiSwapperWithLiquidityManagement } from "contracts/common/swappers/OrigamiSwapperWithLiquidityManagement.sol";
import { OrigamiDelegated4626VaultDeployer } from "contracts/factories/infrared/OrigamiDelegated4626VaultDeployer.sol";
import { OrigamiInfraredVaultManagerDeployer } from "contracts/factories/infrared/OrigamiInfraredVaultManagerDeployer.sol";
import { OrigamiSwapperWithLiquidityManagementDeployer } from "contracts/factories/swappers/OrigamiSwapperWithLiquidityManagementDeployer.sol";

/**
 * @title Origami Infrared Auto-Compounder Factory
 * @notice A factory to create and register new Infrared Auto-Compounder vaults
 */
contract OrigamiInfraredAutoCompounderFactory is OrigamiElevatedAccess {
    using SafeERC20 for IERC20;

    /// @notice The fee collector address to use for future new auto-compounders
    address public feeCollector;

    /// @notice The tokenPrices contract to use for future new auto-compounders
    address public tokenPrices;

    /// @notice The deployer for the vault
    OrigamiDelegated4626VaultDeployer public vaultDeployer;

    /// @notice The deployer for the manager
    OrigamiInfraredVaultManagerDeployer public managerDeployer;

    /// @notice The deployer for the swapper
    OrigamiSwapperWithLiquidityManagementDeployer public swapperDeployer;

    /// @notice The registered vaults for a given reward vault asset
    mapping(address asset => OrigamiDelegated4626Vault vault) public registeredVaults;

    event TokenPricesSet(address indexed tokenPrices);
    event FeeCollectorSet(address indexed feeCollector);
    event ManagerDeployerSet(address indexed deployer);
    event VaultDeployerSet(address indexed deployer);
    event SwapperDeployerSet(address indexed deployer);

    event VaultCreated(
        address vault,
        address asset,
        address manager,
        address swapper
    );

    error AssetNotRegistered(address asset);

    constructor(
        address initialOwner_,
        address tokenPrices_,
        address feeCollector_,
        address vaultDeployer_,
        address managerDeployer_,
        address swapperDeployer_
    ) OrigamiElevatedAccess(initialOwner_) {
        tokenPrices = tokenPrices_;
        feeCollector = feeCollector_;
        vaultDeployer = OrigamiDelegated4626VaultDeployer(vaultDeployer_);
        managerDeployer = OrigamiInfraredVaultManagerDeployer(managerDeployer_);
        swapperDeployer = OrigamiSwapperWithLiquidityManagementDeployer(swapperDeployer_);
    }

    /// @notice Set the token prices contract to use for future new auto-compounders
    function setTokenPrices(address tokenPrices_) external onlyElevatedAccess {
        emit TokenPricesSet(tokenPrices_);
        tokenPrices = tokenPrices_;
    }

    /// @notice Set the fee collector address to use for future new auto-compounders
    function setFeeCollector(address feeCollector_) external onlyElevatedAccess {
        emit FeeCollectorSet(feeCollector_);
        feeCollector = feeCollector_;
    }

    /// @notice Set the deployer for the vault
    function setVaultDeployer(address deployer) external onlyElevatedAccess {
        emit VaultDeployerSet(deployer);
        vaultDeployer = OrigamiDelegated4626VaultDeployer(deployer);
    }

    /// @notice Set the deployer for the manager
    function setManagerDeployer(address deployer) external onlyElevatedAccess {
        emit ManagerDeployerSet(deployer);
        managerDeployer = OrigamiInfraredVaultManagerDeployer(deployer);
    }

    /// @notice Set the deployer for the swapper
    function setSwapperDeployer(address deployer) external onlyElevatedAccess {
        emit SwapperDeployerSet(deployer);
        swapperDeployer = OrigamiSwapperWithLiquidityManagementDeployer(deployer);
    }  

    /// @notice Deploy a new vault
    /// @dev A vault for an Infrared reward vault asset can only be created once,
    /// future calls will return the already registered vault.
    /// The owner will need to claim the ownership after this (the Origami DAO multisig)
    /// and then seed the vault
    function create(
        string calldata name_,
        string calldata symbol_,
        IInfraredVault infraredRewardVault_,
        uint16 performanceFeeBps_,
        address overlord_,
        address[] calldata expectedSwapRouters_
    ) external onlyElevatedAccess returns (OrigamiDelegated4626Vault vault) {
        address asset = infraredRewardVault_.stakingToken();

        // Check if it's been registered already
        vault = registeredVaults[asset];
        if (address(vault) != address(0)) return vault;

        // A new vault
        vault = vaultDeployer.deploy({
            owner: address(this),
            name: name_,
            symbol: symbol_,
            asset: asset,
            tokenPrices: tokenPrices
        });
        registeredVaults[asset] = vault;

        OrigamiSwapperWithLiquidityManagement swapper = swapperDeployer.deploy({
            owner: address(this),
            asset: asset
        });

        OrigamiInfraredVaultManager manager = managerDeployer.deploy({
            owner: address(this),
            vault: address(vault),
            asset: asset,
            infraredRewardVault: address(infraredRewardVault_),
            feeCollector: feeCollector,
            swapper: address(swapper),
            performanceFeeBps: performanceFeeBps_
        });

        IOrigamiElevatedAccess.ExplicitAccess[] memory access = new IOrigamiElevatedAccess.ExplicitAccess[](2);
        access[0] = IOrigamiElevatedAccess.ExplicitAccess(OrigamiSwapperWithLiquidityManagement.execute.selector, true);
        access[1] = IOrigamiElevatedAccess.ExplicitAccess(OrigamiSwapperWithLiquidityManagement.addLiquidity.selector, true);
        swapper.setExplicitAccess(overlord_, access);

        vault.setManager(address(manager), 0);
        for (uint256 i; i < expectedSwapRouters_.length; ++i) {
            swapper.whitelistRouter(expectedSwapRouters_[i], true);
        }

        vault.proposeNewOwner(owner);
        manager.proposeNewOwner(owner);
        swapper.proposeNewOwner(owner);

        emit VaultCreated(
            address(vault),
            address(asset),
            address(manager),
            address(swapper)
        );
    }

    /// @notice Seed the vault for a registered asset while this factory is still the owner
    /// @dev Useful for deployments - it will fail as soon as the vault ownership is claimed
    /// by the intended long term owner.
    function seedVault(
        IERC20 vaultAsset,
        uint256 numAssets,
        address receiver,
        uint256 maxTotalSupply
    ) external onlyElevatedAccess returns (uint256 shares) {
        OrigamiDelegated4626Vault vault = registeredVaults[address(vaultAsset)];
        if (address(vault) == address(0)) revert AssetNotRegistered(address(vaultAsset));

        vaultAsset.safeTransferFrom(msg.sender, address(this), numAssets);
        vaultAsset.forceApprove(address(vault), numAssets);
        shares = vault.seedDeposit(numAssets, receiver, maxTotalSupply);
    }
}
