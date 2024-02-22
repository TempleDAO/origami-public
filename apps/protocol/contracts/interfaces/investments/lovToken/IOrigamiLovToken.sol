pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/lovToken/IOrigamiLovToken.sol)

import { IOrigamiOTokenManager } from "contracts/interfaces/investments/IOrigamiOTokenManager.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";

/**
 * @title Origami lovToken
 * 
 * @notice Users deposit with an accepted token and are minted lovTokens
 * Origami will rebalance to lever up on the underlying reserve token, targetting a
 * specific A/L (assets / liabilities) range
 *
 * @dev The logic on how to handle the specific deposits/exits for each lovToken is delegated
 * to a manager contract
 */
interface IOrigamiLovToken is IOrigamiInvestment {
    event PerformanceFeesCollected(address indexed feeCollector, uint256 mintAmount);
    event FeeCollectorSet(address indexed feeCollector);

    error TooSoon();
    
    /**
     * @notice The token used to track reserves for this investment
     */
    function reserveToken() external view returns (address);

    /**
     * @notice The Origami contract managing the deposits/exits and the application of
     * the deposit tokens into the underlying protocol
     */
    function manager() external view returns (IOrigamiOTokenManager);

    /**
     * @notice Set the Origami lovToken Manager.
     */
    function setManager(address _manager) external;

    /**
     * @notice Set the vault performance fee
     * @dev Represented in basis points
     */
    function setPerformanceFee(uint256 _performanceFee) external;

    /**
     * @notice Set the Origami performance fee collector address
     */
    function setFeeCollector(address _feeCollector) external;
    
    /**
     * @notice Set the helper to calculate current off-chain/subgraph integration
     */
    function setTokenPrices(address _tokenPrices) external;

    /** 
     * @notice Collect the performance fees to the Origami Treasury
     */
    function collectPerformanceFees() external returns (uint256 amount);

    /**
     * @notice How many reserve tokens would one get given a number of lovToken shares
     * @dev Implementations must use the Oracle 'SPOT_PRICE' to value any debt in terms of the reserve token
     */
    function sharesToReserves(uint256 shares) external view returns (uint256);

    /**
     * @notice How many lovToken shares would one get given a number of reserve tokens
     * @dev Implementations must use the Oracle 'SPOT_PRICE' to value any debt in terms of the reserve token
     */
    function reservesToShares(uint256 reserves) external view returns (uint256);

    /**
     * @notice How many reserve tokens would one get given a single share, as of now
     * @dev Implementations must use the Oracle 'HISTORIC_PRICE' to value any debt in terms of the reserve token
     */
    function reservesPerShare() external view returns (uint256);
    
    /**
     * @notice The current amount of available reserves for redemptions
     * @dev Implementations must use the Oracle 'SPOT_PRICE' to value any debt in terms of the reserve token
     */
    function totalReserves() external view returns (uint256);

    /**
     * @notice Retrieve the current assets, liabilities and calculate the ratio
     * @dev Implementations must use the Oracle 'SPOT_PRICE' to value any debt in terms of the reserve token
     */
    function assetsAndLiabilities() external view returns (
        uint256 assets,
        uint256 liabilities,
        uint256 ratio
    );

    /**
     * @notice The current effective exposure (EE) of this lovToken
     * to `PRECISION` precision
     * @dev = reserves / (reserves - liabilities)
     * Implementations must use the Oracle 'SPOT_PRICE' to value any debt in terms of the reserve token
     */
    function effectiveExposure() external view returns (uint128);

    /**
     * @notice The valid lower and upper bounds of A/L allowed when users deposit/exit into lovToken
     * @dev Transactions will revert if the resulting A/L is outside of this range
     */
    function userALRange() external view returns (uint128 floor, uint128 ceiling);

    /**
     * @notice The current deposit and exit fee based on market conditions.
     * Fees are the equivalent of burning lovToken shares - benefit remaining vault users
     * @dev represented in basis points
     */
    function getDynamicFeesBps() external view returns (uint256 depositFeeBps, uint256 exitFeeBps);

    /**
     * @notice The performance fee to Origami treasury
     * Represented in basis points
     */
    function performanceFee() external view returns (uint256);

    /**
     * @notice The address used to collect the Origami performance fees.
     */
    function feeCollector() external view returns (address);

    /**
     * @notice How frequently the performance fee can be collected
     */
    function PERFORMANCE_FEE_FREQUENCY() external view returns (uint32);

    /**
     * @notice The last time the performance fee was collected
     */
    function lastPerformanceFeeTime() external view returns (uint32);

    /**
     * @notice The performance fee amount which would be collected as of now, 
     * based on the total supply
     */
    function performanceFeeAmount() external view returns (uint256);
}