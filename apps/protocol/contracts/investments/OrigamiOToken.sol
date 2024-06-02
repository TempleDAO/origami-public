pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/OrigamiOToken.sol)

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IOrigamiOToken } from "contracts/interfaces/investments/IOrigamiOToken.sol";
import { IOrigamiOTokenManager } from "contracts/interfaces/investments/IOrigamiOTokenManager.sol";
import { OrigamiInvestment } from "contracts/investments/OrigamiInvestment.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/**
 * @title Origami oToken (no native ETH support for deposits/exits)
 * 
 * @notice Users deposit with an accepted token and are minted oTokens
 * Generally speaking this oToken will represent the underlying protocol it is wrapping, 1:1
 *
 * @dev The logic on how to handle the deposits/exits is delegated to a manager contract.
 */
contract OrigamiOToken is OrigamiInvestment, IOrigamiOToken {
    using SafeERC20 for IERC20;

    /**
     * @notice The Origami contract managing the deposits/exits and the application of
     * the deposit tokens into the underlying protocol
     */
    IOrigamiOTokenManager public override manager;

    /**
     * @notice Protocol can mint/burn oToken's for the AMO purposes. This amount is tracked
     * in order to calculate circulating vs non-circulating supply.
     */
    uint256 public override amoMinted;
    
    constructor(
        address _initialOwner,
        string memory _name,
        string memory _symbol
    ) OrigamiInvestment(_name, _symbol, _initialOwner) {}

    /**
     * @notice Set the Origami oToken Manager.
     */
    function setManager(address _manager) external override onlyElevatedAccess {
        if (_manager == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        emit ManagerSet(_manager);
        manager = IOrigamiOTokenManager(_manager);
    }

    /**
     * @notice Protocol mint for AMO capabilities
     */
    function amoMint(address _to, uint256 _amount) external override onlyElevatedAccess {
        amoMinted = amoMinted + _amount;
        emit AmoMint(_to, _amount);
        _mint(_to, _amount);
    }

    /**
     * @notice Protocol burn for AMO capabilities
     * @dev Cannot burn more AMO tokens than were AMO minted.
     */
    function amoBurn(address _account, uint256 _amount) external override onlyElevatedAccess {
        uint256 _amoMinted = amoMinted;
        if (_amount > _amoMinted) revert CommonEventsAndErrors.InvalidAmount(address(this), _amount);
        unchecked {
            amoMinted = _amoMinted - _amount;
        }

        emit AmoBurn(_account, _amount);
        _burn(_account, _amount);
    }

    /** 
     * @notice User buys this oToken with an amount of one of the approved ERC20 tokens
     * @param quoteData The quote data received from investQuote()
     * @return investmentAmount The actual number of receipt tokens received, inclusive of any fees.
     */
    function investWithToken(
        InvestQuoteData calldata quoteData
    ) external virtual override nonReentrant returns (uint256 investmentAmount) {
        if (quoteData.fromTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        // Send the investment token to the manager
        IOrigamiOTokenManager _manager = manager;
        IERC20(quoteData.fromToken).safeTransferFrom(msg.sender, address(_manager), quoteData.fromTokenAmount);
        investmentAmount = _manager.investWithToken(msg.sender, quoteData);

        emit Invested(msg.sender, quoteData.fromTokenAmount, quoteData.fromToken, investmentAmount);

        // Mint the oToken for the user
        if (investmentAmount != 0) {
            _mint(msg.sender, investmentAmount);
        }
    }

    /** 
     * @notice Sell this oToken to receive one of the accepted exit tokens. 
     * @param quoteData The quote data received from exitQuote()
     * @param recipient The receiving address of the `toToken`
     * @return toTokenAmount The number of `toToken` tokens received upon selling the oToken.
     */
    function exitToToken(
        ExitQuoteData calldata quoteData,
        address recipient
    ) external virtual override nonReentrant returns (
        uint256 toTokenAmount
    ) {
        if (quoteData.investmentTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (recipient == address(0)) revert CommonEventsAndErrors.InvalidAddress(recipient);

        // Send the oToken to the manager
        IOrigamiOTokenManager _manager = manager;
        _transfer(msg.sender, address(_manager), quoteData.investmentTokenAmount);
        uint256 oTokenToBurn;
        (toTokenAmount, oTokenToBurn) = _manager.exitToToken(msg.sender, quoteData, recipient);
        
        emit Exited(msg.sender, quoteData.investmentTokenAmount, quoteData.toToken, toTokenAmount, recipient);
        
        // Burn the oToken
        if (oTokenToBurn != 0) {
            _burn(address(_manager), oTokenToBurn);
        }
    }

    /** 
     * @notice Unsupported - cannot invest in this oToken using native chain ETH/AVAX
     */
    function investWithNative(
        InvestQuoteData calldata /*quoteData*/
    ) external payable virtual override returns (uint256) {
        revert Unsupported();
    }

    /** 
     * @notice Unsupported - cannot exit this oToken to native chain ETH/AVAX
     */
    function exitToNative(
        ExitQuoteData calldata /*quoteData*/, address payable /*recipient*/
    ) external virtual override returns (uint256 /*nativeAmount*/) {
        revert Unsupported();
    }

    /**
     * @notice Override to check when burning, the circulatingSupply cannot
     * go negative
     */
    function _afterTokenTransfer(address /*from*/, address to, uint256 amount) internal virtual override {
        // to == address(0) when burning
        if (to == address(0) && amoMinted > totalSupply()) revert CommonEventsAndErrors.InvalidAmount(address(this), amount);
    }

    /**
     * @notice The underlying token this investment wraps. 
     */
    function baseToken() external virtual override view returns (address) {
        return address(manager.baseToken());
    }

    /**
     * @notice The set of accepted tokens which can be used to deposit.
     */
    function acceptedInvestTokens() external virtual override view returns (address[] memory) {
        return manager.acceptedInvestTokens();
    }

    /**
     * @notice The set of accepted tokens which can be used to exit into.
     */
    function acceptedExitTokens() external virtual override view returns (address[] memory) {
        return manager.acceptedExitTokens();
    }
        
    /**
     * @notice Whether new investments are paused.
     */
    function areInvestmentsPaused() external virtual override view returns (bool) {
        return manager.areInvestmentsPaused();
    }

    /**
     * @notice Whether exits are temporarily paused.
     */
    function areExitsPaused() external virtual override view returns (bool) {
        return manager.areExitsPaused();
    }

    /**
     * @notice Get a quote to buy the oToken using an accepted deposit token.
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
        (quoteData, investFeeBps) = manager.investQuote(fromTokenAmount, fromToken, maxSlippageBps, deadline);
    }

    /**
     * @notice Get a quote to sell this oToken to receive one of the accepted exit tokens
     * @param investmentTokenAmount The amount of this oToken to sell
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
        (quoteData, exitFeeBps) = manager.exitQuote(investmentTokenAmount, toToken, maxSlippageBps, deadline);
    }

    /**
     * @notice The amount of non-AMO owned circulating supply
     */
    function circulatingSupply() external override view returns (uint256) {
        unchecked {
            return totalSupply() - amoMinted;
        }
    }
    
    /**
     * @notice The maximum amount of fromToken's that can be deposited
     * taking any other underlying protocol constraints into consideration
     */
    function maxInvest(address fromToken) external override view returns (uint256 amount) {
        amount = manager.maxInvest(fromToken);
    }

    /**
     * @notice The maximum amount of tokens that can be exited into the toToken
     * taking any other underlying protocol constraints into consideration
     */
    function maxExit(address toToken) external override view returns (uint256 amount) {
        amount = manager.maxExit(toToken);
    }
}
