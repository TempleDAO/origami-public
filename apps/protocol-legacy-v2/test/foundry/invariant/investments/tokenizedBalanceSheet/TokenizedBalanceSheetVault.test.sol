pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { TokenizedBalanceSheetProp } from "test/foundry/mocks/common/tokenizedBalanceSheet/TokenizedBalanceSheetProp.p.sol";
import { ITokenizedBalanceSheetVault } from "contracts/interfaces/external/tokenizedBalanceSheetVault/ITokenizedBalanceSheetVault.sol";
import { DummyMintableTokenPermissionless } from "contracts/test/common/DummyMintableTokenPermissionless.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract TokenizedBalanceSheetVaultTest is TokenizedBalanceSheetProp {
    uint256 constant N = 4;

    struct Init {
        address[N] user;
        uint256[N] share;
        uint32[N] yield;
    }

    function setUpBalances(Init memory init) internal virtual returns (address[] memory assets, address[] memory liabilities) {
        assets = _assets();
        liabilities = _liabilities();

        for (uint256 i; i < N; i++) {
            address user = init.user[i];
            vm.label(address(user), string.concat("USER-", vm.toString(i)));

            vm.assume(_isEOA(user));

            if (user == address(0)) continue;

            // First mint enough assets and liabilities for a number of shares
            // limit to uint128 to avoid PRBMath_MulDiv_Overflow's when previewing
            uint256 mintShares = _bound(init.share[i], 1, type(uint96).max);
            (
                uint256[] memory joinAssets, 
                uint256[] memory joinLiabilities
            ) = ITokenizedBalanceSheetVault(_vault_).previewJoinWithShares(mintShares);

            uint256 j;
            for (j; j < assets.length; ++j) {
                DummyMintableTokenPermissionless(assets[j]).mint(user, joinAssets[j]);
            }

            for (j = 0; j < liabilities.length; ++j) {
                DummyMintableTokenPermissionless(liabilities[j]).mint(user, joinLiabilities[j]);
            }

            // Now limit the actual shares to some reasonable amount
            init.share[i] = _bound(init.share[i], 1, type(uint96).max);
            
            _approveVaultSpend(assets, user, type(uint256).max);
            vm.prank(user); _vault_.joinWithShares(init.share[i], user);
        }

        setUpYield(init.yield);
    }

    function setUpYield(uint32[N] memory yield) internal virtual {}

    function test_tokens(Init memory init) public virtual {
        setUpBalances(init);
        address caller = address(init.user[0]);
        prop_tokens(caller);
    }

    function test_balanceSheet(Init memory init) public virtual {
        address caller = address(init.user[0]);
        prop_balanceSheet(caller);
    }

    //
    // convert
    //

    function test_convertFromToken(Init memory init, bool isAsset, uint32 tokenIndex, uint128 tokenAmount) public virtual {
        (address[] memory assets, address[] memory liabilities) = setUpBalances(init);
        (address token,) = _randomizeToken(isAsset, tokenIndex, assets, liabilities);
        
        prop_convertFromToken(init.user[0], init.user[1], token, tokenAmount);
    }

    function test_convertFromShares(Init memory init, uint128 shares) public virtual {
        setUpBalances(init);
        prop_convertFromShares(init.user[0], init.user[1], shares);
    }

    //
    // joins
    //

    function test_maxJoinWithToken(Init memory init, bool isAsset, uint32 tokenIndex) public virtual {
        (address[] memory assets, address[] memory liabilities) = setUpBalances(init);
        (address token,) = _randomizeToken(isAsset, tokenIndex, assets, liabilities);

        prop_maxJoinWithToken(token, init.user[1]);
    }

    function test_previewJoinWithToken(Init memory init, bool isAsset, uint32 tokenIndex, uint256 tokenAmount) public virtual {
        (address[] memory assets, address[] memory liabilities) = setUpBalances(init);
        (address token,) = _randomizeToken(isAsset, tokenIndex, assets, liabilities);

        tokenAmount = _bound(tokenAmount, 0, type(uint128).max);
        tokenAmount = _bound(tokenAmount, 0, _max_joinWithToken(token, init.user[0]));

        _dealTokens(assets, init.user[0], type(uint168).max);   
        _approveVaultSpend(assets, init.user[0], type(uint256).max);
        prop_previewJoinWithToken(token, init.user[0], init.user[1], init.user[2], tokenAmount);
    }

    function test_joinWithToken(Init memory init, bool isAsset, uint32 tokenIndex, uint256 tokenAmount) public virtual {
        (address[] memory assets, address[] memory liabilities) = setUpBalances(init);
        (address token,) = _randomizeToken(isAsset, tokenIndex, assets, liabilities);
        tokenAmount = _bound(tokenAmount, 0, type(uint128).max);
        tokenAmount = _bound(tokenAmount, 0, _max_joinWithToken(token, init.user[0]));

        _dealTokens(assets, init.user[0], type(uint168).max);   
        _approveVaultSpend(assets, init.user[0], type(uint256).max);
        prop_joinWithToken(token, init.user[0], init.user[1], tokenAmount);
    }

    //
    // joinWithShares
    //

    function test_maxJoinWithShares(Init memory init) public virtual {
        setUpBalances(init);
        prop_maxJoinWithShares(init.user[0]);
    }

    function test_previewJoinWithShares(Init memory init, bool isAsset, uint32 tokenIndex, uint256 shares) public virtual {
        (address[] memory assets, address[] memory liabilities) = setUpBalances(init);
        (address token,) = _randomizeToken(isAsset, tokenIndex, assets, liabilities);
        (uint256 maxJoinShares,) = _max_joinWithShares(token, init.user[0]);
        vm.assume(maxJoinShares > 0);

        shares = _bound(shares, 1, type(uint136).max);
        shares = _bound(shares, 1, maxJoinShares);

        _approveVaultSpend(assets, init.user[0], type(uint256).max);
        _dealTokens(assets, init.user[0], type(uint136).max);
        prop_previewJoinWithShares(init.user[0], init.user[1], init.user[2], shares);
    }

    function test_joinWithShares(Init memory init, bool isAsset, uint32 tokenIndex, uint256 shares) public virtual {
        (address[] memory assets, address[] memory liabilities) = setUpBalances(init);
        (address token,) = _randomizeToken(isAsset, tokenIndex, assets, liabilities);

        (uint256 maxJoinShares,) = _max_joinWithShares(token, init.user[0]);
        vm.assume(maxJoinShares > 0);
        shares = _bound(shares, 1, type(uint136).max);
        shares = _bound(shares, 1, maxJoinShares);

        _approveVaultSpend(assets, init.user[0], type(uint256).max);

        _dealTokens(assets, init.user[0], type(uint136).max);
        prop_joinWithShares(init.user[0], init.user[1], shares);
    }

    //
    // exit with token
    //

    function test_maxExitWithToken(Init memory init, bool isAsset, uint32 tokenIndex) public virtual {
        (address token,) = _randomizeToken(isAsset, tokenIndex, _assets(), _liabilities());
        prop_maxExitWithToken(token, init.user[0]);
    }

    function test_previewExitWithToken(Init memory init, bool isAsset, uint32 tokenIndex, uint256 tokenAmount) public virtual {
        (address[] memory assets, address[] memory liabilities) = setUpBalances(init);
        
        (address token,) = _randomizeToken(isAsset, tokenIndex, assets, liabilities);
        tokenIndex = _setTokenIndex(isAsset, token);

        (uint256[] memory assetsAmounts, uint256[] memory liabilitiesAmounts) = _max_exitWithToken(init.user[2]);
        uint256 amount = isAsset ? assetsAmounts[tokenIndex] : liabilitiesAmounts[tokenIndex];
        
        tokenAmount = _bound(tokenAmount, 0, _unlimitedAmount ? type(uint128).max : amount);
        _approveVaultSpend(liabilities, init.user[0], type(uint256).max);

        // This is being called from a different owner - so need to approve that spend and deal
        // the caller enough liabilities
        vm.prank(init.user[2]); _safeApprove(address(_vault_), init.user[0], type(uint256).max);
        _dealTokens(liabilities, init.user[0], type(uint128).max);

        prop_previewExitWithToken(token, init.user[0], init.user[1], init.user[2], init.user[3], tokenAmount);
    }

    function test_exitWithToken(Init memory init, bool isAsset, uint32 tokenIndex, uint256 tokenAmount) public virtual {
        (address[] memory assets, address[] memory liabilities) = setUpBalances(init);

        (address token,) = _randomizeToken(isAsset, tokenIndex, assets, liabilities);
        tokenIndex = _setTokenIndex(isAsset, token);
        (uint256[] memory assetsAmounts, uint256[] memory liabilitiesAmounts) = _max_exitWithToken(init.user[2]);
        uint256 amount = isAsset ? assetsAmounts[tokenIndex] : liabilitiesAmounts[tokenIndex];
        
        tokenAmount = _bound(tokenAmount, 0, _unlimitedAmount ? type(uint128).max : amount);
        _approveVaultSpend(liabilities, init.user[0], type(uint256).max);

        vm.prank(init.user[2]); _safeApprove(address(_vault_), init.user[0], type(uint256).max);
        _dealTokens(liabilities, init.user[0], type(uint128).max);

        prop_exitWithToken(IERC20(token), isAsset, init.user[0], init.user[1], init.user[2], tokenAmount);
    }

    function test_unsuccessful_exitWithToken(Init memory init, bool isAsset, uint32 tokenIndex, uint256 tokenAmount) public virtual {
        (address[] memory assets, address[] memory liabilities) = setUpBalances(init);

        (address token,) = _randomizeToken(isAsset, tokenIndex, assets, liabilities);
        tokenIndex = _setTokenIndex(isAsset, token);

        (uint256[] memory assetsAmounts, uint256[] memory liabilitiesAmounts) = _max_exitWithToken(init.user[2]);
        uint256 amount = isAsset ? assetsAmounts[tokenIndex] : liabilitiesAmounts[tokenIndex];
        tokenAmount = _bound(tokenAmount, 0, _unlimitedAmount ? type(uint128).max : amount);

        vm.assume(init.user[0] != init.user[2]);

        _approveVaultSpend(liabilities, init.user[0], amount); // 
        vm.prank(init.user[2]); _safeApprove(address(_vault_), init.user[0], 0);

        vm.prank(init.user[0]);
        (uint256 shares,,) = _vault_.previewExitWithToken(token, tokenAmount);
        vm.assume(shares > 0);
        if (tokenAmount > 0) vm.expectRevert("ERC20: insufficient allowance");
        _vault_.exitWithToken(token, tokenAmount, init.user[1], init.user[2]);
    }

    //
    // exitWithShares
    //

    function test_maxExitWithShares(Init memory init) public virtual {
        setUpBalances(init);
        prop_maxExitWithShares(init.user[0]);
    }

    function test_previewExitWithShares(Init memory init, uint256 shares) public virtual {
        (, address[] memory liabilities) = setUpBalances(init);
        uint256 maxShares = _max_exitWithShares(init.user[2]);
        vm.assume(maxShares > 0);

        shares = _bound(shares, 1, type(uint136).max);
        shares = _bound(shares, 1, maxShares);
        vm.prank(init.user[2]); _safeApprove(address(_vault_), init.user[0], type(uint256).max);
        _approveVaultSpend(liabilities, init.user[0], type(uint256).max);

        // This is being called from a different owner - so need to approve that spend and deal
        // the caller enough liabilities
        vm.prank(init.user[2]); _safeApprove(address(_vault_), init.user[0], type(uint256).max);
        _dealTokens(liabilities, init.user[0], type(uint128).max);

        prop_previewExitWithShares(init.user[0], init.user[1], init.user[2], init.user[3], shares);
    }

    function test_exitWithShares(Init memory init, uint256 shares) public virtual {
        (, address[] memory liabilities) = setUpBalances(init);
        uint256 maxShares = _max_exitWithShares(init.user[2]);
        vm.assume(maxShares > 0);
        
        shares = _bound(shares, 1, type(uint136).max);
        shares = _bound(shares, 1, maxShares);

        _approveVaultSpend(liabilities, init.user[0], type(uint256).max);

        // This is being called from a different owner - so need to approve that spend and deal
        // the caller enough liabilities
        vm.prank(init.user[2]); _safeApprove(address(_vault_), init.user[0], type(uint256).max);
        _dealTokens(liabilities, init.user[0], type(uint128).max);
        
        prop_exitWithShares(init.user[0], init.user[1], init.user[2], shares);
    }

    //
    // round trip tests
    //

    function test_RT_previewJoinWithToken_exactInput(Init memory init, bool isAsset, uint32 tokenIndex, uint256 tokenAmount) public virtual {
        tokenAmount = _bound(tokenAmount, 0, type(uint128).max);
        (address[] memory assets, address[] memory liabilities) = setUpBalances(init);

        (address token,) = _randomizeToken(isAsset, tokenIndex, assets, liabilities);
        tokenIndex = _setTokenIndex(isAsset, token);

        prop_RT_previewJoinWithToken(token, isAsset, tokenIndex, tokenAmount);
    }

    function test_RT_previewExitWithToken_exactOutput(Init memory init, bool isAsset, uint32 tokenIndex, uint256 tokenAmount) public virtual {
        tokenAmount = _bound(tokenAmount, 0, type(uint128).max);
        (address[] memory assets, address[] memory liabilities) = setUpBalances(init);

        (address token,) = _randomizeToken(isAsset, tokenIndex, assets, liabilities);
        tokenIndex = _setTokenIndex(isAsset, token);

        prop_RT_previewExitWithToken(token, isAsset, tokenIndex, tokenAmount);
    }

    function test_RT_joinWithToken_exitWithShares(Init memory init, bool isAsset, uint32 tokenIndex, uint256 tokenAmount) public virtual {
        (address[] memory assets, address[] memory liabilities) = setUpBalances(init);
        (address token,) = _randomizeToken(isAsset, tokenIndex, assets, liabilities);
        tokenAmount = _bound(tokenAmount, 0, type(uint128).max);
        tokenAmount = _bound(tokenAmount, 0, _max_joinWithToken(token, init.user[0]));
        
        _approveVaultSpend(assets, init.user[0], type(uint256).max);
        _approveVaultSpend(liabilities, init.user[0], type(uint256).max);

        _dealTokens(assets, init.user[0], type(uint168).max);
        _dealTokens(liabilities, init.user[0], type(uint168).max);

        prop_RT_joinWithToken_exitWithShares(token, init.user[0], tokenAmount);
    }

    function test_RT_joinWithToken_exitWithToken(Init memory init, bool isAsset, uint32 tokenIndex, uint256 tokenAmount) public virtual {
        (address[] memory assets, address[] memory liabilities) = setUpBalances(init);

        _vault_.balanceSheet();
        _vault_.totalSupply();

        (address token,) = _randomizeToken(isAsset, tokenIndex, assets, liabilities);
        tokenIndex = _setTokenIndex(isAsset, token);
        
        tokenAmount = _bound(tokenAmount, 0, type(uint128).max);
        tokenAmount = _bound(tokenAmount, 0, _max_joinWithToken(token, init.user[0]));
        
        _approveVaultSpend(assets, init.user[0], type(uint256).max);
        _approveVaultSpend(liabilities, init.user[0], type(uint256).max);

        _dealTokens(assets, init.user[0], type(uint168).max);
        _dealTokens(liabilities, init.user[0], type(uint168).max);

        prop_RT_joinWithToken_exitWithToken(token, isAsset, tokenIndex, init.user[0], tokenAmount);
    }

    function test_RT_exitWithShares_joinWithToken(Init memory init, bool isAsset, uint32 tokenIndex, uint256 shares) public virtual {
        (address[] memory assets, address[] memory liabilities) = setUpBalances(init);

        (address token,) = _randomizeToken(isAsset, tokenIndex, assets, liabilities);
        tokenIndex = _setTokenIndex(isAsset, token);

        uint256 maxShares = _max_exitWithShares(init.user[0]);
        vm.assume(maxShares > 0);

        shares = _bound(shares, 1, type(uint136).max);
        shares = _bound(shares, 1, maxShares);
        
        _approveVaultSpend(assets, init.user[0], type(uint256).max);
        _approveVaultSpend(liabilities, init.user[0], type(uint256).max);
        
        _dealTokens(assets, init.user[0], type(uint136).max);
        _dealTokens(liabilities, init.user[0], type(uint136).max);

        prop_RT_exitWithShares_joinWithToken(token, isAsset, tokenIndex, init.user[0], shares);
    }

    function test_RT_exitWithShares_joinWithShares(Init memory init, uint256 shares) public virtual {
        (address[] memory assets, address[] memory liabilities) = setUpBalances(init);

        uint256 maxShares = _max_exitWithShares(init.user[0]);
        vm.assume(maxShares > 0);

        shares = _bound(shares, 1, type(uint136).max);
        shares = _bound(shares, 1, maxShares);

        _approveVaultSpend(assets, init.user[0], type(uint256).max);
        _approveVaultSpend(liabilities, init.user[0], type(uint256).max);

        _dealTokens(assets, init.user[0], type(uint136).max);
        _dealTokens(liabilities, init.user[0], type(uint136).max);

        prop_RT_exitWithShares_joinWithShares(init.user[0], shares);
    }

    function test_RT_joinWithShares_exitWithToken(Init memory init, bool isAsset, uint32 tokenIndex, uint256 shares) public virtual {
        (address[] memory assets, address[] memory liabilities) = setUpBalances(init);

        (address token,) = _randomizeToken(isAsset, tokenIndex, assets, liabilities);
        tokenIndex = _setTokenIndex(isAsset, token);

        (uint256 maxJoinShares,) = _max_joinWithShares(token, init.user[0]);
        vm.assume(maxJoinShares > 0);
        shares = _bound(shares, 1, type(uint136).max);
        shares = _bound(shares, 1, maxJoinShares);
        
        _approveVaultSpend(assets, init.user[0], type(uint256).max);
        _approveVaultSpend(liabilities, init.user[0], type(uint256).max);

        _dealTokens(assets, init.user[0], type(uint136).max);
        _dealTokens(liabilities, init.user[0], type(uint136).max);

        prop_RT_joinWithShares_exitWithToken(token, isAsset, tokenIndex, init.user[0], shares);
    }

    function test_RT_joinWithShares_exitWithShares(Init memory init,  bool isAsset, uint32 tokenIndex, uint256 shares) public virtual {
        (address[] memory assets, address[] memory liabilities) = setUpBalances(init);
        (address token,) = _randomizeToken(isAsset, tokenIndex, assets, liabilities);
        (uint256 maxJoinShares,) = _max_joinWithShares(token, init.user[0]);
        vm.assume(maxJoinShares > 0);
        shares = _bound(shares, 1, type(uint136).max);
        shares = _bound(shares, 1, maxJoinShares);

        _approveVaultSpend(assets, init.user[0], type(uint256).max);
        _approveVaultSpend(liabilities, init.user[0], type(uint256).max);

        _dealTokens(liabilities, init.user[0], type(uint136).max);
        _dealTokens(assets, init.user[0], type(uint136).max);

        prop_RT_joinWithShares_exitWithShares(init.user[0], shares);
    }

    function test_RT_exitWithToken_joinWithShares(Init memory init, bool isAsset, uint32 tokenIndex, uint256 tokenAmount) public virtual {
        (address[] memory assets, address[] memory liabilities) = setUpBalances(init);

        (address token,) = _randomizeToken(isAsset, tokenIndex, assets, liabilities);
        tokenIndex = _setTokenIndex(isAsset, token);

        (uint256[] memory assetsAmounts, uint256[] memory liabilitiesAmounts) = _max_exitWithToken(init.user[0]);
        
        uint256 amount = isAsset ? assetsAmounts[tokenIndex] : liabilitiesAmounts[tokenIndex];
        tokenAmount = _bound(tokenAmount, 0, _unlimitedAmount ? type(uint128).max : amount);
        
        _approveVaultSpend(assets, init.user[0], type(uint256).max);
        _approveVaultSpend(liabilities, init.user[0], type(uint256).max);

        _dealTokens(liabilities, init.user[0], type(uint136).max);
        _dealTokens(assets, init.user[0], type(uint136).max);

        prop_RT_exitWithToken_joinWithShares(token, init.user[0], tokenAmount);
    }

    function test_RT_withdraw_deposit(Init memory init, bool isAsset, uint32 tokenIndex, uint256 tokenAmount) public virtual {
        (address[] memory assets, address[] memory liabilities) = setUpBalances(init);

        (address token,) = _randomizeToken(isAsset, tokenIndex, assets, liabilities);
        tokenIndex = _setTokenIndex(isAsset, token);

        (uint256[] memory assetsAmounts, uint256[] memory liabilitiesAmounts) = _max_exitWithToken(init.user[0]);
        uint256 amount = isAsset ? assetsAmounts[tokenIndex] : liabilitiesAmounts[tokenIndex];

        tokenAmount = _bound(tokenAmount, 0, _unlimitedAmount ? type(uint128).max : amount);

        _approveVaultSpend(assets, init.user[0], type(uint256).max);
        _approveVaultSpend(liabilities, init.user[0], type(uint256).max);

        _dealTokens(liabilities, init.user[0], type(uint136).max);
        _dealTokens(assets, init.user[0], type(uint136).max);

        prop_RT_exitWithToken_joinWithToken(isAsset, token, init.user[0], tokenAmount);
    }

    function test_RT_round_trips_tokens(Init memory init, bool isAsset, uint32 tokenIndex, uint256 tokenAmount, uint32 tokenIndex2) public virtual {
        (address[] memory assets, address[] memory liabilities) = setUpBalances(init);

        (address token,) = _randomizeToken(isAsset, tokenIndex, assets, liabilities);

        // Because very small numbers have larger rounding/conversion effects, limit this test to 1e18 or 1e6
        uint8 decimals = DummyMintableTokenPermissionless(token).decimals();
        tokenAmount = _bound(tokenAmount, 10 ** decimals, type(uint128).max);

        (, uint256 randAssetIndex) = _randomizeToken(true, tokenIndex2, assets, liabilities);
        (, uint256 randLiabilityIndex) = _randomizeToken(false, tokenIndex2, assets, liabilities);

        prop_RT_round_trips_tokens(token, tokenAmount, randAssetIndex, randLiabilityIndex, assets, liabilities);
    }
    
    function _isContract(address account) internal view returns (bool) { return account.code.length > 0; }
    function _isEOA (address account) internal view returns (bool) { return account.code.length == 0 && account != address(0); }

    function _randomizeToken(
        bool isAsset,
        uint32 tokenIndex,
        address[] memory assets,
        address[] memory liabilities
    ) internal view virtual returns (
        address randomToken,
        uint256 randomIndex
    ) {
        randomIndex = _bound(tokenIndex, 0, isAsset ? assets.length - 1 : liabilities.length - 1);
        randomToken = isAsset ? assets[randomIndex] : liabilities[randomIndex];
    }

    function _setTokenIndex(bool isAsset, address token) internal view returns (uint32 tokenIndex) {
        ITokenizedBalanceSheetVault vault = ITokenizedBalanceSheetVault(_vault_);
        address[] memory tokens;

        if (isAsset) {
            tokens = vault.assetTokens();

            for (uint32 i; i < tokens.length; i++) {
                if (tokens[i] == token) tokenIndex = i; 
            }
        } else {
            tokens = vault.liabilityTokens();

            for (uint32 i; i < tokens.length; i++) {
                if (tokens[i] == token) tokenIndex = i; 
            }
        }
    }

    function _approveVaultSpend(address[] memory tokens, address owner, uint256 amount) internal {
        for (uint256 i; i < tokens.length; ++i) {
            vm.prank(owner); _safeApprove(tokens[i], address(_vault_), amount);
        }
    }

    function _dealTokens(address[] memory tokens, address owner, uint256 amount) internal {
        for (uint256 i; i < tokens.length; ++i) {
            DummyMintableTokenPermissionless(tokens[i]).deal(owner, amount);
        }
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        IERC20(token).approve(spender, amount);
    }

    function _max_joinWithToken(address token, address from) internal virtual returns (uint256) {
        if (_unlimitedAmount) return type(uint128).max;
        return IERC20(token).balanceOf(from);
    }

    function _max_joinWithShares(address token, address from) internal virtual returns (uint256 shares, uint256[] memory assets) {
        if (_unlimitedAmount) return (type(uint128).max, assets);

        (shares, assets,) = vault_convertFromToken(token, IERC20(token).balanceOf(from));

        return (shares, assets);
    }

    function _max_exitWithToken(address from) internal virtual returns (uint256[] memory assets, uint256[] memory liabilities) {
        if (_unlimitedAmount) return (assets, liabilities);//note: do we have to return max for the liabilities as well?
        return vault_convertFromShares(IERC20(_vault_).balanceOf(from));
    }

    function _max_exitWithShares(address from) internal virtual returns (uint256) {
        if (_unlimitedAmount) return type(uint128).max;
        return IERC20(_vault_).balanceOf(from);
    }
}