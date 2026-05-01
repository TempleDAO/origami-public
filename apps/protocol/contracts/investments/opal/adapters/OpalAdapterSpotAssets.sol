pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/opal/adapters/OpalAdapterSpotAssets.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

import { IOpalAdapter } from "contracts/interfaces/investments/opal/adapters/IOpalAdapter.sol";
import { IOpalAdapterSpotAssets } from "contracts/interfaces/investments/opal/adapters/IOpalAdapterSpotAssets.sol";
import { OpalAdapterBase } from "contracts/investments/opal/adapters/OpalAdapterBase.sol";
import { ClonesImmutableReader } from "contracts/libraries/ClonesImmutableReader.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/// @title Origami Portfolio of Assets and Liabilities (OPAL) Adapter - Spot Assets
/// @notice An OPAL Adapter which simply holds a balance of fixed ERC20 asset tokens (no liabilities)
contract OpalAdapterSpotAssets is IOpalAdapterSpotAssets, OpalAdapterBase {
    using SafeERC20 for IERC20;

    /// @dev immutable arg slot positions
    /// Note The getters for the base implementation are expected to be jibberish, not necessarily address(0)
    uint256 private constant _ARGS_OFFSET_NUM_ASSETS = 0x34; // start: byte 52, len: 1 byte (uint8)
    uint256 private constant _ARGS_OFFSET_ASSETS = 0x35; // start: byte 53, len: num * 20 bytes (address)

    /// @dev max number of assets in this adapter
    uint8 private constant MAX_ASSETS = 10;

    constructor(bytes32 _implTypeAndVersion) OpalAdapterBase(_implTypeAndVersion) { }

    /// @inheritdoc OpalAdapterBase
    function _adapterInit(bytes calldata data) internal override {
        (address _initialOwner) = abi.decode(data, (address));
        _init(_initialOwner);

        _validateAssets(assets());
    }

    /****** IMMUTABLE GETTERS ******/

    /// @inheritdoc IOpalAdapterSpotAssets
    function numAssets() public view override returns (uint8) {
        return ClonesImmutableReader._getArgUint8(_ARGS_OFFSET_NUM_ASSETS);
    }

    /// @inheritdoc IOpalAdapterSpotAssets
    function assets() public view override returns (address[] memory result) {
        uint8 _numAssets = numAssets();
        result = new address[](_numAssets);
        for (uint256 i; i < _numAssets; ++i) {
            // Each address in the array is 20 bytes (0x14)
            result[i] = ClonesImmutableReader._getArgAddress(_ARGS_OFFSET_ASSETS + i * 0x14);
        }
    }

    /****** JOIN/EXIT ******/

    /// @inheritdoc IOpalAdapter
    function join(
        uint256[] calldata assetAmounts,
        uint256[] calldata liabilityAmounts,
        address /*receiver*/
    )
        external
        override
        withApprovedBundler
    {
        address[] memory _assets = assets();
        if (assetAmounts.length != _assets.length || liabilityAmounts.length != 0) {
            revert CommonEventsAndErrors.InvalidLength();
        }

        uint256 collateralAmount;
        uint256 totalCollateral;
        for (uint256 i; i < assetAmounts.length; ++i) {
            collateralAmount = assetAmounts[i];
            if (collateralAmount > 0) {
                IERC20(_assets[i]).safeTransferFrom(msg.sender, address(this), collateralAmount);
            }

            // Only being used to check its non-zero, dont care about token decimals.
            totalCollateral += collateralAmount;
        }

        if (totalCollateral > 0) {
            emit Join(assetAmounts, liabilityAmounts);
        }
    }

    /// @inheritdoc IOpalAdapter
    function exit(uint256[] calldata assetAmounts, uint256[] calldata liabilityAmounts, address receiver)
        external
        override
        withApprovedBundler
    {
        address[] memory _assets = assets();
        if (assetAmounts.length != _assets.length || liabilityAmounts.length != 0) {
            revert CommonEventsAndErrors.InvalidLength();
        }

        uint256 collateralAmount;
        uint256 totalCollateral;
        for (uint256 i; i < assetAmounts.length; ++i) {
            collateralAmount = assetAmounts[i];
            if (collateralAmount > 0) {
                IERC20(_assets[i]).safeTransfer(receiver, collateralAmount);
            }

            // Only being used to check its non-zero, dont care about token decimals.
            totalCollateral += collateralAmount;
        }

        if (totalCollateral > 0) {
            emit Exit(assetAmounts, liabilityAmounts);
        }
    }

    /****** VIEWS ******/

    /// @inheritdoc IOpalAdapter
    function groupIds()
        public
        view
        override
        returns (bytes32[] memory assetGroupIds, bytes32[] memory liabilityGroupIds)
    {
        // Simply use this address, such that each instance has a separate cap
        bytes32 grpId = bytes32(uint256(uint160(address(this))));

        uint256 _numAssets = numAssets();
        assetGroupIds = new bytes32[](_numAssets);
        for (uint256 i; i < _numAssets; ++i) {
            assetGroupIds[i] = grpId;
        }

        liabilityGroupIds = new bytes32[](0);
    }

    /// @inheritdoc IOpalAdapterSpotAssets
    function encodeImmutableArgs(address[] calldata _assets) external pure override returns (bytes memory result) {
        _validateAssets(_assets);

        // Pack so its: [length (1 byte), address_0 (20 bytes), address_1 (20 bytes), ...]
        result = abi.encodePacked(uint8(_assets.length));
        for (uint256 i; i < _assets.length; ++i) {
            result = bytes.concat(result, abi.encodePacked(_assets[i]));
        }
    }

    /// @inheritdoc IOpalAdapterSpotAssets
    function encodeInitArgs(address _initialOwner) external pure override returns (bytes memory) {
        return abi.encode(_initialOwner);
    }

    /// @inheritdoc IOpalAdapter
    function tokens() external view override returns (address[] memory assetTokens, address[] memory liabilityTokens) {
        assetTokens = assets();
        liabilityTokens = new address[](0);
    }

    /// @inheritdoc IOpalAdapter
    function balanceSheet()
        external
        view
        override
        returns (uint256[] memory assetAmounts, uint256[] memory liabilityAmounts)
    {
        address[] memory _assets = assets();
        assetAmounts = new uint256[](_assets.length);
        for (uint256 i; i < _assets.length; ++i) {
            assetAmounts[i] = IERC20(_assets[i]).balanceOf(address(this));
        }
        liabilityAmounts = new uint256[](0);
    }

    /// @inheritdoc IOpalAdapter
    function maxJoin()
        external
        view
        override
        returns (uint256[] memory assetAmounts, uint256[] memory liabilityAmounts)
    {
        assetAmounts = new uint256[](numAssets());
        for (uint256 i; i < assetAmounts.length; ++i) {
            assetAmounts[i] = type(uint256).max;
        }
        liabilityAmounts = new uint256[](0);
    }

    /// @inheritdoc IOpalAdapter
    function maxExit()
        external
        view
        override
        returns (uint256[] memory assetAmounts, uint256[] memory liabilityAmounts)
    {
        assetAmounts = new uint256[](numAssets());
        for (uint256 i; i < assetAmounts.length; ++i) {
            assetAmounts[i] = type(uint256).max;
        }
        liabilityAmounts = new uint256[](0);
    }

    /// @inheritdoc IOpalAdapter
    function currentLtv() public pure override(OpalAdapterBase, IOpalAdapter) returns (uint256) {
        // Never any debt, so always return zero (even if no current asset balance)
        return 0;
    }

    /// @inheritdoc IOpalAdapter
    function maxSafeLtv() public pure override returns (uint256) {
        return type(uint256).max;
    }

    /// @inheritdoc IOpalAdapter
    function liquidationLtv() public pure override(OpalAdapterBase, IOpalAdapter) returns (uint256 ltv) {
        return type(uint256).max;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        pure
        virtual
        override(IERC165, OpalAdapterBase)
        returns (bool)
    {
        return OpalAdapterBase.supportsInterface(interfaceId) || interfaceId == type(IOpalAdapterSpotAssets).interfaceId;
    }

    /****** PRIVATE ******/

    /// @dev Verify the assets have been set within range and aren't address(0)
    function _validateAssets(address[] memory _assets) private pure {
        if (_assets.length == 0 || _assets.length > MAX_ASSETS) revert CommonEventsAndErrors.InvalidLength();
        for (uint256 i; i < _assets.length; ++i) {
            if (_assets[i] == address(0)) revert CommonEventsAndErrors.InvalidToken(_assets[i]);
        }
    }
}
