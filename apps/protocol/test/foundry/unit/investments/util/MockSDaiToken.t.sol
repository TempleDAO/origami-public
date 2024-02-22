pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";

import { MockSDaiToken } from "contracts/test/external/maker/MockSDaiToken.m.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";

contract MockSDaiTest is OrigamiTest {
    MockSDaiToken public sdai;
    DummyMintableToken public daiToken;

    // 5% APR = 4.879% APY
    uint96 public interestRate = 0.05e18;

    function setUp() public {
        daiToken = new DummyMintableToken(origamiMultisig, "DAI", "DAI", 18);
        sdai = new MockSDaiToken(daiToken);
        sdai.setInterestRate(interestRate);
        doMint(daiToken, address(sdai), 100_000_000e18);
    }

    function test_sdai_deposit() public {
        uint256 amount = 100_000e18;
        uint256 amountBack = 101_369.863013698630136986e18;

        doMint(daiToken, alice, amount);
        vm.startPrank(alice);
        daiToken.approve(address(sdai), amount);
        uint256 amountOut = sdai.deposit(amount, alice);

        assertEq(amountOut, amount);
        assertEq(sdai.balanceOf(alice), amount);
        assertEq(sdai.previewRedeem(amountOut), amount);

        vm.warp(block.timestamp + 100 days);
        assertEq(sdai.balanceOf(alice), amount);
        assertEq(sdai.previewRedeem(amountOut), amountBack);

        uint256 daiAmountBack = sdai.redeem(amountOut, alice, alice);
        assertEq(daiAmountBack, amountBack);
        assertEq(sdai.balanceOf(alice), 0);
        assertEq(daiToken.balanceOf(alice), amountBack);
        assertEq(sdai.checkpointValue(), 0);
    }
}