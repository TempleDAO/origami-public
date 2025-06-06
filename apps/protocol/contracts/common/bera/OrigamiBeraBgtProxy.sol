pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/bera/OrigamiBeraRewardsStaker.sol)

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { IBeraBgt } from "contracts/interfaces/external/bera/IBeraBgt.sol";
import { IOrigamiBeraBgtProxy } from "contracts/interfaces/common/bera/IOrigamiBeraBgtProxy.sol";
import { OrigamiElevatedAccessUpgradeable } from "contracts/common/access/OrigamiElevatedAccessUpgradeable.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/**
 * @title Origami Berachain BGT Proxy
 * @notice Apply actions on the non-transferrable BGT token
 * @dev Given BGT is non-transferrable, and that there may be new features we need to handle
 * this contract is a UUPS upgradeable contract.
 */
contract OrigamiBeraBgtProxy is 
    IOrigamiBeraBgtProxy,
    Initializable,
    OrigamiElevatedAccessUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @inheritdoc IOrigamiBeraBgtProxy
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IBeraBgt public immutable override bgt;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address bgt_) {
        _disableInitializers();
        bgt = IBeraBgt(bgt_);
    }

    function initialize(address _initialOwner) initializer external {
        __OrigamiElevatedAccess_init(_initialOwner);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address /*newImplementation*/) internal onlyElevatedAccess override {}

    /// @inheritdoc IOrigamiBeraBgtProxy
    function recoverToken(address token, address to, uint256 amount) external override onlyElevatedAccess {
        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20Upgradeable(token).safeTransfer(to, amount);
    }
    
    /// @inheritdoc IOrigamiBeraBgtProxy
    function setTokenAllowance(address token, address spender, uint256 amount) external override onlyElevatedAccess {
        IERC20Upgradeable _token = IERC20Upgradeable(token);
        if (amount == _token.allowance(address(this), spender)) return;
        _token.forceApprove(spender, amount);
    }

    /// @inheritdoc IOrigamiBeraBgtProxy
    function redeem(address receiver, uint256 amount) external override onlyElevatedAccess {
        bgt.redeem(receiver, amount);
    }

    /// @inheritdoc IOrigamiBeraBgtProxy
    function delegate(address delegatee) external override onlyElevatedAccess {
        bgt.delegate(delegatee);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  BGT VALIDATOR BOOSTS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    
    /// @inheritdoc IOrigamiBeraBgtProxy
    function queueBoost(bytes calldata pubkey, uint128 amount) external override onlyElevatedAccess {
        bgt.queueBoost(pubkey, amount);
    }

    /// @inheritdoc IOrigamiBeraBgtProxy
    function cancelBoost(bytes calldata pubkey, uint128 amount) external override onlyElevatedAccess {
        bgt.cancelBoost(pubkey, amount);
    }

    /// @inheritdoc IOrigamiBeraBgtProxy
    function activateBoost(bytes calldata pubkey) external override returns (bool) {
        // @dev No need to add permissions to this function, as any address can activate another account's
        // boost as long as enough time has passed
        // This is just a helper
        return bgt.activateBoost(address(this), pubkey);
    }

    /// @inheritdoc IOrigamiBeraBgtProxy
    function queueDropBoost(bytes calldata pubkey, uint128 amount) external override onlyElevatedAccess {
        bgt.queueDropBoost(pubkey, amount);
    }

    /// @inheritdoc IOrigamiBeraBgtProxy
    function cancelDropBoost(bytes calldata pubkey, uint128 amount) external override onlyElevatedAccess {
        bgt.cancelDropBoost(pubkey, amount);
    }

    /// @inheritdoc IOrigamiBeraBgtProxy
    function dropBoost(bytes calldata pubkey) external override returns (bool) {
        // @dev No need to add permissions to this function, as any address can activate another account's
        // boost as long as enough time has passed
        // This is just a helper
        return bgt.dropBoost(address(this), pubkey);
    }

    /// @inheritdoc IOrigamiBeraBgtProxy
    function balance() external override view returns (uint256) {
        return bgt.balanceOf(address(this));
    }
}
