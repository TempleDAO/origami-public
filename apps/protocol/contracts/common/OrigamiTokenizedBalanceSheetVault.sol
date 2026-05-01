pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import {
    ITokenizedBalanceSheetVault
} from "contracts/interfaces/external/tokenizedBalanceSheetVault/ITokenizedBalanceSheetVault.sol";
import { IOrigamiTokenizedBalanceSheetVault } from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiTeleportableToken } from "contracts/common/omnichain/OrigamiTeleportableToken.sol";
import { OrigamiTBSLib as TBSLib, TBSState } from "contracts/libraries/OrigamiTBSLib.sol";
import { ITokenPrices } from "contracts/interfaces/common/ITokenPrices.sol";

/**
 * @title Tokenized 'Balance Sheet' Vault
 * @notice See `ITokenizedBalanceSheetVault` for more details on what a Tokenized Balance Sheet vault represents
 *
 * This Origami implementation is a more opinionated implementation:
 *  - Fees can be taken (from the shares minted/burned) on joins/exits
 *  - The vault needs to be initially seeded by elevated access prior to trading (and as such are protected from
 * inflation style attacks)
 *  - The vault decimals are kept as 18 decimals regardless of the vault assets
 *  - Donations are allowed and will change the share price of the assets/liabilities
 *  - Assets and liabilities need to be in a tokenized form. If that's not possible then a wrapper must be used to
 * represent the balances.
 *  - maxExitWithToken and maxExitWithShares for the sharesOwner=address(0) returns uint256.max.
 *    This is to reflect that is no explicit exit limits other than the totalSupply. Useful for non-connected users as
 * they browse the dapp
 */
abstract contract OrigamiTokenizedBalanceSheetVault is
    OrigamiTeleportableToken,
    ReentrancyGuard,
    IOrigamiTokenizedBalanceSheetVault
{
    using SafeERC20 for IERC20;
    using OrigamiMath for uint256;
    using TBSLib for TBSState;

    /// @dev The maximum total supply allowed for this vault.
    /// It is initially set to zero, and first set within seed()
    uint256 private _maxTotalSupply;

    /// @inheritdoc ITokenizedBalanceSheetVault
    bytes32 public override currentTokensHash;

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    ITokenPrices public override tokenPrices;

    constructor(address initialOwner_, string memory name_, string memory symbol_, address tokenPrices_)
        OrigamiTeleportableToken(name_, symbol_, initialOwner_)
    {
        tokenPrices = ITokenPrices(tokenPrices_);
    }

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
    function updateCurrentTokensHash() public virtual {
        bytes32 newHash = keccak256(abi.encode(assetTokens(), liabilityTokens()));
        if (currentTokensHash != newHash) {
            currentTokensHash = newHash;
            emit CurrentTokensHashSet(newHash);
        }
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function seed(
        uint256[] calldata assetAmounts,
        uint256[] calldata liabilityAmounts,
        uint256 sharesToMint,
        address receiver,
        uint256 newMaxTotalSupply,
        bytes calldata balanceSheetData
    ) external virtual override onlyElevatedAccess {
        // Only to be used for the first deposit
        if (totalSupply() != 0) revert CommonEventsAndErrors.InvalidAccess();

        TBSState memory $;
        {
            $.assetAddresses = assetTokens();
            $.liabilityAddresses = liabilityTokens();

            // Existing balances in the local state are set exactly to the new balance sheet amounts
            // such that any proportional based calculations are using this seed amount
            // rather than zero's for an empty vault (or if someone skews by depositing funds into the unseeded
            // contracts)
            $.assetBalances = assetAmounts;
            $.liabilityBalances = liabilityAmounts;

            // Implementation specific balance sheet data is encoded by the caller
            // For example, this could be the split across multiple positions (OPAL)
            // This may also be empty - it is unused in hOHM
            $.balanceSheetData = balanceSheetData;
        }

        // Double check the amount arrays length match the addresses length
        if (assetAmounts.length != $.assetAddresses.length) revert CommonEventsAndErrors.InvalidParam();
        if (liabilityAmounts.length != $.liabilityAddresses.length) revert CommonEventsAndErrors.InvalidParam();

        if (sharesToMint > newMaxTotalSupply) {
            revert ExceededMaxJoinWithShares(receiver, sharesToMint, newMaxTotalSupply);
        }
        _maxTotalSupply = newMaxTotalSupply;
        emit MaxTotalSupplySet(newMaxTotalSupply);

        _join($, msg.sender, receiver, sharesToMint, assetAmounts, liabilityAmounts);
    }

    /// @dev Elevated access can recover any token.
    /// Note: If the asset/liability balances are kept directly in this contract
    /// (rather than delegated to a manager/3rd party upon a join), then the asset/liability tokens
    /// should not be recoverable. In that case the implementation should override this function.
    function recoverToken(address token, address to, uint256 amount) external virtual onlyElevatedAccess {
        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function setTokenPrices(address _tokenPrices) external override onlyElevatedAccess {
        if (_tokenPrices == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        emit TokenPricesSet(_tokenPrices);
        tokenPrices = ITokenPrices(_tokenPrices);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     ACCOUNTING LOGIC                       */
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/

    /// @inheritdoc ITokenizedBalanceSheetVault
    function tokens() public view virtual override returns (address[] memory assets, address[] memory liabilities) {
        assets = assetTokens();
        liabilities = liabilityTokens();
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function balanceSheet()
        public
        view
        override
        returns (uint256[] memory totalAssets, uint256[] memory totalLiabilities)
    {
        (totalAssets, totalLiabilities,) = _balanceSheet();
    }

    /// @dev Implementations are required to implement.
    /// @return totalAssets The per token amount of assets in the balance sheet
    /// @return totalLiabilities The per token amount of liabilities in the balance sheet
    /// @return balanceSheetData Optional encoded data which can be used to cache balance sheet
    ///         information, to be used in joins/exits later
    function _balanceSheet()
        internal
        view
        virtual
        returns (uint256[] memory totalAssets, uint256[] memory totalLiabilities, bytes memory balanceSheetData);

    /// @inheritdoc ITokenizedBalanceSheetVault
    function convertFromToken(address tokenAddress, uint256 tokenAmount)
        public
        view
        override
        returns (uint256 shares, uint256[] memory assets, uint256[] memory liabilities)
    {
        // Following ERC4626 convention, round down for the two convert functions.
        (shares, assets, liabilities) = TBSLib.convertInputTokenAmountToSharesAndTokens({
            $: _stateForInputToken(tokenAddress, tokenAmount),
            sharesRounding: OrigamiMath.Rounding.ROUND_DOWN,
            assetsRounding: OrigamiMath.Rounding.ROUND_DOWN,
            liabilitiesRounding: OrigamiMath.Rounding.ROUND_DOWN
        });
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function convertFromShares(uint256 shares)
        public
        view
        override
        returns (uint256[] memory assets, uint256[] memory liabilities)
    {
        // Following ERC4626 convention, round down for the two convert functions.
        return TBSLib.proportionalTokenAmountsFromShares({
            $: _state(),
            shares: shares,
            assetsRounding: OrigamiMath.Rounding.ROUND_DOWN,
            liabilitiesRounding: OrigamiMath.Rounding.ROUND_DOWN
        });
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*         IMPLEMENTATIONS TO OVERRIDE (EXTERNAL FNS)         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function assetTokens() public view virtual override returns (address[] memory);

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function liabilityTokens() public view virtual override returns (address[] memory);

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function joinFeeBps() public view virtual override returns (uint256) {
        return 0;
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function exitFeeBps() public view virtual override returns (uint256) {
        return 0;
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function maxTotalSupply() public view override returns (uint256) {
        return _maxTotalSupply;
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function areJoinsPaused() public view virtual override returns (bool) {
        return false;
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function areExitsPaused() public view virtual override returns (bool) {
        return false;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                            JOINS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc ITokenizedBalanceSheetVault
    function maxJoinWithToken(
        address tokenAddress,
        address /*receiver*/
    )
        public
        view
        virtual
        override
        returns (uint256 maxToken)
    {
        return _maxJoinWithToken(_stateForInputToken(tokenAddress, 0), joinFeeBps());
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function previewJoinWithToken(address tokenAddress, uint256 tokenAmount)
        public
        view
        override
        returns (uint256 shares, uint256[] memory assets, uint256[] memory liabilities)
    {
        (shares,/*shareFeesTaken*/, assets, liabilities) =
            _previewJoinWithToken(_stateForInputToken(tokenAddress, tokenAmount), joinFeeBps());
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function joinWithToken(address tokenAddress, uint256 tokenAmount, address receiver, bytes32 tokensHash)
        public
        override
        nonReentrant
        returns (uint256 shares, uint256[] memory assets, uint256[] memory liabilities)
    {
        if (tokensHash != currentTokensHash) revert IncorrectTokensHash();
        TBSState memory $ = _stateForInputToken(tokenAddress, tokenAmount);

        uint256 feeBps = joinFeeBps();
        uint256 maxTokens = _maxJoinWithToken($, feeBps);
        if (tokenAmount > maxTokens) {
            revert ExceededMaxJoinWithToken(receiver, tokenAddress, tokenAmount, maxTokens);
        }

        uint256 shareFeesTaken;
        (shares, shareFeesTaken, assets, liabilities) = _previewJoinWithToken($, feeBps);
        if (shareFeesTaken > 0) {
            emit InKindFees(FeeType.JOIN_FEE, feeBps, shareFeesTaken);
        }

        _join($, msg.sender, receiver, shares, assets, liabilities);
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function maxJoinWithShares(
        address /*receiver*/
    )
        public
        view
        virtual
        override
        returns (uint256 maxShares)
    {
        return _maxJoinWithShares(totalSupply());
    }

    function _maxJoinWithShares(uint256 _totalSupply) internal view returns (uint256 maxShares) {
        if (areJoinsPaused()) return 0;
        return TBSLib.availableSharesCapacity(_totalSupply, maxTotalSupply());
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function previewJoinWithShares(uint256 shares)
        public
        view
        override
        returns (uint256[] memory assets, uint256[] memory liabilities)
    {
        (
            assets,
            liabilities, /*shareFeesTaken*/
        ) = _previewJoinWithShares(_state(), shares, joinFeeBps());
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function joinWithShares(uint256 shares, address receiver, bytes32 tokensHash)
        public
        override
        nonReentrant
        returns (uint256[] memory assets, uint256[] memory liabilities)
    {
        if (tokensHash != currentTokensHash) revert IncorrectTokensHash();
        TBSState memory $ = _state();
        uint256 maxShares = _maxJoinWithShares($.totalSupply);
        if (shares > maxShares) {
            revert ExceededMaxJoinWithShares(receiver, shares, maxShares);
        }

        uint256 feeBps = joinFeeBps();
        uint256 shareFeesTaken;
        (assets, liabilities, shareFeesTaken) = _previewJoinWithShares($, shares, feeBps);
        if (shareFeesTaken > 0) {
            emit InKindFees(FeeType.JOIN_FEE, feeBps, shareFeesTaken);
        }

        _join($, msg.sender, receiver, shares, assets, liabilities);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                            EXITS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc ITokenizedBalanceSheetVault
    function maxExitWithToken(address tokenAddress, address sharesOwner)
        public
        view
        virtual
        override
        returns (uint256 maxToken)
    {
        return _maxExitWithToken(_stateForInputToken(tokenAddress, 0), sharesOwner, exitFeeBps());
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function previewExitWithToken(address tokenAddress, uint256 tokenAmount)
        public
        view
        override
        returns (uint256 shares, uint256[] memory assets, uint256[] memory liabilities)
    {
        (shares,/*shareFeesTaken*/, assets, liabilities) =
            _previewExitWithToken(_stateForInputToken(tokenAddress, tokenAmount), exitFeeBps());
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function exitWithToken(
        address tokenAddress,
        uint256 tokenAmount,
        address receiver,
        address sharesOwner,
        bytes32 tokensHash
    ) public override nonReentrant returns (uint256 shares, uint256[] memory assets, uint256[] memory liabilities) {
        if (tokensHash != currentTokensHash) revert IncorrectTokensHash();
        TBSState memory $ = _stateForInputToken(tokenAddress, tokenAmount);

        uint256 feeBps = exitFeeBps();
        uint256 maxTokens = _maxExitWithToken($, sharesOwner, feeBps);
        if (tokenAmount > maxTokens) {
            revert ExceededMaxExitWithToken(sharesOwner, tokenAddress, tokenAmount, maxTokens);
        }

        uint256 shareFeesTaken;
        (shares, shareFeesTaken, assets, liabilities) = _previewExitWithToken($, feeBps);
        if (shareFeesTaken > 0) {
            emit InKindFees(FeeType.EXIT_FEE, feeBps, shareFeesTaken);
        }

        _exit($, msg.sender, receiver, sharesOwner, shares, assets, liabilities);
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function maxExitWithShares(address sharesOwner) public view virtual override returns (uint256 maxShares) {
        return _maxExitWithShares(sharesOwner);
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function previewExitWithShares(uint256 shares)
        public
        view
        override
        returns (uint256[] memory assets, uint256[] memory liabilities)
    {
        (/*shareFeesTaken*/, assets, liabilities) = _previewExitWithShares(_state(), shares, exitFeeBps());
    }

    /// @inheritdoc ITokenizedBalanceSheetVault
    function exitWithShares(uint256 shares, address receiver, address sharesOwner, bytes32 tokensHash)
        public
        override
        nonReentrant
        returns (uint256[] memory assets, uint256[] memory liabilities)
    {
        if (tokensHash != currentTokensHash) revert IncorrectTokensHash();
        uint256 maxShares = _maxExitWithShares(sharesOwner);
        if (shares > maxShares) {
            revert ExceededMaxExitWithShares(sharesOwner, shares, maxShares);
        }

        TBSState memory $ = _state();
        uint256 feeBps = exitFeeBps();
        uint256 shareFeesTaken;
        (shareFeesTaken, assets, liabilities) = _previewExitWithShares($, shares, feeBps);
        if (shareFeesTaken > 0) {
            emit InKindFees(FeeType.EXIT_FEE, feeBps, shareFeesTaken);
        }

        _exit($, msg.sender, receiver, sharesOwner, shares, assets, liabilities);
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function burn(uint256 amount) external virtual override {
        _burn(msg.sender, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       EXTERNAL VIEWS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function availableSharesCapacity() public view override returns (uint256 shares) {
        return TBSLib.availableSharesCapacity(totalSupply(), maxTotalSupply());
    }

    /// @inheritdoc IOrigamiTokenizedBalanceSheetVault
    function matchToken(address tokenAddress)
        public
        view
        virtual
        override
        returns (AssetOrLiability kind, uint256 index)
    {
        return TBSLib.matchToken(tokenAddress, assetTokens(), liabilityTokens());
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EXTERNAL ERC165                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        pure
        virtual
        override(IERC165, OrigamiTeleportableToken)
        returns (bool)
    {
        return OrigamiTeleportableToken.supportsInterface(interfaceId)
            || interfaceId == type(IOrigamiTokenizedBalanceSheetVault).interfaceId
            || interfaceId == type(ITokenizedBalanceSheetVault).interfaceId;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*         IMPLEMENTATIONS TO OVERRIDE (INTERNAL FNS)         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev A hook for joins - it must pull assets from caller and send liabilities to receiver,
    /// along with any other interactions required.
    function _joinPreMintHook(
        TBSState memory $,
        address caller,
        address receiver,
        uint256 shares,
        uint256[] memory assets,
        uint256[] memory liabilities
    ) internal virtual;

    /// @dev A hook for exits - it must send assets to receiver and pull liabilities from caller,
    /// along with any other interactions required.
    function _exitPreBurnHook(
        TBSState memory $,
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

    /// @dev What's the max amount that can be joined into the vault
    /// given a cached inputTokenBalance
    function _maxJoinWithToken(TBSState memory $, uint256 feeBps) internal view virtual returns (uint256 maxTokens) {
        if (areJoinsPaused()) return 0;

        // If the token balance of the requested token is zero then cannot join
        if ($.inputTokenBalance() == 0) return 0;

        uint256 availableShares = TBSLib.availableSharesCapacity($.totalSupply, maxTotalSupply());
        if (availableShares == type(uint256).max) return availableShares;

        return TBSLib.sharesToToken({
            // Calculating the number of shares before the fee can be rounded up
            shares: availableShares.inverseSubtractBps(feeBps, OrigamiMath.Rounding.ROUND_UP),
            tokenBalance: $.inputTokenBalance(),
            totalSupply: $.totalSupply,
            // The final max number of tokens is always rounded down
            rounding: OrigamiMath.Rounding.ROUND_DOWN
        });
    }

    /// @dev Preview a join for an amount of one of the cached inputToken
    function _previewJoinWithToken(TBSState memory $, uint256 feeBps)
        internal
        pure
        virtual
        returns (uint256 shares, uint256 shareFeesTaken, uint256[] memory assets, uint256[] memory liabilities)
    {
        // When calculating the number of shares/assets/liabilities when JOINING
        // given an input token amount:
        //   - shares:
        //       - if input token is an asset: ROUND_DOWN
        //       - if input token is a liability: ROUND_UP
        //   - assets: ROUND_UP (the assets which are pulled from the caller)
        //   - liabilities: ROUND_DOWN (liabilities sent to recipient)
        (shares, assets, liabilities) = $.convertInputTokenAmountToSharesAndTokens({
            sharesRounding: $.inputTokenKind == AssetOrLiability.ASSET
                ? OrigamiMath.Rounding.ROUND_DOWN
                : OrigamiMath.Rounding.ROUND_UP,
            assetsRounding: OrigamiMath.Rounding.ROUND_UP,
            liabilitiesRounding: OrigamiMath.Rounding.ROUND_DOWN
        });

        // Deposit fees are taken from the shares in kind
        // The `shares` the recipient gets are rounded down (ie fees rounded up), in favour of the vault
        (shares, shareFeesTaken) = shares.splitSubtractBps(feeBps, OrigamiMath.Rounding.ROUND_DOWN);
    }

    /// @dev Preview a join for an amount of shares
    function _previewJoinWithShares(TBSState memory $, uint256 shares, uint256 feeBps)
        internal
        pure
        virtual
        returns (uint256[] memory assets, uint256[] memory liabilities, uint256 shareFeesTaken)
    {
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
        (assets, liabilities) = $.proportionalTokenAmountsFromShares({
            shares: sharesBeforeFees,
            assetsRounding: OrigamiMath.Rounding.ROUND_UP,
            liabilitiesRounding: OrigamiMath.Rounding.ROUND_DOWN
        });
    }

    /// @dev join for specific assets and liabilities and mint exact shares to the receiver
    /// Implementations must implement the hook which pulls assets from caller and sends
    /// liabilities to receiver
    function _join(
        TBSState memory $,
        address caller,
        address receiver,
        uint256 shares,
        uint256[] memory assets,
        uint256[] memory liabilities
    ) internal virtual {
        if (shares == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        _joinPreMintHook($, caller, receiver, shares, assets, liabilities);

        _mint(receiver, shares);

        emit Join(caller, receiver, assets, liabilities, shares);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*        INTERNAL TOKENIZED BALANCE SHEET VAULT - EXITS      */
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/

    /// @dev What's the max amount that can be exited from the vault for
    /// a cached inputToken
    function _maxExitWithToken(TBSState memory $, address sharesOwner, uint256 feeBps)
        internal
        view
        virtual
        returns (uint256 maxTokens)
    {
        if (areExitsPaused()) return 0;

        // If the token balance of the requested token is zero then cannot join
        uint256 _inputTokenBalance = $.inputTokenBalance();
        if (_inputTokenBalance == 0) return 0;

        // Special case for address(0), unlimited
        if (sharesOwner == address(0)) return type(uint256).max;

        uint256 shares = balanceOf(sharesOwner);

        // The max number of tokens is always rounded down
        (shares,) = shares.splitSubtractBps(feeBps, OrigamiMath.Rounding.ROUND_DOWN);

        uint256 maxFromShares = TBSLib.sharesToToken({
            shares: shares,
            tokenBalance: $.inputTokenBalance(),
            totalSupply: $.totalSupply,
            // The final max number of tokens is always rounded down
            rounding: OrigamiMath.Rounding.ROUND_DOWN
        });

        // Return the minimum of the available balance of the requested token in the balance sheet
        // and the derived amount from the available shares
        return maxFromShares < _inputTokenBalance ? maxFromShares : _inputTokenBalance;
    }

    /// @dev Preview an exit for an amount of one of the asset/liability tokens specified in the state cache
    function _previewExitWithToken(TBSState memory $, uint256 feeBps)
        internal
        pure
        virtual
        returns (uint256 shares, uint256 shareFeesTaken, uint256[] memory assets, uint256[] memory liabilities)
    {
        // When calculating the number of shares/assets/liabilities when EXITING
        // given an input token amount:
        //   - shares:
        //       - if input token is an asset: ROUND_UP
        //       - if input token is a liability: ROUND_DOWN
        //   - assets: ROUND_DOWN (the assets which are sent to the recipient)
        //   - liabilities: ROUND_UP (liabilities pulled from the recipient)
        uint256 sharesAfterFees;
        (sharesAfterFees, assets, liabilities) = $.convertInputTokenAmountToSharesAndTokens({
            sharesRounding: $.inputTokenKind == AssetOrLiability.ASSET
                ? OrigamiMath.Rounding.ROUND_UP
                : OrigamiMath.Rounding.ROUND_DOWN,
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
    function _maxExitWithShares(address sharesOwner) internal view virtual returns (uint256 maxShares) {
        if (areExitsPaused()) return 0;
        return sharesOwner == address(0)
            ? type(uint256).max  // Special case for address(0), unlimited exit
            : balanceOf(sharesOwner);
    }

    /// @dev Preview an exit for an amount of shares
    function _previewExitWithShares(TBSState memory $, uint256 shares, uint256 feeBps)
        internal
        pure
        virtual
        returns (uint256 shareFeesTaken, uint256[] memory assets, uint256[] memory liabilities)
    {
        // The `shares` the user receives are rounded down in favour of the vault
        (shares, shareFeesTaken) = shares.splitSubtractBps(feeBps, OrigamiMath.Rounding.ROUND_DOWN);

        // When calculating the number of assets/liabilities when EXITING
        // given a number of shares:
        //   - assets: ROUND_DOWN (assets are sent to the recipient)
        //   - liabilities: ROUND_UP (liabilities are pulled from the caller)
        (assets, liabilities) = $.proportionalTokenAmountsFromShares({
            shares: shares,
            assetsRounding: OrigamiMath.Rounding.ROUND_DOWN,
            liabilitiesRounding: OrigamiMath.Rounding.ROUND_UP
        });
    }

    /// @dev exit for specific assets and liabilities and burn exact shares to the receiver
    /// Can be called on behalf of a sharesOwner as long as allowance has been provided.
    /// Implementations must implement the hook which pulls liabilities from caller and sends
    /// assets to receiver
    function _exit(
        TBSState memory $,
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
        _exitPreBurnHook($, caller, sharesOwner, receiver, shares, assets, liabilities);

        _burn(sharesOwner, shares);
        $.totalSupply -= shares;

        // If the vault has been fully exited, then reset the maxTotalSupply to zero, as if it were newly created.
        if ($.totalSupply == 0) _maxTotalSupply = 0;

        emit Exit(caller, receiver, sharesOwner, assets, liabilities, shares);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       POPULATE STATE                       */
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/

    /// @dev Populate the TBS state cache
    /// For use when a reference input token address/amount isn't required
    function _state() internal view virtual returns (TBSState memory $) {
        $.assetAddresses = assetTokens();
        $.liabilityAddresses = liabilityTokens();
        ($.assetBalances, $.liabilityBalances, $.balanceSheetData) = _balanceSheet();
        $.totalSupply = totalSupply();
    }

    /// @dev Fill the TBS state cache using the provided input token and amount
    function _stateForInputToken(address inputTokenAddress, uint256 inputTokenAmount)
        internal
        view
        returns (TBSState memory $)
    {
        $ = _state();
        ($.inputTokenKind, $.inputTokenIndex) =
            TBSLib.matchToken(inputTokenAddress, $.assetAddresses, $.liabilityAddresses);
        $.inputTokenAmount = $.inputTokenBalance() == 0 ? 0 : inputTokenAmount;
    }
}
