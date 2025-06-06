pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/bera/OrigamiBeraRewardsStaker.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IBeraRewardsVault } from "contracts/interfaces/external/bera/IBeraRewardsVault.sol";
import { IOrigamiBeraRewardsVaultProxy } from "contracts/interfaces/common/bera/IOrigamiBeraRewardsVaultProxy.sol";

import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/**
 * @title Origami Berachain Rewards Vault Proxy
 * @notice Stake/withdraw from Berachain Reward Vaults to earn BGT
 */
contract OrigamiBeraRewardsVaultProxy is IOrigamiBeraRewardsVaultProxy, OrigamiElevatedAccess {
    using SafeERC20 for IERC20;

    /// @inheritdoc IOrigamiBeraRewardsVaultProxy
    IBeraRewardsVault public immutable override rewardsVault;

    constructor(address initialOwner_, address rewardsVault_) OrigamiElevatedAccess(initialOwner_) {
        rewardsVault = IBeraRewardsVault(rewardsVault_);

        // Grant max approval for the staking token.
        IERC20(address(rewardsVault.stakeToken())).forceApprove(address(rewardsVault), type(uint256).max);
    }

    /// @inheritdoc IOrigamiBeraRewardsVaultProxy
    function recoverToken(address token, address to, uint256 amount) external override onlyElevatedAccess {
        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }
    
    /// @inheritdoc IOrigamiBeraRewardsVaultProxy
    function setTokenAllowance(address token, address spender, uint256 amount) external override onlyElevatedAccess {
        IERC20 _token = IERC20(token);
        if (amount == _token.allowance(address(this), spender)) return;
        _token.forceApprove(spender, amount);
    }

    /// @inheritdoc IOrigamiBeraRewardsVaultProxy
    function setOperator(address operator) external override onlyElevatedAccess {
        rewardsVault.setOperator(operator);
    }

    /// @inheritdoc IOrigamiBeraRewardsVaultProxy
    function stake(uint256 amount) external override onlyElevatedAccess {
        // This assumes:
        //  - The caller has already transferred the staking token to this contract.
        //  - setTokenAllowance has been set on this contract ahead of time
        rewardsVault.stake(amount);
    }

    /// @inheritdoc IOrigamiBeraRewardsVaultProxy
    function withdraw(
        uint256 amount,
        address recipient
    ) external override onlyElevatedAccess {
        if (recipient == address(0)) revert CommonEventsAndErrors.InvalidAddress(recipient);

        rewardsVault.withdraw(amount);
        IERC20(address(rewardsVault.stakeToken())).safeTransfer(recipient, amount);
    }

    /// @inheritdoc IOrigamiBeraRewardsVaultProxy
    function delegateStake(
        address account,
        uint256 amount
    ) external override onlyElevatedAccess {
        // This assumes:
        //  - The caller has already transferred the staking token to this contract.
        //  - setTokenAllowance has been set on this contract ahead of time
        rewardsVault.delegateStake(account, amount);
    }

    /// @inheritdoc IOrigamiBeraRewardsVaultProxy
    function delegateWithdraw(
        address account,
        uint256 amount,
        address recipient
    ) external override onlyElevatedAccess {
        if (recipient == address(0)) revert CommonEventsAndErrors.InvalidAddress(recipient);

        rewardsVault.delegateWithdraw(account, amount);
        IERC20(address(rewardsVault.stakeToken())).safeTransfer(recipient, amount);
    }

    /// @inheritdoc IOrigamiBeraRewardsVaultProxy
    function exit(
        address recipient
    ) external override onlyElevatedAccess {
        rewardsVault.exit(recipient);
        IERC20 stakeToken = IERC20(address(rewardsVault.stakeToken()));
        stakeToken.safeTransfer(recipient, stakeToken.balanceOf(address(this)));
    }

    /// @inheritdoc IOrigamiBeraRewardsVaultProxy
    function getReward(
        address recipient
    ) external override onlyElevatedAccess {
        rewardsVault.getReward(address(this), recipient);
    }

    /// @inheritdoc IOrigamiBeraRewardsVaultProxy
    function stakedBalance() external view override returns (uint256) {
        return rewardsVault.balanceOf(address(this));
    }

    /// @inheritdoc IOrigamiBeraRewardsVaultProxy
    function unclaimedRewardsBalance() external view override returns (uint256) {
        return rewardsVault.earned(address(this));
    }
}
