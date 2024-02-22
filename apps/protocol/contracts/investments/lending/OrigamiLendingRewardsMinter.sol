pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/lending/OrigamiLendingRewardsMinter.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IMintableToken } from "contracts/interfaces/common/IMintableToken.sol";
import { IOrigamiInvestmentVault } from "contracts/interfaces/investments/IOrigamiInvestmentVault.sol";
import { IOrigamiDebtToken } from "contracts/interfaces/investments/lending/IOrigamiDebtToken.sol";
import { IOrigamiLendingRewardsMinter } from "contracts/interfaces/investments/lending/IOrigamiLendingRewardsMinter.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

/**
 * @notice Periodically mint new oToken rewards for the Origami lending vault
 * based on the cummulatively accrued debtToken interest.
 */
contract OrigamiLendingRewardsMinter is IOrigamiLendingRewardsMinter, OrigamiElevatedAccess {
    using SafeERC20 for IMintableToken;
    using SafeERC20 for IERC20;
    using OrigamiMath for uint256;

    /**
     * @notice The Origami oToken which uses this lending manager
     */
    IMintableToken public immutable override oToken;

    /**
     * @notice The Origami ovToken which receives oToken reserves upon harvesting debt
     */
    IOrigamiInvestmentVault public immutable override ovToken;

    /**
     * @notice The token issued to borrowers or idle strategy for the use of the funds
     */
    IOrigamiDebtToken public immutable override debtToken;

    /**
     * @notice The fraction of new `debtToken` accrued interest which is NOT minted as new oToken,
     * in order to keep a buffer for bad debt.
     * @dev Represented in basis points
     */
    uint256 public override carryOverRate;

    /**
     * @notice The address used to collect the Origami performance fees.
     */
    address public override feeCollector;

    /**
     * @notice The cumulative amount of interest which has been minted and added as rewards
     * to the ovToken so far
     */
    uint256 public override cumulativeInterestCheckpoint;

    constructor(
        address _initialOwner,
        address _oToken,
        address _ovToken,
        address _debtToken,
        uint256 _carryOverRate,
        address _feeCollector
    ) OrigamiElevatedAccess(_initialOwner) {
        oToken = IMintableToken(_oToken);
        ovToken = IOrigamiInvestmentVault(_ovToken);
        debtToken = IOrigamiDebtToken(_debtToken);
        if (_carryOverRate > OrigamiMath.BASIS_POINTS_DIVISOR) revert CommonEventsAndErrors.InvalidParam();
        carryOverRate = _carryOverRate;
        feeCollector = _feeCollector;
    }

    /**
     * @notice Set the fraction of new `debtToken` accrued interest which is NOT minted as new oToken
     * when `checkpointDebtAndMintRewards()` is called.
     * @dev Represented as basis points
     */
    function setCarryOverRate(uint256 _carryOverRate) external override onlyElevatedAccess {
        if (_carryOverRate > OrigamiMath.BASIS_POINTS_DIVISOR) revert CommonEventsAndErrors.InvalidParam();
        emit CarryOverRateSet(_carryOverRate);
        carryOverRate = _carryOverRate;
    }

    /**
     * @notice Set the Origami performance fee collector address
     */
    function setFeeCollector(address _feeCollector) external override onlyElevatedAccess {
        if (_feeCollector == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        emit FeeCollectorSet(_feeCollector);
        feeCollector = _feeCollector;
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
     * @notice Checkpoint select `debtToken` debtors interest, then periodically harvest any newly
     * accrued `debtToken` and mint as new oToken reserves into the ovToken.
     * @dev Note the accrued `debtToken` is an estimate based off when each borrower was last
     * checkpoint - so the more debtors which are checkpoint the more accurate this will be.
     */
    function checkpointDebtAndMintRewards(address[] calldata debtors) external override onlyElevatedAccess {
        if (debtors.length != 0) {
            debtToken.checkpointDebtorsInterest(debtors);
        }

        _mintRewards();
    }

    function _mintRewards() internal {
        uint256 _cumulativeInterestCheckpoint = cumulativeInterestCheckpoint;
        // The latest amount of cumulative interest (for all time) minus the previous checkpoint
        uint256 mintAmount = (debtToken.estimatedCumulativeInterest() - _cumulativeInterestCheckpoint).subtractBps(carryOverRate);

        if (mintAmount != 0) {
            uint256 feeRate = ovToken.performanceFee();
            (uint256 newReservesAmount, uint256 feeAmount) = mintAmount.splitSubtractBps(feeRate);
            emit RewardsMinted(newReservesAmount, feeAmount);

            cumulativeInterestCheckpoint = _cumulativeInterestCheckpoint + mintAmount;

            if (feeAmount != 0) {
                oToken.mint(feeCollector, feeAmount);
            }

            if (newReservesAmount != 0) {
                // Mint and add the oToken as reserves into the ovToken
                oToken.mint(address(this), newReservesAmount);
                oToken.safeIncreaseAllowance(address(ovToken), newReservesAmount);
                ovToken.addPendingReserves(newReservesAmount);
            }
        }
    }
}
