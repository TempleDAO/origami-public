pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/bundler/plugins/OrigamiBundlerPluginTbsV2.sol)

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OrigamiBundlerPluginTbsBase } from "contracts/common/bundler/plugins/OrigamiBundlerPluginTbsBase.sol";
import { IOrigamiBundlerPluginTbsV2 } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginTbsV2.sol";
import {
    ITokenizedBalanceSheetVault as ITBSV
} from "contracts/interfaces/external/tokenizedBalanceSheetVault/ITokenizedBalanceSheetVault.sol";

/// @title Origami Bundler - Plugin to join/exit Origami Tokenized Balance Sheet Vaults (V2)
contract OrigamiBundlerPluginTbsV2 is OrigamiBundlerPluginTbsBase, IOrigamiBundlerPluginTbsV2 {
    constructor(address _initialOwner) OrigamiBundlerPluginTbsBase(_initialOwner) { }

    /****** BUNDLER PLUGIN ACTIONS ******/

    /// @inheritdoc IOrigamiBundlerPluginTbsV2
    function joinWithAssetBalance(address vaultAddress, address assetAddress, address receiver, bytes32 tokensHash)
        external
        override
        withApprovedBundler
    {
        // Ensure the input address is an asset in the TBS
        if (!_prepareJoin(vaultAddress, assetAddress)) revert NotAsset();

        uint256 amount = IERC20(assetAddress).balanceOf(address(this));
        if (amount > 0) {
            ITBSV(vaultAddress).joinWithToken(assetAddress, amount, receiver, tokensHash);
        }
    }

    /// @inheritdoc IOrigamiBundlerPluginTbsV2
    function joinWithToken(
        address vaultAddress,
        address tokenAddress,
        uint256 tokenAmount,
        address receiver,
        bytes32 tokensHash
    ) external override withApprovedBundler {
        // No need to check that the input address is an asset/liability
        // as the vault does this
        _prepareJoin(vaultAddress, address(0));

        ITBSV(vaultAddress).joinWithToken(tokenAddress, tokenAmount, receiver, tokensHash);
    }

    /// @inheritdoc IOrigamiBundlerPluginTbsV2
    function joinWithShares(address vaultAddress, uint256 shares, address receiver, bytes32 tokensHash)
        external
        override
        withApprovedBundler
    {
        // No need to check the input token for shares
        _prepareJoin(vaultAddress, address(0));

        ITBSV(vaultAddress).joinWithShares(shares, receiver, tokensHash);
    }

    /// @inheritdoc IOrigamiBundlerPluginTbsV2
    function exitWithLiabilityBalance(
        address vaultAddress,
        address liabilityAddress,
        address receiver,
        bytes32 tokensHash
    ) external override withApprovedBundler {
        // Ensure the input address is a liability in the TBS
        if (!_prepareExit(vaultAddress, liabilityAddress)) revert NotLiability();

        uint256 amount = IERC20(liabilityAddress).balanceOf(address(this));
        if (amount > 0) {
            ITBSV(vaultAddress).exitWithToken(liabilityAddress, amount, receiver, address(this), tokensHash);
        }
    }

    /// @inheritdoc IOrigamiBundlerPluginTbsV2
    function exitWithToken(
        address vaultAddress,
        address tokenAddress,
        uint256 tokenAmount,
        address receiver,
        bytes32 tokensHash
    ) external override withApprovedBundler {
        // No need to check that the input address is an asset/liability
        // as the vault does this
        _prepareExit(vaultAddress, address(0));

        ITBSV(vaultAddress).exitWithToken(tokenAddress, tokenAmount, receiver, address(this), tokensHash);
    }

    /// @inheritdoc IOrigamiBundlerPluginTbsV2
    function exitWithSharesBalance(address vaultAddress, address receiver, bytes32 tokensHash)
        external
        override
        withApprovedBundler
    {
        // No need to check the input token for shares
        _prepareExit(vaultAddress, address(0));

        ITBSV vault = ITBSV(vaultAddress);
        uint256 shares = vault.balanceOf(address(this));
        if (shares > 0) {
            vault.exitWithShares(shares, receiver, address(this), tokensHash);
        }
    }

    /// @inheritdoc IOrigamiBundlerPluginTbsV2
    function exitWithShares(address vaultAddress, uint256 shares, address receiver, bytes32 tokensHash)
        external
        override
        withApprovedBundler
    {
        // No need to check the input token for shares
        _prepareExit(vaultAddress, address(0));

        ITBSV(vaultAddress).exitWithShares(shares, receiver, address(this), tokensHash);
    }

    /****** VIEWS ******/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        pure
        virtual
        override(IERC165, OrigamiBundlerPluginTbsBase)
        returns (bool)
    {
        return OrigamiBundlerPluginTbsBase.supportsInterface(interfaceId)
            || interfaceId == type(IOrigamiBundlerPluginTbsV2).interfaceId;
    }
}
