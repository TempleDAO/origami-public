pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/swappers/OrigamiErc4626AndDexAggregatorSwapper.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { DexAggregator } from "contracts/libraries/DexAggregator.sol";

/**
 * @title Origami ERC-4626 And DEX Aggregator Swapper
 * @notice An on chain swapper contract to integrate with a DEX Aggregator via the 1Inch router | 0x proxy.
 * A custom route is also provided, where after the DEX Aggregator swap the funds can be deposited into an
 * ERC-4626 Vault.
 * 
 * @dev This is intentionally kept quite specific to one use case and will be redundant 
 * once 1inch supports the route directly
 * The amount of tokens bought is expected to be checked for slippage in the calling contract
 */
contract OrigamiErc4626AndDexAggregatorSwapper is IOrigamiSwapper, OrigamiElevatedAccess {
    using SafeERC20 for IERC20;
    using DexAggregator for address;

    /// @notice Approved router contracts for swaps
    mapping(address router => bool allowed) public whitelistedRouters;

    /**
     * @notice The ERC-4626 vault which can be deposited into directly
     */
    IERC4626 public immutable vault;

    /**
     * @notice The underlying asset of the ERC-4626 `vault`
     */
    IERC20 public immutable vaultUnderlyingAsset;

    enum RouteType {
        VIA_DEX_AGGREGATOR_ONLY,
        VIA_DEX_AGGREGATOR_THEN_DEPOSIT_IN_VAULT
    }

    struct RouteData {
        RouteType routeType;
        address router;
        bytes data;
    }

    constructor(
        address _initialOwner,
        address _vault
    ) OrigamiElevatedAccess(_initialOwner) {
        vault = IERC4626(_vault);
        vaultUnderlyingAsset = IERC20(vault.asset());
    }

    function whitelistRouter(address router, bool allowed) external onlyElevatedAccess {
        whitelistedRouters[router] = allowed;
        emit RouterWhitelisted(router, allowed);
    }

    /**
     * @notice Recover any token -- this contract should not ordinarily hold any tokens.
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {
        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice Execute a swap. `swapData` needs to be abi encoded RouteData.
     * The VIA_DEX_AGGREGATOR_THEN_DEPOSIT_IN_VAULT route type is only valid when the buyToken is the ERC-4626 `vault`
     */
    function execute(
        IERC20 sellToken, 
        uint256 sellTokenAmount, 
        IERC20 buyToken, 
        bytes calldata swapData
    ) external override returns (uint256 buyTokenAmount) {
        sellToken.safeTransferFrom(msg.sender, address(this), sellTokenAmount);

        RouteData memory routeData = abi.decode(
            swapData, (RouteData)
        );

        if (!whitelistedRouters[routeData.router]) revert InvalidRouter(routeData.router);

        if (routeData.routeType == RouteType.VIA_DEX_AGGREGATOR_ONLY) {
            buyTokenAmount = routeData.router.swap(sellToken, sellTokenAmount, buyToken, routeData.data);

            // Transfer back to the caller
            buyToken.safeTransfer(msg.sender, buyTokenAmount);
        } else {
            // VIA_DEX_AGGREGATOR_THEN_DEPOSIT_IN_VAULT
            // Only valid if the buyToken is the ERC-4626 Vault
            if (address(buyToken) != address(vault)) revert CommonEventsAndErrors.InvalidToken(address(buyToken));

            // First swap from the sellToken to the vault deposit token
            buyTokenAmount = routeData.router.swap(sellToken, sellTokenAmount, vaultUnderlyingAsset, routeData.data);

            // Now deposit 100% of the bought tokens into the vault
            vaultUnderlyingAsset.forceApprove(address(vault), buyTokenAmount);
            buyTokenAmount = vault.deposit(buyTokenAmount, msg.sender);
            if (buyTokenAmount == 0) revert IOrigamiSwapper.InvalidSwap();
        }

        emit Swap(address(sellToken), sellTokenAmount, address(buyToken), buyTokenAmount);
    }
}
