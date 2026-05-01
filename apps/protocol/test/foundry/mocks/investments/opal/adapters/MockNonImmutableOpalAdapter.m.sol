pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IOpalAdapter } from "contracts/interfaces/investments/opal/adapters/IOpalAdapter.sol";
import { OrigamiElevatedAccessBase } from "contracts/common/access/OrigamiElevatedAccessBase.sol";
import { OpalAdapterBase } from "contracts/investments/opal/adapters/OpalAdapterBase.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

contract MockNonImmutableOpalAdapter is OrigamiElevatedAccessBase, OpalAdapterBase {
    using SafeERC20 for IERC20;

    address internal _asset;
    address internal _liability;

    uint256[] internal _assetAmounts;
    uint256[] internal _liabilityAmounts;

    uint256[] internal _assetJoinCaps;
    uint256[] internal _liabilityJoinCaps;
    uint256[] internal _assetExitCaps;
    uint256[] internal _liabilityExitCaps;

    error InvalidLengthInMock(uint256 i);

    constructor(bytes32 _implTypeAndVersion) OpalAdapterBase(_implTypeAndVersion) { }

    /// @inheritdoc IOpalAdapter
    function groupIds()
        public
        pure
        override
        returns (bytes32[] memory assetGroupIds, bytes32[] memory liabilityGroupIds)
    {
        bytes32 grpId = "mock-group";

        assetGroupIds = new bytes32[](1);
        assetGroupIds[0] = grpId;

        liabilityGroupIds = new bytes32[](1);
        liabilityGroupIds[0] = grpId;
    }

    function setTokens(address asset_, address liability_) external {
        _asset = asset_;
        _liability = liability_;
    }

    function _adapterInit(bytes calldata data) internal virtual override {
        (address _initialOwner, address _initialAsset, address _initialLiability) =
            abi.decode(data, (address, address, address));
        _init(_initialOwner);

        _asset = _initialAsset;
        _liability = _initialLiability;

        _assetAmounts = new uint256[](1);
        _liabilityAmounts = new uint256[](1);

        _assetJoinCaps = new uint256[](1);
        _liabilityJoinCaps = new uint256[](1);
        _assetExitCaps = new uint256[](1);
        _liabilityExitCaps = new uint256[](1);
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
        assetTokens = new address[](1);
        assetTokens[0] = _asset;

        liabilityTokens = new address[](1);
        liabilityTokens[0] = _liability;
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
    function liquidationLtv() public pure override returns (uint256) {
        return 0.95e18;
    }

    /// @inheritdoc IOpalAdapter
    function maxSafeLtv() public pure override returns (uint256) {
        return 0.9e18;
    }
}
