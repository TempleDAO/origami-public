pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/lovToken/IOrigamiLovToken.sol)

import { IOrigamiOTokenManager } from "contracts/interfaces/investments/IOrigamiOTokenManager.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { ITokenPrices } from "contracts/interfaces/common/ITokenPrices.sol";

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
    event MaxTotalSupplySet(uint256 maxTotalSupply);

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
    function setAnnualPerformanceFee(uint48 _annualPerformanceFeeBps) external;

    /**
     * @notice Set the max total supply allowed for investments into this lovToken
     */
    function setMaxTotalSupply(uint256 _maxTotalSupply) external;

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
     * @notice The maximum allowed supply of this token for user investments
     * @dev The actual totalSupply() may be greater than `maxTotalSupply`
     * in order to start organically shrinking supply or from performance fees
     */
    function maxTotalSupply() external view returns (uint256);

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
     * @notice The address used to collect the Origami performance fees.
     */
    function feeCollector() external view returns (address);

    /**
     * @notice The annual performance fee to Origami treasury
     * Represented in basis points
     */
    function annualPerformanceFeeBps() external view returns (uint48);

    /**
     * @notice The last time the performance fee was collected
     */
    function lastPerformanceFeeTime() external view returns (uint48);

    /**
     * @notice The helper contract to retrieve Origami USD prices
     * @dev Required for off-chain/subgraph integration
     */
    function tokenPrices() external view returns (ITokenPrices);

    /**
     * @notice The performance fee amount which would be collected as of now, 
     * based on the total supply
     */
    function accruedPerformanceFee() external view returns (uint256);
}