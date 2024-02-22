pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/lending/IOrigamiLendingBorrower.sol)

interface IOrigamiLendingBorrower {
    struct AssetBalance {
        address asset;
        uint256 balance;
    }

    event AssetBalancesCheckpoint(AssetBalance[] assetBalances);

    /**
     * @notice Checkpoint the underlying idle strategy to get the latest balance.
     * If no checkpoint is required (eg AToken in aave doesn't need this) then
     * calling this will be identical to just calling `latestAssetBalances()`
     */
    function checkpointAssetBalances() external returns (
        AssetBalance[] memory assetBalances
    );

    /**
     * @notice Track the deployed version of this contract. 
     */
    function version() external view returns (string memory);

    /**
     * @notice A human readable name for the borrower
     */
    function name() external view returns (string memory);

    /**
     * @notice The latest checkpoint of each asset balance this borrower holds.
     *
     * @dev The asset value may be stale at any point in time, depending on the borrower. 
     * It may optionally implement `checkpointAssetBalances()` in order to update those balances.
     */
    function latestAssetBalances() external view returns (AssetBalance[] memory assetBalances);
}
