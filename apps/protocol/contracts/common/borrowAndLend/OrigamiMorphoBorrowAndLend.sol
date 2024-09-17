pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/borrowAndLend/OrigamiMorphoBorrowAndLend.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { 
    IMorpho,
    Id as MorphoMarketId,
    MarketParams as MorphoMarketParams
} from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";
import { IOracle as IMorphoOracle } from "@morpho-org/morpho-blue/src/interfaces/IOracle.sol";
import { ORACLE_PRICE_SCALE as MORPHO_ORACLE_PRICE_SCALE } from "@morpho-org/morpho-blue/src/libraries/ConstantsLib.sol";
import { IMorphoSupplyCollateralCallback } from "@morpho-org/morpho-blue/src/interfaces/IMorphoCallbacks.sol";
import { MorphoBalancesLib } from "@morpho-org/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import { MorphoLib } from "@morpho-org/morpho-blue/src/libraries/periphery/MorphoLib.sol";
import { MarketParamsLib } from "@morpho-org/morpho-blue/src/libraries/MarketParamsLib.sol";

import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { IOrigamiMorphoBorrowAndLend } from "contracts/interfaces/common/borrowAndLend/IOrigamiMorphoBorrowAndLend.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

/**
 * @notice An Origami abstraction over a borrow/lend money market for
 * a single `supplyToken` and a single `borrowToken`.
 * This is a Morpho specific interface
 */
contract OrigamiMorphoBorrowAndLend is IOrigamiMorphoBorrowAndLend, IMorphoSupplyCollateralCallback, OrigamiElevatedAccess {
    using SafeERC20 for IERC20;
    using MorphoBalancesLib for IMorpho;
    using MorphoLib for IMorpho;
    using MarketParamsLib for MorphoMarketParams;
    using OrigamiMath for uint256;

    /**
     * @notice The morpho singleton contract
     */
    IMorpho public immutable override morpho;

    /**
     * @notice The token supplied as collateral
     */
    IERC20 private immutable _supplyToken;
    
    /**
     * @notice The token which is borrowed
     */
    IERC20 private immutable _borrowToken;

    /**
     * @notice The Morpho oracle used for the target market
     */
    address public override immutable morphoMarketOracle;

    /**
     * @notice The Morpho Interest Rate Model used for the target market
     */
    address public override immutable morphoMarketIrm;

    /**
     * @notice The Morpho Liquidation LTV for the target market
     */
    uint96 public override immutable morphoMarketLltv;

    /**
     * @notice The derived Morpho market ID given the market parameters
     */
    MorphoMarketId public override immutable marketId;

    /**
     * @notice The approved owner of the borrow/lend position
     */
    address public override positionOwner;

    /**
     * @notice The max LTV we will allow when borrowing or withdrawing collateral.
     * @dev The morpho LTV is the liquidation LTV only, we don't want to allow up to that limit
     */
    uint256 public override maxSafeLtv;
    
    /**
     * @notice The swapper for `borrowToken` <--> `supplyToken`
     */
    IOrigamiSwapper public override swapper;

    /**
     * @dev Factor when converting the Morpho LTV (1e18) to an Origami Assets/Liabilities (1e18)
     */
    uint256 private constant LTV_TO_AL_FACTOR = 1e36;

    /// @dev internal serialization of callback data for increasing leverage
    struct IncreaseLeverageData {
        /// @dev The amount of new `borrowToken` to borrow
        uint256 borrowAmount;

        /// @dev The encoded swap data for `borrowToken` to `supplyToken`
        bytes swapData;
    }

    /// @dev internal serialization of callback data for decreasing leverage
    struct DecreaseLeverageData {
        /// @dev The amount of `supplyToken` to withdraw from collateral
        uint256 withdrawCollateralAmount;

        /// @dev The encoded swap data for `supplyToken` to `borrowToken`
        bytes swapData;
    }
    
    constructor(
        address _initialOwner,
        address __supplyToken,
        address __borrowToken,
        address _morphoAddress,
        address _morphoMarketOracle, 
        address _morphoMarketIrm,
        uint96 _morphoMarketLltv,
        uint256 _maxSafeLtv
    ) OrigamiElevatedAccess(_initialOwner) {
        _supplyToken = IERC20(__supplyToken);
        _borrowToken = IERC20(__borrowToken);
        
        morpho = IMorpho(_morphoAddress);

        morphoMarketOracle = _morphoMarketOracle;
        morphoMarketIrm = _morphoMarketIrm;
        morphoMarketLltv = _morphoMarketLltv;

        if (_maxSafeLtv >= morphoMarketLltv) revert CommonEventsAndErrors.InvalidParam();
        maxSafeLtv = _maxSafeLtv;

        marketId = getMarketParams().id();

        // Verify that the market is valid
        if (morpho.lastUpdate(marketId) == 0) revert CommonEventsAndErrors.InvalidParam();

        // Approve the supply and borrow to the Morpho singleton upfront
        _supplyToken.forceApprove(_morphoAddress, type(uint256).max);
        _borrowToken.forceApprove(_morphoAddress, type(uint256).max);
    }

    /**
     * @notice Set the position owner who can borrow/lend via this contract
     */
    function setPositionOwner(address account) external override onlyElevatedAccess {
        positionOwner = account;
        emit PositionOwnerSet(account);
    }

    /**
     * @notice Set the max LTV we will allow when borrowing or withdrawing collateral.
     * @dev The morpho LTV is the liquidation LTV only, we don't want to allow up to that limit
     * so we set a more restrictive 'safe' LTV'
     */
    function setMaxSafeLtv(uint256 _maxSafeLtv) external override onlyElevatedAccess {
        if (_maxSafeLtv >= morphoMarketLltv) revert CommonEventsAndErrors.InvalidParam();
        maxSafeLtv = _maxSafeLtv;
        emit MaxSafeLtvSet(_maxSafeLtv);
    }
    
    /**
     * @notice Set the swapper responsible for `borrowToken` <--> `supplyToken` swaps
     */
    function setSwapper(address _swapper) external override onlyElevatedAccess {
        if (_swapper == address(0)) revert CommonEventsAndErrors.InvalidAddress(_swapper);

        // Update the approval's for both `supplyToken` and `borrowToken`
        address _oldSwapper = address(swapper);
        if (_oldSwapper != address(0)) {
            _supplyToken.forceApprove(_oldSwapper, 0);
            _borrowToken.forceApprove(_oldSwapper, 0);
        }
        _supplyToken.forceApprove(_swapper, type(uint256).max);
        _borrowToken.forceApprove(_swapper, type(uint256).max);

        emit SwapperSet(_swapper);
        swapper = IOrigamiSwapper(_swapper);
    }

    /**
     * @notice Supply tokens as collateral
     */
    function supply(
        uint256 supplyAmount
    ) external override onlyPositionOwnerOrElevated {
        _supply(supplyAmount, getMarketParams(), "");
    }

    /**
     * @notice Withdraw collateral tokens to recipient
     * @dev Set `withdrawAmount` to type(uint256).max in order to withdraw the whole balance
     */
    function withdraw(
        uint256 withdrawAmount, 
        address recipient
    ) external override onlyPositionOwnerOrElevated returns (uint256 amountWithdrawn) {
        amountWithdrawn = _withdraw(withdrawAmount, recipient, getMarketParams());
    }

    /**
     * @notice Borrow tokens and send to recipient
     */
    function borrow(
        uint256 borrowAmount, 
        address recipient
    ) external override onlyPositionOwnerOrElevated {
        _borrow(borrowAmount, recipient, getMarketParams());
    }

    /**
     * @notice Repay debt. 
     * @dev If `repayAmount` is set higher than the actual outstanding debt balance, it will be capped
     * to that outstanding debt balance
     * `debtRepaidAmount` return parameter will be capped to the outstanding debt balance.
     * Any surplus debtTokens (if debt fully repaid) will remain in this contract
     */
    function repay(
        uint256 repayAmount
    ) external override onlyPositionOwnerOrElevated returns (uint256 debtRepaidAmount) {
        debtRepaidAmount = _repay(repayAmount, getMarketParams(), "");
    }

    /**
     * @notice Repay debt and withdraw collateral in one step
     * @dev If `repayAmount` is set higher than the actual outstanding debt balance, it will be capped
     * to that outstanding debt balance
     * Set `withdrawAmount` to type(uint256).max in order to withdraw the whole balance
     * `debtRepaidAmount` return parameter will be capped to the outstanding debt amount.
     * Any surplus debtTokens (if debt fully repaid) will remain in this contract
     */
    function repayAndWithdraw(
        uint256 repayAmount, 
        uint256 withdrawAmount, 
        address recipient
    ) external override onlyPositionOwnerOrElevated returns (uint256 debtRepaidAmount, uint256 withdrawnAmount) {
        MorphoMarketParams memory marketParams = getMarketParams();
        debtRepaidAmount = _repay(repayAmount, marketParams, "");
        withdrawnAmount = _withdraw(withdrawAmount, recipient, marketParams);
    }

    /**
     * @notice Supply collateral and borrow in one step
     */
    function supplyAndBorrow(
        uint256 supplyAmount, 
        uint256 borrowAmount, 
        address recipient
    ) external override onlyPositionOwnerOrElevated {
        MorphoMarketParams memory marketParams = getMarketParams();
        _supply(supplyAmount, marketParams, "");
        _borrow(borrowAmount, recipient, marketParams);
    }

    /**
     * @notice Increase the leverage of the existing position, by supplying `supplyToken` as collateral
     * and borrowing `borrowToken` and swapping that back to `supplyToken`
     * @dev The totalCollateralSupplied may include any surplus after swapping from the debt to collateral
     */
    function increaseLeverage(
        uint256 supplyAmount,
        uint256 borrowAmount,
        bytes memory swapData,
        uint256 supplyCollateralSurplusThreshold
    ) external override onlyPositionOwnerOrElevated returns (uint256 totalCollateralSupplied) {
        MorphoMarketParams memory marketParams = getMarketParams();
        _supply(
            supplyAmount,
            marketParams,
            abi.encode(IncreaseLeverageData(
                borrowAmount,
                swapData
            ))
        );
        totalCollateralSupplied = supplyAmount;

        // There may be a suplus of `supplyToken` in this contract after the leverage increase
        // If over the threshold, supply any surplus back in as collateral to morpho
        uint256 surplusAfterLeverage = _supplyToken.balanceOf(address(this));
        if (surplusAfterLeverage > supplyCollateralSurplusThreshold) {
            _supply(surplusAfterLeverage, marketParams, "");
            totalCollateralSupplied = totalCollateralSupplied + surplusAfterLeverage;
        }
    }

    /**
     * @notice Callback called when a supply of collateral occurs in Morpho.
     * @dev The callback is called only if data is not empty.
     * @param supplyAmount The amount of supplied collateral.
     * @param data Arbitrary data passed to the `supplyCollateral` function.
     */
    function onMorphoSupplyCollateral(uint256 supplyAmount, bytes calldata data) external override {
        if (msg.sender != address(morpho)) revert CommonEventsAndErrors.InvalidAccess();
        IncreaseLeverageData memory decoded = abi.decode(data, (IncreaseLeverageData));

        MorphoMarketParams memory marketParams = getMarketParams();

        // Perform the borrow
        _borrow(decoded.borrowAmount, address(this), marketParams);

        // Swap from [borrowToken] to [supplyToken]
        // The expected amount of [supplyToken] received after swapping from [borrowToken]
        // needs to at least cover the supplyAmount
        uint256 collateralReceived = swapper.execute(_borrowToken, decoded.borrowAmount, _supplyToken, decoded.swapData);
        if (collateralReceived < supplyAmount) {
            revert CommonEventsAndErrors.Slippage(supplyAmount, collateralReceived);
        }
    }

    /**
     * @notice Decrease the leverage of the existing position, by repaying `borrowToken`
     * and withdrawing `supplyToken` collateral then swapping that back to `borrowToken`
     */
    function decreaseLeverage(
        uint256 repayAmount,
        uint256 withdrawCollateralAmount,
        bytes memory swapData,
        uint256 repaySurplusThreshold
    ) external override onlyPositionOwnerOrElevated returns (
        uint256 debtRepaidAmount, 
        uint256 surplusDebtRepaid
    ) {
        MorphoMarketParams memory marketParams = getMarketParams();
        debtRepaidAmount = _repay(
            repayAmount, 
            marketParams,
            abi.encode(DecreaseLeverageData(
                withdrawCollateralAmount,
                swapData
            ))
        );

        // There may be a suplus of `borrowToken` in this contract after the delverage
        // If over the threshold, repay any surplus back to morpho
        uint256 surplusAfterDeleverage = _borrowToken.balanceOf(address(this));
        if (surplusAfterDeleverage > repaySurplusThreshold) {
            surplusDebtRepaid = _repay(surplusAfterDeleverage, marketParams, "");
        }
    }

    /**
     * @notice Callback called when a repayment occurs.
     * @dev The callback is called only if data is not empty.
     * @param repayAmount The amount of repaid assets.
     * @param data Arbitrary data passed to the `repay` function.
     */
    function onMorphoRepay(uint256 repayAmount, bytes calldata data) external {
        if (msg.sender != address(morpho)) revert CommonEventsAndErrors.InvalidAccess();
        DecreaseLeverageData memory decoded = abi.decode(data, (DecreaseLeverageData));

        MorphoMarketParams memory marketParams = getMarketParams();

        // Withdraw collateral
        uint256 _amountWithdrawn = _withdraw(decoded.withdrawCollateralAmount, address(this), marketParams);
        if (_amountWithdrawn != decoded.withdrawCollateralAmount) {
            revert CommonEventsAndErrors.InvalidAmount(address(_supplyToken), decoded.withdrawCollateralAmount);
        }
        
        // Swap from [supplyToken] to [borrowToken]
        // The expected amount of [borrowToken] received after swapping from [supplyToken]
        // needs to at least cover the repayAmount
        uint256 borrowTokenReceived = swapper.execute(_supplyToken, decoded.withdrawCollateralAmount, _borrowToken, decoded.swapData);
        if (borrowTokenReceived < repayAmount) {
            revert CommonEventsAndErrors.Slippage(repayAmount, borrowTokenReceived);
        }
    }

    /**
     * @notice Recover accidental donations.
     * @dev Does not allow for recovery of supplyToken or borrowToken if there is an outstanding
     * morpho debt on this pool
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {
        if (debtBalance() != 0) {
            if (token == address(_supplyToken) || token == address(_borrowToken)) {
                revert CommonEventsAndErrors.InvalidToken(token);
            }
        }
        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }
        
    /**
     * @notice The Morpho market parameters
     */
    function getMarketParams() public override view returns (MorphoMarketParams memory) {
        return MorphoMarketParams({
            loanToken: address(_borrowToken),
            collateralToken: address(_supplyToken),
            oracle: morphoMarketOracle,
            irm: morphoMarketIrm,
            lltv: morphoMarketLltv
        });
    }

    /**
     * @notice The token supplied as collateral
     */
    function supplyToken() public override view returns (address) {
        return address(_supplyToken);
    }
    
    /**
     * @notice The token which is borrowed
     */
    function borrowToken() public override view returns (address) {
        return address(_borrowToken);
    }

    /**
     * @notice The current (manually tracked) balance of tokens supplied
     */
    function suppliedBalance() public override view returns (uint256) {
        return morpho.collateral(marketId, address(this));
    }

    /**
     * @notice The current debt balance of tokens borrowed
     */
    function debtBalance() public override view returns (uint256) {
        return morpho.expectedBorrowAssets(getMarketParams(), address(this));
    }

    /**
     * @notice Whether a given Assets/Liabilities Ratio is safe, given the upstream
     * money market parameters
     */
    function isSafeAlRatio(uint256 alRatio) external override view returns (bool) {
        return alRatio >= LTV_TO_AL_FACTOR / maxSafeLtv;
    }

    /**
     * @notice How many `supplyToken` are available to withdraw from collateral
     * from the entire protocol, assuming this contract has fully paid down its debt
     */
    function availableToWithdraw() external override view returns (uint256) {
        // The collateral (for borrows) never gets used as they are siloed markets,
        // this contracts collateral is always available to be withdrawn.
        // There's no morpho metric for the entire collateral supplied, instead
        // this just returns our collateral - so the same as `suppliedBalance()`
        return suppliedBalance();
    }

    /**
     * @notice How many `borrowToken` are available to borrow
     * from the entire protocol
     */
    function availableToBorrow() external override view returns (uint256) {
        uint256 totalSupplyAssets = morpho.totalSupplyAssets(marketId);
        uint256 totalBorrowAssets = morpho.totalBorrowAssets(marketId);
        return totalSupplyAssets > totalBorrowAssets ? totalSupplyAssets - totalBorrowAssets : 0;
    }

    /**
     * @notice How much more capacity is available to supply
     */
    function availableToSupply() external override pure returns (
        uint256 supplyCap,
        uint256 available
    ) {
        return (
            type(uint256).max,
            type(uint256).max
        );
    }

    /**
     * @notice Returns the curent Morpho position data
     */
    function debtAccountData() external override view returns (
        uint256 collateral,
        uint256 collateralPrice,
        uint256 borrowed,
        uint256 maxBorrow,
        uint256 currentLtv,
        uint256 healthFactor
    ) {
        // supplyToken decimals
        collateral = suppliedBalance();
        // `36 + borrowToken decimals - supplyToken decimals` decimals of precision.
        collateralPrice = IMorphoOracle(morphoMarketOracle).price();
        // borrowToken decimals
        borrowed = debtBalance();
        
        uint256 _collateralInBorrowTerms = collateral.mulDiv(
            collateralPrice, 
            MORPHO_ORACLE_PRICE_SCALE, 
            OrigamiMath.Rounding.ROUND_DOWN
        );

        maxBorrow = _collateralInBorrowTerms.mulDiv(
            morphoMarketLltv,
            1e18,
            OrigamiMath.Rounding.ROUND_DOWN
        );
        
        if (borrowed == 0) {
            healthFactor = type(uint256).max;
        } else {
            currentLtv = borrowed.mulDiv(
                1e18,
                _collateralInBorrowTerms,
                OrigamiMath.Rounding.ROUND_UP
            );
            healthFactor = maxBorrow.mulDiv(1e18, borrowed, OrigamiMath.Rounding.ROUND_DOWN);
        }
    }

    function _supply(uint256 supplyAmount, MorphoMarketParams memory marketParams, bytes memory data) internal {
        morpho.supplyCollateral(marketParams, supplyAmount, address(this), data);
    }

    function _withdraw(uint256 withdrawAmount, address recipient, MorphoMarketParams memory marketParams) internal returns (uint256 amountWithdrawn) {
        // If `withdrawAmount` == uint256.max, then set the the current supplied collateral balance
        amountWithdrawn = withdrawAmount == type(uint256).max ? suppliedBalance() : withdrawAmount;
        morpho.withdrawCollateral(marketParams, amountWithdrawn, address(this), recipient);
    }

    function _borrow(uint256 borrowAmount, address recipient, MorphoMarketParams memory marketParams) internal {
        (uint256 assetsBorrowed,) = morpho.borrow(
            marketParams, borrowAmount, 0, address(this), recipient
        );
        if (assetsBorrowed != borrowAmount) revert CommonEventsAndErrors.InvalidAmount(address(_borrowToken), assetsBorrowed);
    }
    
    function _repay(uint256 repayAmount, MorphoMarketParams memory marketParams, bytes memory data) internal returns (uint256 debtRepaidAmount) {
        uint256 _debtBalance = debtBalance();

        if (_debtBalance != 0) {
            // If the repayment amount gte the current balance, then repay 100% of the debt.
            if (repayAmount < _debtBalance) {
                // Repay via the amount (not shares)
                (debtRepaidAmount, ) = morpho.repay(marketParams, repayAmount, 0, address(this), data);
            } else {
                // Calculate the current morpho shares owed, and repay via the shares (not amount)
                // Do this when equal to the debt balance to avoid Morpho rounding underflow
                uint256 _repayShares = morpho.position(marketId, address(this)).borrowShares;
                (debtRepaidAmount, ) = morpho.repay(marketParams, 0, _repayShares, address(this), data);
            }
        }
    }

    /**
     * @dev Only the positionOwner or Elevated Access is allowed to call.
     */
    modifier onlyPositionOwnerOrElevated() {
        if (msg.sender != address(positionOwner)) {
            if (!isElevatedAccess(msg.sender, msg.sig)) revert CommonEventsAndErrors.InvalidAccess();
        }
        _;
    }
}
