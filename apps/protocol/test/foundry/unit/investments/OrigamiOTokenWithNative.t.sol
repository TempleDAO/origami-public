pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiMockManagerWithNative } from "test/foundry/mocks/investments/OrigamiMockManagerWithNative.m.sol";
import { OrigamiOTokenWithNative } from "contracts/investments/OrigamiOTokenWithNative.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiManagerPausable } from "contracts/interfaces/investments/util/IOrigamiManagerPausable.sol";
import { DummyWrappedNative } from "test/foundry/mocks/common/DummyWrappedNative.m.sol";

contract OrigamiOTokenWithNativeTestBase is OrigamiTest {
    OrigamiOTokenWithNative public oToken;
    DummyWrappedNative public weth;
    OrigamiMockManagerWithNative public oTokenManager;
    uint128 public exitFeeBps = 500;
    address public ZERO_ADDRESS = address(0);

    function setUp() public {
        weth = new DummyWrappedNative("weth", "weth", origamiMultisig);
        oToken = new OrigamiOTokenWithNative(origamiMultisig, address(weth), "O Token", "oToken");
        oTokenManager = new OrigamiMockManagerWithNative(origamiMultisig, address(oToken), address(weth), feeCollector, exitFeeBps);

        vm.startPrank(origamiMultisig);
        oToken.setManager(address(oTokenManager));
        oTokenManager.setPauser(origamiMultisig, true);
        vm.stopPrank();
    }
}

contract OrigamiOTokenWithNativeTestAccess is OrigamiOTokenWithNativeTestBase {
    function test_setManager_access() public {
        expectElevatedAccess();
        oToken.setManager(address(oTokenManager));
    }
}

contract OrigamiOTokenWithNativeTestAdmin is OrigamiOTokenWithNativeTestBase {
    event ManagerSet(address indexed manager);

    function test_constructor() public {
        assertEq(oToken.apiVersion(), "0.2.0");
        assertEq(oToken.owner(), origamiMultisig);
        assertEq(oToken.name(), "O Token");
        assertEq(oToken.symbol(), "oToken");
        assertEq(oToken.decimals(), 18);

        assertEq(address(oToken.manager()), address(oTokenManager));
    }

    function test_sendEth_failure() public {
        vm.startPrank(msg.sender);
        vm.expectRevert(abi.encodeWithSelector(OrigamiOTokenWithNative.InvalidSender.selector, msg.sender));
        payable(address(oToken)).transfer(0.01e18);
        assertEq(address(oToken).balance, 0);
    }

    function test_sendEth_success() public {
        vm.deal(address(weth), 0.01e18);
        vm.startPrank(address(weth));
        payable(address(oToken)).transfer(0.01e18);
        assertEq(address(oToken).balance, 0.01e18);
    }

    function test_setManager_failure() public {
        vm.startPrank(origamiMultisig);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        oToken.setManager(address(0));
    }

    function test_setManager_success() public {
        assertEq(address(oToken.manager()), address(oTokenManager));

        vm.startPrank(origamiMultisig);
        OrigamiMockManagerWithNative newManager = new OrigamiMockManagerWithNative(origamiMultisig, address(oToken), address(weth), feeCollector, exitFeeBps);

        vm.expectEmit(address(oToken));
        emit ManagerSet(address(newManager));
        oToken.setManager(address(newManager));

        assertEq(address(oToken.manager()), address(newManager));
    }

    function test_baseToken() public {
        assertEq(oToken.baseToken(), ZERO_ADDRESS);
    }

    function test_acceptedInvestTokens() public {
        address[] memory tokens = oToken.acceptedInvestTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], ZERO_ADDRESS);
    }

    function test_acceptedExitTokens() public {
        address[] memory tokens = oToken.acceptedExitTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], ZERO_ADDRESS);
    }

    function test_areInvestmentsPaused() public {
        assertEq(oToken.areInvestmentsPaused(), false);

        vm.prank(origamiMultisig);
        oTokenManager.setPaused(IOrigamiManagerPausable.Paused(true, false));
        assertEq(oToken.areInvestmentsPaused(), true);
    }

    function test_areExitsPaused() public {
        assertEq(oToken.areExitsPaused(), false);

        vm.prank(origamiMultisig);
        oTokenManager.setPaused(IOrigamiManagerPausable.Paused(false, true));
        assertEq(oToken.areExitsPaused(), true);
    }
}

contract OrigamiOTokenWithNativeTestInvest is OrigamiOTokenWithNativeTestBase {
    event Invested(address indexed user, uint256 fromTokenAmount, address indexed fromToken, uint256 investmentAmount);

    function test_investWithNative_failureZeroAmount() public {
        IOrigamiInvestment.InvestQuoteData memory quoteData;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        oToken.investWithNative(quoteData);
    }

    function test_investWithNative_failureMismatchedAmount() public {
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = oToken.investQuote(
            1e18,
            ZERO_ADDRESS,
            100,
            0
        );
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAmount.selector, ZERO_ADDRESS, 123));
        oToken.investWithNative{value: 123}(quoteData);
    }

    function test_investWithNative_failureNotEth() public {
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = oToken.investQuote(
            1e18,
            ZERO_ADDRESS,
            100,
            0
        );
        quoteData.fromToken = alice;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, alice));
        oToken.investWithNative{value: 1e18}(quoteData);
    }

    function test_investWithNative_success() public {
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = oToken.investQuote(
            1e18,
            ZERO_ADDRESS,
            100,
            0
        );

        deal(alice, 1e18);
        vm.startPrank(alice);
        vm.expectEmit(address(oToken));
        emit Invested(alice, 1e18, address(0), 1e18);
        uint256 oTokenAmount = oToken.investWithNative{value: 1e18}(quoteData);

        assertEq(address(weth).balance, 1e18);
        assertEq(weth.balanceOf(address(oTokenManager)), 1e18);

        assertEq(oTokenAmount, 1e18);
        assertEq(oToken.totalSupply(), 1e18);
        assertEq(oToken.balanceOf(alice), 1e18);
        assertEq(oToken.balanceOf(feeCollector), 0);
    }
}

contract OrigamiOTokenWithNativeTestExit is OrigamiOTokenWithNativeTestBase {
    event Exited(address indexed user, uint256 investmentAmount, address indexed toToken, uint256 toTokenAmount, address indexed recipient);

    function test_exitToNative_failureZeroAmount() public {
        IOrigamiInvestment.ExitQuoteData memory quoteData;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        oToken.exitToNative(quoteData, payable(alice));
    }

    function test_exitToNative_failureNotEth() public {
        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = oToken.exitQuote(
            1e18,
            ZERO_ADDRESS,
            100,
            0
        );
        quoteData.toToken = alice;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, alice));
        oToken.exitToNative(quoteData, payable(alice));
    }

    function test_exitToNative_failureNoTokens() public {
        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = oToken.exitQuote(
            1e18,
            ZERO_ADDRESS,
            100,
            0
        );
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        oToken.exitToNative(quoteData, payable(alice));
    }

    function test_exitToNative_success() public {
        // First invest
        {
            (IOrigamiInvestment.InvestQuoteData memory quoteData,) = oToken.investQuote(
                1e18,
                ZERO_ADDRESS,
                100,
                0
            );

            deal(alice, 1e18);
            vm.startPrank(alice);
            oToken.investWithNative{value: 1e18}(quoteData);
        }

        {
            (IOrigamiInvestment.ExitQuoteData memory quoteData,) = oToken.exitQuote(
                1e18,
                ZERO_ADDRESS,
                100,
                0
            );

            vm.expectEmit(address(oToken));
            emit Exited(alice, 1e18, ZERO_ADDRESS, 0.95e18, alice);
            uint256 amountOut = oToken.exitToNative(quoteData, payable(alice));

            assertEq(oToken.totalSupply(), 0.05e18);
            assertEq(oToken.balanceOf(alice), 0);
            assertEq(oToken.balanceOf(feeCollector), 0.05e18);
            assertEq(amountOut, 0.95e18);
            assertEq(alice.balance, 0.95e18);
        }
    }
}
