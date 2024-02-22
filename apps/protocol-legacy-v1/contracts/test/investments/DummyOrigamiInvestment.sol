pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {OrigamiInvestment} from "../../investments/OrigamiInvestment.sol";
import {IWrappedToken} from "../../interfaces/common/IWrappedToken.sol";
import {CommonEventsAndErrors} from "../../common/CommonEventsAndErrors.sol";

contract DummyOrigamiInvestment is OrigamiInvestment {
    using SafeERC20 for IERC20;
    using Address for address payable;

    address public immutable investToken;
    address public immutable exitToken;

    uint256 public investFee = 100; // 1%
    uint256 public exitFee = 500; // 5%

    bool public investmentsPaused;
    bool public exitsPaused;

    constructor(
        address _initialGov,
        string memory _name,
        string memory _symbol,
        address _investToken,
        address _exitToken
    ) OrigamiInvestment(_name, _symbol, _initialGov) {
        investToken = _investToken;
        exitToken = _exitToken;
    }

    function baseToken() external view returns (address) {
        return investToken;
    }

    function acceptedInvestTokens() external override view returns (address[] memory tokens) {
        tokens = new address[](1);
        tokens[0] = investToken;
    }

    function acceptedExitTokens() external override view returns (address[] memory tokens) {
        tokens = new address[](1);
        tokens[0] = exitToken;
    }

    function setPaused(bool investments, bool exits) external {
        investmentsPaused = investments;
        exitsPaused = exits; 
    }

    /**
     * @notice Whether new investments are paused.
     */
    function areInvestmentsPaused() external override view returns (bool) {
        return investmentsPaused;
    }

    /**
     * @notice Whether exits are temporarily paused.
     */
    function areExitsPaused() external override view returns (bool) {
        return exitsPaused;
    }

    function investQuote(
        uint256 fromTokenAmount, 
        address fromToken,
        uint256 maxSlippageBps,
        uint256 deadline
    ) external override view returns (
        InvestQuoteData memory quoteData, 
        uint256[] memory investFeeBps
    ) {
        quoteData.fromToken = fromToken;
        quoteData.fromTokenAmount = fromTokenAmount;
        quoteData.maxSlippageBps = maxSlippageBps;
        quoteData.deadline = deadline;
        quoteData.expectedInvestmentAmount = fromTokenAmount * (10_000 - investFee) / 10_000;
        quoteData.minInvestmentAmount = quoteData.expectedInvestmentAmount;
        investFeeBps = new uint256[](1);
        investFeeBps[0] = investFee;
    }

    function investWithToken(
         InvestQuoteData calldata quoteData
    ) external override returns (
        uint256 investmentAmount
    ) {
        if (investmentsPaused) revert CommonEventsAndErrors.IsPaused();
        if (quoteData.fromToken != investToken) revert CommonEventsAndErrors.InvalidToken(quoteData.fromToken);
        if (quoteData.fromTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        // Pull the tokens and mint
        IERC20(quoteData.fromToken).safeTransferFrom(msg.sender, address(this), quoteData.fromTokenAmount);
        investmentAmount = quoteData.fromTokenAmount * (10_000 - investFee) / 10_000;
        _mint(msg.sender, investmentAmount);
        emit Invested(msg.sender, quoteData.fromTokenAmount, quoteData.fromToken, investmentAmount);
    }

    function investWithNative(
        InvestQuoteData calldata quoteData
    ) external payable override returns (
        uint256 investmentAmount
    ) {
        if (investmentsPaused) revert CommonEventsAndErrors.IsPaused();
        if (quoteData.fromTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (quoteData.fromTokenAmount != msg.value) revert CommonEventsAndErrors.InvalidAmount(address(0), msg.value);
        if (quoteData.fromToken != address(0)) revert CommonEventsAndErrors.InvalidToken(quoteData.fromToken);

        investmentAmount = quoteData.fromTokenAmount * (10_000 - investFee) / 10_000;
        _mint(msg.sender, investmentAmount);
        emit Invested(msg.sender, quoteData.fromTokenAmount, quoteData.fromToken, investmentAmount);
    }

    function exitQuote(
        uint256 investmentAmount, 
        address toToken,
        uint256 maxSlippageBps,
        uint256 deadline
    ) external override view returns (
        ExitQuoteData memory quoteData, 
        uint256[] memory exitFeeBps
    ) {
        quoteData.investmentTokenAmount = investmentAmount;
        quoteData.toToken = toToken;
        quoteData.maxSlippageBps = maxSlippageBps;
        quoteData.deadline = deadline;
        quoteData.expectedToTokenAmount = investmentAmount * (10_000 - exitFee) / 10_000;
        quoteData.minToTokenAmount;
        exitFeeBps = new uint256[](1);
        exitFeeBps[0] = exitFee;
    }

    function exitToToken(
        ExitQuoteData calldata quoteData, 
        address recipient
    ) external override returns (
        uint256 toTokenAmount
    ) {
        if (exitsPaused) revert CommonEventsAndErrors.IsPaused();
        if (quoteData.toToken != exitToken) revert CommonEventsAndErrors.InvalidToken(quoteData.toToken);
        if (quoteData.investmentTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        toTokenAmount = quoteData.investmentTokenAmount * (10_000 - exitFee) / 10_000;
        _burn(msg.sender, quoteData.investmentTokenAmount);
        IERC20(quoteData.toToken).safeTransfer(recipient, toTokenAmount);

        emit Exited(msg.sender, quoteData.investmentTokenAmount, quoteData.toToken, toTokenAmount, recipient);
    }

    function exitToNative(
        ExitQuoteData calldata quoteData,
        address payable recipient
    ) external override returns (
        uint256 nativeAmount
    ) {
        if (exitsPaused) revert CommonEventsAndErrors.IsPaused();
        if (quoteData.investmentTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (quoteData.toToken != address(0)) revert CommonEventsAndErrors.InvalidToken(quoteData.toToken);

        nativeAmount = quoteData.investmentTokenAmount * (10_000 - exitFee) / 10_000;
        _burn(msg.sender, quoteData.investmentTokenAmount);

        recipient.sendValue(nativeAmount);

        emit Exited(msg.sender, quoteData.investmentTokenAmount, quoteData.toToken, nativeAmount, recipient);
    }
}
