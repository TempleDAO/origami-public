pragma solidity ^0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/gmx/OrigamiGmxManager.sol)

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IGmxRewardRouter} from "../../interfaces/external/gmx/IGmxRewardRouter.sol";
import {IOrigamiInvestment} from "../../interfaces/investments/IOrigamiInvestment.sol";
import {IOrigamiGmxManager} from "../../interfaces/investments/gmx/IOrigamiGmxManager.sol";
import {IOrigamiGmxEarnAccount} from "../../interfaces/investments/gmx/IOrigamiGmxEarnAccount.sol";
import {IMintableToken} from "../../interfaces/common/IMintableToken.sol";
import {IGmxVault} from "../../interfaces/external/gmx/IGmxVault.sol";
import {IGlpManager} from "../../interfaces/external/gmx/IGlpManager.sol";
import {IGmxVaultPriceFeed} from "../../interfaces/external/gmx/IGmxVaultPriceFeed.sol";

import {Operators} from "../../common/access/Operators.sol";
import {FractionalAmount} from "../../common/FractionalAmount.sol";
import {CommonEventsAndErrors} from "../../common/CommonEventsAndErrors.sol";

/// @title Origami GMX/GLP Manager
/// @notice Manages Origami's GMX and GLP positions, policy decisions and rewards harvesting/compounding.
contract OrigamiGmxManager is IOrigamiGmxManager, Ownable, Operators {
    using SafeERC20 for IERC20;
    using SafeERC20 for IMintableToken;
    using FractionalAmount for FractionalAmount.Data;

    // Note: The below (GMX.io) contracts can be found here: https://gmxio.gitbook.io/gmx/contracts

    /// @notice $GMX (GMX.io)
    IERC20 public gmxToken;

    /// @notice $GLP (GMX.io)
    IERC20 public glpToken;

    /// @notice The GMX glpManager contract, responsible for buying/selling $GLP (GMX.io)
    IGlpManager public glpManager;

    /// @notice The GMX Vault contract, required for calculating accurate quotes for buying/selling $GLP (GMX.io)
    IGmxVault public gmxVault;

    /// @notice $wrappedNative - wrapped ETH/AVAX
    address public wrappedNativeToken;

    /// @notice $oGMX - The Origami ERC20 receipt token over $GMX
    /// Users get oGMX for initial $GMX deposits, and for each esGMX which Origami is rewarded,
    /// minus a fee.
    IMintableToken public immutable override oGmxToken;

    /// @notice $oGLP - The Origami ECR20 receipt token over $GLP
    /// Users get oGLP for initial $GLP deposits.
    IMintableToken public immutable override oGlpToken;

    /// @notice Percentages of oGMX rewards (minted based off esGMX rewards) that Origami retains as a fee
    FractionalAmount.Data public oGmxRewardsFeeRate;

    /// @notice Percentages of oGMX/oGLP that Origami retains as a fee when users sell out of their position
    FractionalAmount.Data public sellFeeRate;

    /// @notice Percentage of esGMX rewards that Origami will vest into GMX (1/365 per day).
    /// The remainder is staked.
    FractionalAmount.Data public esGmxVestingRate;

    /// @notice The GMX vault rewards aggregator - any harvested rewards from staked GMX/esGMX/mult points are sent here
    address public gmxRewardsAggregator;

    /// @notice The GLP vault rewards aggregator - any harvested rewards from staked GLP are sent here.
    address public glpRewardsAggregator;

    /// @notice The set of reward tokens that the GMX manager yields to users.
    /// [ ETH/AVAX, oGMX ]
    address[] public rewardTokens;

    /// @notice The address used to collect the Origami fees.
    address public feeCollector;

    // @notice The Origami contract holding the majority of staked GMX/GLP/multiplier points/esGMX.
    // @dev When users sell GMX/GLP positions are unstaked from this account.
    // GMX positions are also deposited directly into this account (no cooldown for GMX, unlike GLP)
    IOrigamiGmxEarnAccount public primaryEarnAccount;

    // @notice The Origami contract holding a small amount of staked GMX/GLP/multiplier points/esGMX.
    // @dev This account is used to accept user deposits for GLP, such that the cooldown clock isn't reset
    // in the primary earn account (which may block any user withdrawals)
    // Staked GLP positions are transferred to the primaryEarnAccount on a schedule (eg daily), which does
    // not reset the cooldown clock.
    IOrigamiGmxEarnAccount public secondaryEarnAccount;

    /// @notice The current paused/unpaused state of investments/exits.
    IOrigamiGmxManager.Paused private _paused;

    struct GlpUnderlyingInvestQuoteData {
        uint256 expectedUsdg;
    }

    event OGmxRewardsFeeRateSet(uint128 numerator, uint128 denominator);
    event SellFeeRateSet(uint128 numerator, uint128 denominator);
    event EsGmxVestingRateSet(uint128 numerator, uint128 denominator);
    event FeeCollectorSet(address indexed feeCollector);
    event RewardsAggregatorsSet(address gmxRewardsAggregator, address glpRewardsAggregator);
    event PrimaryEarnAccountSet(address indexed account);
    event SecondaryEarnAccountSet(address indexed account);
    event PausedSet(Paused paused);

    constructor(
        address _gmxRewardRouter,
        address _glpRewardRouter,
        address _oGmxTokenAddr,
        address _oGlpTokenAddr,
        address _feeCollectorAddr,
        address _primaryEarnAccount,
        address _secondaryEarnAccount
    ) {
        initGmxContracts(_gmxRewardRouter, _glpRewardRouter);

        oGmxToken = IMintableToken(_oGmxTokenAddr);
        oGlpToken = IMintableToken(_oGlpTokenAddr);

        rewardTokens = [wrappedNativeToken, _oGmxTokenAddr, _oGlpTokenAddr];

        primaryEarnAccount = IOrigamiGmxEarnAccount(_primaryEarnAccount);
        secondaryEarnAccount = IOrigamiGmxEarnAccount(_secondaryEarnAccount);
        feeCollector = _feeCollectorAddr;

        // All numerators start at 0 on construction
        oGmxRewardsFeeRate.denominator = 100;
        sellFeeRate.denominator = 100;
        esGmxVestingRate.denominator = 100;
    }

    /// @dev In case any of the upstream GMX contracts are upgraded this can be re-initialized.
    function initGmxContracts(
        address _gmxRewardRouter, 
        address _glpRewardRouter
    ) public onlyOwner {
        IGmxRewardRouter gmxRewardRouter = IGmxRewardRouter(_gmxRewardRouter);
        IGmxRewardRouter glpRewardRouter = IGmxRewardRouter(_glpRewardRouter);
        glpManager = IGlpManager(glpRewardRouter.glpManager());
        wrappedNativeToken = gmxRewardRouter.weth();
        
        gmxToken = IERC20(gmxRewardRouter.gmx());
        glpToken = IERC20(glpRewardRouter.glp());
        gmxVault = IGmxVault(glpManager.vault());
    }

    function paused() external view override returns (IOrigamiGmxManager.Paused memory) {
        // GLP investments can also be temporarily paused if it's paused in order to 
        // transfer staked glp from secondary -> primary
        bool areSecondaryGlpInvestmentsPaused = (address(secondaryEarnAccount) == address(0))
            ? false
            : secondaryEarnAccount.glpInvestmentsPaused();
        return IOrigamiGmxManager.Paused({
            glpInvestmentsPaused: _paused.glpInvestmentsPaused || areSecondaryGlpInvestmentsPaused,
            gmxInvestmentsPaused: _paused.gmxInvestmentsPaused,
            glpExitsPaused: _paused.glpExitsPaused,
            gmxExitsPaused: _paused.gmxExitsPaused
        });
    }

    function setPaused(Paused memory updatedPaused) external onlyOwner {
        _paused = updatedPaused;
        emit PausedSet(_paused);
    }

    /// @notice Set the fee rate Origami takes on oGMX rewards
    /// (which are minted based off the quantity of esGMX rewards we receive)
    function setOGmxRewardsFeeRate(uint128 _numerator, uint128 _denominator) external onlyOwner {
        oGmxRewardsFeeRate.set(_numerator, _denominator);
        emit OGmxRewardsFeeRateSet(_numerator, _denominator);
    }

    /// @notice Set the proportion of esGMX that we vest whenever rewards are harvested.
    /// The remainder are staked.
    function setEsGmxVestingRate(uint128 _numerator, uint128 _denominator) external onlyOwner {
        esGmxVestingRate.set(_numerator, _denominator);
        emit EsGmxVestingRateSet(_numerator, _denominator);
    }

    /// @notice Set the proportion of fees oGMX/oGLP Origami retains when users sell out
    /// of their position.
    function setSellFeeRate(uint128 _numerator, uint128 _denominator) external onlyOwner {
        sellFeeRate.set(_numerator, _denominator);
        emit SellFeeRateSet(_numerator, _denominator);
    }

    /// @notice Set the address for where Origami fees are sent
    function setFeeCollector(address _feeCollector) external onlyOwner {
        feeCollector = _feeCollector;
        emit FeeCollectorSet(_feeCollector);
    }

    /// @notice Set the Origami account responsible for holding the majority of staked GMX/GLP/esGMX/mult points on GMX.io
    function setPrimaryEarnAccount(address _primaryEarnAccount) external onlyOwner {
        if (_primaryEarnAccount == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        primaryEarnAccount = IOrigamiGmxEarnAccount(_primaryEarnAccount);
        emit PrimaryEarnAccountSet(_primaryEarnAccount);
    }

    /// @notice Set the Origami account responsible for holding a smaller/initial amount of staked GMX/GLP/esGMX/mult points on GMX.io
    /// @dev This is allowed to be set to 0x, ie unset.
    function setSecondaryEarnAccount(address _secondaryEarnAccount) external onlyOwner {
        secondaryEarnAccount = IOrigamiGmxEarnAccount(_secondaryEarnAccount);
        emit SecondaryEarnAccountSet(_secondaryEarnAccount);
    }

    /// @notice Set the Origami GMX/GLP rewards aggregators
    function setRewardsAggregators(address _gmxRewardsAggregator, address _glpRewardsAggregator) external onlyOwner {
        gmxRewardsAggregator = _gmxRewardsAggregator;
        glpRewardsAggregator = _glpRewardsAggregator;
        emit RewardsAggregatorsSet(_gmxRewardsAggregator, _glpRewardsAggregator);
    }

    function addOperator(address _address) external override onlyOwner {
        _addOperator(_address);
    }

    function removeOperator(address _address) external override onlyOwner {
        _removeOperator(_address);
    }

    /// @notice The set of reward tokens we give to the staking contract.
    function rewardTokensList() external view override returns (address[] memory tokens) {
        return rewardTokens;
    }

    /// @notice The amount of rewards up to this block that Origami is due to distribute to users.
    /// @param vaultType If GLP, get the reward rates for just staked GLP rewards. If GMX, get the reward rates for combined GMX/esGMX/mult points
    /// ie the net amount after Origami has deducted it's fees.
    function harvestableRewards(IOrigamiGmxEarnAccount.VaultType vaultType) external override view returns (uint256[] memory amounts) {
        amounts = new uint256[](rewardTokens.length);

        // Pull the currently claimable amount from Origami's staked positions at GMX.
        // Secondary earn account rewards aren't automatically harvested, so intentionally not included here.
        (uint256 nativeAmount, uint256 esGmxAmount) = primaryEarnAccount.harvestableRewards(vaultType);

        // Ignore any portions we will be retaining as fees.
        amounts[0] = nativeAmount;
        (, amounts[1]) = oGmxRewardsFeeRate.split(esGmxAmount);
        // amounts[2] is reserved for oGLP while compounding
    }

    /// @notice The current native token and oGMX reward rates per second
    /// @param vaultType If GLP, get the reward rates for just staked GLP rewards. If GMX, get the reward rates for combined GMX/esGMX/mult points
    /// @dev Based on the current total Origami rewards, minus any portion of fees which we will take
    function projectedRewardRates(IOrigamiGmxEarnAccount.VaultType vaultType) external override view returns (uint256[] memory amounts) {
        amounts = new uint256[](rewardTokens.length);

        // Pull the reward rates from Origami's staked positions at GMX.
        (uint256 primaryNativeRewardRate, uint256 primaryEsGmxRewardRate) = primaryEarnAccount.rewardRates(vaultType);

        // Also include any native rewards from the secondary earn account (GLP deposits)
        // as native rewards (ie ETH) from the secondary earn account are harvested and distributed to users periodically.
        // esGMX rewards are not included from the secondary earn account, as these are perpetually staked and not automatically 
        // distributed to users.
        (uint256 secondaryNativeRewardRate,) = (address(secondaryEarnAccount) == address(0))
            ? (0, 0)
            : secondaryEarnAccount.rewardRates(vaultType);

        // Ignore any portions we will be retaining as fees.
        amounts[0] = primaryNativeRewardRate + secondaryNativeRewardRate;
        (, amounts[1]) = oGmxRewardsFeeRate.split(primaryEsGmxRewardRate);
        // amounts[2] is reserved for oGLP while compounding
    }

    /** 
     * @notice Harvest any claimable rewards up to this block from GMX.io, from the primary earn account.
     * 1/ Claimed esGMX:
     *     Vest a portion, and stake the rest -- according to `esGmxVestingRate` ratio
     *     Mint oGMX 1:1 for any esGMX that has been claimed.
     * 2/ Claimed GMX (from vested esGMX):
     *     Stake the GMX at GMX.io
     * 3/ Claimed ETH/AVAX
     *     Collect a portion as protocol fees and send the rest to the reward aggregators
     * 4/ Minted oGMX (from esGMX 1:1)
     *     Collect a portion as protocol fees and send the rest to the reward aggregators
     */
    function harvestRewards() external override onlyOperators {
        // Harvest the rewards from the primary earn account which has staked positions at GMX.io
        IOrigamiGmxEarnAccount.ClaimedRewards memory claimed = primaryEarnAccount.harvestRewards(esGmxVestingRate);

        // Apply any of the newly vested GMX
        if (claimed.vestedGmx > 0) {
            _applyGmx(claimed.vestedGmx);
        }

        // Handle esGMX rewards -- mint oGMX rewards and collect fees
        uint256 totalFees;
        uint256 _fees;
        uint256 _rewards;
        {
            // Any rewards claimed from staked GMX/esGMX/mult points => GMX Rewards Aggregator
            if (claimed.esGmxFromGmx > 0) {
                (_fees, _rewards) = oGmxRewardsFeeRate.split(claimed.esGmxFromGmx);
                totalFees += _fees;
                if (_rewards > 0) oGmxToken.mint(gmxRewardsAggregator, _rewards);
            }

            // Any rewards claimed from staked GLP => GLP Rewards Aggregator
            if (claimed.esGmxFromGlp > 0) {
                (_fees, _rewards) = oGmxRewardsFeeRate.split(claimed.esGmxFromGlp);
                totalFees += _fees;
                if (_rewards > 0) oGmxToken.mint(glpRewardsAggregator, _rewards);
            }

            // Mint the total oGMX fees
            if (totalFees > 0) {
                oGmxToken.mint(feeCollector, totalFees);
            }
        }

        // Handle ETH/AVAX rewards
        _processNativeRewards(claimed);
    }

    function _processNativeRewards(IOrigamiGmxEarnAccount.ClaimedRewards memory claimed) internal {
        // Any rewards claimed from staked GMX/esGMX/mult points => GMX Investment Manager
        if (claimed.wrappedNativeFromGmx > 0) {
            IERC20(wrappedNativeToken).safeTransfer(gmxRewardsAggregator, claimed.wrappedNativeFromGmx);
        }

        // Any rewards claimed from staked GLP => GLP Investment Manager
        if (claimed.wrappedNativeFromGlp > 0) {
            IERC20(wrappedNativeToken).safeTransfer(glpRewardsAggregator, claimed.wrappedNativeFromGlp);
        }
    }

    /** 
     * @notice Claim any ETH/AVAX rewards from the secondary earn account,
     * and perpetually stake any esGMX/multiplier points.
     */
    function harvestSecondaryRewards() external override onlyOperators {
        IOrigamiGmxEarnAccount.ClaimedRewards memory claimed = secondaryEarnAccount.handleRewards(
            IOrigamiGmxEarnAccount.HandleGmxRewardParams({
                shouldClaimGmx: false,
                shouldStakeGmx: false,
                shouldClaimEsGmx: true,
                shouldStakeEsGmx: true,
                shouldStakeMultiplierPoints: true,
                shouldClaimWeth: true,
                shouldConvertWethToEth: false
            })
        );

        _processNativeRewards(claimed);
    }

    /// @notice The amount of native ETH/AVAX rewards up to this block that the secondary earn account is due to distribute to users.
    /// @param vaultType If GLP, get the reward rates for just staked GLP rewards. If GMX, get the reward rates for combined GMX/esGMX/mult points
    /// ie the net amount after Origami has deducted it's fees.
    function harvestableSecondaryRewards(IOrigamiGmxEarnAccount.VaultType vaultType) external view returns (uint256[] memory amounts) {
        amounts = new uint256[](rewardTokens.length);

        // esGMX rewards aren't harvestable from the secondary earn account as they are perpetually staked - so intentionally not included here.
        (amounts[0],) = secondaryEarnAccount.harvestableRewards(vaultType);
    }

    /// @notice Apply any unstaked GMX (eg from user deposits) of $GMX into Origami's GMX staked position.
    function applyGmx(uint256 _amount) external onlyOperators {
        if (_amount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        _applyGmx(_amount);
    }

    function _applyGmx(uint256 _amount) internal {
        gmxToken.safeTransfer(address(primaryEarnAccount), _amount);
        primaryEarnAccount.stakeGmx(_amount);
    }

    /// @notice The set of accepted tokens which can be used to invest/exit into oGMX.
    function acceptedOGmxTokens() external view override returns (address[] memory tokens) {
        tokens = new address[](1);
        tokens[0] = address(gmxToken);
    }

    /**
     * @notice Get a quote to buy the oGMX using GMX.
     * @param fromTokenAmount How much of GMX to invest with
     * @param fromToken This must be the address of the GMX token
     * @return quoteData The quote data, including any other quote params required for this investment type. To be passed through when executing the quote.
     * @return investFeeBps [GMX.io's fee when depositing with `fromToken`]
     */
    function investOGmxQuote(
        uint256 fromTokenAmount,
        address fromToken
    ) external override view returns (
        IOrigamiInvestment.InvestQuoteData memory quoteData, 
        uint256[] memory investFeeBps
    ) {
        if (fromToken != address(gmxToken)) revert CommonEventsAndErrors.InvalidToken(fromToken);
        if (fromTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        // oGMX is minted 1:1, no fees
        quoteData.fromToken = fromToken;
        quoteData.fromTokenAmount = fromTokenAmount;
        quoteData.expectedInvestmentAmount = fromTokenAmount;
        // No extra underlyingInvestmentQuoteData

        investFeeBps = new uint256[](0);
    }

    /** 
      * @notice User buys oGMX with an amount GMX.
      * @param quoteData The quote data received from investQuote()
      * @return investmentAmount The actual number of receipt tokens received, inclusive of any fees.
      */
    function investOGmx(
        IOrigamiInvestment.InvestQuoteData calldata quoteData, 
        uint256 /*slippageBps currently unused*/
    ) external override onlyOperators returns (
        uint256 investmentAmount
    ) {
        if (_paused.gmxInvestmentsPaused) revert CommonEventsAndErrors.IsPaused();

        // Transfer the GMX straight to the primary earn account which stakes the GMX at GMX.io
        // NB: There is no cooldown when transferring GMX, so using the primary earn account for deposits is fine.
        gmxToken.safeTransfer(address(primaryEarnAccount), quoteData.fromTokenAmount);
        primaryEarnAccount.stakeGmx(quoteData.fromTokenAmount);

        // User gets 1:1 oGMX for the GMX provided.
        investmentAmount = quoteData.fromTokenAmount;
    }

    /**
     * @notice Get a quote to sell oGMX to GMX.
     * @param investmentTokenAmount The amount of oGMX to sell
     * @param toToken This must be the address of the GMX token
     * @return quoteData The quote data, including any other quote params required for this investment type. To be passed through when executing the quote.
     * @return exitFeeBps [Origami's exit fee]
     */
    function exitOGmxQuote(
        uint256 investmentTokenAmount, 
        address toToken
    ) external override view returns (
        IOrigamiInvestment.ExitQuoteData memory quoteData, 
        uint256[] memory exitFeeBps
    ) {
        if (investmentTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (toToken != address(gmxToken)) revert CommonEventsAndErrors.InvalidToken(toToken);

        quoteData.investmentTokenAmount = investmentTokenAmount;
        quoteData.toToken = toToken;
        // No extra underlyingInvestmentQuoteData

        exitFeeBps = new uint256[](1);
        exitFeeBps[0] = sellFeeRate.asBasisPoints();
        (, quoteData.expectedToTokenAmount) = sellFeeRate.split(investmentTokenAmount);
    }
    
    /** 
      * @notice Sell oGMX to receive GMX. 
      * @param quoteData The quote data received from exitQuote()
      * @param recipient The receiving address of the `t\oToken`
      */
    function exitOGmx(
        IOrigamiInvestment.ExitQuoteData memory quoteData, 
        uint256 /*slippageBps currently unused*/,
        address recipient
    ) external override onlyOperators returns (uint256) {
        if (_paused.gmxExitsPaused) revert CommonEventsAndErrors.IsPaused();

        (uint256 fees, uint256 nonFees) = sellFeeRate.split(quoteData.investmentTokenAmount);

        // Send the oGlp fees to the fee collector
        if (fees > 0) {
            oGmxToken.safeTransfer(feeCollector, fees);
        }

        if (nonFees > 0) {
            // Burn the users oGmx
            oGmxToken.burn(address(this), nonFees);

            // Unstake the GMX - NB this burns any multiplier points
            primaryEarnAccount.unstakeGmx(nonFees);

            // Send the GMX to the recipient
            gmxToken.safeTransfer(recipient, nonFees);
        }

        return nonFees;
    }

    /// @notice The set of whitelisted GMX.io tokens which can be used to buy GLP (and hence oGLP)
    /// @dev Native tokens (ETH/AVAX) and using staked GLP can also be used.
    function acceptedGlpTokens() external view override returns (address[] memory tokens) {
        uint256 length = gmxVault.allWhitelistedTokensLength();
        tokens = new address[](length + 2);

        // Add in the GMX.io whitelisted tokens
        // uint256 tokenIdx;
        uint256 i;
        for (; i < length; ++i) {
            tokens[i] = gmxVault.allWhitelistedTokens(i);
        }

        // ETH/AVAX is at [length-1 + 1]. Already instantiated as 0x
        // staked GLP is at [length-1 + 2]
        tokens[i+1] = address(primaryEarnAccount.stakedGlp());
    }

    /**
     * @notice Get a quote to buy the oGLP using one of the approved tokens, inclusive of GMX.io fees.
     * @dev The 0x0 address can be used for native chain ETH/AVAX
     * @param fromTokenAmount How much of `fromToken` to invest with
     * @param fromToken What ERC20 token to purchase with. This must be one of `acceptedInvestTokens`
     * @return quoteData The quote data, including any other quote params required for the underlying investment type. To be passed through when executing the quote.
     * @return investFeeBps [GMX.io's fee when depositing with `fromToken`]
     */
    function investOGlpQuote(
        uint256 fromTokenAmount, 
        address fromToken
    ) external view override returns (
        IOrigamiInvestment.InvestQuoteData memory quoteData, 
        uint256[] memory investFeeBps
    ) {
        if (fromTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        quoteData.fromToken = fromToken;
        quoteData.fromTokenAmount = fromTokenAmount;

        uint256 expectedUsdg;
        if (fromToken == address(primaryEarnAccount.stakedGlp())) {
            quoteData.expectedInvestmentAmount = fromTokenAmount; // 1:1 for staked GLP
            investFeeBps = new uint256[](1); // investFeeBps[0]=0, expectedUsdg=0
        } else {
            address tokenIn = (fromToken == address(0)) ? wrappedNativeToken : fromToken;

            // GMX.io don't provide on-contract external functions to obtain the quote. Logic extracted from:
            // https://github.com/gmx-io/gmx-contracts/blob/83bd5c7f4a1236000e09f8271d58206d04d1d202/contracts/core/GlpManager.sol#L160
            investFeeBps = new uint256[](1);
            uint256 aumInUsdg = glpManager.getAumInUsdg(true); // Assets Under Management
            uint256 glpSupply = IERC20(glpToken).totalSupply();

            (investFeeBps[0], expectedUsdg) = buyUsdgQuote(fromTokenAmount, tokenIn);

            quoteData.expectedInvestmentAmount = (aumInUsdg == 0) ? expectedUsdg : expectedUsdg * glpSupply / aumInUsdg;
        }
        
        quoteData.underlyingInvestmentQuoteData = abi.encode(GlpUnderlyingInvestQuoteData(expectedUsdg));
    }

    /** 
      * @notice User buys oGLP with an amount of one of the approved ERC20 tokens. 
      * @param fromToken The token override to invest with. May be different from the `quoteData.fromToken`
      * @param quoteData The quote data received from investQuote()
      * @param slippageBps Acceptable slippage, applied to the encodedQuote params
      * @return investmentAmount The actual number of receipt tokens received, inclusive of any fees.
      */
    function investOGlp(
        address fromToken,
        IOrigamiInvestment.InvestQuoteData calldata quoteData, 
        uint256 slippageBps
    ) external override onlyOperators returns (
        uint256 investmentAmount
    ) {
        if (_paused.glpInvestmentsPaused) revert CommonEventsAndErrors.IsPaused();

        if (fromToken == address(primaryEarnAccount.stakedGlp())) {
            // Pull staked GLP tokens from the user and transfer directly to the primary Origami earn account contract, responsible for staking.
            // This doesn't reset the cooldown clock for withdrawals, so it's ok to send directly to the primary earn account.
            IERC20(fromToken).safeTransfer(address(primaryEarnAccount), quoteData.fromTokenAmount);
            investmentAmount = quoteData.fromTokenAmount;
        } else {
            // Pull ERC20 tokens from the user and send to the secondary Origami earn account contract which purchases GLP on GMX.io and stakes it
            // This DOES reset the cooldown clock for withdrawals, so the secondary account is used in order 
            // to avoid withdrawals blocking from cooldown in the primary account.
            IERC20(fromToken).safeTransfer(address(secondaryEarnAccount), quoteData.fromTokenAmount);

            GlpUnderlyingInvestQuoteData memory underlyingQuoteData = abi.decode(quoteData.underlyingInvestmentQuoteData, (GlpUnderlyingInvestQuoteData));
            investmentAmount = secondaryEarnAccount.mintAndStakeGlp(
                quoteData.fromTokenAmount, fromToken, underlyingQuoteData.expectedUsdg, quoteData.expectedInvestmentAmount, slippageBps
            );
        }
    }

    /**
     * @notice Get a quote to sell oGLP to receive one of the accepted tokens.
     * @dev The 0x0 address can be used for native chain ETH/AVAX
     * @param investmentTokenAmount The amount of oGLP to sell
     * @param toToken The token to receive when selling. This must be one of `acceptedExitTokens`
     * @return quoteData The quote data, including any other quote params required for this investment type. To be passed through when executing the quote.
     * @return exitFeeBps [Origami's exit fee, GMX.io's fee when selling to `toToken`]
     */
    function exitOGlpQuote(
        uint256 investmentTokenAmount, 
        address toToken
    ) external override view returns (
        IOrigamiInvestment.ExitQuoteData memory quoteData, 
        uint256[] memory exitFeeBps
    ) {
        if (investmentTokenAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        quoteData.investmentTokenAmount = investmentTokenAmount;
        quoteData.toToken = toToken;
        // No extra underlyingInvestmentQuoteData on exit

        exitFeeBps = new uint256[](2);  // [Origami's exit fee, GMX's exit fee]
        exitFeeBps[0] = sellFeeRate.asBasisPoints();
        (, uint256 glpAmount) = sellFeeRate.split(investmentTokenAmount);
        if (glpAmount == 0) return (quoteData, exitFeeBps);

        if (toToken == address(primaryEarnAccount.stakedGlp())) {
            // No GMX related fees for staked GLP transfers
            quoteData.expectedToTokenAmount = glpAmount;
        } else {
            address tokenOut = (toToken == address(0)) ? wrappedNativeToken : toToken;

            // GMX.io don't provide on-contract external functions to obtain the quote. Logic extracted from:
            // https://github.com/gmx-io/gmx-contracts/blob/83bd5c7f4a1236000e09f8271d58206d04d1d202/contracts/core/GlpManager.sol#L183
            uint256 aumInUsdg = glpManager.getAumInUsdg(false); // Assets Under Management
            uint256 glpSupply = IERC20(glpToken).totalSupply();
            uint256 usdgAmount = (glpSupply == 0) ? 0 : glpAmount * aumInUsdg / glpSupply;
            
            (exitFeeBps[1], quoteData.expectedToTokenAmount) = sellUsdgQuote(usdgAmount, tokenOut);
        }
    }

    /** 
      * @notice Sell oGLP to receive one of the accepted tokens. 
      * @param toToken The token override to invest with. May be different from the `quoteData.toToken`
      * @param quoteData The quote data received from exitQuote()
      * @param slippageBps Acceptable slippage, applied to the encodedQuote params
      * @param recipient The receiving address of the `toToken`
      * @return amountOut The number of `toToken` tokens received upon selling the Origami receipt token.
      */
    function exitOGlp(
        address toToken,
        IOrigamiInvestment.ExitQuoteData calldata quoteData, 
        uint256 slippageBps, 
        address recipient
    ) external override onlyOperators returns (uint256 amountOut) {
        if (_paused.glpExitsPaused) revert CommonEventsAndErrors.IsPaused();

        (uint256 fees, uint256 nonFees) = sellFeeRate.split(quoteData.investmentTokenAmount);

        // Send the oGlp fees to the fee collector
        if (fees > 0) {
            oGlpToken.safeTransfer(feeCollector, fees);
        }

        if (nonFees > 0) {
            // Burn the remaining oGlp
            oGlpToken.burn(address(this), nonFees);

            if (toToken == address(primaryEarnAccount.stakedGlp())) {
                // Transfer the remaining staked GLP to the recipient
                primaryEarnAccount.transferStakedGlp(
                    nonFees,
                    recipient
                );
                amountOut = nonFees;
            } else {
                // Sell from the primary earn account and send the resulting token to the recipient.
                amountOut = primaryEarnAccount.unstakeAndRedeemGlp(
                    nonFees,
                    toToken,
                    quoteData.expectedToTokenAmount,
                    slippageBps,
                    recipient
                );
            }
        }
    }

    function buyUsdgQuote(uint256 fromAmount, address fromToken) internal view returns (
        uint256 feeBasisPoints,
        uint256 usdgAmountOut
    ) {
        // Used as part of the quote to buy GLP. Forked from:
        // https://github.com/gmx-io/gmx-contracts/blob/83bd5c7f4a1236000e09f8271d58206d04d1d202/contracts/core/Vault.sol#L452
        if (!gmxVault.whitelistedTokens(fromToken)) revert CommonEventsAndErrors.InvalidToken(fromToken);
        uint256 price = IGmxVaultPriceFeed(gmxVault.priceFeed()).getPrice(fromToken, false, true, true);
        uint256 pricePrecision = gmxVault.PRICE_PRECISION();
        uint256 basisPointsDivisor = FractionalAmount.BASIS_POINTS_DIVISOR;
        address usdg = gmxVault.usdg();
        uint256 usdgAmount = fromAmount * price / pricePrecision;
        usdgAmount = gmxVault.adjustForDecimals(usdgAmount, fromToken, usdg);

        feeBasisPoints = getFeeBasisPoints(
            fromToken, usdgAmount, 
            true  // true for buy, false for sell
        );

        uint256 amountAfterFees = fromAmount * (basisPointsDivisor - feeBasisPoints) / basisPointsDivisor;
        usdgAmountOut = gmxVault.adjustForDecimals(amountAfterFees * price / pricePrecision, fromToken, usdg);
    }

    function sellUsdgQuote(
        uint256 usdgAmount, address toToken
    ) internal view returns (uint256 feeBasisPoints, uint256 amountOut) {
        // Used as part of the quote to sell GLP. Forked from:
        // https://github.com/gmx-io/gmx-contracts/blob/83bd5c7f4a1236000e09f8271d58206d04d1d202/contracts/core/Vault.sol#L484
        if (usdgAmount == 0) return (feeBasisPoints, amountOut);
        if (!gmxVault.whitelistedTokens(toToken)) revert CommonEventsAndErrors.InvalidToken(toToken);
        uint256 pricePrecision = gmxVault.PRICE_PRECISION();
        uint256 price = IGmxVaultPriceFeed(gmxVault.priceFeed()).getPrice(toToken, true, true, true);
        address usdg = gmxVault.usdg();
        uint256 redemptionAmount = gmxVault.adjustForDecimals(usdgAmount * pricePrecision / price, usdg, toToken);

        feeBasisPoints = getFeeBasisPoints(
            toToken, usdgAmount,
            false  // true for buy, false for sell
        );

        uint256 basisPointsDivisor = FractionalAmount.BASIS_POINTS_DIVISOR;
        amountOut = redemptionAmount * (basisPointsDivisor - feeBasisPoints) / basisPointsDivisor;
    }

    function getFeeBasisPoints(address _token, uint256 _usdgDelta, bool _increment) internal view returns (uint256) {
        // Used as part of the quote to buy/sell GLP. Forked from:
        // https://github.com/gmx-io/gmx-contracts/blob/83bd5c7f4a1236000e09f8271d58206d04d1d202/contracts/core/VaultUtils.sol#L143
        uint256 feeBasisPoints = gmxVault.mintBurnFeeBasisPoints();
        uint256 taxBasisPoints = gmxVault.taxBasisPoints();
        if (!gmxVault.hasDynamicFees()) { return feeBasisPoints; }

        // The GMX.io website sell quotes are slightly off when calculating the fee. When actually selling, 
        // the code already has the sell amount (_usdgDelta) negated from initialAmount and usdgSupply,
        // however when getting a quote, it doesn't have this amount taken off - so we get slightly different results.
        // To have the quotes match the exact amounts received when selling, this tweak is required.
        // https://github.com/gmx-io/gmx-contracts/issues/28
        uint256 initialAmount = gmxVault.usdgAmounts(_token);
        uint256 usdgSupply = IERC20(gmxVault.usdg()).totalSupply();
        if (!_increment) {
            initialAmount = (_usdgDelta > initialAmount) ? 0 : initialAmount - _usdgDelta;
            usdgSupply = (_usdgDelta > usdgSupply) ? 0 : usdgSupply - _usdgDelta;
        }
        // End tweak

        uint256 nextAmount = initialAmount + _usdgDelta;
        if (!_increment) {
            nextAmount = _usdgDelta > initialAmount ? 0 : initialAmount - _usdgDelta;
        }

        uint256 targetAmount = (usdgSupply == 0)
            ? 0
            : gmxVault.tokenWeights(_token) * usdgSupply / gmxVault.totalTokenWeights();
        if (targetAmount == 0) { return feeBasisPoints; }

        uint256 initialDiff = initialAmount > targetAmount ? initialAmount - targetAmount : targetAmount - initialAmount;
        uint256 nextDiff = nextAmount > targetAmount ? nextAmount - targetAmount : targetAmount - nextAmount;

        // action improves relative asset balance
        if (nextDiff < initialDiff) {
            uint256 rebateBps = taxBasisPoints * initialDiff / targetAmount;
            return rebateBps > feeBasisPoints ? 0 : feeBasisPoints - rebateBps;
        }

        uint256 averageDiff = (initialDiff + nextDiff) / 2;
        if (averageDiff > targetAmount) {
            averageDiff = targetAmount;
        }

        uint256 taxBps = taxBasisPoints * averageDiff / targetAmount;
        return feeBasisPoints + taxBps;
    }

    /// @notice Owner can recover tokens
    function recoverToken(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        IERC20(_token).safeTransfer(_to, _amount);
        emit CommonEventsAndErrors.TokenRecovered(_to, _token, _amount);
    }
}