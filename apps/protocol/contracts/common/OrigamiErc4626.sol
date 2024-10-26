pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/OrigamiErc4626.sol)

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IOrigamiErc4626 } from "contracts/interfaces/common/IOrigamiErc4626.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Origami ERC-4626
 * @notice A fork of the openzeppelin ERC-4626, with:
 *  - `_decimalsOffset()` set to zero (OZ defaults to zero anyway)
 *  - Always has decimals() of 18dp (rather than using the underlying asset)
 *  - Deposit and Withdraw fees, which are taken from the _shares_ of the user,
 *    benefiting the existing vault holders.
 *  - Permit support
 *  - IERC165 support
 *  - Reentrancy guard on deposit/mint/withdraw/redeem
 *  - maxRedeem & maxWithdraw for address(0) returns the total vault capacity (given any caps within the implementation) 
 *    which can be withdrawn/redeemed (rather than always returning zero)
 * 
 * For the reference implementation, see:
 *  - https://github.com/OpenZeppelin/openzeppelin-contracts/blob/cae60c595b37b1e7ed7dd50ad0257387ec07c0cf/contracts/token/ERC20/extensions/ERC4626.sol
 *  - https://github.com/OpenZeppelin/openzeppelin-contracts/blob/cae60c595b37b1e7ed7dd50ad0257387ec07c0cf/contracts/token/ERC20/extensions/ERC20Permit.sol
 */
contract OrigamiErc4626 is 
    ERC20, 
    IERC4626,
    EIP712,
    ReentrancyGuard,
    OrigamiElevatedAccess,
    IOrigamiErc4626
{
    using SafeERC20 for IERC20;
    using OrigamiMath for uint256;

    // Note the `_maxTotalSupply` is initally set to zero.
    // It is first set upon elevated access calling `seedDeposit()`
    uint256 private _maxTotalSupply;

    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    IERC20 internal immutable _asset;

    mapping(address account => uint256) private _nonces;

    uint8 private constant DECIMALS = 18;

    /// @dev The scalar to convert from `asset` decimals to 18 decimals
    uint256 private immutable _assetsToSharesScalar;

    constructor(
        address initialOwner_,
        string memory name_,
        string memory symbol_,
        IERC20 asset_
    ) 
        OrigamiElevatedAccess(initialOwner_)
        ERC20(name_, symbol_)
        EIP712(name_, "1") 
    {
        uint8 _underlyingDecimals = IERC20Metadata(address(asset_)).decimals();

        // Only allow <= 18 decimal places in the underlying
        // This satisfies the virtual offset requirement where:
        // > Said otherwise, we use more decimal places to represent the shares than the underlying token does to represent the assets.
        // https://docs.openzeppelin.com/contracts/4.x/erc4626#defending_with_a_virtual_offset
        if (_underlyingDecimals > DECIMALS) revert CommonEventsAndErrors.InvalidToken(address(asset_));
        _assetsToSharesScalar = 10 ** (DECIMALS - _underlyingDecimals);

        _asset = asset_;
    }

    /// @inheritdoc IOrigamiErc4626
    function setMaxTotalSupply(uint256 maxTotalSupply_) public virtual override onlyElevatedAccess {
        // Cannot set if the totalSupply is zero - seedDeposit should be used first
        if (totalSupply() == 0) revert CommonEventsAndErrors.InvalidParam();
        _maxTotalSupply = maxTotalSupply_;
        emit MaxTotalSupplySet(maxTotalSupply_);
    }

    /// @inheritdoc IOrigamiErc4626
    function seedDeposit(
        uint256 assets, 
        address receiver, 
        uint256 maxTotalSupply_
    ) external override onlyElevatedAccess returns (uint256 shares) {
        // Only to be used for the first deposit
        if (totalSupply() != 0) revert CommonEventsAndErrors.InvalidParam();

        // The new maxTotalSupply needs to be at least the size of the
        // new shares minted, or the deposit() will revert.
        _maxTotalSupply = maxTotalSupply_;
        emit MaxTotalSupplySet(maxTotalSupply_);
        return deposit(assets, receiver);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       EXTERNAL ERC20                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC20Metadata
    function decimals() public view virtual override(IERC20Metadata, ERC20) returns (uint8) {
        return DECIMALS;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EXTERNAL ERC4626                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC4626
    function asset() public view virtual override returns (address) {
        return address(_asset);
    }

    /// @inheritdoc IERC4626
    function totalAssets() public view virtual override returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    /// @inheritdoc IERC4626
    function convertToShares(uint256 assets) public view virtual override returns (uint256) {
        return _convertToShares(assets, OrigamiMath.Rounding.ROUND_DOWN);
    }

    /// @inheritdoc IERC4626
    function convertToAssets(uint256 shares) public view virtual override returns (uint256) {
        return _convertToAssets(shares, OrigamiMath.Rounding.ROUND_DOWN);
    }

    /// @inheritdoc IERC4626
    function maxDeposit(address /*receiver*/) public override view returns (uint256 maxAssets) {
        return _maxDeposit(depositFeeBps());
    }

    /// @inheritdoc IERC4626
    function maxMint(address /*receiver*/) public override view returns (uint256 maxShares) {
        uint256 maxTotalSupply_ = maxTotalSupply();
        if (maxTotalSupply_ == type(uint256).max) return type(uint256).max;

        uint256 _totalSupply = totalSupply();
        if (_totalSupply > maxTotalSupply_) return 0;

        unchecked {
            maxShares = maxTotalSupply_ - _totalSupply;
        }
    }

    /// @inheritdoc IERC4626
    function maxWithdraw(address sharesOwner) public override view returns (uint256 maxAssets) {
        return _maxWithdraw(sharesOwner, withdrawalFeeBps());
    }

    /// @inheritdoc IERC4626
    function maxRedeem(address sharesOwner) public override view returns (uint256 maxShares) {
        return _maxRedeem(sharesOwner, withdrawalFeeBps());
    }

    /// @inheritdoc IERC4626
    function previewDeposit(uint256 assets) public view virtual override returns (uint256 shares) {
        (shares,) = _previewDeposit(assets, depositFeeBps());
    }

    /// @inheritdoc IERC4626
    function previewMint(uint256 shares) public view virtual override returns (uint256 assets) {
        (assets,) = _previewMint(shares, depositFeeBps());
    }

    /// @inheritdoc IERC4626
    function previewWithdraw(uint256 assets) public view virtual override returns (uint256 shares) {
        (shares,) = _previewWithdraw(assets, withdrawalFeeBps());
    }

    /// @inheritdoc IERC4626
    function previewRedeem(uint256 shares) public view virtual override returns (uint256 assets) {
        (assets,) = _previewRedeem(shares, withdrawalFeeBps());
    }
    
    /// @inheritdoc IERC4626
    function deposit(
        uint256 assets, 
        address receiver
    ) public virtual override nonReentrant returns (uint256) {
        uint256 feeBps = depositFeeBps();
        uint256 maxAssets = _maxDeposit(feeBps);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        (uint256 shares, uint256 shareFeesTaken) = _previewDeposit(assets, feeBps);
        if (shareFeesTaken > 0) {
            emit InKindFees(FeeType.DEPOSIT_FEE, feeBps, shareFeesTaken);
        }

        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    /// @inheritdoc IERC4626
    function mint(
        uint256 shares, 
        address receiver
    ) public virtual override nonReentrant returns (uint256) {
        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
        }
        
        uint256 feeBps = depositFeeBps();
        (uint256 assets, uint256 shareFeesTaken) = _previewMint(shares, feeBps);
        if (shareFeesTaken > 0) {
            emit InKindFees(FeeType.DEPOSIT_FEE, feeBps, shareFeesTaken);
        }

        _deposit(_msgSender(), receiver, assets, shares);

        return assets;
    }

    /// @inheritdoc IERC4626
    function withdraw(
        uint256 assets, 
        address receiver, 
        address sharesOwner
    ) public virtual override nonReentrant returns (uint256) {
        uint256 feeBps = withdrawalFeeBps();
        uint256 maxAssets = _maxWithdraw(sharesOwner, feeBps);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxWithdraw(sharesOwner, assets, maxAssets);
        }

        (uint256 shares, uint256 shareFeesTaken) = _previewWithdraw(assets, feeBps);
        if (shareFeesTaken > 0) {
            emit InKindFees(FeeType.WITHDRAWAL_FEE, feeBps, shareFeesTaken);
        }

        _withdraw(_msgSender(), receiver, sharesOwner, assets, shares);

        return shares;
    }

    /// @inheritdoc IERC4626
    function redeem(
        uint256 shares, 
        address receiver, 
        address sharesOwner
    ) public virtual override nonReentrant returns (uint256) {
        uint256 feeBps = withdrawalFeeBps();
        uint256 maxShares = _maxRedeem(sharesOwner, feeBps);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(sharesOwner, shares, maxShares);
        }

        (uint256 assets, uint256 shareFeesTaken) = _previewRedeem(shares, feeBps);
        if (shareFeesTaken > 0) {
            emit InKindFees(FeeType.WITHDRAWAL_FEE, feeBps, shareFeesTaken);
        }

        _withdraw(_msgSender(), receiver, sharesOwner, assets, shares);

        return assets;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*              EXT. IMPLEMENTATIONS TO OVERRIDE              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/


    /// @inheritdoc IOrigamiErc4626
    function depositFeeBps() public virtual override view returns (uint256) {
        return 0;
    }

    /// @inheritdoc IOrigamiErc4626
    function withdrawalFeeBps() public virtual override view returns (uint256) {
        return 0;
    }

    /// @inheritdoc IOrigamiErc4626
    function maxTotalSupply() public virtual override view returns (uint256) {
        return _maxTotalSupply;
    }

    /// @inheritdoc IOrigamiErc4626
    function areDepositsPaused() external virtual override view returns (bool) {
        return false;
    }

    /// @inheritdoc IOrigamiErc4626
    function areWithdrawalsPaused() external virtual override view returns (bool) {
        return false;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   EXTERNAL ERC20Permit                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @inheritdoc IERC20Permit
     */
    function permit(
        address sharesOwner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override {
        if (block.timestamp > deadline) {
            revert ERC2612ExpiredSignature(deadline);
        }

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, sharesOwner, spender, value, _useNonce(sharesOwner), deadline));

        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = ECDSA.recover(hash, v, r, s);
        if (signer != sharesOwner) {
            revert ERC2612InvalidSigner(signer, sharesOwner);
        }

        _approve(sharesOwner, spender, value);
    }

    /// @inheritdoc IERC20Permit
    function nonces(address sharesOwner) public override view returns (uint256) {
        return _nonces[sharesOwner];
    }

    /// @inheritdoc IERC20Permit
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external override view virtual returns (bytes32) {
        return _domainSeparatorV4();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EXTERNAL ERC165                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public virtual override pure returns (bool) {
        return interfaceId == type(IERC4626).interfaceId 
            || interfaceId == type(IERC20Permit).interfaceId
            || interfaceId == type(EIP712).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    /**
     * @notice Recover any token other than the underlying erc4626 asset.
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {
        if (token == asset()) revert CommonEventsAndErrors.InvalidToken(token);

        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INTERNAL ERC4626                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev Calculate the max number of assets which can be deposited given the available shares
     * under the maxTotalSupply()
     * This may revert with an overflow for very extreme/unrealistic cases of either a maxTotalSupply
     * which is close to but not exactly type(uint256).max, or an extremely unbalanced share price.
     */
    function _maxDeposit(uint256 feeBps) internal view returns (uint256 maxAssets) {
        uint256 maxTotalSupply_ = maxTotalSupply();
        if (maxTotalSupply_ == type(uint256).max) return type(uint256).max;

        uint256 _totalSupply = totalSupply();
        if (_totalSupply > maxTotalSupply_) return 0;

        uint256 availableShares;
        unchecked {
            availableShares = maxTotalSupply_ - _totalSupply;
        }

        return _convertToAssets(
            availableShares.inverseSubtractBps(feeBps, OrigamiMath.Rounding.ROUND_UP),
            OrigamiMath.Rounding.ROUND_UP
        );
    }

    /**
     * @dev Calculate the max number of assets which can be withdrawn given the number of shares
     * owned by `sharesOwner`
     * May be overridden to enforce other constraints, such as current assets available to withdraw
     * from the underlying asset deployment
     */
    function _maxWithdraw(
        address sharesOwner, 
        uint256 feeBps
    ) internal virtual view returns (uint256 maxAssets) {
        if (sharesOwner == address(0)) return type(uint256).max;

        uint256 shares = balanceOf(sharesOwner);
        // Withdrawal fees are taken from the shares the user redeems
        (shares,) = shares.splitSubtractBps(feeBps, OrigamiMath.Rounding.ROUND_DOWN);
        return _convertToAssets(shares, OrigamiMath.Rounding.ROUND_DOWN);
    }

    /**
     * @dev Calculate the max number of shares which can be redeemed given the number of shares
     * owned by `sharesOwner`
     * May be overridden to enforce other constraints, such as current assets available to withdraw
     * from the underlying asset deployment
     */
    function _maxRedeem(
        address sharesOwner,
        uint256 /*feeBps*/
    ) internal virtual view returns (uint256 maxShares) {
        return sharesOwner == address(0)
            ? type(uint256).max
            : balanceOf(sharesOwner);
    }

    function _previewDeposit(uint256 assets, uint256 feeBps) internal virtual view returns (
        uint256 shares,
        uint256 shareFeesTaken
    ) {
        shares = _convertToShares(assets, OrigamiMath.Rounding.ROUND_DOWN);

        // Deposit fees are taken from the shares in kind
        (shares, shareFeesTaken) = shares.splitSubtractBps(feeBps, OrigamiMath.Rounding.ROUND_DOWN);
    }

    function _previewMint(uint256 shares, uint256 feeBps) internal virtual view returns (
        uint256 assets,
        uint256 shareFeesTaken
    ) {
        // Deposit fees are taken from the shares the user would otherwise receive
        // so calculate the amount of shares required before fees are taken.
        uint256 sharesPlusFees = shares.inverseSubtractBps(feeBps, OrigamiMath.Rounding.ROUND_UP);
        unchecked {
            shareFeesTaken = sharesPlusFees - shares;
        }

        assets = _convertToAssets(sharesPlusFees, OrigamiMath.Rounding.ROUND_UP);
    }
    
    function _previewWithdraw(uint256 assets, uint256 feeBps) internal view returns (
        uint256 shares,
        uint256 shareFeesTaken
    ) {
        uint256 sharesExcludingFees = _convertToShares(assets, OrigamiMath.Rounding.ROUND_UP);
        // Withdrawal fees are taken from the shares the user redeems
        // so calculate the amount of shares required before fees are taken.
        shares = sharesExcludingFees.inverseSubtractBps(feeBps, OrigamiMath.Rounding.ROUND_UP);
        unchecked {
            shareFeesTaken = shares - sharesExcludingFees;
        }
    }

    function _previewRedeem(uint256 shares, uint256 feeBps) internal view returns (
        uint256 assets,
        uint256 shareFeesTaken
    ) {
        (shares, shareFeesTaken) = shares.splitSubtractBps(feeBps, OrigamiMath.Rounding.ROUND_DOWN);
        assets = _convertToAssets(shares, OrigamiMath.Rounding.ROUND_DOWN);
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     */
    function _convertToShares(uint256 assets, OrigamiMath.Rounding rounding) internal view virtual returns (uint256) {
        return assets.mulDiv(totalSupply() + _assetsToSharesScalar, totalAssets() + 1, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, OrigamiMath.Rounding rounding) internal view virtual returns (uint256) {
        return shares.mulDiv(totalAssets() + 1, totalSupply() + _assetsToSharesScalar, rounding);
    }

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual {
        _depositHook(caller, assets);

        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev A hook for the implementation to do something with the deposited assets
     */
    function _depositHook(address caller, uint256 assets) internal virtual {
        // The default implementation assumes the assets are just pulled into this contract.
        SafeERC20.safeTransferFrom(_asset, caller, address(this), assets);
    }

    /**
     * @dev Withdraw/redeem common workflow.
     */
    function _withdraw(
        address caller,
        address receiver,
        address sharesOwner,
        uint256 assets,
        uint256 shares
    ) internal virtual {
        if (caller != sharesOwner) {
            _spendAllowance(sharesOwner, caller, shares);
        }

        // If _asset is ERC777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // shares are burned and after the assets are transferred, which is a valid state.
        _burn(sharesOwner, shares);
        
        // If the vault has been fully exited, then reset the maxTotalSupply to zero, as if it were newly created.
        if (totalSupply() == 0) _maxTotalSupply = 0;

        _withdrawHook(assets, receiver);

        emit Withdraw(caller, receiver, sharesOwner, assets, shares);
    }

    /**
     * @dev A hook for the implementation to pull and send assets to the receiver
     */
    function _withdrawHook(
        uint256 assets,
        address receiver
    ) internal virtual {
        // The default implementation assumes the assets are just sitting in this contract.
        SafeERC20.safeTransfer(_asset, receiver, assets);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    INTERNAL ERC20Permit                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev Consumes a nonce.
     * Returns the current value and increments nonce.
     */
    function _useNonce(address sharesOwner) internal returns (uint256) {
        // For each account, the nonce has an initial value of 0, can only be incremented by one, and cannot be
        // decremented or reset. This guarantees that the nonce never overflows.
        unchecked {
            // It is important to do x++ and not ++x here.
            return _nonces[sharesOwner]++;
        }
    }
}
