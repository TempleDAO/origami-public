pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/bera/OrigamiBoycoUsdcManager.sol)

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IBalancerVault } from "contracts/interfaces/external/balancer/IBalancerVault.sol";
import { IOrigamiBalancerPoolHelper } from "contracts/interfaces/common/balancer/IOrigamiBalancerPoolHelper.sol";
import { IOrigamiBeraRewardsVaultProxy } from "contracts/interfaces/common/bera/IOrigamiBeraRewardsVaultProxy.sol";
import { IOrigamiDelegated4626Vault } from "contracts/interfaces/investments/erc4626/IOrigamiDelegated4626Vault.sol";
import { IOrigamiDelegated4626VaultManager } from "contracts/interfaces/investments/erc4626/IOrigamiDelegated4626VaultManager.sol";
import { IOrigamiBoycoManager } from "contracts/interfaces/investments/bera/IOrigamiBoycoManager.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiManagerPausable } from "contracts/investments/util/OrigamiManagerPausable.sol";

/**
 * @title Origami Boyco USDC Manager
 * @notice Handles USDC deposits and orchestrates the farming of (i)BGT
 * This manager implements a strategy specifically for single-sided deposit of USDC into BEX pools followed by staking the received LP token
 */
contract OrigamiBoycoUsdcManager is 
    IOrigamiBoycoManager,
    OrigamiElevatedAccess,
    OrigamiManagerPausable
{
    using SafeERC20 for IERC20;
    using OrigamiMath for uint256;

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    IOrigamiDelegated4626Vault public immutable override vault;

    /// @inheritdoc IOrigamiBoycoManager
    IERC20 public override bexLpToken;

    /// @inheritdoc IOrigamiBoycoManager
    IOrigamiBalancerPoolHelper public override bexPoolHelper;

    /// @inheritdoc IOrigamiBoycoManager
    IOrigamiBeraRewardsVaultProxy public override beraRewardsVaultProxy;

    /// @inheritdoc IOrigamiBoycoManager
    IERC20 public override immutable usdcToken;

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    uint256 public override totalAssets;

    /// @dev The index of the USDC token in the BEX pool
    uint256 private _usdcIndex;

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    uint16 public override constant depositFeeBps = 0;

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    uint16 public override constant withdrawalFeeBps = 0;

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    uint256 public override constant maxDeposit = type(uint256).max;

    constructor(
        address initialOwner_,
        address vault_,
        address usdcToken_,
        address bexPoolHelper_,
        address beraRewardsVaultProxy_
    ) 
        OrigamiElevatedAccess(initialOwner_)
    {
        vault = IOrigamiDelegated4626Vault(vault_);
        usdcToken = IERC20(usdcToken_);
        beraRewardsVaultProxy = IOrigamiBeraRewardsVaultProxy(beraRewardsVaultProxy_);

        _setBexPoolHelper(bexPoolHelper_);
    }
    
    /// @inheritdoc IOrigamiBoycoManager
    function setBexPoolHelper(address bexPoolHelper_) external override onlyElevatedAccess {
        emit BexPoolHelperSet(bexPoolHelper_);
        _setBexPoolHelper(bexPoolHelper_);
    }

    /// @inheritdoc IOrigamiBoycoManager
    function setBeraRewardsVaultProxy(address beraRewardsVaultProxy_) external override onlyElevatedAccess {
        emit BeraRewardsVaultProxySet(beraRewardsVaultProxy_);
        beraRewardsVaultProxy = IOrigamiBeraRewardsVaultProxy(beraRewardsVaultProxy_);
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function deposit(
        uint256 assetsAmount
    ) external override onlyVault returns (uint256 assetsDeposited) {
        assetsDeposited = assetsAmount;
        totalAssets += assetsDeposited;
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function withdraw(
        uint256 amount,
        address receiver
    ) external override onlyVault returns (uint256 assetsWithdrawn) {
        // This may fail if the USDC (more than the requested amount)
        // is still being utilised within the LP farming.
        // A withdraw buffer shall be maintained via keepers (via `recallLiquidity()`) such that we can incrementally allow for exits.
        uint256 assetBalance = unallocatedAssets();
        if (amount > assetBalance) revert NotEnoughUsdc(assetBalance, amount);
        assetsWithdrawn = amount;
        
        usdcToken.safeTransfer(receiver, assetsWithdrawn);
        totalAssets -= assetsWithdrawn;
    }

    /// @inheritdoc IOrigamiBoycoManager
    function deployLiquidityQuote(
        address depositToken,
        uint256 depositAmount,
        uint256 slippageBps
    ) external override returns (
        uint256 expectedLpTokenAmount,
        uint256 minLpTokenAmount,
        IBalancerVault.JoinPoolRequest memory requestData
    ) {
        // Note: Future managers may allow non-USDC capital deployments (ie first convert USDC -> depositToken)
        if (depositToken != address(usdcToken)) revert CommonEventsAndErrors.InvalidToken(depositToken);
        
        // Verify USDC is still in the expected index in the pool
        if (bexPoolHelper.poolTokens()[_usdcIndex] != depositToken) revert CommonEventsAndErrors.InvalidParam();

        // Get a quote to add USDC to the Balancer pool
        uint256[] memory tokenAmounts;
        (
            tokenAmounts,
            expectedLpTokenAmount,
            minLpTokenAmount,
            requestData
        ) = bexPoolHelper.addLiquidityQuote(
            _usdcIndex,
            depositAmount,
            slippageBps
        );
    }
    
    /// @inheritdoc IOrigamiBoycoManager
    function deployLiquidity(
        address depositToken,
        uint256 usdcAmountToDeposit,
        IBalancerVault.JoinPoolRequest calldata requestData
    ) external override onlyElevatedAccess {
        // Note: Future managers may allow non-USDC capital deployments (ie first convert USDC -> depositToken)
        if (depositToken != address(usdcToken)) revert CommonEventsAndErrors.InvalidToken(depositToken);

        // 1. Add the USDC as liquidity into BEX and receive an LP receipt token
        usdcToken.forceApprove(address(bexPoolHelper), usdcAmountToDeposit);
        bexPoolHelper.addLiquidity(address(this), requestData);

        // 2. Stake the entire LP receipt token balance
        uint256 lpBalance = bexLpToken.balanceOf(address(this));
        bexLpToken.safeTransfer(address(beraRewardsVaultProxy), lpBalance);
        beraRewardsVaultProxy.stake(lpBalance);

        emit LiquidityDeployed(usdcAmountToDeposit, depositToken, usdcAmountToDeposit, lpBalance);
    }

    /// @inheritdoc IOrigamiBoycoManager
    function recallLiquidityQuote(
        uint256 lpTokenAmount,
        address exitToken,
        uint256 slippageBps
    ) external override returns (
        uint256[] memory expectedTokenAmounts,
        uint256[] memory minTokenAmounts,
        IBalancerVault.ExitPoolRequest memory requestData
    ) {
        // Note: Future managers may allow non-USDC recalls
        if (exitToken != address(usdcToken)) revert CommonEventsAndErrors.InvalidToken(exitToken);
        
        // Verify USDC is still in the expected index in the pool
        if (bexPoolHelper.poolTokens()[_usdcIndex] != exitToken) revert CommonEventsAndErrors.InvalidParam();

        (    
            expectedTokenAmounts,
            minTokenAmounts,
            requestData
        ) = bexPoolHelper.removeLiquidityQuote(_usdcIndex, lpTokenAmount, slippageBps);
    }

    /// @inheritdoc IOrigamiBoycoManager
    function recallLiquidity(
        uint256 lpTokenAmount,
        address exitToken,
        IBalancerVault.ExitPoolRequest calldata requestData
    ) external override onlyElevatedAccess {
        // Note: Future managers may allow non-USDC recalls
        if (exitToken != address(usdcToken)) revert CommonEventsAndErrors.InvalidToken(exitToken);

        uint256 usdcBalance = unallocatedAssets();

        // 1. Unstake the amount of LP
        beraRewardsVaultProxy.withdraw(
            lpTokenAmount,
            address(this)
        );

        // 2. Remove liquidity
        bexLpToken.forceApprove(address(bexPoolHelper), lpTokenAmount);
        bexPoolHelper.removeLiquidity(lpTokenAmount, address(this), requestData);
        uint256 usdcFromLp = unallocatedAssets() - usdcBalance;

        emit LiquidityRecalled(usdcFromLp, exitToken, usdcFromLp, lpTokenAmount);
    }

    /**
     * @notice Recover ERC20 tokens.
     */
    function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {
        // USDC/LP/other tokens are still allowed to be pulled here in case of emergency,
        // since Bera is new and there may be launch issues with the minter/BEX/staking
        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function asset() external override view returns (address) {
        return address(usdcToken);
    }

    /// @inheritdoc IOrigamiBoycoManager
    function lpBalanceStaked() public override view returns (uint256) {
        return beraRewardsVaultProxy.stakedBalance();
    }

    /// @inheritdoc IOrigamiBoycoManager
    function bexTokenBalances() external override view returns (uint256[] memory) {
        return bexPoolHelper.tokenAmountsForLpTokens(lpBalanceStaked());
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function unallocatedAssets() public override view returns (uint256) {
        return usdcToken.balanceOf(address(this));
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function performanceFeeBps() external override pure returns (uint16 forCaller, uint16 forOrigami) {
        return (0, 0);
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function areDepositsPaused() external virtual override view returns (bool) {
        return _paused.investmentsPaused;
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function areWithdrawalsPaused() external virtual override view returns (bool) {
        return _paused.exitsPaused;
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function maxWithdraw() external view override returns (uint256) {
        // Cap the amount of shares available based on the actual assets available in the manager as of now.
        return unallocatedAssets();
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public override pure returns (bool) {
        return interfaceId == type(IOrigamiBoycoManager).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }
    
    modifier onlyVault() {
        if (msg.sender != address(vault)) revert CommonEventsAndErrors.InvalidAccess();
        _;
    }

    /// @dev Update the BEX pool helper and refresh the LP token address and
    /// USDC index in case it's changed
    function _setBexPoolHelper(address bexPoolHelper_) internal {
        bexPoolHelper = IOrigamiBalancerPoolHelper(bexPoolHelper_);
        bexLpToken = bexPoolHelper.lpToken();
        
        // find the index of the USDC token
        address[] memory tokens = bexPoolHelper.poolTokens();
        uint256 ui = tokens.length;
        uint256 i = ui;
        do {
            --i;
            if (tokens[i] == address(usdcToken)) {
                ui = i;
                break;
            }
        } while(i > 0);

        if (ui == tokens.length) revert CommonEventsAndErrors.InvalidParam();
        _usdcIndex = ui;
    }
}
