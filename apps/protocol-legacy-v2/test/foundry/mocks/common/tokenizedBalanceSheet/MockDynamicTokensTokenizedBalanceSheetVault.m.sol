pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { MockBorrowLend } from "test/foundry/mocks/common/tokenizedBalanceSheet/MockBorrowLend.m.sol";
import { MockTokenizedBalanceSheetVaultWithFees } from "test/foundry/mocks/common/tokenizedBalanceSheet/MockTokenizedBalanceSheetVaultWithFees.m.sol";
import { MintableToken } from "contracts/common/MintableToken.sol";

contract MockDynamicTokensTokenizedBalanceSheetVault is MockTokenizedBalanceSheetVaultWithFees {
    struct Rollover {
        address[] tokensRenewed;
        uint256[] amountsRenewedMin;

        address[] tokensExpired;
        uint256[] amountsExpired;
    }
    constructor(
        address initialOwner_,
        string memory name_,
        string memory symbol_,
        address[] memory assetTokens_,
        address[] memory liabilityTokens_,
        uint256 joinFeeBps_,
        uint256 exitFeeBps_,
        MockBorrowLend borrowLend_
    ) MockTokenizedBalanceSheetVaultWithFees(
        initialOwner_,
        name_,
        symbol_,
        assetTokens_,
        liabilityTokens_,
        joinFeeBps_,
        exitFeeBps_,
        borrowLend_
        )
    {}

    //note: always the same number of pts are exited, the same are renewed?
    function rebalance(Rollover calldata tokensRollover) external {
        uint256 assetTokensLength = assetTokens().length;
        uint256 tokensExpiredLength = tokensRollover.tokensExpired.length;

        require(tokensExpiredLength <= assetTokensLength, "Length missmatch #1");
        require(tokensExpiredLength == tokensRollover.amountsExpired.length, "Length missmatch #2");

        borrowLend.redeemExpired(tokensRollover.tokensExpired, tokensRollover.amountsExpired);

        uint256[] memory amountsRenewed = new uint256[](tokensExpiredLength);
        
        //note: handle issue where not all the tokens are given
        for(uint256 i; i < tokensExpiredLength; i++) {
            address _tokenIn = tokensRollover.tokensExpired[i];
            uint256 _amountIn = tokensRollover.amountsExpired[i];
            
            address _tokenOut = tokensRollover.tokensRenewed[i];
            uint256 _amountOutMin = tokensRollover.amountsRenewedMin[i];
            
            amountsRenewed[i] = _mockSwapExactTokensForTokens(_tokenIn, _tokenOut, _amountIn, _amountOutMin);
        }

        for(uint256 i; i < tokensRollover.tokensExpired.length; i++) {
            MintableToken(tokensRollover.tokensRenewed[i]).approve(address(borrowLend), type(uint256).max);//note: normally we should do this in a separate function, but for sake of the mocking

            _assetTokens.push(tokensRollover.tokensRenewed[i]);
        }

        borrowLend.rolloverRenewed(tokensRollover.tokensRenewed, amountsRenewed);
    }

    function _mockSwapExactTokensForTokens(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin) internal returns (uint256) {
        MintableToken(tokenIn).burn(address(this), amountIn);

        //TODO: add custom rate logic, don't mint always the min amount

        MintableToken(tokenOut).mint(address(this), amountOutMin);

        return amountOutMin;
    }
}