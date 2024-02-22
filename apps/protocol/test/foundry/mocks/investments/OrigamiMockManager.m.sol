pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IMintableToken } from "contracts/interfaces/common/IMintableToken.sol";
import { IOrigamiOTokenManager } from "contracts/interfaces/investments/IOrigamiOTokenManager.sol";

import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiManagerPausable } from "contracts/investments/util/OrigamiManagerPausable.sol";

contract OrigamiMockManager is IOrigamiOTokenManager, OrigamiManagerPausable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IMintableToken;
    using OrigamiMath for uint256;

    /* solhint-disable immutable-vars-naming */
    IERC20 public immutable depositToken;
    IMintableToken public immutable oToken;
    address public immutable feeCollector;
    uint256 public sellFeeRate;

    constructor(
        address _initialOwner,
        address _oToken,
        address _depositToken,
        address _feeCollector,
        uint128 _sellFeeRate
    ) OrigamiElevatedAccess(_initialOwner) {
        oToken = IMintableToken(_oToken);
        depositToken = IERC20(_depositToken);
        feeCollector = _feeCollector;
        if (_sellFeeRate > OrigamiMath.BASIS_POINTS_DIVISOR) revert CommonEventsAndErrors.InvalidParam();
        sellFeeRate = _sellFeeRate;
    }

    function investWithToken(
        address /*account*/,
        IOrigamiInvestment.InvestQuoteData calldata quoteData
    ) external override view returns (
        uint256 investmentAmount
    ) {
        if (_paused.investmentsPaused) revert CommonEventsAndErrors.IsPaused();
        if (quoteData.fromToken != address(depositToken)) revert CommonEventsAndErrors.InvalidToken(quoteData.fromToken);

        // User gets 1:1
        investmentAmount = quoteData.fromTokenAmount;
    }

    function exitToToken(
        address /*account*/,
        IOrigamiInvestment.ExitQuoteData memory quoteData,
        address recipient
    ) external override returns (
        uint256 toTokenAmount,
        uint256 toBurnAmount
    ){
        if (_paused.exitsPaused) revert CommonEventsAndErrors.IsPaused();
        if (quoteData.investmentTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (quoteData.toToken != address(depositToken)) revert CommonEventsAndErrors.InvalidToken(quoteData.toToken);

        (uint256 nonFees, uint256 fees) = quoteData.investmentTokenAmount.splitSubtractBps(sellFeeRate);
        toTokenAmount = nonFees;

        if (fees != 0) {
            oToken.safeTransfer(feeCollector, fees);
        }

        if (nonFees != 0) {
            depositToken.safeTransfer(recipient, nonFees);

            // Burn the remaining
            toBurnAmount = nonFees;
        }
    }

    function baseToken() external view returns (address) {
        return address(depositToken);
    }

    function acceptedInvestTokens() external override view returns (address[] memory tokens) {
        tokens = new address[](1);
        tokens[0] = address(depositToken);
    }

    function acceptedExitTokens() external override view returns (address[] memory tokens) {
        tokens = new address[](1);
        tokens[0] = address(depositToken);
    }
        
    /**
     * @notice Whether new investments are paused.
     */
    function areInvestmentsPaused() external override view returns (bool) {
        return _paused.investmentsPaused;
    }

    /**
     * @notice Whether exits are temporarily paused.
     */
    function areExitsPaused() external override view returns (bool) {
        return _paused.exitsPaused;
    }

    function investQuote(
        uint256 fromTokenAmount,
        address fromToken,
        uint256 maxSlippageBps,
        uint256 deadline
    ) external override view returns (
        IOrigamiInvestment.InvestQuoteData memory quoteData, 
        uint256[] memory investFeeBps
    ) {
        if (fromToken != address(depositToken)) revert CommonEventsAndErrors.InvalidToken(fromToken);
        if (fromTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        // minted 1:1, no fees or slippage
        quoteData = IOrigamiInvestment.InvestQuoteData({
            fromToken: fromToken,
            fromTokenAmount: fromTokenAmount,
            maxSlippageBps: maxSlippageBps,
            deadline: deadline,
            expectedInvestmentAmount: fromTokenAmount,
            minInvestmentAmount: fromTokenAmount,
            underlyingInvestmentQuoteData: "" // No extra underlyingInvestmentQuoteData
        });
        
        investFeeBps = new uint256[](0);
    }

    function exitQuote(
        uint256 investmentTokenAmount, 
        address toToken,
        uint256 maxSlippageBps,
        uint256 deadline
    ) external override view returns (
        IOrigamiInvestment.ExitQuoteData memory quoteData, 
        uint256[] memory exitFeeBps
    ) {
        if (investmentTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (toToken != address(depositToken)) revert CommonEventsAndErrors.InvalidToken(toToken);

        uint256 _sellFeeRate = sellFeeRate;

        // sold 1:1, no slippage, with exit fee
        quoteData.investmentTokenAmount = investmentTokenAmount;
        quoteData.toToken = toToken;
        quoteData.maxSlippageBps = maxSlippageBps;
        quoteData.deadline = deadline;
        quoteData.expectedToTokenAmount = investmentTokenAmount.subtractBps(_sellFeeRate);
        quoteData.minToTokenAmount = quoteData.expectedToTokenAmount;
        // No extra underlyingInvestmentQuoteData

        exitFeeBps = new uint256[](1);
        exitFeeBps[0] = _sellFeeRate;
    }
    
    /**
     * @notice The maximum amount of fromToken's that can be deposited
     * taking any other underlying protocol constraints into consideration
     */
    function maxInvest(address /*fromToken*/) external override pure returns (uint256 amount) {
        amount = 123e18;
    }

    /**
     * @notice The maximum amount of tokens that can be exited into the toToken
     * taking any other underlying protocol constraints into consideration
     */
    function maxExit(address /*toToken*/) external override pure returns (uint256 amount) {
        amount = 456e18;
    }
}