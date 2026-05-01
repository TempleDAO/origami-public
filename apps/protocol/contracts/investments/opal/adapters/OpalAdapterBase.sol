pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/opal/adapters/OpalAdapterBase.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { LibString } from "solady/utils/LibString.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

import { IOrigamiBundlerPlugin } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol";
import { IOpalAdapter } from "contracts/interfaces/investments/opal/adapters/IOpalAdapter.sol";
import { IMerklDistributor } from "contracts/interfaces/external/merkl/IMerklDistributor.sol";
import { OrigamiBundlerPluginCore } from "contracts/common/bundler/plugins/OrigamiBundlerPluginCore.sol";
import { ClonesImmutableReader } from "contracts/libraries/ClonesImmutableReader.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiElevatedAccessBase } from "contracts/common/access/OrigamiElevatedAccessBase.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";

/// @title Origami Portfolio of Assets and Liabilities (OPAL) Adapter - Base Implementation
/// @notice Core required functions for adapters to slot into the OPAL Tokenized Balance Sheet vault framework
abstract contract OpalAdapterBase is IOpalAdapter, OrigamiBundlerPluginCore, OrigamiElevatedAccessBase {
    using SafeERC20 for IERC20;
    using OrigamiMath for uint256;

    /// @inheritdoc IOpalAdapter
    bool public override isDeprecated;

    /// @notice The adapter implementation type and version as a null terminated short string
    /// @dev Format should be {TYPE_STR}.{VERSION_STARTING_AT_1}
    ///      eg "AAVE_V3.1" to represent the first version of an Aave v3 adapter
    /// If the implementation logic is updated for the same type, a new "AAVE_V3.2" would be
    /// deployed and registered in the factory.
    bytes32 private immutable _implTypeAndVersion;

    /// @dev immutable arg slot positions
    /// Note The getters for the base implementation are expected to be jibberish, not necessarily address(0)
    uint256 private constant _ARGS_OFFSET_MANAGER = 0x00; // byte 0, len: 20 bytes (address)
    uint256 private constant _ARGS_OFFSET_DESCRIPTION = 0x14; // byte 20, len: 32 bytes (bytes32 for short string)

    /// @dev Whether the clone instance has been initialized after factory creation
    /// There are no runtime checks that this is true -- it is assumed the manager
    /// will initialize prior to use.
    bool internal _initialized;

    constructor(bytes32 implTypeAndVersion_) {
        _implTypeAndVersion = implTypeAndVersion_;

        // Ensure base implementations cannot be initialized
        _initialized = true;
    }

    /****** IMMUTABLE GETTERS ******/

    /// @inheritdoc IOpalAdapter
    function manager() public view override returns (address) {
        return ClonesImmutableReader._getArgAddress(_ARGS_OFFSET_MANAGER);
    }

    /// @inheritdoc IOpalAdapter
    function implTypeAndVersion() external view override returns (string memory) {
        return LibString.fromSmallString(_implTypeAndVersion);
    }

    /// @inheritdoc IOpalAdapter
    function description() external view override returns (string memory) {
        return LibString.fromSmallString(ClonesImmutableReader._getArgBytes32(_ARGS_OFFSET_DESCRIPTION));
    }

    /****** ADMIN ******/

    /// @inheritdoc IOpalAdapter
    function initialize(bytes calldata data) external override {
        // Ensure it can only be initialized once, notmally by the bundler right after cloning
        // The base implementation cannot be initialized here
        if (_initialized) revert InitializeFailed();

        // Initialize, and ensure that the owner and bundler are set as part of this
        // (just a sanity check that it's non-zero though, cannot be a comprehensive check)
        _adapterInit(data);
        if (owner == address(0)) revert InitializeFailed();
        if (manager() == address(0)) revert InitializeFailed();

        _initialized = true;
        emit Initialized();
    }

    /// @dev Each implementation implements initialization logic to set non-immutable args
    /// from encoded data
    function _adapterInit(bytes calldata data) internal virtual;

    /// @inheritdoc IOpalAdapter
    function setDeprecated(bool value) external override onlyElevatedAccess {
        emit SetDeprecated(value);
        isDeprecated = value;
    }

    /****** BUNDLER PLUGIN ACTIONS ******/

    /// @inheritdoc IOpalAdapter
    function erc20Approve(address token, address spender, uint256 amount) external override withApprovedBundler {
        IERC20(token).forceApprove(spender, amount);
    }

    /// @inheritdoc IOpalAdapter
    function merklClaim(
        address merklRewardsDistributor,
        address[] calldata rewardTokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs,
        address recipient
    ) external override withApprovedBundler {
        // Create a users list for this address matching the length of tokens/amounts/proofs
        // No need to explicitly check tokens/amounts/proofs lengths are the same
        address[] memory users = new address[](rewardTokens.length);
        for (uint256 i; i < rewardTokens.length; ++i) {
            users[i] = address(this);
        }

        // Claim from merkl. No check required on the tokens here
        IMerklDistributor(merklRewardsDistributor).claim(users, rewardTokens, amounts, proofs);

        // Send claimed rewards to recipient
        if (recipient != address(this)) {
            uint256 amount;
            for (uint256 i; i < rewardTokens.length; ++i) {
                amount = amounts[i];
                if (amount > 0) {
                    IERC20(rewardTokens[i]).safeTransfer(recipient, amount);
                }
            }
        }
    }

    /****** VIEWS ******/

    /// @inheritdoc IOrigamiBundlerPlugin
    function isApprovedBundler(address account)
        public
        view
        override(IOrigamiBundlerPlugin, OrigamiBundlerPluginCore)
        returns (bool)
    {
        return account == manager();
    }

    /// @inheritdoc IOpalAdapter
    function currentLtv() public view virtual override returns (uint256);

    /// @inheritdoc IOpalAdapter
    function liquidationLtv() public view virtual override returns (uint256);

    /// @inheritdoc IOpalAdapter
    function healthFactor() external view override returns (uint256) {
        // NOTE: this is indicative only, it may not exactly match the underlying protocol
        // due to div before mul, rounding or how it exactly calculates the health
        return _healthFactor(currentLtv(), liquidationLtv());
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        pure
        virtual
        override(IERC165, OrigamiBundlerPluginCore)
        returns (bool)
    {
        return OrigamiBundlerPluginCore.supportsInterface(interfaceId) || interfaceId == type(IOpalAdapter).interfaceId
            || interfaceId == type(IOrigamiElevatedAccess).interfaceId;
    }

    /// @dev Calculate the LTV given debt and collateral, both represented in the same unit of account.
    /// Represented as WAD (eg 0.9e18 == 90% LTV)
    function _calculateLtv(uint256 _debtInUnitOfAcct, uint256 _collateralInUnitOfAcct)
        internal
        pure
        returns (uint256 ltv)
    {
        if (_debtInUnitOfAcct == 0) return 0;
        if (_collateralInUnitOfAcct == 0) return type(uint256).max;

        // Rounded up to be conservative.
        return _debtInUnitOfAcct.mulDiv(OrigamiMath.WAD, _collateralInUnitOfAcct, OrigamiMath.Rounding.ROUND_UP);
    }

    /// @dev Calculate the health factor given the current LTV and the liquidation LTV.
    /// HF < 1 may be up for liquidation.
    /// Represented as WAD (eg 1.1e18 == HF of 1.1)
    function _healthFactor(uint256 _currentLtv, uint256 _lltv) internal pure returns (uint256) {
        if (_currentLtv == 0) return type(uint256).max;

        // Rounded down to be conservative.
        return _lltv.mulDiv(OrigamiMath.WAD, _currentLtv, OrigamiMath.Rounding.ROUND_DOWN);
    }
}
