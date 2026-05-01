pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { CommonBase } from "forge-std/Base.sol";
import { StdUtils } from "forge-std/StdUtils.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { DummyMintableTokenPermissionless } from "contracts/test/common/DummyMintableTokenPermissionless.sol";

import { MockTokenizedBalanceSheetVaultWithFees } from "test/foundry/mocks/common/tokenizedBalanceSheet/MockTokenizedBalanceSheetVaultWithFees.m.sol";
import { MockBorrowLend } from "test/foundry/mocks/common/tokenizedBalanceSheet/MockBorrowLend.m.sol";

contract Interactor is CommonBase, StdUtils, StdCheats {
    using EnumerableSet for  EnumerableSet.AddressSet;

    event InteractorJoinToken(address token, uint256[] assets, uint256[] liabilities, uint256 shares, address receiver);
    event InteractorJoinShares(uint256[] assets, uint256[] liabilities, uint256 shares, address receiver);

    event InteractorExitToken(address token, uint256[] assets, uint256[] liabilities, uint256 shares, address receiver, address sharesOwner);
    event InteractorExitShares(uint256[] assets, uint256[] liabilities, uint256 shares, address receiver, address sharesOwner);

    MockTokenizedBalanceSheetVaultWithFees private immutable vault;
    MockBorrowLend private immutable borrowLend;

    mapping(address asset => uint256 amt) assetDeposits;
    mapping(address liability => uint256 amt) liabilitiesBorrows;
    uint256 totalShares;

    EnumerableSet.AddressSet assetsCached;
    EnumerableSet.AddressSet liabilitiesCached;

    constructor(MockTokenizedBalanceSheetVaultWithFees _vault, MockBorrowLend _borrowLend) {
        vault = _vault;
        borrowLend = _borrowLend;

        (address[] memory _assetsCached, address[] memory _liabilitiesCached) = vault.tokens();

        for (uint256 i; i < _assetsCached.length; i++){
            address _token = _assetsCached[i];

            DummyMintableTokenPermissionless(_token).deal(address(this), type(uint168).max);
            IERC20(_token).approve(address(borrowLend), type(uint168).max);
            
            assetsCached.add(_token);
        }

        for (uint256 i; i < _liabilitiesCached.length; i++){
            address _token = _liabilitiesCached[i];

            DummyMintableTokenPermissionless(_token).deal(address(this), type(uint168).max);
            IERC20(_token).approve(address(borrowLend), type(uint168).max);
            
            liabilitiesCached.add(_token);
        }
    }

    function joinToken(bool isAsset, uint8 tokenIndex, uint256 amount) external {
        address _token = _assumeValidToken(tokenIndex, isAsset);

        if(isAsset){
            uint256 balanceOfThis = IERC20(_token).balanceOf(address(this));
            amount = _bound(
                amount, 
                0, 
                balanceOfThis < 100_000e18 ? balanceOfThis : 100_000_000e18);
        } 
        else {
            (,uint256[] memory totalLiabilities) = vault.balanceSheet();
            uint8 indexOfLiability;
            for(indexOfLiability; indexOfLiability < liabilitiesCached.length(); indexOfLiability++){
                if(liabilitiesCached.at(indexOfLiability) == _token) {
                    break;
                }
            }

            amount = _bound(amount, 0, totalLiabilities[indexOfLiability]);
        }

        (
            uint256 shares, 
            uint256[] memory assetsGiven, 
            uint256[] memory liabReceived
        ) = vault.previewJoinWithToken(_token, amount);
        vm.assume(shares > 0);
        
        _doJoin(assetsGiven, liabReceived, shares);

        vault.joinWithToken(_token, amount, address(this));

        emit InteractorJoinToken(_token, assetsGiven, liabReceived, shares, address(this));
    }

    function joinShares(uint256 shares) external {
        shares = _bound(shares, 1, 100_000_000e18);

        (
            uint256[] memory assetsGiven, 
            uint256[] memory liabReceived
        ) = vault.previewJoinWithShares(shares);

        _doJoin(assetsGiven, liabReceived, shares);

        vault.joinWithShares(shares, address(this));

        emit InteractorJoinShares(assetsGiven, liabReceived, shares, address(this));
    }

    function exitToken(bool isAsset, uint8 tokenIndex, uint256 amount) external {
        address _token = _assumeValidToken(tokenIndex, isAsset);

        amount = _bound(amount, 0, vault.maxExitWithToken(_token, address(this)) / 10);

        (
            uint256 shares, 
            uint256[] memory assetsReceived, 
            uint256[] memory liabilitiesGiven
        ) = vault.previewExitWithToken(_token, amount);
        vm.assume(shares > 0);

        _doExit(assetsReceived, liabilitiesGiven, shares);

        totalShares -= shares > totalShares ? totalShares : shares;

        vault.exitWithToken(_token, amount, address(this), address(this));

        emit InteractorExitToken(_token, assetsReceived, liabilitiesGiven, shares, address(this), address(this));
    }

    function exitShares(uint256 shares) external {
        uint256 balance = vault.balanceOf(address(this));
        vm.assume(balance > 0);
        shares = _bound(shares, 1, balance);

        (
            uint256[] memory assetsReceived,
            uint256[] memory liabilitiesGiven
        ) = vault.previewExitWithShares(shares);

        _doExit(assetsReceived, liabilitiesGiven, shares);
        vault.exitWithShares(shares, address(this), address(this));

        emit InteractorExitShares(assetsReceived, liabilitiesGiven, shares, address(this), address(this));
    }

    function increaseSharePrice(uint256 asset1Amount, uint256 asset2Amount, uint256 debt1Amount, uint256 debt2Amount, address receiver) external {
        vm.assume(receiver != address(0));
        asset1Amount = _bound(asset1Amount, 0, IERC20(assetsCached.at(0)).balanceOf(address(this)) > 100_000e18 ? 100_000e18 : IERC20(assetsCached.at(0)).balanceOf(address(this)));
        asset2Amount = _bound(asset2Amount, 0, IERC20(assetsCached.at(1)).balanceOf(address(this)) > 100_000e6 ? 100_000e6 : IERC20(assetsCached.at(1)).balanceOf(address(this)));
        
        debt1Amount = _bound(debt1Amount, 0, IERC20(liabilitiesCached.at(0)).balanceOf(address(borrowLend)) > 100_000e18 ? 100_000e18 : IERC20(liabilitiesCached.at(0)).balanceOf(address(borrowLend)));
        debt2Amount = _bound(debt2Amount, 0, IERC20(liabilitiesCached.at(1)).balanceOf(address(borrowLend)) > 100_000e6 ? 100_000e6 : IERC20(liabilitiesCached.at(1)).balanceOf(address(borrowLend)));

        uint256[] memory collaterals = new uint256[](2);
        (collaterals[0], collaterals[1]) = (asset1Amount, asset2Amount);

        uint256[] memory debts = new uint256[](2);
        (debts[0], debts[1]) = (debt1Amount, debt2Amount);

        borrowLend.addCollateralAndBorrow(collaterals, debts, receiver);
    }

    function _doJoin(uint256[] memory assetsGiven, uint256[] memory liabilitiesReceived, uint256 shares) private {
        for(uint8 i; i < assetsCached.length(); i++){
            address _token = assetsCached.at(i);
            uint256 _amount = assetsGiven[i];

            DummyMintableTokenPermissionless(_token).deal(address(this), _amount);
            IERC20(_token).approve(address(vault), _amount);

            assetDeposits[_token] += _amount;
        }

        for(uint8 i; i < liabilitiesCached.length(); i++) {
            address _token = liabilitiesCached.at(i);
            uint256 _amount = liabilitiesReceived[i];

            DummyMintableTokenPermissionless(_token).deal(address(borrowLend), _amount + 1e18);

            liabilitiesBorrows[_token] += _amount;
        }

        totalShares += shares;
    }

    function _doExit(uint256[] memory assetsReceived, uint256[] memory liabilitiesGiven, uint256 shares) private {
        for(uint8 i; i < liabilitiesCached.length(); i++){
            address _token = liabilitiesCached.at(i);
            uint256 _amount = liabilitiesGiven[i];

            DummyMintableTokenPermissionless(_token).deal(address(this), _amount);
            IERC20(_token).approve(address(vault), _amount);

            liabilitiesBorrows[_token] -= _amount > liabilitiesBorrows[_token] ? liabilitiesBorrows[_token] : _amount;
        }

        for(uint8 i; i < assetsCached.length(); i++) {
            address _token = assetsCached.at(i);
            uint256 _amount = assetsReceived[i];
            
            assetDeposits[_token] -= _amount > assetDeposits[_token] ? assetDeposits[_token] : _amount;
        }

        totalShares -= shares > totalShares ? totalShares : shares;
    }

    function _assumeValidToken(uint256 tokenIndex, bool isAsset) private view returns(address _token) {
        if (isAsset) {
            tokenIndex = _bound(tokenIndex, 0, assetsCached.length() - 1);
        
            return assetsCached.at(tokenIndex);
        } else {
            tokenIndex = _bound(tokenIndex, 0, liabilitiesCached.length() - 1);
        
            return liabilitiesCached.at(tokenIndex);
        }
    }
}