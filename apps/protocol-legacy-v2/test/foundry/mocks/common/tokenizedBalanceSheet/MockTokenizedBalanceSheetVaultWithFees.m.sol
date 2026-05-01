pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OrigamiTokenizedBalanceSheetVault } from "contracts/common/OrigamiTokenizedBalanceSheetVault.sol";
import { MockBorrowLend } from "test/foundry/mocks/common/tokenizedBalanceSheet/MockBorrowLend.m.sol";

contract MockTokenizedBalanceSheetVaultWithFees is OrigamiTokenizedBalanceSheetVault {
    using SafeERC20 for IERC20;

    uint256 private immutable _joinFeeBps;
    uint256 private immutable _exitFeeBps;

    address[] internal _assetTokens;
    address[] internal _liabilityTokens;

    bool public joinsPaused;
    bool public exitsPaused;

    MockBorrowLend public immutable borrowLend;

    constructor(
        address initialOwner_,
        string memory name_,
        string memory symbol_,
        address[] memory assetTokens_,
        address[] memory liabilityTokens_,
        uint256 joinFeeBps_,
        uint256 exitFeeBps_,
        MockBorrowLend borrowLend_
    ) OrigamiTokenizedBalanceSheetVault(initialOwner_, name_, symbol_)
    {
        _assetTokens = assetTokens_;
        _liabilityTokens = liabilityTokens_;
        _joinFeeBps = joinFeeBps_;
        _exitFeeBps = exitFeeBps_;
        borrowLend = borrowLend_;

        // Max approve for adding collateral, and repaying debt
        for (uint256 i; i < assetTokens_.length; ++i) {
            IERC20(assetTokens_[i]).forceApprove(address(borrowLend), type(uint256).max);
        }
        for (uint256 i; i < liabilityTokens_.length; ++i) {
            IERC20(liabilityTokens_[i]).forceApprove(address(borrowLend), type(uint256).max);
        }
    }

    function setPaused(bool joins, bool exits) external {
        joinsPaused = joins;
        exitsPaused = exits;
    }

    function assetTokens() public override view returns (address[] memory) {
        return _assetTokens;
    }

    function liabilityTokens() public override view returns (address[] memory tokens) {
        return _liabilityTokens;
    }

    function joinFeeBps() public override view returns (uint256) {
        return _joinFeeBps;
    }

    function exitFeeBps() public override view returns (uint256) {
        return _exitFeeBps;
    }

    function areJoinsPaused() public override view returns (bool) {
        return joinsPaused;
    }

    function areExitsPaused() public override view returns (bool) {
        return exitsPaused;
    }

    function _joinPreMintHook(
        address caller,
        address receiver,
        uint256 /*shares*/,
        uint256[] memory assets,
        uint256[] memory liabilities
    ) internal override {
        // Pull the assets from caller
        for (uint256 i; i < assets.length; ++i) {
            IERC20(_assetTokens[i]).safeTransferFrom(caller, address(this), assets[i]);
        }

        // Add as collateral and borrow the debt (which goes to the receiver)
        borrowLend.addCollateralAndBorrow(assets, liabilities, receiver);
    }

    function _exitPreBurnHook(
        address caller,
        address /*sharesOwner*/,
        address receiver,
        uint256 /*shares*/,
        uint256[] memory assets,
        uint256[] memory liabilities
    ) internal override {
        // Pull the liabilities from the caller
        for (uint256 i; i < liabilities.length; ++i) {
            IERC20(_liabilityTokens[i]).safeTransferFrom(caller, address(this), liabilities[i]);
        }

        // Repay debt and withdraw collateral (which goes to the receiver)
        borrowLend.repayAndWithdrawCollateral(assets, liabilities, receiver);
    }

    function _tokenBalance(address tokenAddress) internal override view returns (uint256) {
        return borrowLend.balanceOfToken(tokenAddress);
    }
}
