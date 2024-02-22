pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiMockManager } from "test/foundry/mocks/investments/OrigamiMockManager.m.sol";
import { OrigamiOToken } from "contracts/investments/OrigamiOToken.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiManagerPausable } from "contracts/interfaces/investments/util/IOrigamiManagerPausable.sol";

contract OrigamiOTokenTestBase is OrigamiTest {
    OrigamiOToken public oToken;
    OrigamiMockManager public oTokenManager;
    DummyMintableToken public depositToken;
    uint128 public exitFeeBps = 500;

    function setUp() public {
        oToken = new OrigamiOToken(origamiMultisig, "O Token", "oToken");
        depositToken = new DummyMintableToken(origamiMultisig, "Deposit Token", "token", 18);
        oTokenManager = new OrigamiMockManager(origamiMultisig, address(oToken), address(depositToken), feeCollector, exitFeeBps);

        vm.startPrank(origamiMultisig);
        oToken.setManager(address(oTokenManager));
        oTokenManager.setPauser(origamiMultisig, true);
        vm.stopPrank();
    }
}

contract OrigamiOTokenTestAccess is OrigamiOTokenTestBase {
    function test_setManager_access() public {
        expectElevatedAccess();
        oToken.setManager(address(oTokenManager));
    }

    function test_amoMint_access() public {
        expectElevatedAccess();
        oToken.amoMint(alice, 100);
    }

    function test_amoBurn_access() public {
        expectElevatedAccess();
        oToken.amoBurn(alice, 100);
    }
}

contract OrigamiOTokenTestAdmin is OrigamiOTokenTestBase {
    event ManagerSet(address indexed manager);

    function test_constructor() public {
        assertEq(oToken.apiVersion(), "0.2.0");
        assertEq(oToken.owner(), origamiMultisig);
        assertEq(oToken.name(), "O Token");
        assertEq(oToken.symbol(), "oToken");
        assertEq(oToken.decimals(), 18);
        assertEq(oToken.amoMinted(), 0);
        assertEq(oToken.circulatingSupply(), 0);

        assertEq(address(oToken.manager()), address(oTokenManager));
    }

    function test_setManager_failure() public {
        vm.startPrank(origamiMultisig);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        oToken.setManager(address(0));
    }

    function test_setManager_success() public {
        assertEq(address(oToken.manager()), address(oTokenManager));

        vm.startPrank(origamiMultisig);
        OrigamiMockManager newManager = new OrigamiMockManager(origamiMultisig, address(oToken), address(depositToken), feeCollector, exitFeeBps);

        vm.expectEmit(address(oToken));
        emit ManagerSet(address(newManager));
        oToken.setManager(address(newManager));

        assertEq(address(oToken.manager()), address(newManager));
    }

    function test_baseToken() public {
        assertEq(oToken.baseToken(), address(depositToken));
    }

    function test_acceptedInvestTokens() public {
        address[] memory tokens = oToken.acceptedInvestTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(depositToken));
    }

    function test_acceptedExitTokens() public {
        address[] memory tokens = oToken.acceptedExitTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(depositToken));
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

contract OrigamiOTokenTestInvest is OrigamiOTokenTestBase {
    event Invested(address indexed user, uint256 fromTokenAmount, address indexed fromToken, uint256 investmentAmount);

    function test_maxInvest() public {
        // Calls the underlying manager
        assertEq(oToken.maxInvest(address(depositToken)), oTokenManager.maxInvest(address(depositToken)));
        assertEq(oToken.maxInvest(address(depositToken)), 123e18);
    }

    function test_investQuote() public {
        (IOrigamiInvestment.InvestQuoteData memory quoteData, uint256[] memory investFeeBps) = oToken.investQuote(
            1e18,
            address(depositToken),
            100,
            0
        );

        assertEq(quoteData.fromToken, address(depositToken));
        assertEq(quoteData.fromTokenAmount, 1e18);
        assertEq(quoteData.maxSlippageBps, 100);
        assertEq(quoteData.deadline, 0);
        assertEq(quoteData.expectedInvestmentAmount, 1e18);
        assertEq(quoteData.minInvestmentAmount, 1e18);
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));

        assertEq(investFeeBps.length, 0);
    }

    function test_investWithNative_failure() public {
        IOrigamiInvestment.InvestQuoteData memory quoteData;
        vm.expectRevert(abi.encodeWithSelector(IOrigamiInvestment.Unsupported.selector));
        oToken.investWithNative(quoteData);
    }

    function test_investWithToken_failureZeroAmount() public {
        IOrigamiInvestment.InvestQuoteData memory quoteData;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        oToken.investWithToken(quoteData);
    }

    function test_investWithToken_failureNoTokens() public {
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = oToken.investQuote(
            1e18,
            address(depositToken),
            100,
            0
        );
        vm.expectRevert("ERC20: insufficient allowance");
        oToken.investWithToken(quoteData);

        depositToken.approve(address(oToken), 1e18);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        oToken.investWithToken(quoteData);
    }

    function test_investWithToken_fail_badToken() public {
        vm.startPrank(alice);
        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = oToken.investQuote(
            100,
            address(depositToken),
            100,
            123
        );
        DummyMintableToken badToken = new DummyMintableToken(origamiMultisig, "BAD", "BAD", 18);
        deal(address(badToken), alice, 100e18);
        badToken.approve(address(oToken), 100e18);
        quoteData.fromToken = address(badToken);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(badToken)));
        oToken.investWithToken(quoteData);
    }

    function test_investWithToken_success() public {
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = oToken.investQuote(
            1e18,
            address(depositToken),
            100,
            0
        );

        deal(address(depositToken), alice, 1e18, true);
        vm.startPrank(alice);
        depositToken.approve(address(oToken), 1e18);

        vm.expectEmit(address(oToken));
        emit Invested(alice, 1e18, address(depositToken), 1e18);
        uint256 oTokenAmount = oToken.investWithToken(quoteData);

        assertEq(oToken.totalSupply(), 1e18);
        assertEq(oToken.balanceOf(alice), 1e18);
        assertEq(oToken.balanceOf(feeCollector), 0);
        assertEq(oTokenAmount, 1e18);
        assertEq(oToken.amoMinted(), 0);
        assertEq(oToken.circulatingSupply(), 1e18);
    }
}

contract OrigamiOTokenTestExit is OrigamiOTokenTestBase {
    event Exited(address indexed user, uint256 investmentAmount, address indexed toToken, uint256 toTokenAmount, address indexed recipient);

    function test_maxExit() public {
        // Calls the underlying manager
        assertEq(oToken.maxExit(address(depositToken)), oTokenManager.maxExit(address(depositToken)));
        assertEq(oToken.maxExit(address(depositToken)), 456e18);
    }

    function test_exitQuote() public {
        (IOrigamiInvestment.ExitQuoteData memory quoteData, uint256[] memory exitFeeBps) = oToken.exitQuote(
            1e18,
            address(depositToken),
            100,
            0
        );

        assertEq(quoteData.investmentTokenAmount, 1e18);
        assertEq(quoteData.toToken, address(depositToken));
        assertEq(quoteData.maxSlippageBps, 100);
        assertEq(quoteData.deadline, 0);
        assertEq(quoteData.expectedToTokenAmount, 0.95e18);
        assertEq(quoteData.minToTokenAmount, 0.95e18);
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));

        assertEq(exitFeeBps.length, 1);
        assertEq(exitFeeBps[0], 500);
    }

    function test_exitToNative_failure() public {
        IOrigamiInvestment.ExitQuoteData memory quoteData;
        vm.expectRevert(abi.encodeWithSelector(IOrigamiInvestment.Unsupported.selector));
        oToken.exitToNative(quoteData, payable(alice));
    }

    function test_exitToToken_failureZeroAmount() public {
        IOrigamiInvestment.ExitQuoteData memory quoteData;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        oToken.exitToToken(quoteData, alice);
    }

    function test_exitToToken_failureNoTokens() public {
        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = oToken.exitQuote(
            1e18,
            address(depositToken),
            100,
            0
        );
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        oToken.exitToToken(quoteData, alice);
    }

    function test_exitToToken_fail_zeroRecipient() public {
        // First invest
        {
            (IOrigamiInvestment.InvestQuoteData memory quoteData,) = oToken.investQuote(
                1e18,
                address(depositToken),
                100,
                0
            );

            deal(address(depositToken), alice, 1e18, true);
            vm.startPrank(alice);
            depositToken.approve(address(oToken), 1e18);
            oToken.investWithToken(quoteData);
        }

        {
            (IOrigamiInvestment.ExitQuoteData memory quoteData,) = oToken.exitQuote(
                1e18,
                address(depositToken),
                100,
                0
            );

            vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
            oToken.exitToToken(quoteData, address(0));
        }
    }

    function test_exitToToken_fail_badToken() public {
        // First invest
        {
            (IOrigamiInvestment.InvestQuoteData memory quoteData,) = oToken.investQuote(
                1e18,
                address(depositToken),
                100,
                0
            );

            deal(address(depositToken), alice, 1e18, true);
            vm.startPrank(alice);
            depositToken.approve(address(oToken), 1e18);
            oToken.investWithToken(quoteData);
        }

        {
            (IOrigamiInvestment.ExitQuoteData memory quoteData,) = oToken.exitQuote(
                1e18,
                address(depositToken),
                100,
                0
            );
            DummyMintableToken badToken = new DummyMintableToken(origamiMultisig, "BAD", "BAD", 18);
            quoteData.toToken = address(badToken);

            vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(badToken)));
            oToken.exitToToken(quoteData, alice);
        }
    }

    function test_exitToToken_success() public {
        // First invest
        {
            (IOrigamiInvestment.InvestQuoteData memory quoteData,) = oToken.investQuote(
                1e18,
                address(depositToken),
                100,
                0
            );

            deal(address(depositToken), alice, 1e18, true);
            vm.startPrank(alice);
            depositToken.approve(address(oToken), 1e18);
            oToken.investWithToken(quoteData);
        }

        {
            (IOrigamiInvestment.ExitQuoteData memory quoteData,) = oToken.exitQuote(
                1e18,
                address(depositToken),
                100,
                0
            );


            vm.expectEmit(address(oToken));
            emit Exited(alice, 1e18, address(depositToken), 0.95e18, alice);
            uint256 amountOut = oToken.exitToToken(quoteData, alice);

            assertEq(oToken.totalSupply(), 0.05e18);
            assertEq(oToken.balanceOf(alice), 0);
            assertEq(oToken.balanceOf(feeCollector), 0.05e18);
            assertEq(amountOut, 0.95e18);
            assertEq(depositToken.balanceOf(alice), 0.95e18);
            assertEq(oToken.amoMinted(), 0);
            assertEq(oToken.circulatingSupply(), 0.05e18);
        }
    }
}

contract OrigamiOTokenTestAmo is OrigamiOTokenTestBase {
    event AmoMint(address indexed to, uint256 amount);
    event AmoBurn(address indexed account, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function _invest() internal returns (uint256) {
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = oToken.investQuote(
            1e18,
            address(depositToken),
            100,
            0
        );

        deal(address(depositToken), alice, 1e18, true);
        vm.startPrank(alice);
        depositToken.approve(address(oToken), 1e18);
        return oToken.investWithToken(quoteData);
    }

    function test_amoMint() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;

        // AMO mint
        {
            vm.expectEmit(address(oToken));
            emit AmoMint(alice, amount);
            vm.expectEmit(address(oToken));
            emit Transfer(address(0), alice, amount);

            oToken.amoMint(alice, amount);
        }

        assertEq(oToken.amoMinted(), amount);
        assertEq(oToken.circulatingSupply(), 0);
        assertEq(oToken.totalSupply(), amount);
        assertEq(oToken.balanceOf(alice), amount);

        // Alice Invests
        uint256 aliceAmount = _invest();
        assertEq(oToken.amoMinted(), amount);
        assertEq(oToken.circulatingSupply(), aliceAmount);
        assertEq(oToken.totalSupply(), aliceAmount + amount);
        assertEq(oToken.balanceOf(alice), aliceAmount + amount);
    }

    function test_amoMint_fails_zeroAddress() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        vm.expectRevert("ERC20: mint to the zero address");
        oToken.amoMint(address(0), amount);
    }

    function test_amoBurn_failsTooMuch() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        oToken.amoMint(alice, amount);
        _invest();

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAmount.selector, address(oToken), amount+1));
        oToken.amoBurn(alice, amount+1);

        // Works for the exact amount
        oToken.amoBurn(alice, amount);
    }

    function test_amoBurn_fails_zeroAddress() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        oToken.amoMint(alice, amount);
        _invest();

        vm.startPrank(origamiMultisig);
        vm.expectRevert("ERC20: burn from the zero address");
        oToken.amoBurn(address(0), amount);
    }

    function test_amoBurn_success() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        oToken.amoMint(alice, amount);
        uint256 aliceAmount = _invest();

        vm.startPrank(origamiMultisig);

        uint256 burnAmount = 25e18;
        {
            vm.expectEmit(address(oToken));
            emit AmoBurn(alice, burnAmount);
            vm.expectEmit(address(oToken));
            emit Transfer(alice, address(0), burnAmount);
            oToken.amoBurn(alice, burnAmount);
        }

        assertEq(oToken.amoMinted(), amount-burnAmount);
        assertEq(oToken.circulatingSupply(), aliceAmount);
        assertEq(oToken.totalSupply(), aliceAmount + amount - burnAmount);
        assertEq(oToken.balanceOf(alice), aliceAmount + amount - burnAmount);

        // Zero amount also fine.
        oToken.amoBurn(alice, 0);
    }
}
