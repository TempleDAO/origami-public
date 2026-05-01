pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { DummyMintableTokenPermissionless } from "contracts/test/common/DummyMintableTokenPermissionless.sol";

// NB: This implementation doesn't increase the collateral or debt balance over time, it's just fixed.
// Other tests will use real money markets - eg OHM Cooler loans.
contract MockBorrowLend {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _collateralTokens;
    EnumerableSet.AddressSet private _debtTokens;

    mapping(address token => uint256 amount) public collateralBalances;
    mapping(address token => uint256 amount) public debtBalances;

    constructor(address[] memory collateralTokens_, address[] memory debtTokens_) {
        uint256 i;
        uint256 _length = collateralTokens_.length;
        for (; i < _length; ++i) {
            _collateralTokens.add(collateralTokens_[i]);
        }

        _length = debtTokens_.length;
        for (i=0; i < _length; ++i) {
            _debtTokens.add(debtTokens_[i]);
        }
    }

    function balanceOfToken(address token) external view returns (uint256 amount) {
        if (_collateralTokens.contains(token)) {
            return collateralBalances[token];
        } else if (_debtTokens.contains(token)) {
            return debtBalances[token];
        }

        return 0;
    }

    function addCollateralAndBorrow(uint256[] memory collaterals, uint256[] memory debts, address debtReceiver) external {
        address tokenAddr;
        uint256 amount;

        address[] memory tokenAddrs = _collateralTokens.values();
        for (uint256 i; i < tokenAddrs.length; ++i) {
            tokenAddr = tokenAddrs[i];
            amount = collaterals[i];
            IERC20(tokenAddr).safeTransferFrom(msg.sender, address(this), amount);
            collateralBalances[tokenAddr] += amount;
        }

        tokenAddrs = _debtTokens.values();
        for (uint256 i; i < tokenAddrs.length; ++i) {
            tokenAddr = tokenAddrs[i];
            amount = debts[i];

            DummyMintableTokenPermissionless(tokenAddr).mint(debtReceiver, amount);
            debtBalances[tokenAddr] += amount;
        }
    }

    function repayAndWithdrawCollateral(uint256[] memory collaterals, uint256[] memory debts, address collateralReceiver) external {
        address tokenAddr;
        uint256 amount;

        address[] memory tokenAddrs = _debtTokens.values();
        for (uint256 i; i < tokenAddrs.length; ++i) {
            tokenAddr = tokenAddrs[i];
            amount = debts[i];
            debtBalances[tokenAddr] -= amount;
            IERC20(tokenAddr).safeTransferFrom(msg.sender, address(this), amount);
        }

        tokenAddrs = _collateralTokens.values();
        for (uint256 i; i < tokenAddrs.length; ++i) {
            tokenAddr = tokenAddrs[i];
            amount = collaterals[i];
            collateralBalances[tokenAddr] -= amount;
            IERC20(tokenAddr).safeTransfer(collateralReceiver, amount);
        }
    }

    function redeemExpired(address[] calldata collateralTokens, uint256[] calldata collateralsAmounts) external {
        require(collateralTokens.length == collateralsAmounts.length, "old: assets != tokens");

        address tokenAddr;
        uint256 amount;

        for(uint256 i; i < collateralTokens.length; i++) {
            tokenAddr = collateralTokens[i];
            amount = collateralsAmounts[i];

            require(_collateralTokens.contains(tokenAddr), "non-existing collateral");//note: or remove?

            collateralBalances[tokenAddr] -= amount;
            IERC20(tokenAddr).safeTransfer(msg.sender, amount);
        }
    }

    function rolloverRenewed(address[] calldata collateralTokens, uint256[] calldata collateralsAmounts) external {
        require(collateralTokens.length == collateralsAmounts.length, "new: assets != tokens");

        address tokenAddr;
        uint256 amount;

        for(uint256 i; i < collateralTokens.length; i++) {
            require(_collateralTokens.add(collateralTokens[i]), "Duplicated asset");
            tokenAddr = collateralTokens[i];
            amount = collateralsAmounts[i];

            collateralBalances[tokenAddr] += amount;
            IERC20(tokenAddr).safeTransferFrom(msg.sender, address(this), amount);
        }
    }
}
