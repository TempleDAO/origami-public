pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IOpalAdapter } from "contracts/interfaces/investments/opal/adapters/IOpalAdapter.sol";
import { OrigamiElevatedAccessBase } from "contracts/common/access/OrigamiElevatedAccessBase.sol";
import { OpalAdapterBase } from "contracts/investments/opal/adapters/OpalAdapterBase.sol";
import { ClonesImmutableReader } from "contracts/libraries/ClonesImmutableReader.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

contract MockMultiTokenOpalAdapter is OrigamiElevatedAccessBase, OpalAdapterBase {
    using SafeERC20 for IERC20;

    uint256[] internal _assetAmounts;
    uint256[] internal _liabilityAmounts;

    uint256[] internal _assetJoinCaps;
    uint256[] internal _liabilityJoinCaps;
    uint256[] internal _assetExitCaps;
    uint256[] internal _liabilityExitCaps;

    error InvalidLengthInMock(uint256 i);

    // Just testing that init sets the value correctly
    uint256 public maxSafeLtv;

    /// @dev immutable arg slot positions
    /// Note The getters for the base implementation are expected to be jibberish, not necessarily address(0)
    uint256 private constant _ARGS_OFFSET_ASSET1 = 0x34; // byte 52, len: 20 bytes (address)
    uint256 private constant _ARGS_OFFSET_ASSET2 = 0x48; // byte 72, len: 20 bytes (address)
    uint256 private constant _ARGS_OFFSET_LIABILITY1 = 0x5c; // byte 92, len: 20 bytes (address)
    uint256 private constant _ARGS_OFFSET_LIABILITY2 = 0x70; // byte 112, len: 20 bytes (address)
    uint256 private constant _ARGS_OFFSET_GROUP_ID = 0x84; // byte 132, len: 32 bytes (bytes32)

    // Just testing what happens if the group ids are dodgy
    bool public useBadGroupIds;

    constructor(bytes32 _implTypeAndVersion) OpalAdapterBase(_implTypeAndVersion) { }

    function encodeImmutableArgs(
        address _asset1,
        address _asset2,
        address _liability1,
        address _liability2,
        bytes32 _groupId
    ) external pure returns (bytes memory) {
        return abi.encodePacked(
            // bundler is at position 0x00
            // description is at position 0x14
            _asset1,
            _asset2,
            _liability1,
            _liability2,
            _groupId
        );
    }

    function encodeInitArgs(address _initialOwner, uint256 _maxSafeLtv, bool _useBadGroupIds)
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(_initialOwner, _maxSafeLtv, _useBadGroupIds);
    }

    /// @inheritdoc IOpalAdapter
    function groupIds()
        public
        view
        override
        returns (bytes32[] memory assetGroupIds, bytes32[] memory liabilityGroupIds)
    {
        (address[] memory a, address[] memory l) = tokens();

        // So we can force OpalManager.addAdapter to fail
        if (useBadGroupIds) {
            if (a.length == 2) {
                return (new bytes32[](0), new bytes32[](0));
            } else if (a.length == 1 && l.length == 1) {
                return (new bytes32[](1), new bytes32[](0));
            }
        }

        bytes32 grpId = ClonesImmutableReader._getArgBytes32(_ARGS_OFFSET_GROUP_ID);

        assetGroupIds = new bytes32[](a.length);
        for (uint256 i; i < assetGroupIds.length; ++i) {
            assetGroupIds[i] = grpId;
        }

        liabilityGroupIds = new bytes32[](l.length);
        for (uint256 i; i < liabilityGroupIds.length; ++i) {
            liabilityGroupIds[i] = grpId;
        }
    }

    function _adapterInit(bytes calldata data) internal virtual override {
        (address _initialOwner, uint256 _maxSafeLtv, bool _useBadGroupIds) = abi.decode(data, (address, uint256, bool));
        _init(_initialOwner);
        maxSafeLtv = _maxSafeLtv;
        useBadGroupIds = _useBadGroupIds;

        (address[] memory a, address[] memory l) = tokens();
        _assetAmounts = new uint256[](a.length);
        _liabilityAmounts = new uint256[](l.length);

        _assetJoinCaps = new uint256[](a.length);
        _liabilityJoinCaps = new uint256[](l.length);
        _assetExitCaps = new uint256[](a.length);
        _liabilityExitCaps = new uint256[](l.length);
    }

    function setAmounts(uint256[] calldata assetAmounts, uint256[] calldata liabilityAmounts) external {
        if (assetAmounts.length != _assetAmounts.length) revert InvalidLengthInMock(1);
        if (liabilityAmounts.length != _liabilityAmounts.length) revert InvalidLengthInMock(2);

        _assetAmounts = assetAmounts;
        _liabilityAmounts = liabilityAmounts;
    }

    function setJoinExitCaps(
        uint256[] memory assetJoinCaps,
        uint256[] memory liabilityJoinCaps,
        uint256[] memory assetExitCaps,
        uint256[] memory liabilityExitCaps
    ) external {
        if (assetJoinCaps.length != _assetJoinCaps.length) {
            revert InvalidLengthInMock(1);
        }
        if (liabilityJoinCaps.length != _liabilityJoinCaps.length) revert InvalidLengthInMock(2);
        if (assetExitCaps.length != _assetExitCaps.length) revert InvalidLengthInMock(3);
        if (liabilityExitCaps.length != _liabilityExitCaps.length) revert InvalidLengthInMock(4);

        _assetJoinCaps = assetJoinCaps;
        _liabilityJoinCaps = liabilityJoinCaps;
        _assetExitCaps = assetExitCaps;
        _liabilityExitCaps = liabilityExitCaps;
    }

    /// @inheritdoc IOpalAdapter
    function join(uint256[] calldata assetAmounts, uint256[] calldata liabilityAmounts, address recipient)
        external
        override
    {
        (address[] memory a, address[] memory l) = tokens();
        if (a.length != assetAmounts.length) revert InvalidLengthInMock(1);
        if (l.length != liabilityAmounts.length) revert InvalidLengthInMock(2);

        for (uint256 i; i < a.length; ++i) {
            IERC20(a[i]).safeTransferFrom(msg.sender, address(this), assetAmounts[i]);
        }
        for (uint256 i; i < l.length; ++i) {
            IERC20(l[i]).safeTransfer(recipient, liabilityAmounts[i]);
        }
        emit Join(assetAmounts, liabilityAmounts);
    }

    /// @inheritdoc IOpalAdapter
    function exit(uint256[] calldata assetAmounts, uint256[] calldata liabilityAmounts, address recipient)
        external
        override
    {
        (address[] memory a, address[] memory l) = tokens();
        if (a.length != assetAmounts.length) revert InvalidLengthInMock(1);
        if (l.length != liabilityAmounts.length) revert InvalidLengthInMock(2);

        for (uint256 i; i < l.length; ++i) {
            IERC20(l[i]).safeTransferFrom(msg.sender, address(this), liabilityAmounts[i]);
        }
        for (uint256 i; i < a.length; ++i) {
            IERC20(a[i]).safeTransfer(recipient, assetAmounts[i]);
        }
        emit Exit(assetAmounts, liabilityAmounts);
    }

    /// @inheritdoc IOpalAdapter
    function tokens() public view override returns (address[] memory assetTokens, address[] memory liabilityTokens) {
        address a1 = ClonesImmutableReader._getArgAddress(_ARGS_OFFSET_ASSET1);
        address a2 = ClonesImmutableReader._getArgAddress(_ARGS_OFFSET_ASSET2);
        address l1 = ClonesImmutableReader._getArgAddress(_ARGS_OFFSET_LIABILITY1);
        address l2 = ClonesImmutableReader._getArgAddress(_ARGS_OFFSET_LIABILITY2);

        if (a2 != address(0) && a1 != address(0)) {
            assetTokens = new address[](2);
            assetTokens[0] = a1;
            assetTokens[1] = a2;
        } else if (a1 != address(0)) {
            assetTokens = new address[](1);
            assetTokens[0] = a1;
        } else {
            assetTokens = new address[](0);
        }

        if (l2 != address(0) && l1 != address(0)) {
            liabilityTokens = new address[](2);
            liabilityTokens[0] = l1;
            liabilityTokens[1] = l2;
        } else if (l1 != address(0)) {
            liabilityTokens = new address[](1);
            liabilityTokens[0] = l1;
        } else {
            liabilityTokens = new address[](0);
        }
    }

    /// @inheritdoc IOpalAdapter
    function balanceSheet() external view override returns (uint256[] memory assets, uint256[] memory liabilities) {
        assets = _assetAmounts;
        liabilities = _liabilityAmounts;
    }

    /// @inheritdoc IOpalAdapter
    function maxJoin() external view override returns (uint256[] memory assets, uint256[] memory liabilities) {
        uint256 length = _assetJoinCaps.length;
        assets = new uint256[](length);
        if (length > 0) assets[0] = _assetJoinCaps[0];
        if (length > 1) assets[1] = _assetJoinCaps[1];

        length = _liabilityJoinCaps.length;
        liabilities = new uint256[](length);
        if (length > 0) liabilities[0] = _liabilityJoinCaps[0];
        if (length > 1) liabilities[1] = _liabilityJoinCaps[1];
    }

    /// @inheritdoc IOpalAdapter
    function maxExit() external view override returns (uint256[] memory assets, uint256[] memory liabilities) {
        uint256 length = _assetExitCaps.length;
        assets = new uint256[](length);
        if (assets.length > 0) assets[0] = _assetExitCaps[0];
        if (assets.length > 1) assets[1] = _assetExitCaps[1];

        length = _liabilityExitCaps.length;
        liabilities = new uint256[](length);
        if (liabilities.length > 0) liabilities[0] = _liabilityExitCaps[0];
        if (liabilities.length > 1) liabilities[1] = _liabilityExitCaps[1];
    }

    function setMaxSafeLtv(uint256 _maxSafeLtv) external {
        maxSafeLtv = _maxSafeLtv;
    }

    /// @inheritdoc IOpalAdapter
    function currentLtv() public view override returns (uint256 ltv) {
        // Just sum up the asset balance and collateral balance
        // there's no unit conversion, but it's just a mock anyway..
        uint256 collateral;
        uint256 debt;
        for (uint256 i; i < _assetAmounts.length; ++i) {
            collateral += _assetAmounts[i];
        }
        for (uint256 i; i < _liabilityAmounts.length; ++i) {
            debt += _liabilityAmounts[i];
        }

        if (collateral == 0) return type(uint256).max;
        if (debt == 0) return 0;
        return OrigamiMath.mulDiv(debt, 1e18, collateral, OrigamiMath.Rounding.ROUND_UP);
    }

    /// @inheritdoc IOpalAdapter
    function liquidationLtv() public view override returns (uint256) {
        // Just add 10%
        return maxSafeLtv * 1.1e18 / 1e18;
    }
}
