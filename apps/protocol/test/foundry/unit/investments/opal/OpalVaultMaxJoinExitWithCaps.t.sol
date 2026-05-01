pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { OpalManager } from "contracts/investments/opal/OpalManager.sol";
import { IOpalManager } from "contracts/interfaces/investments/opal/IOpalManager.sol";
import { OpalVault } from "contracts/investments/opal/OpalVault.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { IOpalAdapter } from "contracts/interfaces/investments/opal/adapters/IOpalAdapter.sol";

import { OpalAdapterBase } from "contracts/investments/opal/adapters/OpalAdapterBase.sol";
import { OpalAdapterFactory } from "contracts/investments/opal/OpalAdapterFactory.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import {
    ITokenizedBalanceSheetVault
} from "contracts/interfaces/external/tokenizedBalanceSheetVault/ITokenizedBalanceSheetVault.sol";
import {
    OrigamiTokenizedBalanceSheetTestUtils
} from "test/foundry/unit/investments/tokenizedBalanceSheet/OrigamiTokenizedBalanceSheetTestUtils.t.sol";
import { IOrigamiTokenizedBalanceSheetVault } from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ClonesImmutableReader } from "contracts/libraries/ClonesImmutableReader.sol";

contract GroupLimit {
    mapping(uint256 => uint256) public limit;

    constructor() { }

    function setLimit(uint256 _group, uint256 _limit) external {
        limit[_group] = _limit;
    }

    function join(uint256 _group, uint256 _limit) external {
        require(limit[_group] >= _limit, "Group JOIN limit exceeded");
        limit[_group] -= _limit;
    }

    function exit(uint256 _group, uint256 _limit) external {
        require(limit[_group] >= _limit, "Group EXIT limit exceeded");
        limit[_group] -= _limit;
    }
}

contract OpalAdapterSpotAssetsWithMax is OpalAdapterBase {
    using SafeERC20 for IERC20;

    /// @dev immutable arg slot positions
    /// Note The getters for the base implementation are expected to be jibberish, not necessarily address(0)
    uint256 private constant _ARGS_OFFSET_GROUP_ID = 0x34; // start: byte 52, len: 1 byte (uint8)
    uint256 private constant _ARGS_OFFSET_GROUP_CONTRACT = 0x35; // start: byte 53, len: 20 bytes (address)
    uint256 private constant _ARGS_OFFSET_NUM_ASSETS = 0x49; // start: byte 73, len: 1 byte (uint8)
    uint256 private constant _ARGS_OFFSET_ASSETS = 0x4A; // start: byte 74, len: num * 20 bytes (address)

    /// @dev max number of assets in this adapter
    uint8 private constant MAX_ASSETS = 10;

    uint256 private _groupId;
    GroupLimit private _groupContract;

    constructor(bytes32 _implTypeAndVersion) OpalAdapterBase(_implTypeAndVersion) { }

    function _adapterInit(bytes calldata data) internal override {
        (address _initialOwner) = abi.decode(data, (address));
        _init(_initialOwner);

        _groupId = ClonesImmutableReader._getArgUint8(_ARGS_OFFSET_GROUP_ID);
        _groupContract = GroupLimit(ClonesImmutableReader._getArgAddress(_ARGS_OFFSET_GROUP_CONTRACT));
        _groupContract.setLimit(_groupId, type(uint256).max);

        _validateAssets(assets());
    }

    /****** IMMUTABLE GETTERS ******/

    function numAssets() public view returns (uint8) {
        return ClonesImmutableReader._getArgUint8(_ARGS_OFFSET_NUM_ASSETS);
    }

    function assets() public view returns (address[] memory result) {
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
            _groupContract.join(_groupId, collateralAmount);
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
            _groupContract.exit(_groupId, collateralAmount);
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
        bytes32 grpId = bytes32(_groupId);

        uint256 _numAssets = numAssets();
        assetGroupIds = new bytes32[](_numAssets);
        for (uint256 i; i < _numAssets; ++i) {
            assetGroupIds[i] = grpId;
        }

        liabilityGroupIds = new bytes32[](0);
    }

    function encodeImmutableArgs(uint256 group, address groupContract, address[] calldata _assets)
        external
        pure
        returns (bytes memory result)
    {
        _validateAssets(_assets);

        // Pack so its: [groupId (1 byte), groupContract (20 bytes), length (1 byte), address_0 (20 bytes), address_1
        // (20 bytes), ...]
        result = abi.encodePacked(uint8(group), groupContract, uint8(_assets.length));
        for (uint256 i; i < _assets.length; ++i) {
            result = bytes.concat(result, abi.encodePacked(_assets[i]));
        }
    }

    function encodeInitArgs(address _initialOwner) external pure returns (bytes memory) {
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
            assetAmounts[i] = _groupContract.limit(_groupId);
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
            assetAmounts[i] = _groupContract.limit(_groupId);
        }
        liabilityAmounts = new uint256[](0);
    }

    /// @inheritdoc IOpalAdapter
    function currentLtv() public pure override returns (uint256) {
        // Never any debt, so always return zero (even if no current asset balance)
        return 0;
    }

    /// @inheritdoc IOpalAdapter
    function maxSafeLtv() public pure override returns (uint256) {
        return type(uint256).max;
    }

    /// @inheritdoc IOpalAdapter
    function liquidationLtv() public pure override returns (uint256 ltv) {
        return type(uint256).max;
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

contract OpalVaultMaxJoinExitWithCapsTestBase is OrigamiTokenizedBalanceSheetTestUtils {
    OpalManager internal manager;
    OpalVault internal vault;
    TokenPrices internal tokenPrices;

    OpalAdapterFactory internal adapterFactory;

    OpalAdapterSpotAssetsWithMax internal adapterImpl;
    OpalAdapterSpotAssetsWithMax[] internal adapters;
    GroupLimit internal groupContract;

    uint16 internal constant PERFORMANCE_FEE = 330; // 3.3%

    IERC20 internal constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 internal constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    uint16 internal JOIN_FEE_BPS = 0;
    uint16 internal EXIT_FEE_BPS = 0;

    bytes32 internal tokenHash;

    function setUp() public virtual {
        fork("mainnet", 23_072_242);
        vm.label(address(DAI), "DAI");
        vm.label(address(USDC), "USDC");

        tokenPrices = new TokenPrices(30);

        deployVault();
        deployAdapters();

        tokenHash = vault.currentTokensHash();
    }

    function getVault() internal view override returns (IOrigamiTokenizedBalanceSheetVault) {
        return vault;
    }

    function deployAdapters() internal {
        vm.startPrank(origamiMultisig);

        // Create the factory, a Morpho OpalAdapter, and register it (allowing the manager to create new instances)
        {
            groupContract = new GroupLimit();
            adapterImpl = new OpalAdapterSpotAssetsWithMax("SPOT.ASSETS.WITH.MAX");
            adapterFactory.addImplementation(address(adapterImpl));
        }

        // Create the new adapters
        adapters = new OpalAdapterSpotAssetsWithMax[](3);
        for (uint256 i; i < adapters.length; i++) {
            bytes memory immutableArgs =
                adapterImpl.encodeImmutableArgs(i + 1, address(groupContract), mkArray(address(USDC)));

            bytes memory initArgs = adapterImpl.encodeInitArgs(origamiMultisig);
            adapters[i] = OpalAdapterSpotAssetsWithMax(
                manager.addAdapter(address(adapterImpl), "USDC", immutableArgs, initArgs)
            );
            vm.label(address(adapters[i]), "ADAPTER-SPOT-WITH-MAX");
        }

        vm.stopPrank();
    }

    function deployVault() internal {
        vault = new OpalVault(
            origamiMultisig,
            "OPAL Test Max Join/Exit",
            "OPAL-Test-Max",
            PERFORMANCE_FEE,
            feeCollector,
            address(tokenPrices)
        );
        adapterFactory = new OpalAdapterFactory(origamiMultisig);
        manager = new OpalManager(origamiMultisig, address(vault), address(adapterFactory));

        vm.startPrank(origamiMultisig);
        vault.setManager(address(manager));
        manager.setFees(JOIN_FEE_BPS, EXIT_FEE_BPS);
        vm.stopPrank();
    }

    function dealAsset(address account, uint256 amount) internal {
        deal(address(USDC), account, USDC.balanceOf(account) + amount, false);
    }

    function seedDeposit(address account, uint256 seedShares, uint256 maxSupply, uint256[] memory seedAdapterAmounts)
        internal
    {
        uint256 totalAssets = seedAdapterAmounts[0] + seedAdapterAmounts[1] + seedAdapterAmounts[2];
        uint256[] memory assetAmounts = mkArray(totalAssets);
        uint256[] memory liabilityAmounts = new uint256[](0);

        vm.startPrank(account);
        dealAsset(account, assetAmounts[0]);
        USDC.approve(address(vault), assetAmounts[0]);

        IOpalManager.AssetsAndLiabilities[] memory perAdapterBS = new IOpalManager.AssetsAndLiabilities[](3);
        (perAdapterBS[0].assets, perAdapterBS[0].liabilities) = (mkArray(seedAdapterAmounts[0]), new uint256[](0));
        (perAdapterBS[1].assets, perAdapterBS[1].liabilities) = (mkArray(seedAdapterAmounts[1]), new uint256[](0));
        (perAdapterBS[2].assets, perAdapterBS[2].liabilities) = (mkArray(seedAdapterAmounts[2]), new uint256[](0));

        vault.seed(assetAmounts, liabilityAmounts, seedShares, account, maxSupply, abi.encode(perAdapterBS));
        vm.stopPrank();
    }

    function joinWithToken(address account, IERC20 token, uint256 tokenAmount, address receiver)
        internal
        returns (uint256 shares, uint256[] memory assets, uint256[] memory liabilities)
    {
        uint256 prevShares = vault.balanceOf(receiver);
        (uint256 previewShares, uint256[] memory previewAssets, uint256[] memory previewLiabilities) =
            vault.previewJoinWithToken(address(token), tokenAmount);

        // Check that the input token amount matches the result
        _checkInputTokenAmount(token, tokenAmount, previewAssets, previewLiabilities);

        if (previewShares > 0) {
            vm.startPrank(account);
            dealAsset(account, previewAssets[0]);
            USDC.approve(address(vault), previewAssets[0]);

            {
                (uint256 sharesNoFees,,) = vault.convertFromToken(address(token), tokenAmount);
                uint256 expectedFeeAmount = sharesNoFees > previewShares ? sharesNoFees - previewShares : 0;
                bool isAsset = address(token) == address(USDC);
                assertEq(
                    expectedFeeAmount,
                    sharesNoFees
                        - OrigamiMath.mulDiv(
                            sharesNoFees,
                            10_000 - JOIN_FEE_BPS,
                            10_000,
                            isAsset ? OrigamiMath.Rounding.ROUND_DOWN : OrigamiMath.Rounding.ROUND_UP
                        ),
                    "joinWithToken::expectedShareFees"
                );
            }

            vm.expectEmit(address(vault));
            emit ITokenizedBalanceSheetVault.Join(account, receiver, previewAssets, previewLiabilities, previewShares);
            (shares, assets, liabilities) = vault.joinWithToken(address(token), tokenAmount, receiver, tokenHash);
            vm.stopPrank();

            assertEq(shares, previewShares, "joinWithToken::shares");
            assertEq(vault.balanceOf(receiver), prevShares + shares);
            expectArr(previewAssets, assets);
            expectArr(previewLiabilities, liabilities);

            // Check that the input token amount matches the result
            _checkInputTokenAmount(token, tokenAmount, assets, liabilities);
        }
    }

    function joinWithShares(address account, uint256 shares, address receiver)
        internal
        returns (uint256[] memory assets, uint256[] memory liabilities)
    {
        uint256 prevShares = vault.balanceOf(receiver);
        (uint256[] memory previewAssets, uint256[] memory previewLiabilities) = vault.previewJoinWithShares(shares);

        if (shares > 0) {
            vm.startPrank(account);
            dealAsset(account, previewAssets[0]);
            USDC.approve(address(vault), previewAssets[0]);

            vm.expectEmit(address(vault));
            emit ITokenizedBalanceSheetVault.Join(account, receiver, previewAssets, previewLiabilities, shares);
            (assets, liabilities) = vault.joinWithShares(shares, receiver, tokenHash);
            vm.stopPrank();

            assertEq(vault.balanceOf(receiver), prevShares + shares);
            expectArr(previewAssets, assets);
            expectArr(previewLiabilities, liabilities);
        }
    }

    function exitWithShares(address account, uint256 shares, address receiver)
        internal
        returns (uint256[] memory assets, uint256[] memory liabilities)
    {
        uint256 prevShares = vault.balanceOf(account);
        (uint256[] memory previewAssets, uint256[] memory previewLiabilities) = vault.previewExitWithShares(shares);

        if (shares > 0) {
            vm.startPrank(account);

            vm.expectEmit(address(vault));
            emit ITokenizedBalanceSheetVault.Exit(account, receiver, account, previewAssets, previewLiabilities, shares);
            (assets, liabilities) = vault.exitWithShares(shares, receiver, account, tokenHash);
            vm.stopPrank();

            assertEq(vault.balanceOf(account), prevShares - shares);
            expectArr(previewAssets, assets);
            expectArr(previewLiabilities, liabilities);
        }
    }

    function exitWithToken(address account, IERC20 token, uint256 tokenAmount, address receiver)
        internal
        returns (uint256 shares, uint256[] memory assets, uint256[] memory liabilities)
    {
        uint256 prevShares = vault.balanceOf(account);
        (uint256 previewShares, uint256[] memory previewAssets, uint256[] memory previewLiabilities) =
            vault.previewExitWithToken(address(token), tokenAmount);

        // Check that the input token amount matches the result
        _checkInputTokenAmount(token, tokenAmount, previewAssets, previewLiabilities);

        if (previewShares > 0) {
            vm.startPrank(account);

            vm.expectEmit(address(vault));
            emit ITokenizedBalanceSheetVault.Exit(
                account, receiver, account, previewAssets, previewLiabilities, previewShares
            );
            (shares, assets, liabilities) =
                vault.exitWithToken(address(token), tokenAmount, receiver, account, tokenHash);
            vm.stopPrank();

            assertEq(vault.balanceOf(account), prevShares - shares);
            expectArr(previewAssets, assets);
            expectArr(previewLiabilities, liabilities);
        }
    }

    function _checkInputTokenAmount(
        IERC20 token,
        uint256 tokenAmount,
        uint256[] memory assetAmounts,
        uint256[] memory /*liabilityAmounts*/
    )
        internal
        pure
    {
        if (address(token) == address(USDC)) {
            assertEq(assetAmounts[0], tokenAmount, "USDC input tokenAmount not matching derived output amount");
        } else {
            assertFalse(true, "unknown token in _checkInputTokenAmount");
        }
    }

    function test_fuzz_maxJoinWithShares(
        uint256 seedShares,
        uint256 adapterAmt1,
        uint256 adapterAmt2,
        uint256 adapterAmt3,
        uint256 limit1,
        uint256 limit2,
        uint256 limit3
    ) public {
        seedShares = bound(seedShares, 1, 100e18);
        adapterAmt1 = bound(adapterAmt1, 0, 100e18);
        adapterAmt2 = bound(adapterAmt2, 0, 100e18);
        adapterAmt3 = bound(adapterAmt3, 0, 100e18);
        limit1 = bound(limit1, 0, 200e18);
        limit2 = bound(limit2, 0, 200e18);
        limit3 = bound(limit3, 0, 200e18);

        seedDeposit(origamiMultisig, seedShares, type(uint256).max, mkArray(adapterAmt1, adapterAmt2, adapterAmt3));

        groupContract.setLimit(1, limit1);
        groupContract.setLimit(2, limit2);
        groupContract.setLimit(3, limit3);

        uint256 maxJoinShares = vault.maxJoinWithShares(address(this));
        joinWithShares(alice, maxJoinShares, alice);
    }

    function test_fuzz_maxJoinWithToken(
        uint256 seedShares,
        uint256 adapterAmt1,
        uint256 adapterAmt2,
        uint256 adapterAmt3,
        uint256 limit1,
        uint256 limit2,
        uint256 limit3
    ) public {
        seedShares = bound(seedShares, 1, 100e18);
        adapterAmt1 = bound(adapterAmt1, 0, 100e18);
        adapterAmt2 = bound(adapterAmt2, 0, 100e18);
        adapterAmt3 = bound(adapterAmt3, 0, 100e18);
        limit1 = bound(limit1, 0, 200e18);
        limit2 = bound(limit2, 0, 200e18);
        limit3 = bound(limit3, 0, 200e18);

        seedDeposit(origamiMultisig, seedShares, type(uint256).max, mkArray(adapterAmt1, adapterAmt2, adapterAmt3));

        groupContract.setLimit(1, limit1);
        groupContract.setLimit(2, limit2);
        groupContract.setLimit(3, limit3);

        uint256 maxJoinTokens = vault.maxJoinWithToken(address(USDC), address(this));
        joinWithToken(alice, USDC, maxJoinTokens, alice);
    }

    function test_fuzz_maxExitWithShares(
        uint256 seedShares,
        uint256 adapterAmt1,
        uint256 adapterAmt2,
        uint256 adapterAmt3,
        uint256 limit1,
        uint256 limit2,
        uint256 limit3
    ) public {
        seedShares = bound(seedShares, 100e18, 100_000e18);
        adapterAmt1 = bound(adapterAmt1, 0, 100e18);
        adapterAmt2 = bound(adapterAmt2, 0, 100e18);
        adapterAmt3 = bound(adapterAmt3, 0, 100e18);
        limit1 = bound(limit1, 0, 200e18);
        limit2 = bound(limit2, 0, 200e18);
        limit3 = bound(limit3, 0, 200e18);

        seedDeposit(origamiMultisig, seedShares, type(uint256).max, mkArray(1000e6, 1000e6, 1000e6));

        groupContract.setLimit(1, limit1);
        groupContract.setLimit(2, limit2);
        groupContract.setLimit(3, limit3);

        uint256 maxExitShares = vault.maxExitWithShares(origamiMultisig);
        exitWithShares(origamiMultisig, maxExitShares, origamiMultisig);
    }

    function test_fuzz_maxExitWithToken(
        uint256 seedShares,
        uint256 adapterAmt1,
        uint256 adapterAmt2,
        uint256 adapterAmt3,
        uint256 limit1,
        uint256 limit2,
        uint256 limit3
    ) public {
        seedShares = bound(seedShares, 100e18, 100_000e18);
        adapterAmt1 = bound(adapterAmt1, 0, 100e18);
        adapterAmt2 = bound(adapterAmt2, 0, 100e18);
        adapterAmt3 = bound(adapterAmt3, 0, 100e18);
        limit1 = bound(limit1, 0, 200e18);
        limit2 = bound(limit2, 0, 200e18);
        limit3 = bound(limit3, 0, 200e18);

        seedDeposit(origamiMultisig, seedShares, type(uint256).max, mkArray(1000e6, 1000e6, 1000e6));

        groupContract.setLimit(1, limit1);
        groupContract.setLimit(2, limit2);
        groupContract.setLimit(3, limit3);

        uint256 maxExitToken = vault.maxExitWithToken(address(USDC), origamiMultisig);
        exitWithToken(origamiMultisig, USDC, maxExitToken, origamiMultisig);
    }
}
