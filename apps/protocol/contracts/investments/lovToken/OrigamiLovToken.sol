pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/lovToken/OrigamiLovToken.sol)

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IOrigamiOTokenManager } from "contracts/interfaces/investments/IOrigamiOTokenManager.sol";
import { IOrigamiLovToken } from "contracts/interfaces/investments/lovToken/IOrigamiLovToken.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";
import { ITokenPrices } from "contracts/interfaces/common/ITokenPrices.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiInvestment } from "contracts/investments/OrigamiInvestment.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

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
contract OrigamiLovToken is IOrigamiLovToken, OrigamiInvestment {
    using SafeERC20 for IERC20;

    /**
     * @notice The Origami contract managing the deposits/exits and the application of
     * the deposit tokens into the underlying protocol
     */
    IOrigamiLovTokenManager internal lovManager;

    /**
     * @notice The performance fee which Origami takes from harvested rewards before compounding into reserves.
     * @dev Represented in basis points
     */
    uint256 public override performanceFee;

    /**
     * @notice The address used to collect the Origami performance fees.
     */
    address public override feeCollector;

    /**
     * @notice The helper contract to retrieve Origami USD prices
     * @dev Required for off-chain/subgraph integration
     */
    ITokenPrices public tokenPrices;

    /**
     * @notice How frequently the performance fee can be collected
     */
    uint32 public override constant PERFORMANCE_FEE_FREQUENCY = 7 days;

    /**
     * @notice The last time the performance fee was collected
     */
    uint32 public override lastPerformanceFeeTime;

    constructor(
        address _initialOwner,
        string memory _name,
        string memory _symbol,
        uint256 _performanceFee,
        address _feeCollector,
        address _tokenPrices
    ) OrigamiInvestment(_name, _symbol, _initialOwner) {
        if (_performanceFee > OrigamiMath.BASIS_POINTS_DIVISOR) revert CommonEventsAndErrors.InvalidParam();
        performanceFee = _performanceFee;
        feeCollector = _feeCollector;
        tokenPrices = ITokenPrices(_tokenPrices);
    }

    /**
     * @notice Set the Origami lovToken Manager.
     */
    function setManager(address _manager) external override onlyElevatedAccess {
        if (_manager == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        emit ManagerSet(_manager);
        lovManager = IOrigamiLovTokenManager(_manager);
    }

    /**
     * @notice Set the vault performance fee
     * @dev Represented in basis points
     */
    function setPerformanceFee(uint256 _performanceFee) external override onlyElevatedAccess {
        if (_performanceFee > OrigamiMath.BASIS_POINTS_DIVISOR) revert CommonEventsAndErrors.InvalidParam();
        emit PerformanceFeeSet(_performanceFee);
        performanceFee = _performanceFee;
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
     * @notice Set the helper to calculate current off-chain/subgraph integration
     */
    function setTokenPrices(address _tokenPrices) external override onlyElevatedAccess {
        if (_tokenPrices == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        emit TokenPricesSet(_tokenPrices);
        tokenPrices = ITokenPrices(_tokenPrices);
    }
    
    /** 
      * @notice User buys this lovToken with an amount of one of the approved ERC20 tokens
      * @param quoteData The quote data received from investQuote()
      * @return investmentAmount The actual number of receipt tokens received, inclusive of any fees.
      */
    function investWithToken(
        InvestQuoteData calldata quoteData
    ) external virtual override nonReentrant returns (uint256 investmentAmount) {
        if (quoteData.fromTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        // Send the investment token to the manager
        IOrigamiLovTokenManager _manager = lovManager;
        IERC20(quoteData.fromToken).safeTransferFrom(msg.sender, address(_manager), quoteData.fromTokenAmount);
        investmentAmount = _manager.investWithToken(msg.sender, quoteData);

        emit Invested(msg.sender, quoteData.fromTokenAmount, quoteData.fromToken, investmentAmount);

        // Mint the lovToken for the user
        if (investmentAmount != 0) {
            _mint(msg.sender, investmentAmount);
        }
    }

    /** 
      * @notice Sell this lovToken to receive one of the accepted exit tokens. 
      * @param quoteData The quote data received from exitQuote()
      * @param recipient The receiving address of the `toToken`
      * @return toTokenAmount The number of `toToken` tokens received upon selling the lovToken.
      */
    function exitToToken(
        ExitQuoteData calldata quoteData,
        address recipient
    ) external virtual override nonReentrant returns (
        uint256 toTokenAmount
    ) {
        if (quoteData.investmentTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (recipient == address(0)) revert CommonEventsAndErrors.InvalidAddress(recipient);

        // Send the lovToken to the manager
        IOrigamiLovTokenManager _manager = lovManager;
        _transfer(msg.sender, address(_manager), quoteData.investmentTokenAmount);

        uint256 lovTokenToBurn;
        (toTokenAmount, lovTokenToBurn) = _manager.exitToToken(msg.sender, quoteData, recipient);
        
        emit Exited(msg.sender, quoteData.investmentTokenAmount, quoteData.toToken, toTokenAmount, recipient);
        
        // Burn the lovToken
        if (lovTokenToBurn != 0) {
            _burn(address(_manager), lovTokenToBurn);
        }
    }

    /** 
      * @notice Unsupported - cannot invest in this lovToken to the native chain asset (eg ETH)
      * @dev In future, if required, a separate version which does support this flow will be added
      */
    function investWithNative(
        InvestQuoteData calldata /*quoteData*/
    ) external payable virtual override returns (uint256) {
        revert Unsupported();
    }

    /** 
      * @notice Unsupported - cannot exit this lovToken to the native chain asset (eg ETH)
      * @dev In future, if required, a separate version which does support this flow will be added
      */
    function exitToNative(
        ExitQuoteData calldata /*quoteData*/, address payable /*recipient*/
    ) external virtual override returns (uint256 /*nativeAmount*/) {
        revert Unsupported();
    }

    /** 
     * @notice Collect the performance fees to the Origami Treasury
     */
    function collectPerformanceFees() external override onlyElevatedAccess returns (uint256 amount) {
        if (block.timestamp < (lastPerformanceFeeTime + PERFORMANCE_FEE_FREQUENCY)) revert TooSoon();

        address _feeCollector = feeCollector;
        amount = performanceFeeAmount();
        if (amount != 0) {
            emit PerformanceFeesCollected(_feeCollector, amount);
            _mint(_feeCollector, amount);
        }

        lastPerformanceFeeTime = uint32(block.timestamp);
    }

    /**
     * @notice The Origami contract managing the deposits/exits and the application of
     * the deposit tokens into the underlying protocol
     */
    function manager() external view returns (IOrigamiOTokenManager) {
        return IOrigamiOTokenManager(address(lovManager));
    }

    /**
     * @notice The token used to track reserves for this investment
     */
    function reserveToken() external view returns (address) {
        return lovManager.reserveToken();
    }

    /**
     * @notice The underlying reserve token this investment wraps. 
     */
    function baseToken() external virtual override view returns (address) {
        return address(lovManager.baseToken());
    }

    /**
     * @notice The set of accepted tokens which can be used to deposit.
     */
    function acceptedInvestTokens() external virtual override view returns (address[] memory) {
        return lovManager.acceptedInvestTokens();
    }

    /**
     * @notice The set of accepted tokens which can be used to exit into.
     */
    function acceptedExitTokens() external virtual override view returns (address[] memory) {
        return lovManager.acceptedExitTokens();
    }
        
    /**
     * @notice Whether new investments are paused.
     */
    function areInvestmentsPaused() external virtual override view returns (bool) {
        return lovManager.areInvestmentsPaused();
    }

    /**
     * @notice Whether exits are temporarily paused.
     */
    function areExitsPaused() external virtual override view returns (bool) {
        return lovManager.areExitsPaused();
    }

    /**
     * @notice Get a quote to buy the lovToken using an accepted deposit token.
     * @param fromTokenAmount How much of the deposit token to invest with
     * @param fromToken What ERC20 token to purchase with. This must be one of `acceptedInvestTokens`
     * @param maxSlippageBps The maximum acceptable slippage of the received investment amount
     * @param deadline The maximum deadline to execute the exit.
     * @return quoteData The quote data, including any params required for the underlying investment type.
     * @return investFeeBps Any fees expected when investing with the given token, either from Origami or from the underlying investment.
     */
    function investQuote(
        uint256 fromTokenAmount,
        address fromToken,
        uint256 maxSlippageBps,
        uint256 deadline
    ) external virtual override view returns (
        InvestQuoteData memory quoteData, 
        uint256[] memory investFeeBps
    ) {
        (quoteData, investFeeBps) = lovManager.investQuote(fromTokenAmount, fromToken, maxSlippageBps, deadline);
    }

    /**
     * @notice Get a quote to sell this lovToken to receive one of the accepted exit tokens
     * @param investmentTokenAmount The amount of this lovToken to sell
     * @param toToken The token to receive when selling. This must be one of `acceptedExitTokens`
     * @param maxSlippageBps The maximum acceptable slippage of the received `toToken`
     * @param deadline The maximum deadline to execute the exit.
     * @return quoteData The quote data, including any other quote params required for this investment type.
     * @return exitFeeBps Any fees expected when exiting the investment to the nominated token, either from Origami or from the underlying investment.
     */
    function exitQuote(
        uint256 investmentTokenAmount, 
        address toToken,
        uint256 maxSlippageBps,
        uint256 deadline
    ) external virtual override view returns (
        ExitQuoteData memory quoteData, 
        uint256[] memory exitFeeBps
    ) {
        (quoteData, exitFeeBps) = lovManager.exitQuote(investmentTokenAmount, toToken, maxSlippageBps, deadline);
    }

    /**
     * @notice How many reserve tokens would one get given a number of lovToken shares
     * @dev This will use the `SPOT_PRICE` to value any debt in terms of the reserve token
     */
    function sharesToReserves(uint256 shares) external override view returns (uint256) {
        return lovManager.sharesToReserves(shares, IOrigamiOracle.PriceType.SPOT_PRICE);
    }

    /**
     * @notice How many lovToken shares would one get given a number of reserve tokens
     * @dev This will use the Oracle `SPOT_PRICE` to value any debt in terms of the reserve token
     */
    function reservesToShares(uint256 reserves) external override view returns (uint256) {
        return lovManager.reservesToShares(reserves, IOrigamiOracle.PriceType.SPOT_PRICE);
    }

    /**
     * @notice How many reserve tokens would one get given a single share, as of now
     * @dev This will use the Oracle 'HISTORIC_PRICE' to value any debt in terms of the reserve token
     */
    function reservesPerShare() external override view returns (uint256) {
        return lovManager.sharesToReserves(10 ** decimals(), IOrigamiOracle.PriceType.HISTORIC_PRICE);
    }
    
    /**
     * @notice The current amount of available reserves for redemptions
     * @dev This will use the Oracle `SPOT_PRICE` to value any debt in terms of the reserve token
     */
    function totalReserves() external override view returns (uint256) {
        return lovManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE);
    }

    /**
     * @notice Retrieve the current assets, liabilities and calculate the ratio
     * @dev This will use the Oracle `SPOT_PRICE` to value any debt in terms of the reserve token
     */
    function assetsAndLiabilities() external override view returns (
        uint256 /*assets*/,
        uint256 /*liabilities*/,
        uint256 /*ratio*/
    ) {
        return lovManager.assetsAndLiabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
    }

    /**
     * @notice The current effective exposure (EE) of this lovToken
     * to `PRECISION` precision
     * @dev = reserves / (reserves - liabilities)
     * This will use the Oracle `SPOT_PRICE` to value any debt in terms of the reserve token
     */
    function effectiveExposure() external override view returns (uint128 /*effectiveExposure*/) {
        return lovManager.effectiveExposure(IOrigamiOracle.PriceType.SPOT_PRICE);
    }

    /**
     * @notice The valid lower and upper bounds of A/L allowed when users deposit/exit into lovToken
     * @dev Transactions will revert if the resulting A/L is outside of this range
     */
    function userALRange() external override view returns (uint128 /*floor*/, uint128 /*ceiling*/) {
        return lovManager.userALRange();
    }

    /**
     * @notice The current deposit and exit fee based on market conditions.
     * Fees are the equivalent of burning lovToken shares - benefit remaining vault users
     * @dev represented in basis points
     */
    function getDynamicFeesBps() external override view returns (uint256 depositFeeBps, uint256 exitFeeBps) {
        return lovManager.getDynamicFeesBps();
    }

    /**
     * @notice The maximum amount of fromToken's that can be deposited
     * taking any other underlying protocol constraints into consideration
     */
    function maxInvest(address fromToken) external override view returns (uint256) {
        return lovManager.maxInvest(fromToken);
    }

    /**
     * @notice The maximum amount of tokens that can be exited into the toToken
     * taking any other underlying protocol constraints into consideration
     */
    function maxExit(address toToken) external override view returns (uint256) {
        return lovManager.maxExit(toToken);
    }
    
    /**
     * @notice The performance fee amount which would be minted as of now, 
     * based on the total supply
     */
    function performanceFeeAmount() public override view returns (uint256) {
        // totalSupply * feeBps * 7 days / 365 days / 10_000
        // Round down (protocol takes less of a fee)
        return OrigamiMath.mulDiv(
            totalSupply(), 
            performanceFee * PERFORMANCE_FEE_FREQUENCY, 
            OrigamiMath.BASIS_POINTS_DIVISOR * 365 days, 
            OrigamiMath.Rounding.ROUND_DOWN
        );
    }
}
