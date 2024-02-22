pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/lending/IOrigamiLendingRewardsMinter.sol)

import { IMintableToken } from "contracts/interfaces/common/IMintableToken.sol";
import { IOrigamiInvestmentVault } from "contracts/interfaces/investments/IOrigamiInvestmentVault.sol";
import { IOrigamiDebtToken } from "contracts/interfaces/investments/lending/IOrigamiDebtToken.sol";

/**
 * @notice Periodically mint new oToken rewards for the Origami lending vault
 * based on the cummulatively accrued debtToken interest.
 */
interface IOrigamiLendingRewardsMinter {
    event RewardsMinted(uint256 newReservesAmmount, uint256 feeAmount);
    event CarryOverRateSet(uint256 rate);
    event FeeCollectorSet(address indexed feeCollector);

    /**
     * @notice The Origami oToken which uses this lending manager
     */
    function oToken() external view returns (IMintableToken);

    /**
     * @notice The Origami ovToken which receives oToken reserves upon harvesting debt
     */
    function ovToken() external view returns (IOrigamiInvestmentVault);

    /**
     * @notice The token issued to borrowers or idle strategy for the use of the funds
     */
    function debtToken() external view returns (IOrigamiDebtToken);

    /**
     * @notice The fraction of new `debtToken` accrued interest which is NOT minted as new oToken,
     * in order to keep a buffer for bad debt.
     * @dev Represented as basis points
     */
    function carryOverRate() external view returns (uint256);

    /**
     * @notice The address used to collect the Origami performance fees.
     */
    function feeCollector() external view returns (address);

    /**
     * @notice The cumulative amount of interest which has been minted and added as rewards
     * to the ovToken so far
     */
    function cumulativeInterestCheckpoint() external view returns (uint256);

    /**
     * @notice Set the fraction of new `debtToken` accrued interest which is NOT minted as new oToken
     * when `checkpointDebtAndMintRewards()` is called.
     * @dev Represented as basis points
     */
    function setCarryOverRate(uint256 _carryOverRate) external;

    /**
     * @notice Set the Origami performance fee collector address
     */
    function setFeeCollector(address _feeCollector) external;

    /**
     * @notice Checkpoint select `debtToken` debtors interest, then periodically harvest any newly
     * accrued `debtToken` and mint as new oToken reserves into the ovToken.
     * @dev Note the accrued `debtToken` is an estimate based off when each borrower was last
     * checkpoint - so the more debtors which are checkpoint the more accurate this will be.
     */
    function checkpointDebtAndMintRewards(address[] calldata debtors) external;
}
