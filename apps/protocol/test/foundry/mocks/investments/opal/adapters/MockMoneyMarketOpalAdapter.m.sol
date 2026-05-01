pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    IMorphoSupplyCollateralCallback,
    IMorphoRepayCallback
} from "@morpho-org/morpho-blue/src/interfaces/IMorphoCallbacks.sol";

import { IOpalAdapter } from "contracts/interfaces/investments/opal/adapters/IOpalAdapter.sol";
import { OrigamiElevatedAccessBase } from "contracts/common/access/OrigamiElevatedAccessBase.sol";
import { OpalAdapterBase } from "contracts/investments/opal/adapters/OpalAdapterBase.sol";
import { ClonesImmutableReader } from "contracts/libraries/ClonesImmutableReader.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

contract MockMorpho {
    using SafeERC20 for IERC20Metadata;
    using OrigamiMath for uint256;

    error NotEnoughCollateral();

    IERC20Metadata public collateralToken;
    IERC20Metadata public loanToken;

    uint256 public collateralBalance;
    uint256 public debtBalance;

    // An assumption on the debtToken => collateralToken conversion
    // when checking the LTV
    // 18 decimals
    uint256 public debtToCollateralPrice;

    uint256 public constant LLTV = 0.8e18; // 80%

    constructor(address _collateralToken, address _loanToken) {
        collateralToken = IERC20Metadata(_collateralToken);
        loanToken = IERC20Metadata(_loanToken);

        debtToCollateralPrice = 10 ** (18 + collateralToken.decimals() - loanToken.decimals());
    }

    function setDebtToCollateralPrice(uint256 price) external {
        debtToCollateralPrice = price;
    }

    function supplyCollateral(uint256 assets, bytes memory callbackData) external {
        collateralBalance += assets;
        if (callbackData.length > 0) {
            IMorphoSupplyCollateralCallback(msg.sender).onMorphoSupplyCollateral(assets, callbackData);
        }
        collateralToken.safeTransferFrom(msg.sender, address(this), assets);
    }

    function withdrawCollateral(uint256 assets, address receiver) external {
        collateralBalance -= assets;
        if (currentLtv() > LLTV) revert NotEnoughCollateral();
        collateralToken.safeTransfer(receiver, assets);
    }

    function borrow(uint256 assets, address receiver) external {
        debtBalance += assets;
        if (currentLtv() > LLTV) revert NotEnoughCollateral();
        loanToken.safeTransfer(receiver, assets);
    }

    function repay(uint256 assets, bytes memory callbackData) external {
        debtBalance -= assets;
        if (callbackData.length > 0) IMorphoRepayCallback(msg.sender).onMorphoRepay(assets, callbackData);
        loanToken.safeTransferFrom(msg.sender, address(this), assets);
    }

    function currentLtv() public view returns (uint256 ltv) {
        uint256 collateral = collateralBalance;
        uint256 debtInCollateralTerms = debtBalance.mulDiv(debtToCollateralPrice, 1e18, OrigamiMath.Rounding.ROUND_UP);

        if (collateral == 0) return type(uint256).max;
        if (debtInCollateralTerms == 0) return 0;
        return debtInCollateralTerms.mulDiv(1e18, collateral, OrigamiMath.Rounding.ROUND_UP);
    }
}

contract MockMoneyMarketOpalAdapter is OrigamiElevatedAccessBase, OpalAdapterBase {
    using SafeERC20 for IERC20Metadata;

    // Just testing that init sets the value correctly
    uint256 public override maxSafeLtv;

    MockMorpho public mockMorpho;

    /// @dev immutable arg slot positions
    /// Note The getters for the base implementation are expected to be jibberish, not necessarily address(0)
    uint256 private constant _ARGS_OFFSET_COLLATERAL_TOKEN = 0x34; // byte 52, len: 20 bytes (address)
    uint256 private constant _ARGS_OFFSET_LOAN_TOKEN = 0x48; // byte 72, len: 20 bytes (address)
    uint256 private constant _ARGS_OFFSET_GROUP_ID = 0x5c; // byte 92, len: 20 bytes (address)

    constructor(bytes32 _implTypeAndVersion) OpalAdapterBase(_implTypeAndVersion) { }

    function _adapterInit(bytes calldata data) internal virtual override {
        (address _initialOwner, uint256 _maxSafeLtv) = abi.decode(data, (address, uint256));
        _init(_initialOwner);
        maxSafeLtv = _maxSafeLtv;

        // Each instance gets their own mock morpho
        mockMorpho = new MockMorpho(address(collateralToken()), address(loanToken()));

        // Approve the supply and borrow to the Morpho singleton upfront
        collateralToken().safeApprove(address(mockMorpho), type(uint256).max);
        loanToken().safeApprove(address(mockMorpho), type(uint256).max);
    }

    /****** IMMUTABLE GETTERS ******/

    function collateralToken() public view returns (IERC20Metadata) {
        return IERC20Metadata(ClonesImmutableReader._getArgAddress(_ARGS_OFFSET_COLLATERAL_TOKEN));
    }

    function loanToken() public view returns (IERC20Metadata) {
        return IERC20Metadata(ClonesImmutableReader._getArgAddress(_ARGS_OFFSET_LOAN_TOKEN));
    }

    /// @inheritdoc IOpalAdapter
    function groupIds()
        public
        view
        override
        returns (bytes32[] memory assetGroupIds, bytes32[] memory liabilityGroupIds)
    {
        bytes32 grpId = ClonesImmutableReader._getArgBytes32(_ARGS_OFFSET_GROUP_ID);

        assetGroupIds = new bytes32[](1);
        assetGroupIds[0] = grpId;

        liabilityGroupIds = new bytes32[](1);
        liabilityGroupIds[0] = grpId;
    }

    /****** JOIN/EXIT ******/

    /// @inheritdoc IOpalAdapter
    function join(uint256[] calldata assetAmounts, uint256[] calldata liabilityAmounts, address recipient)
        external
        override
    {
        // The bundler must set approval to pull the tokens
        // The bundler is trusted to line up the assets and liabilities lists -- no need to do any extra sense checks.
        (uint256 supplyAmount, uint256 borrowAmount) = (assetAmounts[0], liabilityAmounts[0]);

        if (supplyAmount > 0) {
            collateralToken().safeTransferFrom(msg.sender, address(this), supplyAmount);
            mockMorpho.supplyCollateral(supplyAmount, "");
        }

        if (borrowAmount > 0) {
            mockMorpho.borrow(borrowAmount, recipient);
        }

        emit Join(assetAmounts, liabilityAmounts);
    }

    /// @inheritdoc IOpalAdapter
    function exit(uint256[] calldata assetAmounts, uint256[] calldata liabilityAmounts, address recipient)
        external
        override
    {
        // The bundler is trusted to line up the assets and liabilities lists -- no need to do any extra sense checks.
        (uint256 withdrawAmount, uint256 repayAmount) = (assetAmounts[0], liabilityAmounts[0]);

        if (repayAmount > 0) {
            loanToken().safeTransferFrom(msg.sender, address(this), repayAmount);
            mockMorpho.repay(liabilityAmounts[0], "");
        }

        if (withdrawAmount > 0) {
            mockMorpho.withdrawCollateral(assetAmounts[0], recipient);
        }

        // validateHealth();
        emit Exit(assetAmounts, liabilityAmounts);
    }

    /****** BUNDLER PLUGIN ACTIONS ******/

    function supplyCollateral(uint256 amount, bytes memory callbackData) external withApprovedBundler {
        mockMorpho.supplyCollateral(amount, callbackData);
    }

    function withdrawCollateral(uint256 amount, address receiver) external withApprovedBundler {
        mockMorpho.withdrawCollateral(amount, receiver);
    }

    function borrow(uint256 amount, address receiver) external withApprovedBundler {
        mockMorpho.borrow(amount, receiver);
    }

    function repay(uint256 amount, bytes memory callbackData) external withApprovedBundler {
        mockMorpho.repay(amount, callbackData);
    }

    function onMorphoSupplyCollateral(
        uint256,
        /*assets*/
        bytes calldata callbackData
    )
        external
    {
        _morphoCallback(callbackData);
    }

    function onMorphoRepay(
        uint256,
        /*assets*/
        bytes calldata callbackData
    )
        external
    {
        _morphoCallback(callbackData);
    }

    /****** VIEWS ******/

    function encodeImmutableArgs(address _asset, address _liability, bytes32 _groupId)
        external
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(
            // bundler is at position 0x00
            // description is at position 0x14
            _asset,
            _liability,
            _groupId
        );
    }

    function encodeInitArgs(address _initialOwner, uint256 _maxSafeLtv) external pure returns (bytes memory) {
        return abi.encode(_initialOwner, _maxSafeLtv);
    }

    /// @inheritdoc IOpalAdapter
    function tokens() public view override returns (address[] memory assetTokens, address[] memory liabilityTokens) {
        assetTokens = new address[](1);
        assetTokens[0] = address(collateralToken());
        liabilityTokens = new address[](1);
        liabilityTokens[0] = address(loanToken());
    }

    /// @inheritdoc IOpalAdapter
    function balanceSheet() external view override returns (uint256[] memory assets, uint256[] memory liabilities) {
        assets = new uint256[](1);
        assets[0] = collateralBalance();
        liabilities = new uint256[](1);
        liabilities[0] = debtBalance();
    }

    /// @inheritdoc IOpalAdapter
    function maxJoin() external view override returns (uint256[] memory assets, uint256[] memory liabilities) {
        // Morpho has no cap on what collateral can be supplied
        // But there is a cap on what can be borrowed, based on available
        // debt in the market.
        assets = new uint256[](1);
        assets[0] = type(uint256).max;
        liabilities = new uint256[](1);
        liabilities[0] = availableToBorrow();
    }

    /// @inheritdoc IOpalAdapter
    function maxExit() external pure override returns (uint256[] memory assets, uint256[] memory liabilities) {
        // There is no cap on exits, since there's no cap on what can be repaid
        // and supplied collateral can always be withdrawn.
        assets = new uint256[](1);
        assets[0] = type(uint256).max;
        liabilities = new uint256[](1);
        liabilities[0] = type(uint256).max;
    }

    function collateralBalance() public view returns (uint256) {
        return mockMorpho.collateralBalance();
    }

    function debtBalance() public view returns (uint256) {
        return mockMorpho.debtBalance();
    }

    function availableToBorrow() public view returns (uint256) {
        return loanToken().balanceOf(address(mockMorpho));
    }

    /// @inheritdoc IOpalAdapter
    function currentLtv() public view override returns (uint256 ltv) {
        return mockMorpho.currentLtv();
    }

    /// @inheritdoc IOpalAdapter
    function liquidationLtv() public view override returns (uint256) {
        return mockMorpho.LLTV();
    }

    /****** PRIVATE ******/

    /// @dev Triggers `_multicall` logic during a callback.
    function _morphoCallback(bytes calldata callbackData) private {
        if (msg.sender != address(mockMorpho)) revert CommonEventsAndErrors.InvalidAccess();

        // No need to approve Morpho to pull tokens because it should already be approved max.
        _reenterBundle(callbackData);
    }
}
