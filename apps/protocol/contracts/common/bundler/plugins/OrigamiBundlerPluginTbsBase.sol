pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/bundler/plugins/OrigamiBundlerPluginTbsBase.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EnumerableSetLib } from "solady/utils/EnumerableSetLib.sol";
import { LibCall } from "solady/utils/LibCall.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

import { OrigamiBundlerPluginMultiAccess } from "contracts/common/bundler/plugins/OrigamiBundlerPluginMultiAccess.sol";
import {
    ITokenizedBalanceSheetVault as ITBSV
} from "contracts/interfaces/external/tokenizedBalanceSheetVault/ITokenizedBalanceSheetVault.sol";
import {
    IOrigamiBundlerPluginTbsBase
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginTbsBase.sol";

/// @title Origami Bundler - Plugin to join/exit Origami Tokenized Balance Sheet Vaults
abstract contract OrigamiBundlerPluginTbsBase is OrigamiBundlerPluginMultiAccess, IOrigamiBundlerPluginTbsBase {
    using SafeERC20 for IERC20;
    using EnumerableSetLib for EnumerableSetLib.AddressSet;

    struct VaultTrustStruct {
        /// @dev Whether the vault is trusted or not
        bool isTrusted;

        /// @dev Incremented when the vault is un-trusted, as a gas efficient way to remove all
        /// the tracked approved tokens for a vault.
        uint256 nonce;

        /// @dev Per nonce tracked approved tokens
        mapping(uint256 nonce => EnumerableSetLib.AddressSet tokens) approvedTokens;
    }

    /// @dev Track the tokens a vault has approved, so they can be revoked if the vault is set to be untrusted later.
    mapping(address vault => VaultTrustStruct vaultTrust) private _vaults;

    constructor(address _initialOwner) OrigamiBundlerPluginMultiAccess(_initialOwner) { }

    /// @inheritdoc IOrigamiBundlerPluginTbsBase
    function trustVault(address vault) external override onlyElevatedAccess {
        _vaults[vault].isTrusted = true;
        emit TrustedVaultSet(vault, true);
    }

    /// @inheritdoc IOrigamiBundlerPluginTbsBase
    function dontTrustVault(address vault, bool revokeTokenApprovals, uint256 revokeGasStipend)
        external
        override
        onlyElevatedAccess
    {
        VaultTrustStruct storage _vaultTrust = _vaults[vault];
        _vaultTrust.isTrusted = false;

        uint256 _nonce = _vaultTrust.nonce;
        if (revokeTokenApprovals) {
            EnumerableSetLib.AddressSet storage tokenSet = _vaultTrust.approvedTokens[_nonce];
            uint256 length = tokenSet.length();
            for (uint256 i; i < length; ++i) {
                // If revoke reverts (non compliant ERC20), or uses too much gas, skip silently.
                LibCall.tryCall({
                    target: tokenSet.at(i),
                    value: 0,
                    gasStipend: revokeGasStipend,
                    maxCopy: type(uint16).max,
                    data: abi.encodeWithSelector(IERC20.approve.selector, vault, 0)
                });
            }
        }

        _vaultTrust.nonce = _nonce + 1;
        emit TrustedVaultSet(vault, false);
    }

    /// @inheritdoc IOrigamiBundlerPluginTbsBase
    function revokeApprovals(address vault, address[] calldata tokens) external override onlyElevatedAccess {
        // If any of the revoke's revert, it will bubble up.
        for (uint256 i; i < tokens.length; ++i) {
            IERC20(tokens[i]).safeApprove(vault, 0);
        }
    }

    /****** VIEWS ******/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        pure
        virtual
        override(IERC165, OrigamiBundlerPluginMultiAccess)
        returns (bool)
    {
        return OrigamiBundlerPluginMultiAccess.supportsInterface(interfaceId)
            || interfaceId == type(IOrigamiBundlerPluginTbsBase).interfaceId;
    }

    /// @inheritdoc IOrigamiBundlerPluginTbsBase
    function isVaultTrusted(address vault) external view returns (bool) {
        return _vaults[vault].isTrusted;
    }

    /// @inheritdoc IOrigamiBundlerPluginTbsBase
    function getApprovedTokens(address vault) external view override returns (address[] memory) {
        VaultTrustStruct storage _vaultTrust = _vaults[vault];
        return _vaultTrust.approvedTokens[_vaultTrust.nonce].values();
    }

    /****** INTERNALS ******/

    function _prepareJoin(address vaultAddress, address inputToken) internal returns (bool matchFound) {
        VaultTrustStruct storage _vaultTrust = _vaults[vaultAddress];
        if (!_vaultTrust.isTrusted) revert InvalidVault();

        (
            address[] memory assetTokens, /*address[] memory liabilityTokens*/
        ) = ITBSV(vaultAddress).tokens();

        // Approvals can remain at max, since the vault address is trusted.
        return _maxApproveTokens(vaultAddress, _vaultTrust, assetTokens, inputToken);
    }

    function _prepareExit(address vaultAddress, address inputToken) internal returns (bool matchFound) {
        VaultTrustStruct storage _vaultTrust = _vaults[vaultAddress];
        if (!_vaultTrust.isTrusted) revert InvalidVault();

        (/*address[] memory assetTokens*/, address[] memory liabilityTokens) = ITBSV(vaultAddress).tokens();

        // Approvals can remain at max, since the vault address is trusted.
        return _maxApproveTokens(vaultAddress, _vaultTrust, liabilityTokens, inputToken);
    }

    /// @dev Set the allowance for the vault to pull each of the tokens, and return if the `inputToken` was found in the
    /// `tokens` list. Revoking approval on these vaults is not required as the vaults are trusted, even if isTrusted is
    /// set to false after the fact. A new instance of this contract can be deployed if necessary.
    function _maxApproveTokens(
        address vaultAddress,
        VaultTrustStruct storage _vaultTrust,
        address[] memory tokens,
        address inputToken
    ) private returns (bool matchFound) {
        EnumerableSetLib.AddressSet storage _approvedTokens = _vaultTrust.approvedTokens[_vaultTrust.nonce];

        uint256 length = tokens.length;
        address _token;
        for (uint256 i; i < length; ++i) {
            _token = tokens[i];
            if (_token == inputToken) matchFound = true;

            if (IERC20(_token).allowance(address(this), vaultAddress) != type(uint256).max) {
                // Track approved tokens so they can be revoked later. A set is used so duplicates aren't added
                _approvedTokens.add(_token);

                // Most ERC20's wont need re-approval if max is already granted. However there are exceptions
                // eg gOHM which still decrements the max allowance.
                IERC20(_token).forceApprove(vaultAddress, type(uint256).max);
            }
        }
    }
}
