pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { ITokenizedBalanceSheetVault } from "contracts/interfaces/external/tokenizedBalanceSheetVault/ITokenizedBalanceSheetVault.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";

abstract contract TokenizedBalanceSheetProp is Test {
    uint256 internal _delta_;

    ITokenizedBalanceSheetVault internal _vault_;

    bool internal _vaultMayBeEmpty;
    bool internal _unlimitedAmount;

    function _assets() internal view returns (address[] memory) {
        return _vault_.assetTokens();
    }

    function _liabilities() internal view returns (address[] memory) {
        return _vault_.liabilityTokens();
    }

    // tokens
    // "MUST NOT revert."
    function prop_tokens(address caller) public {
        vm.prank(caller); _vault_.tokens();
    }

    // balanceSheet
    // "MUST NOT revert."
    function prop_balanceSheet(address caller) public {
        vm.prank(caller); _vault_.balanceSheet();
    }

    //
    // convert
    //

    // convertFromToken
    // "MUST NOT show any variations depending on the caller."
    function prop_convertFromToken(address caller1, address caller2, address token, uint256 amount) public {
        vm.prank(caller1); (uint256 shares1, uint256[] memory assets1, uint256[] memory liabilities1) = vault_convertFromToken(token, amount); // "MAY revert due to integer overflow caused by an unreasonably large input."
        vm.prank(caller2); (uint256 shares2, uint256[] memory assets2, uint256[] memory liabilities2) = vault_convertFromToken(token, amount); // "MAY revert due to integer overflow caused by an unreasonably large input."

        assertEq(shares1, shares2);

        for(uint256 i; i < assets1.length; i++){
            assertEq(assets1[i], assets2[i]);
        }

        for(uint256 i; i < liabilities1.length; i++){
            assertEq(liabilities1[i], liabilities2[i]);
        }
    }

    // convertFromShares
    // "MUST NOT show any variations depending on the caller."
    function prop_convertFromShares(address caller1, address caller2, uint256 shares) public {
        vm.prank(caller1); (uint256[] memory assets1, uint256[] memory liabilities1) = vault_convertFromShares(shares); // "MAY revert due to integer overflow caused by an unreasonably large input."
        vm.prank(caller2); (uint256[] memory assets2, uint256[] memory liabilities2) = vault_convertFromShares(shares); // "MAY revert due to integer overflow caused by an unreasonably large input."
       
        for(uint256 i; i < assets1.length; i++){
            assertEq(assets1[i], assets2[i]);
        }

        for(uint256 i; i < liabilities1.length; i++){
            assertEq(liabilities1[i], liabilities2[i]);
        }
    }

    //
    // join with token
    //

    // maxJoinWithToken
    // "MUST NOT revert."
    function prop_maxJoinWithToken(address token, address receiver) public view {
        _vault_.maxJoinWithToken(token, receiver);
    }

    // previewJoinWithToken
    // "MUST return as close to and no more than the exact amount of Vault
    // shares that would be minted in a deposit call in the same transaction.
    // I.e. deposit should return the same or more shares as previewDeposit if
    // called in the same transaction."
    function prop_previewJoinWithToken(address token, address caller, address receiver, address other, uint256 tokenAmount) public {
        vm.prank(other); (uint256 sharesPreview,,) = vault_previewJoinWithToken(token, tokenAmount); // "MAY revert due to other conditions that would also cause deposit to revert."
        vm.assume(sharesPreview > 0);
        vm.prank(caller); (uint256 sharesActual,,) = vault_joinWithToken(token, tokenAmount, receiver);
        assertApproxGeAbs(sharesActual, sharesPreview, _delta_);
    }

    // joinWithToken
    function prop_joinWithToken(address token, address caller, address receiver, uint256 tokenAmount) public {
        address[] memory assets = _assets();
        address[] memory liabilities = _liabilities();

        uint256[] memory oldBalancesAssets = new uint256[](assets.length);
        uint256[] memory oldBalancesLiabilities = new uint256[](liabilities.length);
        
        uint256 oldReceiverShare = _vault_.balanceOf(receiver);

        for (uint256 i; i < assets.length; i++) {
            oldBalancesAssets[i] = IERC20(assets[i]).balanceOf(caller);
        }

        for (uint256 i; i < liabilities.length; i++) {
            oldBalancesLiabilities[i] = IERC20(liabilities[i]).balanceOf(receiver);
        }

        (uint256 pshares,,) = _vault_.previewJoinWithToken(token, tokenAmount);
        vm.assume(pshares > 0);
        vm.prank(caller); (uint256 shares, uint256[] memory assetsJoin, uint256[] memory liabilitiesJoin) = vault_joinWithToken(token, tokenAmount, receiver);

        for (uint256 i; i < assets.length; i++) {
            uint256 bal = IERC20(assets[i]).balanceOf(caller);
            assertApproxEqAbs(bal, oldBalancesAssets[i] - assetsJoin[i], _delta_, "asset");
        }

        for (uint256 i; i < liabilities.length; i++) {
            uint256 bal = IERC20(liabilities[i]).balanceOf(receiver);
            assertApproxEqAbs(bal, oldBalancesLiabilities[i] + liabilitiesJoin[i], _delta_, "liabilities");
        }

        assertApproxEqAbs(_vault_.balanceOf(receiver), oldReceiverShare + shares, _delta_, "share");
    }

    //
    // join with shares
    //

    // maxJoinWithShares
    // "MUST NOT revert."
    function prop_maxJoinWithShares(address receiver) public view {
        _vault_.maxJoinWithShares(receiver);
    }

    // previewJoinWithShares
    // "MUST return as close to and no fewer than the exact amount of assets
    // that would be deposited in a mint call in the same transaction. I.e. mint
    // should return the same or fewer assets as previewMint if called in the
    // same transaction."
    function prop_previewJoinWithShares(address caller, address receiver, address other, uint256 shares) public {
        vm.prank(other); (uint256[] memory assets1, uint256[] memory liabilities1) = vault_previewJoinWithShares(shares);
        vm.prank(caller); (uint256[] memory assets2, uint256[] memory liabilities2) = vault_joinWithShares(shares, receiver);

        for(uint256 i; i < assets1.length; i++){
            assertApproxLeAbs(assets1[i], assets2[i], _delta_);
        }

        for(uint256 i; i < liabilities1.length; i++){
            assertApproxLeAbs(liabilities1[i], liabilities2[i], _delta_);
        }
    }

    // joinWithShares
    function prop_joinWithShares(address caller, address receiver, uint256 shares) public {
        address[] memory assets = _assets();
        address[] memory liabilities = _liabilities();

        uint256 aLength = assets.length;
        uint256 lLength = liabilities.length;
        uint256[] memory oldBalancesAssets = new uint256[](aLength);
        uint256[] memory oldBalancesLiabilities = new uint256[](lLength);

        uint256 oldReceiverShare = _vault_.balanceOf(receiver);

        for(uint8 i; i < aLength; i++)
        {
            oldBalancesAssets[i] = IERC20(assets[i]).balanceOf(caller);
        }

        for(uint8 i; i < lLength; i++)
        {
            oldBalancesLiabilities[i] = IERC20(liabilities[i]).balanceOf(receiver);
        }

        vm.prank(caller); (uint256[] memory assetAmounts, uint256[] memory liabilityAmounts) = vault_joinWithShares(shares, receiver);

        for(uint8 i; i < aLength; i++)
        {
            assertApproxEqAbs(IERC20(assets[i]).balanceOf(caller), oldBalancesAssets[i] - assetAmounts[i], _delta_, "asset");
        }

        for(uint8 i; i < lLength; i++)
        {
            assertApproxEqAbs(IERC20(liabilities[i]).balanceOf(receiver), oldBalancesLiabilities[i] + liabilityAmounts[i], _delta_, "liabilities");
        }

        uint256 newReceiverShare = _vault_.balanceOf(receiver);
        assertApproxEqAbs(newReceiverShare, oldReceiverShare + shares, _delta_, "share");
    }

    //
    // exit with token
    //

    // maxExitWithToken
    // "MUST NOT revert."
    // NOTE: some implementations failed due to arithmetic overflow
    function prop_maxExitWithToken(address token, address owner) public view {
        _vault_.maxExitWithToken(token, owner);
    }

    // previewExitWithToken
    // "MUST return as close to and no fewer than the exact amount of Vault
    // shares that would be burned in a withdraw call in the same transaction.
    // I.e. withdraw should return the same or fewer shares as previewWithdraw
    // if called in the same transaction."
    function prop_previewExitWithToken(address token, address caller, address receiver, address owner, address other, uint256 tokenAmount) public {
        vm.prank(other); (uint256 sharesPreview,,) = vault_previewExitWithToken(token, tokenAmount);
        vm.assume(sharesPreview > 0);
        vm.prank(caller); (uint256 sharesActual,,) = vault_exitWithToken(token, tokenAmount, receiver, owner);
        assertApproxLeAbs(sharesActual, sharesPreview, _delta_);
    }

    // exitWithToken
    function prop_exitWithToken(IERC20 token, bool isAsset, address caller, address receiver, address owner, uint256 tokenAmount) public {
        uint256 oldTokenBalance = isAsset ? token.balanceOf(receiver) : token.balanceOf(caller);
        uint256 oldOwnerShare = _vault_.balanceOf(owner);
        uint256 oldAllowance = _vault_.allowance(owner, caller);

        (uint256 pshares,,) = _vault_.previewExitWithToken(address(token), tokenAmount);
        vm.assume(pshares > 0);
        vm.prank(caller); (uint256 shares,,) = vault_exitWithToken(address(token), tokenAmount, receiver, owner);

        uint256 newOwnerShare = _vault_.balanceOf(owner);
        uint256 newAllowance = _vault_.allowance(owner, caller);

        assertApproxEqAbs(newOwnerShare, oldOwnerShare - shares, _delta_, "share");

        if (isAsset) {
            // Assets are sent to the receiver
            uint256 newTokenBalance = token.balanceOf(receiver);
            assertApproxEqAbs(newTokenBalance, oldTokenBalance + tokenAmount, _delta_+1, "asset");           
        } else {
            // Liabilities are pulled from the owner
            uint256 newTokenBalance = token.balanceOf(caller);
            assertApproxEqAbs(newTokenBalance, oldTokenBalance - tokenAmount, _delta_+1, "liability");
        }

        if (caller != owner && oldAllowance != type(uint).max) assertApproxEqAbs(newAllowance, oldAllowance - shares, _delta_, "allowance");

        assertTrue(caller == owner || oldAllowance != 0 || (shares == 0 && tokenAmount == 0), "access control");
    }

    //
    // exit with shares
    //

    // maxExitWithShares
    // "MUST NOT revert."
    function prop_maxExitWithShares(address owner) public view {
        _vault_.maxExitWithShares(owner);
    }

    // previewExitWithShares
    // "MUST return as close to and no more than the exact amount of assets that
    // would be withdrawn in a redeem call in the same transaction. I.e. redeem
    // should return the same or more assets as previewRedeem if called in the
    // same transaction."

    function prop_previewExitWithShares(address caller, address receiver, address owner, address other, uint256 shares) public {
        vm.prank(other); (uint256[] memory assetsPreview, uint256[] memory liabilitiesPreview) = vault_previewExitWithShares(shares);
        vm.prank(caller); (uint256[] memory assetsJoin, uint256[] memory liabilitiesJoin) = vault_exitWithShares(shares, receiver, owner);
       
       for(uint256 i; i < assetsPreview.length; i++) {
            assertApproxGeAbs(assetsJoin[i], assetsPreview[i], _delta_);
       }

       for(uint256 i; i < liabilitiesPreview.length; i++) {
            assertApproxGeAbs(liabilitiesJoin[i], liabilitiesPreview[i], _delta_);
       }
    }

    // exitWithShares
    function prop_exitWithShares(address caller, address receiver, address owner, uint256 shares) public {
        address[] memory assets = _assets();
        address[] memory liabilities = _liabilities();

        uint256 oldOwnerShare = _vault_.balanceOf(owner);

        uint256[] memory oldBalancesAssets = new uint256[](assets.length);
        uint256[] memory oldBalancesLiabilities = new uint256[](liabilities.length);

        for (uint256 i; i < assets.length; i++) {
            oldBalancesAssets[i] = IERC20(assets[i]).balanceOf(receiver);
        }

        for (uint256 i; i < liabilities.length; i++) {
            oldBalancesLiabilities[i] = IERC20(liabilities[i]).balanceOf(caller);
        }

        vm.prank(caller); (uint256[] memory assetsExit, uint256[] memory liabilitiesExit) = vault_exitWithShares(shares, receiver, owner);

        for (uint256 i; i < assets.length; i++) {
            uint256 bal = IERC20(assets[i]).balanceOf(receiver);
            assertApproxEqAbs(bal, oldBalancesAssets[i] + assetsExit[i], _delta_, "asset"); // NOTE: this may fail if the receiver is a contract in which the asset is stored
        }

        for (uint256 i; i < liabilities.length; i++) {
            uint256 bal = IERC20(liabilities[i]).balanceOf(caller);
            assertApproxEqAbs(bal, oldBalancesLiabilities[i] - liabilitiesExit[i], _delta_, "liabilities"); // NOTE: this may fail if the receiver is a contract in which the asset is stored
        }

        uint256 newOwnerShare = _vault_.balanceOf(owner);

        assertApproxEqAbs(newOwnerShare, oldOwnerShare - shares, _delta_, "share");
    }

    //
    // round trip properties
    //

    // joinWithToken(a) == input(a)
    function prop_RT_previewJoinWithToken(address token, bool isAsset, uint256 tokenIndex, uint256 tokenAmount) public view {
        (uint256 shares, uint256[] memory assetsJoin, uint256[] memory liabilitiesJoin) = vault_previewJoinWithToken(token, tokenAmount);
        vm.assume(shares > 0);

        uint256 takenAssets = isAsset ? assetsJoin[tokenIndex] : liabilitiesJoin[tokenIndex];

        assertEq(tokenAmount, takenAssets, "rounding");
    }

    // exitWithToken(a) == output(a)
    function prop_RT_previewExitWithToken(address token, bool isAsset, uint256 tokenIndex, uint256 tokenAmount) public view {
        (, uint256[] memory assetsExit, uint256[] memory liabilitiesExit) = vault_previewExitWithToken(token, tokenAmount);

        uint256 takenAssets = isAsset ? assetsExit[tokenIndex] : liabilitiesExit[tokenIndex];

        assertEq(tokenAmount, takenAssets, "rounding");
    }

    // exitWithShares(joinWithToken(a)) <= a
    function prop_RT_joinWithToken_exitWithShares(address token, address caller, uint256 tokenAmount) public {
        if (!_vaultMayBeEmpty) vm.assume(_vault_.totalSupply() > 0);
        (uint256 pshares,,) = _vault_.previewJoinWithToken(token, tokenAmount);
        vm.assume(pshares > 0);
        vm.prank(caller); (uint256 shares, uint256[] memory assetsJoin, uint256[] memory liabilitiesJoin) = vault_joinWithToken(token, tokenAmount, caller);
        vm.prank(caller); (uint256[] memory assetsExit, uint256[] memory liabilitiesExit) = vault_exitWithShares(shares, caller, caller);

        for (uint256 i; i < assetsExit.length; i++) {
            assertApproxLeAbs(assetsExit[i], assetsJoin[i], _delta_);
        }

        for (uint256 i; i < liabilitiesJoin.length; i++) {
            assertApproxLeAbs(liabilitiesJoin[i], liabilitiesExit[i], _delta_);
        }
    }

    // s = joinWithToken(a)
    // s' = exitWithToken(a)
    // s' >= s
    function prop_RT_joinWithToken_exitWithToken(address token, bool isAsset, uint256 tokenIndex, address caller, uint256 tokenAmount) public {
        if (!_vaultMayBeEmpty) vm.assume(_vault_.totalSupply() > 0);

        (uint256 shares,,) = _vault_.previewJoinWithToken(token, tokenAmount);
        vm.assume(shares > 0);
        vm.prank(caller); (uint256 sharesJoin, uint256[] memory assetsJoin, uint256[] memory liabilitiesJoin) = vault_joinWithToken(token, tokenAmount, caller);

        uint256 amount = isAsset ? assetsJoin[tokenIndex] : liabilitiesJoin[tokenIndex];
        uint256 maxExit = _vault_.maxExitWithToken(token, caller);
        (shares,,) = _vault_.previewExitWithToken(token, tokenAmount);
        vm.assume(shares > 0);
        vm.prank(caller); (uint256 sharesExit, uint256[] memory assetsExit, uint256[] memory liabilitiesExit) = vault_exitWithToken(
            token, amount < maxExit ? amount : maxExit, caller, caller
        );

        for (uint256 i; i < assetsJoin.length; i++) {
            if (sharesJoin >= sharesExit) {
                assertApproxGeAbs(assetsJoin[i], assetsExit[i], _delta_);
            }
        }

        for (uint256 i; i < liabilitiesExit.length; i++) {
            if (sharesExit >= sharesJoin) {
                assertApproxGeAbs(liabilitiesExit[i], liabilitiesJoin[i], _delta_);
            }
        }
    }

    // joinWithToken(exitWithShares(s)) <= s
    //note: here 2 have at least 2 edge case scenarios:
    //1. rounding the assets down and then passing 0 to the join, this will break the assertion but works correctly, since exit must round down.
    //2. passing liability to the join will cause the shares assertion to break since liabilities are rounded up when exiting, therefore the shares from the join are more than when exiting.
    function prop_RT_exitWithShares_joinWithToken(address token, bool isAsset, uint256 tokenIndex, address caller, uint256 shares) public {
        vm.prank(caller); (uint256[] memory assetsExit, uint256[] memory liabilitiesExit) = vault_exitWithShares(shares, caller, caller);
        if (!_vaultMayBeEmpty) vm.assume(_vault_.totalSupply() > 0);

        uint256 amount = isAsset ? assetsExit[tokenIndex] : liabilitiesExit[tokenIndex];

        (uint256[] memory assetsJoin, uint256[] memory liabilitiesJoin) = vault_previewJoinWithShares(shares);

        (uint256 pshares,,) = _vault_.previewJoinWithToken(token, amount);
        vm.assume(pshares > 0);
        vm.prank(caller); (uint256 sharesJoin,,) = vault_joinWithToken(token, amount, caller);

        if(isAsset) {
            assertApproxLeAbs(sharesJoin, shares, _delta_);
        } else {
            //note: this happens because, when liabilities are rounded up, shares also increase, point 2
            assertApproxGeAbs(sharesJoin, shares, _delta_);
        }

        for (uint256 i; i < assetsJoin.length; i++) {
            assertApproxGeAbs(assetsJoin[i], assetsExit[i], _delta_);
        }

        for (uint256 i; i < liabilitiesExit.length; i++) {
            assertApproxGeAbs(liabilitiesExit[i], liabilitiesJoin[i], _delta_);
        }
    }

    // a = exitWithShares(s)
    // a' = joinWithShares(s)
    // a' >= a
    function prop_RT_exitWithShares_joinWithShares(address caller, uint256 shares) public {
        vm.prank(caller); (uint256[] memory assetsExit, uint256[] memory liabilitiesExit) = vault_exitWithShares(shares, caller, caller);
        if (!_vaultMayBeEmpty) vm.assume(_vault_.totalSupply() > 0);
        vm.prank(caller); (uint256[] memory assetsJoin, uint256[] memory liabilitiesJoin) = vault_joinWithShares(shares, caller);

        for (uint256 i; i < assetsJoin.length; i++) {
            assertApproxGeAbs(assetsJoin[i], assetsExit[i], _delta_);
        }

        for (uint256 i; i < liabilitiesExit.length; i++) {
            assertApproxGeAbs(liabilitiesExit[i], liabilitiesJoin[i], _delta_);
        }
    }

    // exitWithToken(joinWithShares(s)) >= s
    function prop_RT_joinWithShares_exitWithToken(address token, bool isAsset, uint256 tokenIndex, address caller, uint256 shares) public {
        if (!_vaultMayBeEmpty) vm.assume(_vault_.totalSupply() > 0);
        vm.prank(caller); (uint256[] memory assetsJoin, uint256[] memory liabilitiesJoin) = vault_joinWithShares(shares, caller);
        uint256 amount = isAsset ? assetsJoin[tokenIndex] : liabilitiesJoin[tokenIndex];
        uint256 maxExit = _vault_.maxExitWithToken(token, caller);
        vm.assume(amount < maxExit); // skip if there isn't enough of this amount to exit

        (uint256 pshares,,) = _vault_.previewExitWithToken(token, amount);
        vm.assume(pshares > 0);
        vm.prank(caller);(uint256 shares2,,) = vault_exitWithToken(token, amount, caller, caller);
        assertApproxGeAbs(shares2, shares, _delta_ + 0.005e18); //note Depending on which token is passed and the ratio some roundings happen which causes join to give more tokens than exit
    }

    // a = joinWithShares(s)
    // a' = exitWithShares(s)
    // a' <= a
    function prop_RT_joinWithShares_exitWithShares(address caller, uint256 shares) public {
        if (!_vaultMayBeEmpty) vm.assume(_vault_.totalSupply() > 0);
        vm.prank(caller); (uint256[] memory assetsJoin, uint256[] memory liabilitiesJoin) = vault_joinWithShares(shares, caller);
        vm.prank(caller); (uint256[] memory assetsExit, uint256[] memory liabilitiesExit) = vault_exitWithShares(shares, caller, caller);
       
       for (uint256 i; i < assetsExit.length; i++) {
            assertApproxLeAbs(assetsExit[i], assetsJoin[i], _delta_);
        }

        for (uint256 i; i < liabilitiesJoin.length; i++) {
            assertApproxLeAbs(liabilitiesJoin[i], liabilitiesExit[i], _delta_);
        }
    }

    // joinWithShares(exitWithToken(a)) >= a
    function prop_RT_exitWithToken_joinWithShares(address token, address caller, uint256 tokenAmount) public {
        (uint256 pshares,,) = _vault_.previewExitWithToken(token, tokenAmount);
        vm.assume(pshares > 0);
        vm.prank(caller); (uint256 shares, uint256[] memory assetsExit, uint256[] memory liabilitiesExit) = vault_exitWithToken(token, tokenAmount, caller, caller);
        if (!_vaultMayBeEmpty) vm.assume(_vault_.totalSupply() > 0);

        vm.prank(caller); (uint256[] memory assetsJoin, uint256[] memory liabilitiesJoin) = vault_joinWithShares(shares, caller);

        // NB: Add 1 to the allowed delta here, because of expected rounding on exit vs join
        for (uint256 i; i < assetsExit.length; i++) {
            assertApproxLeAbs(assetsExit[i], assetsJoin[i], _delta_+1);
        }

        for (uint256 i; i < liabilitiesExit.length; i++) {
            assertApproxGeAbs(liabilitiesExit[i], liabilitiesJoin[i], _delta_+1);
        }
    }

    // s = exitWithToken(a)
    // s' = joinWithToken(a)
    // s' <= s
    function prop_RT_exitWithToken_joinWithToken(bool isAsset, address token, address caller, uint256 tokenAmount) public {
        (uint256 shares,,) = _vault_.previewExitWithToken(token, tokenAmount);
        vm.assume(shares > 0);
        vm.prank(caller); (uint256 sharesFromExit, uint256[] memory assetsExit, uint256[] memory liabilitiesExit) = vault_exitWithToken(token, tokenAmount, caller, caller);
        if (!_vaultMayBeEmpty) vm.assume(_vault_.totalSupply() > 0);
        (shares,,) = _vault_.previewJoinWithToken(token, tokenAmount);
        vm.assume(shares > 0);
        vm.prank(caller); (uint256 sharesFromJoin, uint256[] memory assetsJoin, uint256[] memory liabilitiesJoin) = vault_joinWithToken(token, tokenAmount, caller);

        if (isAsset) {
            // on exit: shares will round up for an asset input token
            // on join: shares will round down for an asset input token
            assertApproxLeAbs(sharesFromJoin, sharesFromExit, _delta_);
        } else {
            // on exit: shares will round down for a liability input token
            // on join: shares will round up for a liability input token
            assertApproxGeAbs(sharesFromJoin, sharesFromExit, _delta_);
        }

        for (uint256 i; i < assetsExit.length; i++) {
            // Because the number of shares from the join may be slightly higher than the number of shares from exit, 
            // the assets on the exit may be slightly more than on join
            assertApproxLeAbs(assetsExit[i], assetsJoin[i], _delta_ + 1);
        }

        for (uint256 i; i < liabilitiesExit.length; i++) {
            // Because the number of shares from the join may be slightly higher than the number of shares from exit, 
            // the liabilities on the exit may be slightly less than on join
            assertApproxLeAbs(liabilitiesJoin[i], liabilitiesExit[i], _delta_ + 1);
        }
    }

    struct PreviewData {
        uint256[] assetAmounts;
        uint256[] liabilityAmounts;
        uint256 shares;
    }

    function prop_RT_round_trips_tokens(
        address token, 
        uint256 amount, 
        uint256 randAssetIndex,
        uint256 randLiabilityIndex,
        address[] memory assets,
        address[] memory liabilities
    ) public view {
        PreviewData memory previewJoinTemplate;
        (previewJoinTemplate.shares, previewJoinTemplate.assetAmounts, previewJoinTemplate.liabilityAmounts) = vault_previewJoinWithToken(token, amount);

        PreviewData memory preivewData;
        preivewData.shares = previewJoinTemplate.shares;
        (preivewData.assetAmounts, preivewData.liabilityAmounts) = vault_previewJoinWithShares(previewJoinTemplate.shares);
        checkPreviewJoin(previewJoinTemplate, preivewData);

        // Pick one of the asset's at random to check
        // Small token amounts are expected to have larger differences -- it's better for the user
        // if they exit with shares.
        uint256 randAmount = previewJoinTemplate.assetAmounts[randAssetIndex];
        if (randAmount > 1e3) {
            (preivewData.shares, preivewData.assetAmounts, preivewData.liabilityAmounts) = vault_previewJoinWithToken(
                assets[randAssetIndex],
                randAmount
            );
            checkPreviewJoin(previewJoinTemplate, preivewData);
        }

        // Pick one of the liabilities's at random to check
        randAmount = previewJoinTemplate.liabilityAmounts[randLiabilityIndex];
        if (randAmount > 1e3) {
            (preivewData.shares, preivewData.assetAmounts, preivewData.liabilityAmounts) = vault_previewJoinWithToken(
                liabilities[randLiabilityIndex],
                randAmount
            );
            checkPreviewJoin(previewJoinTemplate, preivewData);
        }
    }

    function checkPreviewJoin(PreviewData memory lhs, PreviewData memory rhs) private pure {
        assertApproxEqRel(lhs.shares, rhs.shares, 0.001e18, "shares");
        checkUintList(lhs.assetAmounts, rhs.assetAmounts, "assets");
        checkUintList(lhs.liabilityAmounts, rhs.liabilityAmounts, "assets");
    }

    function checkUintList(uint256[] memory lhs, uint256[] memory rhs, string memory what) private pure {
        for (uint256 i; i < lhs.length; ++i) {
            assertApproxEqRel(lhs[i], rhs[i], 0.001e18, what);
        }
    }

    //
    // utils
    //

    function vault_convertFromToken(address token, uint256 amount) internal view returns(uint256 sharesConvert, uint256[] memory assetsConver, uint256[] memory liabilitiesConvert) {
        return _vault_.convertFromToken(token, amount);
    }

    function vault_convertFromShares(uint256 shares) internal view returns (uint256[] memory assetsConvert, uint256[] memory liabilitiesConvert) {
        return _vault_.convertFromShares(shares);
    }

    function vault_previewJoinWithToken(address token, uint256 amount) internal view returns (uint256 sharesPreview, uint256[] memory assetsPreview, uint256[] memory liabilitiesPreview) {
        return _vault_.previewJoinWithToken(token, amount);
    }

    function vault_previewJoinWithShares(uint256 shares) internal view returns (uint256[] memory assetsPreview, uint256[] memory liabilitiesPreview) {
        return _vault_.previewJoinWithShares(shares);
    }

    function vault_previewExitWithToken(address token, uint256 amount) internal view returns (uint256 sharesPreview, uint256[] memory assetsPreview, uint256[] memory liabilitiesPreview) {
        return _vault_.previewExitWithToken(token, amount);
    }

    function vault_previewExitWithShares(uint256 shares) internal view returns (uint256[] memory assetsPreview, uint256[] memory liabilitiesPreview) {
        return _vault_.previewExitWithShares(shares);
    }

    function vault_joinWithToken(address token, uint256 amount, address receiver) internal returns (uint256 sharesJoin, uint256[] memory assetsJoin, uint256[] memory liabilitiesJoin) {
        return _vault_.joinWithToken(token, amount, receiver);
    }

    function vault_joinWithShares(uint256 shares, address receiver) internal returns (uint256[] memory assetsJoin, uint256[] memory liabilitiesJoin) {
        return _vault_.joinWithShares(shares, receiver);
    }

    function vault_exitWithToken(address token, uint256 amount, address receiver, address owner) internal returns (uint256 sharesExit, uint256[] memory assetsExit, uint256[] memory liabilitiesExit) {
        return _vault_.exitWithToken(token, amount, receiver, owner);
    }

    function vault_exitWithShares(uint256 shares, address receiver, address owner) internal returns (uint256[] memory assetsExit, uint256[] memory liabilitiesExit) {
        return _vault_.exitWithShares(shares, receiver, owner);
    }

    function assertApproxGeAbs(uint256 a, uint256 b, uint256 maxDelta) internal {
        if (!(a >= b)) {
            uint256 dt = b - a;
            if (dt > maxDelta) {
                emit log                ("Error: a >=~ b not satisfied [uint]");
                emit log_named_uint     ("   Value a", a);
                emit log_named_uint     ("   Value b", b);
                emit log_named_uint     (" Max Delta", maxDelta);
                emit log_named_uint     ("     Delta", dt);
                fail();
            }
        }
    }

    function assertApproxLeAbs(uint256 a, uint256 b, uint256 maxDelta) internal {
        if (!(a <= b)) {
            uint256 dt = a - b;
            if (dt > maxDelta) {
                emit log                ("Error: a <=~ b not satisfied [uint]");
                emit log_named_uint     ("   Value a", a);
                emit log_named_uint     ("   Value b", b);
                emit log_named_uint     (" Max Delta", maxDelta);
                emit log_named_uint     ("     Delta", dt);
                fail();
            }
        }
    }
}
