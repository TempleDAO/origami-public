pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiAbstractLovTokenManager } from "contracts/investments/lovToken/managers/OrigamiAbstractLovTokenManager.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";
import { IOrigamiOTokenManager } from "contracts/interfaces/investments/IOrigamiOTokenManager.sol";

contract OrigamiTestnetLovTokenManager is OrigamiAbstractLovTokenManager {
    using SafeERC20 for IERC20;
    /**
     * @notice reserveToken that this lovToken levers up on
     * This is also the asset which users deposit/exit with in this lovToken manager
     */
    IERC20 private immutable _reserveToken;

    /**
     * @notice The number of reserves this lovToken holds.
     */
    uint256 private _reservesBalance;

    /**
     * @notice The number of liabilities this lovToken has
     */
    uint256 private _liabilitiesBalance;

    constructor(
        address _initialOwner,
        address _reserveToken_,
        address _lovToken
    ) OrigamiAbstractLovTokenManager(_initialOwner, _lovToken) {
        _reserveToken = IERC20(_reserveToken_);
    }

    /**
     * @notice Adds `addedLiabilities` to both liabilities and reserves.
     */
    function rebalanceDown(uint256 addedLiabilities) external onlyElevatedAccess {
        // Get the current A/L to check for oracle prices, and so we can compare that the new A/L is lower after the rebalance
        Cache memory cache = populateCache(IOrigamiOracle.PriceType.SPOT_PRICE);
        uint128 alRatioBefore = _assetToLiabilityRatio(cache);

        _liabilitiesBalance += addedLiabilities;
        _reservesBalance += addedLiabilities;

        // Validate that the new A/L is still within the `rebalanceALRange` and expected slippage range
        uint128 alRatioAfter = _validateAfterRebalance(
            cache, 
            alRatioBefore, 
            0, 
            type(uint128).max, 
            AlValidationMode.LOWER_THAN_BEFORE, 
            true
        );

        emit Rebalance(
            int256(addedLiabilities),
            int256(addedLiabilities),
            alRatioBefore,
            alRatioAfter
        );
    }

    /**
     * @notice Removes `removedLiabilities` from both liabilities and reserves.
     */
    function rebalanceUp(uint256 removedLiabilities) external onlyElevatedAccess {
        // Get the current A/L to check for oracle prices, and so we can compare that the new A/L is lower after the rebalance
        Cache memory cache = populateCache(IOrigamiOracle.PriceType.SPOT_PRICE);
        uint128 alRatioBefore = _assetToLiabilityRatio(cache);

        _liabilitiesBalance -= removedLiabilities;
        _reservesBalance -= removedLiabilities;

        // Validate that the new A/L is still within the `rebalanceALRange` and expected slippage range
        uint128 alRatioAfter = _validateAfterRebalance(
            cache, 
            alRatioBefore, 
            0, 
            type(uint128).max, 
            AlValidationMode.HIGHER_THAN_BEFORE, 
            true
        );

        emit Rebalance(
            -int256(removedLiabilities),
            -int256(removedLiabilities),
            alRatioBefore,
            alRatioAfter
        );
    }

    /**
     * @notice Recover any token, excluding the `reserveToken`
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external override onlyElevatedAccess {
        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc OrigamiAbstractLovTokenManager
    function reservesBalance() public override view returns (uint256) {
        return _reservesBalance;
    }

    /// @inheritdoc IOrigamiOTokenManager
    function baseToken() external override view returns (address) {
        return address(_reserveToken);
    }

    /// @inheritdoc IOrigamiOTokenManager
    function acceptedInvestTokens() external override view returns (address[] memory tokens) {
        tokens = new address[](1);
        tokens[0] = address(_reserveToken);
    }

    /// @inheritdoc IOrigamiOTokenManager
    function acceptedExitTokens() external override view returns (address[] memory tokens) {
        tokens = new address[](1);
        tokens[0] = address(_reserveToken);
    }

    /// @inheritdoc IOrigamiLovTokenManager
    function reserveToken() public override view returns (address) {
        return address(_reserveToken);
    }

    /// @inheritdoc IOrigamiLovTokenManager
    function debtToken() external override view returns (address) {
        return address(_reserveToken);
    }

    /// @inheritdoc IOrigamiLovTokenManager
    function liabilities(IOrigamiOracle.PriceType /*debtPriceType*/) public override view returns (uint256) {
        return _liabilitiesBalance;
    }

    /// @inheritdoc OrigamiAbstractLovTokenManager
    function _dynamicDepositFeeBps() internal override view returns (uint256) {
        return _minDepositFeeBps;
    }

    /// @inheritdoc OrigamiAbstractLovTokenManager
    function _dynamicExitFeeBps() internal override view returns (uint256) {
        return _minExitFeeBps;
    }

    /// @inheritdoc OrigamiAbstractLovTokenManager
    function _depositIntoReserves(address fromToken, uint256 fromTokenAmount) internal override returns (uint256 newReservesAmount) {
        if (fromToken == address(_reserveToken)) {
            newReservesAmount = fromTokenAmount;

            // Increase the counter of reserves
            _reservesBalance += newReservesAmount;
        } else {
            revert CommonEventsAndErrors.InvalidToken(fromToken);
        }
    }

    /// @inheritdoc OrigamiAbstractLovTokenManager
    function _previewDepositIntoReserves(address fromToken, uint256 fromTokenAmount) internal override view returns (uint256) {
        return fromToken == address(_reserveToken) ? fromTokenAmount : 0;
    }

    /// @inheritdoc OrigamiAbstractLovTokenManager
    function _maxDepositIntoReserves(address fromToken) internal override view returns (uint256) {
        return fromToken == address(_reserveToken) ? MAX_TOKEN_AMOUNT : 0;
    }

    /// @inheritdoc OrigamiAbstractLovTokenManager
    function _previewMintReserves(address toToken, uint256 reservesAmount) internal override view returns (uint256) {
        return toToken == address(_reserveToken) ? reservesAmount : 0;
    }

    /// @inheritdoc OrigamiAbstractLovTokenManager
    function _redeemFromReserves(uint256 reservesAmount, address toToken, address recipient) internal override returns (uint256 toTokenAmount) {
        if (toToken == address(_reserveToken)) {
            toTokenAmount = reservesAmount;

            _reservesBalance -= reservesAmount;
            _reserveToken.safeTransfer(address(recipient), toTokenAmount);
        } else {
            revert CommonEventsAndErrors.InvalidToken(toToken);
        }
    }

    /// @inheritdoc OrigamiAbstractLovTokenManager
    function _previewRedeemFromReserves(uint256 reservesAmount, address toToken) internal override view returns (uint256 toTokenAmount) {
        return toToken == address(_reserveToken) ? reservesAmount : 0;
    }

    /// @inheritdoc OrigamiAbstractLovTokenManager
    function _maxRedeemFromReserves(address toToken, Cache memory /*cache*/) internal override view returns (uint256 reservesAmount) {
        return toToken == address(_reserveToken) ? _reservesBalance : 0;
    }
}
