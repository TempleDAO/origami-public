pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiAbstractLovTokenManager } from "contracts/investments/lovToken/managers/OrigamiAbstractLovTokenManager.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

/* solhint-disable immutable-vars-naming */
contract OrigamiMockLovTokenManager is OrigamiAbstractLovTokenManager {
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IERC4626;
    using OrigamiMath for uint256;

    /**
     * @notice For this mock - the deposit asset is the reserve asset for the lovToken
     * it doesn't actually do any leverage
     */
    IERC20Metadata public immutable depositAsset;

    /**
     * @notice The ERC-4626 reserves that this lovToken levers up on
     * @dev This is the reserve token for lovToken when calculating the reservesPerShare
     */
    IERC4626 private immutable _reserveToken;

    /**
     * @notice The number of reserves this lovToken holds.
     * @dev Explicitly tracked rather than via using the reserveToken.balanceOf() 
     * to avoid donation/inflation vectors.
     */
    uint256 private _internalReservesBalance;

    // @dev For testing - manually set the amount of liabilities (in reserveToken terms)
    uint256 internal _liabilities;

    // @dev For testing to override the test__MaxDepositAmt() amount
    uint256 public test__MaxDepositAmt;
    // @dev For testing to override the test__MaxRedeemAmt() amount
    uint256 public test__MaxRedeemAmt;

    // @dev For testing, use the forced number of assets after a deposit/exit
    uint256 public test__ForceAssets;
    bool public test__useForcedAssets;

    constructor(
        address _initialOwner,
        address _depositAsset,
        address _reserveToken_,
        address _lovToken
    ) OrigamiAbstractLovTokenManager(_initialOwner, _lovToken) {
        depositAsset = IERC20Metadata(_depositAsset);
        _reserveToken = IERC4626(_reserveToken_);
    }

    function setTest__ForceAssets(uint256 value) external {
        test__ForceAssets = value;
    }

    function setTest__MaxDepositAmt(uint256 amount) external {
        test__MaxDepositAmt = amount;
    }
    
    function setTest__MaxRedeemAmt(uint256 amount) external {
        test__MaxRedeemAmt = amount;
    }

    function rebalanceDown(uint256 borrowReservesAmount) external {
        Cache memory cache = populateCache(IOrigamiOracle.PriceType.SPOT_PRICE);
        uint128 alRatioBefore = _assetToLiabilityRatio(cache);

        _liabilities += borrowReservesAmount;
        _reserveToken.safeTransferFrom(msg.sender, address(this), borrowReservesAmount);
        _internalReservesBalance += borrowReservesAmount;

        // Validate that the new A/L is still within the `rebalanceALRange`
        // Need to recalculate both the assets and liabilities in the cache
        cache.assets = reservesBalance();
        cache.liabilities = liabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        uint128 alRatioAfter = _assetToLiabilityRatio(cache);
        _validateALRatio(rebalanceALRange, alRatioBefore, alRatioAfter, AlValidationMode.LOWER_THAN_BEFORE, cache);
    }

    function rebalanceUp(uint256 repayReservesAmount) external {
        Cache memory cache = populateCache(IOrigamiOracle.PriceType.SPOT_PRICE);

        // Get the current A/L to check for oracle prices, and so we can compare that the new A/L is higher after the rebalance
        uint128 alRatioBefore = _assetToLiabilityRatio(cache);

        _liabilities -= repayReservesAmount;
        _reserveToken.safeTransfer(msg.sender, repayReservesAmount);
        _internalReservesBalance -= repayReservesAmount;

        // Validate that the new A/L is still within the `rebalanceALRange`
        // Need to recalculate both the assets and liabilities in the cache
        cache.assets = reservesBalance();
        cache.liabilities = liabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        uint128 alRatioAfter = _assetToLiabilityRatio(cache);
        _validateALRatio(rebalanceALRange, alRatioBefore, alRatioAfter, AlValidationMode.HIGHER_THAN_BEFORE, cache);
    }

    /**
     * @notice Recover any token, excluding the `reserveToken`
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external override onlyElevatedAccess {
        // If the token to recover is the reserve token, can only remove any *surplus* reserves (ie donation reserves).
        // It can't dip into the actual user or protocol added reserves. 
        if (token == address(_reserveToken)) {
            uint256 bal = _reserveToken.balanceOf(address(this));
            if (amount > (bal - reservesBalance())) revert CommonEventsAndErrors.InvalidAmount(token, amount);
        }

        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20Metadata(token).safeTransfer(to, amount);
    }

    /**
     * @notice The total balance of reserve tokens this lovToken holds.
     * @dev All internally held tokens for the ERC-4626 implementation.
     */
    function reservesBalance() public override view returns (uint256) {
        // If set, use the explicit assets set from the test harness
        if (test__useForcedAssets) return test__ForceAssets;

        return _internalReservesBalance;
    }

    /**
     * @notice The underlying token this investment wraps. In this case, it's the ERC-4626 `reserveToken`
     */
    function baseToken() external override view returns (address) {
        return address(_reserveToken);
    }

    /**
     * @notice The set of accepted tokens which can be used to invest. 
     * Either the ERC-4626 `reserveToken` or the underlying `depositAsset`
     */
    function acceptedInvestTokens() external override view returns (address[] memory tokens) {
        tokens = new address[](2);
        (tokens[0], tokens[1]) = (address(depositAsset), address(_reserveToken));
    }

    /**
     * @notice The set of accepted tokens which can be used to exit into.
     * Either the ERC-4626 `reserveToken` or the underlying `depositAsset`
     */
    function acceptedExitTokens() external override view returns (address[] memory tokens) {
        tokens = new address[](2);
        (tokens[0], tokens[1]) = (address(depositAsset), address(_reserveToken));
    }

    /**
     * @notice The reserveToken that the lovToken levers up on
     */
    function reserveToken() public override view returns (address) {
        return address(_reserveToken);
    }

    /**
     * @notice The asset which lovToken borrows to increase the A/L ratio
     */
    function debtToken() external override view returns (address) {
        return address(_reserveToken);
    }

    /**
     * @notice The debt of the lovToken to the Origami `lendingClerk`, converted into the `reserveToken`
     * @dev Use the Oracle `debtPriceType` to value any debt in terms of the reserve token
     */
    function liabilities(IOrigamiOracle.PriceType /*debtPriceType*/) public override view returns (uint256) {
        return _liabilities;
    }

    /**
     * @notice The current deposit fee based on market conditions.
     * Deposit fees are applied to the portion of lovToken shares the depositor 
     * would have received. Instead that fee portion isn't minted (benefiting remaining users)
     * @dev represented in basis points
     */
    function _dynamicDepositFeeBps() internal override view returns (uint256) {
        return _minDepositFeeBps > 20 ? _minDepositFeeBps : 20;
    }

    /**
     * @notice The current exit fee based on market conditions.
     * Exit fees are applied to the lovToken shares the user is exiting. 
     * That portion is burned prior to being redeemed (benefiting remaining users)
     * @dev represented in basis points
     */
    function _dynamicExitFeeBps() internal override view returns (uint256) {
        return _minExitFeeBps > 50 ? _minExitFeeBps : 50;
    }

    /**
     * @notice A ERC-4626 based lovToken either accepts the `depositAsset` (and deposits into the ERC-4626 vault), or the existing ERC-4626 shares
     */
    function _depositIntoReserves(address fromToken, uint256 fromTokenAmount) internal override returns (uint256 newReservesAmount) {
        if (fromToken == address(depositAsset)) {
            // Use the `fromToken` to deposit in the underlying and receive `reserveToken`
            // No need to check for slippage on this, as it's done based on the total lovToken's received.
            depositAsset.safeIncreaseAllowance(address(_reserveToken), fromTokenAmount);
            newReservesAmount = _reserveToken.deposit(fromTokenAmount, address(this));
        } else if (fromToken == address(_reserveToken)) {
            // If depositing with the reserve token, nothing else to do. 
            newReservesAmount = fromTokenAmount;
        } else {
            revert CommonEventsAndErrors.InvalidToken(fromToken);
        }

        // Increase the counter of reserves
        _internalReservesBalance += newReservesAmount;

        // @dev For testing only - asset's are forced to be an explicit value from the test harness
        // in order to get an expected A/L after the invest
        if (test__ForceAssets != 0) {
            test__useForcedAssets = true;
        }
    }

    /**
     * @notice A ERC-4626 based lovToken can exit to the ERC-4626 shares, or to the `depositAsset` by redeeming from the ERC-4626 vault
     */
    function _redeemFromReserves(uint256 reservesAmount, address toToken, address recipient) internal override returns (uint256 toTokenAmount) {
        // Now redeem the non-fee user lovToken's
        // If exiting to the reserve token, redeem and send them to the user
        // Otherwise first redeem the reserve tokens and then exit the underlying Origami investment
        if (toToken == address(depositAsset)) {
            toTokenAmount = _reserveToken.redeem(reservesAmount, recipient, address(this));
        } else if (toToken == address(_reserveToken)) {
            toTokenAmount = reservesAmount;
            _reserveToken.safeTransfer(recipient, reservesAmount);
        } else {
            revert CommonEventsAndErrors.InvalidToken(toToken);
        }

        // Decrease the counter of reserves
        _internalReservesBalance -= reservesAmount;

        // @dev For testing only - asset's are forced to be an explicit value from the test harness
        // in order to get an expected A/L after the exit
        if (test__ForceAssets != 0) {
            test__useForcedAssets = true;
        }
    }

    /**
     * @notice An ERC-4626 based lovToken can exit to the ERC-4626 shares, or to the `depositAsset` by redeeming from the ERC-4626 vault
     */
    function _previewRedeemFromReserves(uint256 reservesAmount, address toToken) internal override view returns (uint256 toTokenAmount) {
        if (toToken == address(depositAsset)) {
            // Redeem from the ERC4626 first
            toTokenAmount = _reserveToken.previewRedeem(reservesAmount);
        } else if (toToken == address(_reserveToken)) {
            // Just the existing ERC4626 token
            toTokenAmount = reservesAmount;
        }

        // Anything else returns 0
    }

    /// @notice Maximum amount of fromToken that can be deposited into the reserveToken
    function _maxDepositIntoReserves(address fromToken) internal override view returns (uint256 fromTokenAmount) {
        // @dev For test only
        if (test__MaxDepositAmt != 0) return test__MaxDepositAmt;

        if (fromToken == address(depositAsset)) {
            fromTokenAmount = _reserveToken.maxDeposit(address(this));
        } else if (fromToken == address(_reserveToken)) {
            fromTokenAmount = MAX_TOKEN_AMOUNT;
        }

        // Anything else returns 0
    }

    /**
     * @notice A ERC-4626 based lovToken either accepts the `depositAsset` (and deposits into the ERC-4626 vault), or the existing ERC-4626 shares
     */
    function _previewDepositIntoReserves(address fromToken, uint256 fromTokenAmount) internal override view returns (uint256 newReservesAmount) {
        if (fromToken == address(depositAsset)) {
            // Deposit into the ERC4626 first
            newReservesAmount = _reserveToken.previewDeposit(fromTokenAmount);
        } else if (fromToken == address(_reserveToken)) {
            // Just the existing ERC4626 token
            newReservesAmount = fromTokenAmount;
        }

        // Anything else returns 0
    }

    /// @notice How many reserve tokens would be received given an amount of toToken
    function _previewMintReserves(address toToken, uint256 reservesAmount) internal override view returns (uint256 newReservesAmount) {
        if (toToken == address(depositAsset)) {
            newReservesAmount = _reserveToken.previewMint(reservesAmount);
        } else if (toToken == address(_reserveToken)) {
            newReservesAmount = reservesAmount;
        }

        // Anything else returns 0
    }

    /**
     * @notice Calculate the maximum amount of lovToken shares to a particular toToken
     * For an ERC-4626 based lovToken, use the max redeemable from that vault
     */
    function _maxRedeemFromReserves(address toToken, Cache memory /*cache*/) internal override view returns (uint256 reservesAmount) {
        if (test__MaxRedeemAmt != 0) return test__MaxRedeemAmt;

        if (toToken == address(depositAsset)) {
            // The standard ERC-4626 implementation uses the balance of reserveToken's that this contract holds.
            // But could also constrain in other ways depending on the implementation
            uint256 _maxUnderlyingRedeem = _reserveToken.maxRedeem(address(this));

            // Use the min of the reserve balance and the underlying maxRedeem
            reservesAmount = reservesBalance();
            if (_maxUnderlyingRedeem < reservesAmount) {
                reservesAmount = _maxUnderlyingRedeem;
            }
        } else if (toToken == address(_reserveToken)) {
            // Just use the current balance of reserveToken
            reservesAmount = reservesBalance();
        }

        // Anything else returns 0
    }
}
