pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { MockBorrowAndLend } from "contracts/test/common/borrowAndLend/MockBorrowAndLend.m.sol";
import { MockStEthToken } from "contracts/test/external/lido/MockStEthToken.m.sol";
import { MockWstEthToken } from "contracts/test/external/lido/MockWstEthToken.m.sol";
import { MockWrappedEther } from "contracts/test/external/MockWrappedEther.m.sol";
import { OrigamiStableChainlinkOracle } from "contracts/common/oracle/OrigamiStableChainlinkOracle.sol";
import { OrigamiWstEthToEthOracle } from "contracts/common/oracle/OrigamiWstEthToEthOracle.sol";
import { DummyOracle } from "contracts/test/common/DummyOracle.sol";
import { Range } from "contracts/libraries/Range.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

contract MockBorrowAndLendTestBase is OrigamiTest {
    MockWrappedEther internal wethToken;
    MockStEthToken internal stEthToken;
    MockWstEthToken internal wstEthToken;
    MockBorrowAndLend internal borrowLend;

    DummyOracle internal clStEthToEthOracle;
    OrigamiStableChainlinkOracle internal oStEthToEthOracle;
    OrigamiWstEthToEthOracle internal oWstEthToEthOracle;

    address internal posOwner = makeAddr("posOwner");
    uint96 internal WSTETH_SUPPLY_INTEREST_RATE = 0.01e18;
    uint96 internal WETH_BORROW_INTEREST_RATE = 0.03e18;

    uint96 internal STETH_INTEREST_RATE = 0.04e18;
    uint256 internal constant STETH_ETH_HISTORIC_RATE = 1e18;
    uint256 internal constant STETH_ETH_ORACLE_RATE = 1.001640797743598e18;
    uint256 internal MAX_LTV = 9000;
    uint256 internal MAX_SUPPLY = 5_000_000e18;

    function setUp() public {
        vm.warp(1672531200); // 1 Jan 2023
        wethToken = new MockWrappedEther(origamiMultisig);
        stEthToken = new MockStEthToken(origamiMultisig, STETH_INTEREST_RATE);
        wstEthToken = new MockWstEthToken(origamiMultisig, stEthToken);

        // 18 decimals
        clStEthToEthOracle = new DummyOracle(
            DummyOracle.Answer({
                roundId: 1,
                answer: int256(STETH_ETH_ORACLE_RATE),
                startedAt: 0,
                updatedAtLag: 0,
                answeredInRound: 1
            }),
            18
        );

        oStEthToEthOracle = new OrigamiStableChainlinkOracle(
            origamiMultisig,
            IOrigamiOracle.BaseOracleParams(
                "stETH/ETH",
                address(stEthToken),
                18,
                address(wethToken),
                18
            ),
            STETH_ETH_HISTORIC_RATE,
            address(clStEthToEthOracle),
            100 days,
            Range.Data(0.99e18, 1.01e18),
            true, // Chainlink does use roundId
            true // It does use lastUpdatedAt
        );

        oWstEthToEthOracle = new OrigamiWstEthToEthOracle(
            IOrigamiOracle.BaseOracleParams(
                "wstETH/ETH",
                address(wstEthToken),
                18, 
                address(wethToken),
                18
            ),
            address(stEthToken),
            address(oStEthToEthOracle)
        );

        borrowLend = new MockBorrowAndLend(
            origamiMultisig,
            address(wstEthToken),
            address(wethToken),
            MAX_LTV,
            MAX_SUPPLY,
            WSTETH_SUPPLY_INTEREST_RATE,
            WETH_BORROW_INTEREST_RATE,
            address(oWstEthToEthOracle)
        );

        vm.startPrank(origamiMultisig);
        borrowLend.setPositionOwner(posOwner);
        vm.stopPrank();
    }
}

contract MockStEthTest is MockBorrowAndLendTestBase {
    function test_submit() public {
        vm.startPrank(alice);
        deal(alice, 100e18);
        uint256 shares = stEthToken.submit{value: 1e18}(address(0));
        assertEq(shares, 1e18);

        {
            assertEq(address(stEthToken).balance, 1e18);
            assertEq(stEthToken.balanceOf(alice), 1e18);
            assertEq(alice.balance, 99e18);
            assertEq(stEthToken.getSharesByPooledEth(1e18), 1e18);
            assertEq(stEthToken.getPooledEthByShares(1e18), 1e18);
        }

        uint256 expectedRatio = 1.040810774192388226e18;
        uint256 expectedInverseRatio = 0.960789439152323210e18;
        {
            vm.warp(block.timestamp + 365 days);
            assertEq(address(stEthToken).balance, 1e18);
            assertEq(stEthToken.balanceOf(alice), expectedRatio);
            assertEq(alice.balance, 99e18);
            assertEq(stEthToken.getSharesByPooledEth(1e18), expectedInverseRatio);
            assertEq(stEthToken.getPooledEthByShares(1e18), expectedRatio);
        }

        vm.startPrank(bob);
        deal(bob, 100e18);
        shares = stEthToken.submit{value: 1e18}(address(0));
        assertEq(shares, expectedInverseRatio);

        {
            assertEq(address(stEthToken).balance, 2e18);
            assertEq(stEthToken.balanceOf(alice), expectedRatio);
            assertEq(stEthToken.balanceOf(bob), 0.999999999999999999e18);
            assertEq(bob.balance, 99e18);
            assertEq(stEthToken.getSharesByPooledEth(1e18), expectedInverseRatio);
            assertEq(stEthToken.getPooledEthByShares(1e18), expectedRatio);
        }

        {
            vm.warp(block.timestamp + 365 days);
            assertEq(address(stEthToken).balance, 2e18);
            assertEq(stEthToken.balanceOf(alice), 1.083287067674958553e18);
            assertEq(stEthToken.balanceOf(bob), expectedRatio-1);
            assertEq(bob.balance, 99e18);
            assertEq(stEthToken.getSharesByPooledEth(1e18), 0.923116346386635784e18);
            assertEq(stEthToken.getPooledEthByShares(1e18), 1.083287067674958553e18);
        }
    }

    function test_recoverNative() public {
        vm.startPrank(alice);
        deal(alice, 100e18);
        stEthToken.submit{value: 1e18}(address(0));

        vm.startPrank(origamiMultisig);
        stEthToken.recoverNative(0.25e18, payable(bob));
        assertEq(bob.balance, 0.25e18);
        assertEq(address(stEthToken).balance, 0.75e18);
    }

}

contract MockWstEthTest is MockBorrowAndLendTestBase {
    function test_wrap() public {
        vm.startPrank(alice);
        deal(alice, 100e18);
        stEthToken.submit{value: 1e18}(address(0));
        stEthToken.approve(address(wstEthToken), 10e18);
        uint256 amountOut = wstEthToken.wrap(1e18);
        assertEq(amountOut, 1e18);

        {
            assertEq(wstEthToken.balanceOf(alice), 1e18);
            assertEq(stEthToken.balanceOf(address(wstEthToken)), 1e18);
            assertEq(wstEthToken.getWstETHByStETH(1e18), 1e18);
            assertEq(wstEthToken.getStETHByWstETH(1e18), 1e18);
            assertEq(wstEthToken.stEthPerToken(), 1e18);
            assertEq(wstEthToken.tokensPerStEth(), 1e18);
        }

        uint256 expectedRatio = 1.040810774192388226e18;
        uint256 expectedInverseRatio = 0.960789439152323210e18;
        {
            vm.warp(block.timestamp + 365 days);
            assertEq(wstEthToken.balanceOf(alice), 1e18);
            assertEq(stEthToken.balanceOf(address(wstEthToken)), expectedRatio);
            assertEq(wstEthToken.getStETHByWstETH(1e18), expectedRatio);
            assertEq(wstEthToken.getWstETHByStETH(1e18), expectedInverseRatio);
            assertEq(wstEthToken.stEthPerToken(), expectedRatio);
            assertEq(wstEthToken.tokensPerStEth(), expectedInverseRatio);
        }

        vm.startPrank(bob);
        deal(bob, 100e18);
        uint256 shares = stEthToken.submit{value: 1e18}(address(0));
        assertEq(shares, expectedInverseRatio);
        stEthToken.approve(address(wstEthToken), 1e18);

        amountOut = wstEthToken.wrap(999999999999999999);
        assertEq(amountOut, expectedInverseRatio - 1);

        {
            assertEq(address(stEthToken).balance, 2e18);
            assertEq(stEthToken.balanceOf(alice), 0);
            assertEq(stEthToken.balanceOf(bob), 1);

            assertEq(wstEthToken.balanceOf(alice), 1e18);
            assertEq(wstEthToken.balanceOf(bob), expectedInverseRatio-1);
            assertEq(stEthToken.balanceOf(address(wstEthToken)), 1e18+expectedRatio-2);
            assertEq(wstEthToken.getStETHByWstETH(1e18), expectedRatio);
            assertEq(wstEthToken.getWstETHByStETH(1e18), expectedInverseRatio);
            assertEq(wstEthToken.stEthPerToken(), expectedRatio);
            assertEq(wstEthToken.tokensPerStEth(), expectedInverseRatio);
        }

        {
            vm.warp(block.timestamp + 365 days);
            assertEq(address(stEthToken).balance, 2e18);
            assertEq(wstEthToken.balanceOf(alice), 1e18);
            assertEq(wstEthToken.balanceOf(bob), expectedInverseRatio-1);
            assertEq(stEthToken.balanceOf(address(wstEthToken)), 2.124097841867346777e18);
            assertEq(wstEthToken.getStETHByWstETH(1e18), 1.083287067674958553e18);
            assertEq(wstEthToken.getWstETHByStETH(1e18), 0.923116346386635784e18);
            assertEq(wstEthToken.stEthPerToken(), 1.083287067674958553e18);
            assertEq(wstEthToken.tokensPerStEth(), 0.923116346386635784e18);
        }

        vm.startPrank(bob);
        uint256 expectedOut = 1.083287067674958553e18*(expectedInverseRatio-1)/1e18;
        amountOut = wstEthToken.unwrap(expectedInverseRatio-1);
        assertEq(amountOut, expectedOut);
        assertEq(stEthToken.balanceOf(bob), expectedOut+1);
        assertEq(wstEthToken.balanceOf(bob), 0);

        vm.startPrank(alice);
        expectedOut = 1.083287067674958553e18;
        amountOut = wstEthToken.unwrap(1e18);
        assertEq(amountOut, expectedOut);
        assertEq(stEthToken.balanceOf(alice), expectedOut);
        assertEq(wstEthToken.balanceOf(alice), 0);
    }
}

contract MockBorrowAndLendTest is MockBorrowAndLendTestBase {
    error Fail();

    function dealWstEth(uint256 ethAmount, address recipient) internal returns (uint256) {
        deal(recipient, ethAmount);
        uint256 balBefore = wstEthToken.balanceOf(recipient);
        vm.startPrank(recipient);
        (bool success,) = payable(wstEthToken).call{value: ethAmount}("");
        if (!success) revert Fail();

        vm.stopPrank();
        return wstEthToken.balanceOf(recipient) - balBefore;
    }

    function supply(uint256 ethAmount, address recipient) internal returns (uint256) {
        uint256 wstEthAmount = dealWstEth(ethAmount, recipient);
        vm.startPrank(recipient);
        wstEthToken.transfer(address(borrowLend), wstEthAmount);
        borrowLend.supply(wstEthAmount);
        return wstEthAmount;
    }

    function test_supply() public {
        vm.warp(block.timestamp + 365 days);

        uint256 ethAmount = 100e18;
        uint256 wstEthAmount = dealWstEth(ethAmount, posOwner);
        assertEq(wstEthAmount, ethAmount);
        assertEq(wstEthToken.balanceOf(posOwner), ethAmount);

        vm.startPrank(posOwner);
        wstEthToken.transfer(address(borrowLend), wstEthAmount);
        borrowLend.supply(wstEthAmount);
        assertEq(borrowLend.suppliedBalance(), wstEthAmount);
        assertEq(borrowLend.availableToWithdraw(), wstEthAmount);
        (
            uint256 _supplyCap,
            uint256 available
        ) = borrowLend.availableToSupply();
        assertEq(_supplyCap, MAX_SUPPLY);
        assertEq(available, _supplyCap-wstEthAmount);

        (
            uint256 accumulatorUpdatedAt,
            uint256 accumulator,
            uint256 checkpoint,
            uint96 interestRate
        ) = borrowLend.supplyAccumulatorData();
        assertEq(accumulatorUpdatedAt, block.timestamp);
        assertEq(accumulator, 1010050167084168057000000000);
        assertEq(checkpoint, wstEthAmount);
        assertEq(interestRate, WSTETH_SUPPLY_INTEREST_RATE);
    }

    function test_borrow() public {
        vm.warp(block.timestamp + 365 days);
        uint256 ethAmount = 100e18;
        uint256 wstEthAmount = supply(ethAmount, posOwner);

        uint256 borrowAmount = 90e18;
        deal(address(wethToken), address(borrowLend.escrow()), 1_000e18);
        borrowLend.borrow(borrowAmount, posOwner);

        (
            uint256 accumulatorUpdatedAt,
            uint256 accumulator,
            uint256 checkpoint,
            uint96 interestRate
        ) = borrowLend.supplyAccumulatorData();
        assertEq(accumulatorUpdatedAt, block.timestamp);
        assertEq(accumulator, 1010050167084168057000000000);
        assertEq(checkpoint, wstEthAmount);
        assertEq(interestRate, WSTETH_SUPPLY_INTEREST_RATE);

        (
            accumulatorUpdatedAt,
            accumulator,
            checkpoint,
            interestRate
        ) = borrowLend.borrowAccumulatorData();
        assertEq(accumulatorUpdatedAt, block.timestamp);
        assertEq(accumulator, 1030454533953516855000000000);
        assertEq(checkpoint, borrowAmount);
        assertEq(interestRate, WETH_BORROW_INTEREST_RATE);

        assertEq(borrowLend.suppliedBalance(), wstEthAmount);
        assertEq(borrowLend.debtBalance(), borrowAmount);
        vm.warp(block.timestamp + 365 days);
        assertEq(borrowLend.suppliedBalance(), 101.005016708416805700e18);
        assertEq(borrowLend.debtBalance(), 92.740908055816516950e18);
    }

    function test_repay() public {
        vm.warp(block.timestamp + 365 days);
        uint256 ethAmount = 100e18;
        supply(ethAmount, posOwner);

        uint256 borrowAmount = 90e18;
        deal(address(wethToken), address(borrowLend.escrow()), 1_000e18);
        borrowLend.borrow(borrowAmount, posOwner);

        vm.warp(block.timestamp + 365 days);
        assertEq(borrowLend.suppliedBalance(), 101.005016708416805700e18);
        assertEq(borrowLend.debtBalance(), 92.740908055816516950e18);
        assertEq(wethToken.balanceOf(posOwner), borrowAmount);

        deal(address(wethToken), address(borrowLend), 92.740908055816516950e18);
        borrowLend.repay(borrowAmount);
        assertEq(borrowLend.suppliedBalance(), 101.005016708416805700e18);
        assertEq(borrowLend.debtBalance(), 2.740908055816516950e18);
        borrowLend.repay(10e18);
        assertEq(borrowLend.suppliedBalance(), 101.005016708416805700e18);
        assertEq(borrowLend.debtBalance(), 0);
    }

    function test_withdraw() public {
        vm.warp(block.timestamp + 365 days);
        uint256 ethAmount = 100e18;
        supply(ethAmount, posOwner);

        uint256 borrowAmount = 90e18;
        deal(address(wethToken), address(borrowLend.escrow()), 1_000e18);
        borrowLend.borrow(borrowAmount, posOwner);
        vm.warp(block.timestamp + 365 days);

        deal(address(wethToken), address(borrowLend), 92.740908055816516950e18);
        borrowLend.repay(5e18);

        vm.expectRevert();
        borrowLend.withdraw(10e18, posOwner);
        borrowLend.withdraw(5e18, posOwner);
        assertEq(borrowLend.suppliedBalance(), 101.005016708416805700e18-5e18);
        assertEq(borrowLend.debtBalance(), 92.740908055816516950e18-5e18);

        borrowLend.repay(100e18);

        deal(address(wstEthToken), address(borrowLend.escrow()), 500e18);
        borrowLend.withdraw(type(uint256).max, posOwner);
        assertEq(borrowLend.suppliedBalance(), 0);
        assertEq(borrowLend.debtBalance(), 0);
        assertEq(wstEthToken.balanceOf(posOwner), 101.005016708416805700e18);
    }

}