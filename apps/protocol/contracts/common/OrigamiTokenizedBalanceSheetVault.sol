pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { ITokenizedBalanceSheetVault } from "contracts/interfaces/external/tokenizedBalanceSheetVault/ITokenizedBalanceSheetVault.sol";
import { IOrigamiTokenizedBalanceSheetVault } from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiTeleportableToken } from "contracts/common/omnichain/OrigamiTeleportableToken.sol";

/**
 * @title Tokenized 'Balance Sheet' Vault
 * @notice See `ITokenizedBalanceSheetVault` for more details on what a Tokenized Balance Sheet vault represents
 *
 * This Origami implementation is a more opinionated implementation:
 *  - Fees can be taken (from the shares minted/burned) on joins/exits
 *  - The vault needs to be initially seeded by elevated access prior to trading (and as such are protected from inflation style attacks)
 *  - The vault decimals are kept as 18 decimals regardless of the vault assets
 *  - Donations are allowed and will change the share price of the assets/liabilities
 *  - Assets and liabilities need to be in a tokenized form. If that's not possible then a wrapper must be used to represent the balances.
 *  - maxExitWithToken and maxExitWithShares for the sharesOwner=address(0) returns uint256.max. 
 *    This is to reflect that is no explicit exit limits other than the totalSupply. Useful for non-connected users as they browse the dapp
 */
abstract contract OrigamiTokenizedBalanceSheetVault is
    OrigamiTeleportableToken,
    ReentrancyGuard,
    IOrigamiTokenizedBalanceSheetVault
{
    using SafeERC20 for IERC20;
    using OrigamiMath for uint256;

    /// @dev The maximum total supply allowed for this vault.
    /// It is initially set to zero, and first set within seed()
    uint256 private _maxTotalSupply;

    /// @dev Internal cache to save recalculating token balances multiple times
    struct _Cache {
        address inputTokenAddress;
        bool inputTokenIsAsset;
        bool inputTokenIsLiability;
        uint256 inputTokenAmount;
        uint256 inputTokenBalance;
        uint256 totalSupply;
    }

    constructor(
        address initialOwner_,
        string memory name_,
        string memory symbol_
    )
        OrigamiTeleportableToken(name_, symbol_, initialOwner_)
    {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ADMIN                            */
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function setMaxTotalSupply(uint256 maxTotalSupply_) external override onlyElevatedAccess {
        // Cannot set if the totalSupply is zero - seed should be used first
        if (totalSupply() == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        _maxTotalSupply = maxTotalSupply_;
        emit MaxTotalSupplySet(maxTotalSupply_);
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function seed(
        uint256[] calldata assetAmounts,
        uint256[] calldata liabilityAmounts,
        uint256 sharesToMint,
        address receiver,
        uint256 newMaxTotalSupply
    ) external override virtual onlyElevatedAccess {
        // Only to be used for the first deposit
        if (totalSupply() != 0) revert CommonEventsAndErrors.InvalidAccess();

        (address[] memory assetAddresses, address[] memory liabilityAddresses) = tokens();
        if (assetAmounts.length != assetAddresses.length) revert CommonEventsAndErrors.InvalidParam();
        if (liabilityAmounts.length != liabilityAddresses.length) revert CommonEventsAndErrors.InvalidParam();

        if (sharesToMint > newMaxTotalSupply) revert ExceededMaxJoinWithShares(receiver, sharesToMint, newMaxTotalSupply);
        _maxTotalSupply = newMaxTotalSupply;
        emit MaxTotalSupplySet(newMaxTotalSupply);

        _join(msg.sender, receiver, sharesToMint, assetAmounts, liabilityAmounts);
    }

    /// @dev Elevated access can recover any token.
    /// Note: If the asset/liability balances are kept directly in this contract
    /// (rather than delegated to a manager/3rd party upon a join), then the asset/liability tokens
    /// should not be recoverable. In that case the implementation should override this function.
    function recoverToken(address token, address to, uint256 amount) virtual external onlyElevatedAccess {
        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     ACCOUNTING LOGIC                       */
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/

    /// @inheritdoc ITokenizedBalanceSheetVault
    function tokens() public virtual override view returns (address[] memory assets, address[] memory liabilities) {
        assets = assetTokens();
        liabilities = liabilityTokens();
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function balanceSheet() public virtual override view returns (
        uint256[] memory totalAssets, 
        uint256[] memory totalLiabilities
    ) {
        (address[] memory assetAddresses, address[] memory liabilityAddresses) = tokens();

        // First the assets
        uint256 index;
        uint256 length = assetAddresses.length;
        totalAssets = new uint256[](length);
        for (; index < assetAddresses.length; ++index) {
            totalAssets[index] = _tokenBalance(assetAddresses[index]);
        }

        // Now the liabilities
        length = liabilityAddresses.length;
        totalLiabilities = new uint256[](length);
        for (index = 0; index < liabilityAddresses.length; ++index) {
            totalLiabilities[index] = _tokenBalance(liabilityAddresses[index]);
        }
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function convertFromToken(
        address tokenAddress,
        uint256 tokenAmount
    ) public view override returns (
        uint256 shares,
        uint256[] memory assets,
        uint256[] memory liabilities
    ) {
        // Following ERC4626 convention, round down for the two convert functions.
        (shares, assets, liabilities) = _convertOneTokenToSharesAndTokens({
            cache: _fillCache(tokenAddress, tokenAmount),
            sharesRounding: OrigamiMath.Rounding.ROUND_DOWN,
            assetsRounding: OrigamiMath.Rounding.ROUND_DOWN,
            liabilitiesRounding: OrigamiMath.Rounding.ROUND_DOWN
        });
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function convertFromShares(
        uint256 shares
    ) public view override returns (
        uint256[] memory assets,
        uint256[] memory liabilities
    ) {
        // Following ERC4626 convention, round down for the two convert functions.
        return _proportionalTokenAmountFromShares({
            shares: shares,
            cache: _fillCache(),
            assetsRounding: OrigamiMath.Rounding.ROUND_DOWN,
            liabilitiesRounding: OrigamiMath.Rounding.ROUND_DOWN
        });
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*         IMPLEMENTATIONS TO OVERRIDE (EXTERNAL FNS)         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc ITokenizedBalanceSheetVault
    function assetTokens() public virtual override view returns (address[] memory);

    /// @inheritdoc ITokenizedBalanceSheetVault
    function liabilityTokens() public virtual override view returns (address[] memory);

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function joinFeeBps() public virtual override view returns (uint256) {
        return 0;
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function exitFeeBps() public virtual override view returns (uint256) {
        return 0;
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function maxTotalSupply() public override view returns (uint256) {
        return _maxTotalSupply;
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function areJoinsPaused() public virtual override view returns (bool) {
        return false;
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function areExitsPaused() public virtual override view returns (bool) {
        return false;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                            JOINS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc ITokenizedBalanceSheetVault
    function maxJoinWithToken(
        address tokenAddress, 
        address /*receiver*/
    ) public view override virtual returns (uint256 maxToken) {
        return _maxJoinWithToken(_fillCache(tokenAddress, 0), joinFeeBps());
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function previewJoinWithToken(
        address tokenAddress,
        uint256 tokenAmount
    ) public view override returns (
        uint256 shares,
        uint256[] memory assets,
        uint256[] memory liabilities
    ) {
        (shares, /*shareFeesTaken*/, assets, liabilities) = _previewJoinWithToken(
            _fillCache(tokenAddress, tokenAmount),
            joinFeeBps()
        );
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function joinWithToken(
        address tokenAddress,
        uint256 tokenAmount,
        address receiver
    ) public override nonReentrant returns (
        uint256 shares,
        uint256[] memory assets,
        uint256[] memory liabilities
    ) {
        _Cache memory cache = _fillCache(tokenAddress, tokenAmount);

        uint256 feeBps = joinFeeBps();
        uint256 maxTokens = _maxJoinWithToken(cache, feeBps);
        if (tokenAmount > maxTokens) {
            revert ExceededMaxJoinWithToken(receiver, tokenAddress, tokenAmount, maxTokens);
        }

        uint256 shareFeesTaken;
        (shares, shareFeesTaken, assets, liabilities) = _previewJoinWithToken(cache, feeBps);
        if (shareFeesTaken > 0) {
            emit InKindFees(FeeType.JOIN_FEE, feeBps, shareFeesTaken);
        }

        _join(msg.sender, receiver, shares, assets, liabilities);
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function maxJoinWithShares(address /*receiver*/) public view override virtual returns (uint256 maxShares) {
        if (areJoinsPaused()) return 0;
        return availableSharesCapacity();
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function previewJoinWithShares(
        uint256 shares
    ) public view override returns (
        uint256[] memory assets,
        uint256[] memory liabilities
    ) {
        (assets, liabilities, /*shareFeesTaken*/) = _previewJoinWithShares(shares, joinFeeBps());
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function joinWithShares(
        uint256 shares,
        address receiver
    ) public override nonReentrant returns (
        uint256[] memory assets,
        uint256[] memory liabilities
    ) {
        uint256 maxShares = maxJoinWithShares(receiver);
        if (shares > maxShares) {
            revert ExceededMaxJoinWithShares(receiver, shares, maxShares);
        }

        uint256 feeBps = joinFeeBps();
        uint256 shareFeesTaken;
        (assets, liabilities, shareFeesTaken) = _previewJoinWithShares(shares, feeBps);
        if (shareFeesTaken > 0) {
            emit InKindFees(FeeType.JOIN_FEE, feeBps, shareFeesTaken);
        }

        _join(msg.sender, receiver, shares, assets, liabilities);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                            EXITS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc ITokenizedBalanceSheetVault
    function maxExitWithToken(
        address tokenAddress,
        address sharesOwner
    ) public view override virtual returns (uint256 maxToken) {
        return _maxExitWithToken(_fillCache(tokenAddress, 0), sharesOwner, exitFeeBps());
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function previewExitWithToken(
        address tokenAddress,
        uint256 tokenAmount
    ) public view override returns (
        uint256 shares,
        uint256[] memory assets,
        uint256[] memory liabilities
    ) {
        (shares, /*shareFeesTaken*/, assets, liabilities) = _previewExitWithToken(
            _fillCache(tokenAddress, tokenAmount),
            exitFeeBps()
        );
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function exitWithToken(
        address tokenAddress,
        uint256 tokenAmount,
        address receiver,
        address sharesOwner
    ) public override nonReentrant returns (
        uint256 shares,
        uint256[] memory assets,
        uint256[] memory liabilities
    ) {
        _Cache memory cache = _fillCache(tokenAddress, tokenAmount);

        uint256 feeBps = exitFeeBps();
        uint256 maxTokens = _maxExitWithToken(cache, sharesOwner, feeBps);
        if (tokenAmount > maxTokens) {
            revert ExceededMaxExitWithToken(sharesOwner, tokenAddress, tokenAmount, maxTokens);
        }

        uint256 shareFeesTaken;
        (shares, shareFeesTaken, assets, liabilities) = _previewExitWithToken(cache, feeBps);
        if (shareFeesTaken > 0) {
            emit InKindFees(FeeType.EXIT_FEE, feeBps, shareFeesTaken);
        }

        _exit(cache, msg.sender, receiver, sharesOwner, shares, assets, liabilities);
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function maxExitWithShares(
        address sharesOwner
    ) public view override virtual returns (uint256 maxShares) {
        return _maxExitWithShares(sharesOwner);
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function previewExitWithShares(
        uint256 shares
    ) public view override returns (
        uint256[] memory assets,
        uint256[] memory liabilities
    ) {
        (/*shareFeesTaken*/, assets, liabilities) = _previewExitWithShares(
            _fillCache(),
            shares, 
            exitFeeBps()
        );
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function exitWithShares(
        uint256 shares,
        address receiver,
        address sharesOwner
    ) public override nonReentrant returns (
        uint256[] memory assets,
        uint256[] memory liabilities
    ) {
        uint256 maxShares = _maxExitWithShares(sharesOwner);
        if (shares > maxShares) {
            revert ExceededMaxExitWithShares(sharesOwner, shares, maxShares);
        }

        _Cache memory cache = _fillCache();
        uint256 feeBps = exitFeeBps();
        uint256 shareFeesTaken;
        (shareFeesTaken, assets, liabilities) = _previewExitWithShares(cache, shares, feeBps);
        if (shareFeesTaken > 0) {
            emit InKindFees(FeeType.EXIT_FEE, feeBps, shareFeesTaken);
        }

        _exit(cache, msg.sender, receiver, sharesOwner, shares, assets, liabilities);        
    }
    
    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function burn(uint256 amount) external virtual override {
        _burn(msg.sender, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       EXTERNAL VIEWS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function availableSharesCapacity() public override view returns (uint256 shares) {
        uint256 maxTotalSupply_ = maxTotalSupply();
        if (maxTotalSupply_ == type(uint256).max) return maxTotalSupply_;
        return _availableSharesCapacity(totalSupply(), maxTotalSupply_);
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function isBalanceSheetToken(
        address tokenAddress
    ) public virtual override view returns (
        bool isAsset, 
        bool isLiability
    ) {
        // NOTE: The default implementation here iterates over the tokens to find a match
        // It is recommendation to implement this for the specific use case (if possible) for efficiency
        (address[] memory assetAddresses, address[] memory liabilityAddresses) = tokens();

        for (uint256 i; i < assetAddresses.length; ++i) {
            if (assetAddresses[i] == tokenAddress) {
                return (true, false);
            }
        }

        for (uint256 i; i < liabilityAddresses.length; ++i) {
            if (liabilityAddresses[i] == tokenAddress) {
                return (false, true);
            }
        }

        return (false, false);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EXTERNAL ERC165                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public virtual override(IERC165, OrigamiTeleportableToken) pure returns (bool) {
        return OrigamiTeleportableToken.supportsInterface(interfaceId)
            || interfaceId == type(IOrigamiTokenizedBalanceSheetVault).interfaceId 
            || interfaceId == type(ITokenizedBalanceSheetVault).interfaceId;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*         IMPLEMENTATIONS TO OVERRIDE (INTERNAL FNS)         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Return the current token balance of one of the assets or liability tokens in the vault
    /// Should not revert - return zero if tokenAddress is not valid.
    function _tokenBalance(address tokenAddress) internal virtual view returns (uint256);

    /// @dev A hook for joins - it must pull assets from caller and send liabilities to receiver,
    /// along with any other interactions required.
    function _joinPreMintHook(
        address caller,
        address receiver,
        uint256 shares,
        uint256[] memory assets,
        uint256[] memory liabilities
    ) internal virtual;

    /// @dev A hook for exits - it must send assets to receiver and pull liabilities from caller,
    /// along with any other interactions required.
    function _exitPreBurnHook(
        address caller,
        address sharesOwner,
        address receiver,
        uint256 sharesPreBurn,
        uint256[] memory assets,
        uint256[] memory liabilities
    ) internal virtual;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*        INTERNAL TOKENIZED BALANCE SHEET VAULT - JOINS      */
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/

    /// @dev What's the max amount that can be joined into the vault for 
    /// a token address in the cache
    function _maxJoinWithToken(
        _Cache memory cache,
        uint256 feeBps
    ) internal virtual view returns (uint256 maxTokens) {
        if (areJoinsPaused()) return 0;

        // If the token balance of the requested token is zero then cannot join
        if (cache.inputTokenBalance == 0) return 0;

        uint256 maxTotalSupply_ = maxTotalSupply();
        if (maxTotalSupply_ == type(uint256).max) return maxTotalSupply_;

        uint256 availableShares = _availableSharesCapacity(cache.totalSupply, maxTotalSupply_);

        // The max number of tokens is always rounded down
        return _convertSharesToOneToken({
            // Number of shares can be rounded since this is the inverse
            shares: availableShares.inverseSubtractBps(feeBps, OrigamiMath.Rounding.ROUND_UP), 
            cache: cache, 
            rounding: OrigamiMath.Rounding.ROUND_DOWN
        });
    }

    /// @dev Preview a join for an amount of one of the asset/liability tokens specified in the cache
    function _previewJoinWithToken(
        _Cache memory cache,
        uint256 feeBps
    ) internal virtual view returns (
        uint256 shares,
        uint256 shareFeesTaken,
        uint256[] memory assets,
        uint256[] memory liabilities
    ) {
        // When calculating the number of shares/assets/liabilities when JOINING 
        // given an input token amount:
        //   - shares: 
        //       - if input token is an asset: ROUND_DOWN
        //       - if input token is a liability: ROUND_UP
        //   - assets: ROUND_UP (the assets which are pulled from the caller)
        //   - liabilities: ROUND_DOWN (liabilities sent to recipient)
        (shares, assets, liabilities) = _convertOneTokenToSharesAndTokens({
            cache: cache, 
            sharesRounding: cache.inputTokenIsAsset ? OrigamiMath.Rounding.ROUND_DOWN : OrigamiMath.Rounding.ROUND_UP,
            assetsRounding: OrigamiMath.Rounding.ROUND_UP,
            liabilitiesRounding: OrigamiMath.Rounding.ROUND_DOWN
        });

        // Deposit fees are taken from the shares in kind
        // The `shares` the recipient gets are rounded down (ie fees rounded up), in favour of the vault
        (shares, shareFeesTaken) = shares.splitSubtractBps(feeBps, OrigamiMath.Rounding.ROUND_DOWN);
    }

    /// @dev Preview a join for an amount of shares
    function _previewJoinWithShares(uint256 shares, uint256 feeBps) internal virtual view returns (
        uint256[] memory assets,
        uint256[] memory liabilities,
        uint256 shareFeesTaken
    ) {
        // Deposit fees are taken from the shares the user would otherwise receive
        // so calculate the amount of shares required before fees are taken.
        // Round up the fees taken, so it's in favour of the vault
        uint256 sharesBeforeFees = shares.inverseSubtractBps(feeBps, OrigamiMath.Rounding.ROUND_UP);
        unchecked {
            shareFeesTaken = sharesBeforeFees - shares;
        }

        // When calculating the number of assets/liabilities when JOINING
        // given a number of shares:
        //   - assets: ROUND_UP (the assets which are pulled from the caller)
        //   - liabilities: ROUND_DOWN (liabilities sent to recipient)
        (assets, liabilities) = _proportionalTokenAmountFromShares({
            shares: sharesBeforeFees,
            cache: _fillCache(),
            assetsRounding: OrigamiMath.Rounding.ROUND_UP,
            liabilitiesRounding: OrigamiMath.Rounding.ROUND_DOWN
        });
    }

    /// @dev join for specific assets and liabilities and mint exact shares to the receiver
    /// Implementations must implement the hook which pulls assets from caller and sends 
    /// liabilities to receiver
    function _join(
        address caller,
        address receiver,
        uint256 shares,
        uint256[] memory assets,
        uint256[] memory liabilities
    ) internal virtual {
        if (shares == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        _joinPreMintHook(caller, receiver, shares, assets, liabilities);

        _mint(receiver, shares);

        emit Join(caller, receiver, assets, liabilities, shares);
    }
    
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*        INTERNAL TOKENIZED BALANCE SHEET VAULT - EXITS      */
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/

    /// @dev What's the max amount that can be exited from the vault for 
    /// a token address in the cache
    function _maxExitWithToken(
        _Cache memory cache,
        address sharesOwner,
        uint256 feeBps
    ) internal virtual view returns (uint256 maxTokens) {
        if (areExitsPaused()) return 0;

        // If the token balance of the requested token is zero then cannot join
        if (cache.inputTokenBalance == 0) return 0;

        // Special case for address(0), unlimited
        if (sharesOwner == address(0)) return type(uint256).max;

        uint256 shares = balanceOf(sharesOwner);

        // The max number of tokens is always rounded down
        (shares,) = shares.splitSubtractBps(feeBps, OrigamiMath.Rounding.ROUND_DOWN);
        uint256 maxFromShares = _convertSharesToOneToken({
            shares: shares,
            cache: cache,   
            rounding: OrigamiMath.Rounding.ROUND_DOWN
        });

        // Return the minimum of the available balance of the requested token in the balance sheet
        // and the derived amount from the available shares
        return maxFromShares < cache.inputTokenBalance ? maxFromShares : cache.inputTokenBalance;
    }

    /// @dev Preview an exit for an amount of one of the asset/liability tokens specified in the cache
    function _previewExitWithToken(
        _Cache memory cache,
        uint256 feeBps
    ) internal virtual view returns (
        uint256 shares,
        uint256 shareFeesTaken,
        uint256[] memory assets,
        uint256[] memory liabilities
    ) {
        // When calculating the number of shares/assets/liabilities when EXITING 
        // given an input token amount:
        //   - shares: 
        //       - if input token is an asset: ROUND_UP
        //       - if input token is a liability: ROUND_DOWN
        //   - shares: ROUND_UP (number of shares burned from the recipient)
        //   - assets: ROUND_DOWN (the assets which are sent to the recipient)
        //   - liabilities: ROUND_UP (liabilities pulled from the recipient)
        uint256 sharesAfterFees;
        (sharesAfterFees, assets, liabilities) = _convertOneTokenToSharesAndTokens({
            cache: cache,
            sharesRounding: cache.inputTokenIsAsset ? OrigamiMath.Rounding.ROUND_UP : OrigamiMath.Rounding.ROUND_DOWN,
            assetsRounding: OrigamiMath.Rounding.ROUND_DOWN,
            liabilitiesRounding: OrigamiMath.Rounding.ROUND_UP
        });

        // Exit fees are taken in 'shares' prior to redeeming to the underlying assets 
        // & liability tokens. So now calculate the total number of shares to burn from
        // the user.
        // Round up the shares needing to be burned, so it's in favour of the vault
        shares = sharesAfterFees.inverseSubtractBps(feeBps, OrigamiMath.Rounding.ROUND_UP);
        unchecked {
            shareFeesTaken = shares - sharesAfterFees;
        }
    }

    /// @dev What's the max amount of shares that can be exited from the vault for an owner
    function _maxExitWithShares(
        address sharesOwner
    ) internal virtual view returns (uint256 maxShares) {
        if (areExitsPaused()) return 0;
        return sharesOwner == address(0)
            ? type(uint256).max // Special case for address(0), unlimited exit
            : balanceOf(sharesOwner);
    }

    /// @dev Preview an exit for an amount of shares
    function _previewExitWithShares(
        _Cache memory cache,
        uint256 shares,
        uint256 feeBps
    ) internal virtual view returns (
        uint256 shareFeesTaken,
        uint256[] memory assets,
        uint256[] memory liabilities
    ) {
        // The `shares` the user receives are rounded down in favour of the vault
        (shares, shareFeesTaken) = shares.splitSubtractBps(feeBps, OrigamiMath.Rounding.ROUND_DOWN);

        // When calculating the number of assets/liabilities when EXITING
        // given a number of shares:
        //   - assets: ROUND_DOWN (assets are sent to the recipient)
        //   - liabilities: ROUND_UP (liabilities are pulled from the caller)
        (assets, liabilities) = _proportionalTokenAmountFromShares({
            shares: shares,
            cache: cache,
            assetsRounding: OrigamiMath.Rounding.ROUND_DOWN,
            liabilitiesRounding: OrigamiMath.Rounding.ROUND_UP
        });
    }

    /// @dev exit for specific assets and liabilities and burn exact shares to the receiver
    /// Can be called on behalf of a sharesOwner as long as allowance has been provided.
    /// Implementations must implement the hook which pulls liabilities from caller and sends 
    /// assets to receiver
    function _exit(
        _Cache memory cache,
        address caller,
        address receiver,
        address sharesOwner,
        uint256 shares,
        uint256[] memory assets,
        uint256[] memory liabilities
    ) internal virtual {
        if (shares == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (sharesOwner == address(0)) revert CommonEventsAndErrors.InvalidAddress(sharesOwner);
        if (receiver == address(0)) revert CommonEventsAndErrors.InvalidAddress(receiver);
        if (caller != sharesOwner) {
            _spendAllowance(sharesOwner, caller, shares);
        }

        // Call the exit hook prior to burning shares, such that any
        // ERC20 _afterTokenTransfer() hooks the vault may implement (eg hOHM)
        // will use the latest balances
        _exitPreBurnHook(caller, sharesOwner, receiver, shares, assets, liabilities);

        _burn(sharesOwner, shares);
        cache.totalSupply -= shares;

        // If the vault has been fully exited, then reset the maxTotalSupply to zero, as if it were newly created.
        if (cache.totalSupply == 0) _maxTotalSupply = 0;
        
        emit Exit(caller, receiver, sharesOwner, assets, liabilities, shares);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*    INTERNAL TOKENIZED BALANCE SHEET VAULT - CONVERSIONS    */
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/

    /// @dev Convert an amount of one of the asset/liability tokens (specified in the cache) into
    /// the full set of shares/assets/liabilities.
    /// Based off the balance of that token in the vault and total supply of shares
    function _convertOneTokenToSharesAndTokens(
        _Cache memory cache,
        OrigamiMath.Rounding sharesRounding,
        OrigamiMath.Rounding assetsRounding,
        OrigamiMath.Rounding liabilitiesRounding
    ) private view returns (
        uint256 shares,
        uint256[] memory assets,
        uint256[] memory liabilities
    ) {
        shares = _convertOneTokenToShares(cache, sharesRounding);

        (assets, liabilities) = _proportionalTokenAmountFromShares({
            shares: shares,
            cache: cache,
            assetsRounding: assetsRounding,
            liabilitiesRounding: liabilitiesRounding
        });
    }

    /// @dev For each token in tokenAddresses, calculate the proportional token
    /// amount given an amount of shares and the current total supply
    ///   otherTokenAmount = shares * otherTokenBalance / totalSupply
    function _proportionalTokenAmountFromShares(
        uint256 shares,
        _Cache memory cache,
        address[] memory tokenAddresses,
        OrigamiMath.Rounding rounding
    ) internal view returns (uint256[] memory amounts) {
        uint256 length = tokenAddresses.length;
        amounts = new uint256[](length);
        address iTokenAddress;
        for (uint256 i; i < length; ++i) {
            iTokenAddress = tokenAddresses[i];
            if (cache.totalSupply == 0) {
                // denominator is zero
                amounts[i] = 0;
            } else if (iTokenAddress != address(0) && iTokenAddress == cache.inputTokenAddress) {
                // This is from a calculation where the input token is used to calculate
                // the shares first, and then each of the token amounts is derived from the shares.
                // In this case, the exact input token amount needs to be used.
                amounts[i] = cache.inputTokenAmount;
            } else {
                amounts[i] = shares.mulDiv(
                    _getTokenBalance(tokenAddresses[i], cache),
                    cache.totalSupply,
                    rounding
                );
            }
        }
    }

    /// @dev For each of the asset and liability tokens, calculate the proportional token
    /// amount given an amount of shares and the current total supply
    function _proportionalTokenAmountFromShares(
        uint256 shares,
        _Cache memory cache,
        OrigamiMath.Rounding assetsRounding,
        OrigamiMath.Rounding liabilitiesRounding
    ) internal view returns (
        uint256[] memory assets,
        uint256[] memory liabilities
    ) {
        (address[] memory assetAddresses, address[] memory liabilityAddresses) = tokens();
        assets = _proportionalTokenAmountFromShares(shares, cache, assetAddresses, assetsRounding);
        liabilities = _proportionalTokenAmountFromShares(shares, cache, liabilityAddresses, liabilitiesRounding);
    }

    /// @dev Convert an amount of one of the asset/liability tokens into equivalent shares, based
    /// on the balance of that token and the total supply of the vault.
    function _convertOneTokenToShares(
        _Cache memory cache,
        OrigamiMath.Rounding rounding
    ) private pure returns (uint256) {
        // An initial seed deposit is required first. 
        // In the case of a new asset added to an existing vault, a donation of tokens 
        // must be added to the vault first.
        return cache.inputTokenBalance == 0
            ? 0
            : cache.inputTokenAmount.mulDiv(cache.totalSupply, cache.inputTokenBalance, rounding);
    }

    /// @dev Convert an amount of shares into one of the asset/liability tokens, based on the
    /// balance of that token and the total supply of the vault.
    function _convertSharesToOneToken(
        uint256 shares,
        _Cache memory cache,
        OrigamiMath.Rounding rounding
    ) private pure returns (uint256) {
        // An initial seed deposit is required first. 
        // In the case of a new asset added to an existing vault, a donation of tokens 
        // must be added to the vault first.
        return cache.inputTokenBalance == 0
            ? 0
            : shares.mulDiv(cache.inputTokenBalance, cache.totalSupply, rounding);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*       INTERNAL TOKENIZED BALANCE SHEET VAULT - UTILS       */
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/

    /// @dev Fill the internal cache.
    /// For this purpose, only the totalSupply is required
    function _fillCache() private view returns (_Cache memory cache) {
        cache.totalSupply = totalSupply();
    }

    /// @dev Fill the internal cache.
    function _fillCache(address inputTokenAddress, uint256 inputTokenAmount) private view returns (_Cache memory cache) {       
        // Must exlusively be an asset or liability
        (bool inputTokenIsAsset, bool inputTokenIsLiability) = isBalanceSheetToken(inputTokenAddress);
        
        // Must be exlusively an asset or liability
        if ((inputTokenIsAsset && !inputTokenIsLiability) || (!inputTokenIsAsset && inputTokenIsLiability)) {
            cache = _Cache(
                inputTokenAddress, 
                inputTokenIsAsset, 
                inputTokenIsLiability, 
                inputTokenAmount, 
                _tokenBalance(inputTokenAddress), 
                totalSupply()
            );

            // If there's no balance of the token then ensure the inputTokenAmount is also zero
            if (cache.inputTokenBalance == 0) cache.inputTokenAmount = 0;
        }

        // leave uninitialized
    }

    /// @dev Get the cached balance of a token in the vault. 
    /// If the tokenAddress doesn't match the asset in the cache then it is calculated
    function _getTokenBalance(address tokenAddress, _Cache memory cache) private view returns (uint256) {
        return tokenAddress == cache.inputTokenAddress
            ? cache.inputTokenBalance
            : _tokenBalance(tokenAddress);
    }

    /// @dev What is the spare capacity of shares which can be minted under the maxTotalSupply
    function _availableSharesCapacity(
        uint256 totalSupply_, 
        uint256 maxTotalSupply_
    ) internal virtual pure returns (uint256 shares) {
        if (totalSupply_ > maxTotalSupply_) {
            shares = 0;
        } else {
            unchecked {
                shares = maxTotalSupply_ - totalSupply_;
            }
        }
    }
}