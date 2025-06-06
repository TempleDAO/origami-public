pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { OrigamiSwapperWithCallback } from "contracts/common/swappers/OrigamiSwapperWithCallback.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { DummyDexRouter } from "contracts/test/common/swappers/DummyDexRouter.sol";
import { IOrigamiSwapCallback } from "contracts/interfaces/common/swappers/IOrigamiSwapCallback.sol";

contract MockBurnableToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}
    
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function allowance(address, address) public pure override returns (uint256) {
        return type(uint256).max;
    }
}

contract MockCallbackHandler is IOrigamiSwapCallback {   
    MockBurnableToken internal immutable token;

    constructor(MockBurnableToken _token) {
        token = _token;
    }

    function swapCallback() external {
        token.burn(token.balanceOf(address(this)));
    }
}

contract OrigamiSwapperWithCallbackTest is OrigamiTest {
    OrigamiSwapperWithCallback internal swapper;
    DummyDexRouter internal router;

    MockBurnableToken internal sellToken;
    MockBurnableToken internal buyToken; 

    MockCallbackHandler internal callbackHandler;

    event Swap(address indexed sellToken, uint256 sellTokenAmount, address indexed buyToken, uint256 buyTokenAmount);
    event RouterWhitelisted(address indexed router, bool allowed);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        sellToken = new MockBurnableToken("SELL_TOKEN", "SELL_TOKEN");
        buyToken = new MockBurnableToken("BUY_TOKEN", "BUY_TOKEN");
        callbackHandler = new MockCallbackHandler(buyToken);
        
        swapper = new OrigamiSwapperWithCallback(origamiMultisig);
        router = new DummyDexRouter();

        doMint(buyToken, address(router), 1_000_000e18);

        vm.startPrank(origamiMultisig);
        swapper.whitelistRouter(address(router), true);

        setExplicitAccess(swapper, address(callbackHandler), IOrigamiSwapper.execute.selector, true);
        vm.stopPrank();
    }

    function test_initialization() public view {
        assertEq(swapper.owner(), origamiMultisig);
        assertEq(swapper.whitelistedRouters(address(router)), true);
        assertEq(swapper.whitelistedRouters(address(alice)), false);
    }

    function test_access_execute() public {
        expectElevatedAccess();
        swapper.execute(sellToken, 100e18, buyToken, encode(100e18, 100e18, 100e18));
    }

    function test_access_whitelistRouter() public {
        expectElevatedAccess();
        swapper.whitelistRouter(alice, true);
    }

    function test_access_recoverToken() public {
        expectElevatedAccess();
        swapper.recoverToken(alice, alice, 100e18);
    }

    function test_whitelistRouter() public {
        vm.startPrank(origamiMultisig);
        assertEq(swapper.whitelistedRouters(alice), false);

        vm.expectEmit(address(swapper));
        emit RouterWhitelisted(alice, true);
        swapper.whitelistRouter(alice, true);
        assertEq(swapper.whitelistedRouters(alice), true);

        vm.expectEmit(address(swapper));
        emit RouterWhitelisted(alice, false);
        swapper.whitelistRouter(alice, false);
        assertEq(swapper.whitelistedRouters(alice), false);
    }

    function test_recoverToken() public {
        check_recoverToken(address(swapper));
    }

    function encode(uint256 sellAmount, uint256 minBuyAmount, uint256 buyTokenToReceiveAmount) internal view returns (bytes memory) {
        return abi.encode(IOrigamiSwapper.RouteDataWithCallback({
            minBuyAmount: minBuyAmount,
            router: address(router),
            receiver: address(callbackHandler),
            data: abi.encodeCall(DummyDexRouter.doExactSwap, (address(sellToken), sellAmount, address(buyToken), buyTokenToReceiveAmount))
        }));
    }

    function test_execute_fail_invalidRouter() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.InvalidRouter.selector, bob));        
        swapper.execute(
            sellToken, 123, buyToken, 
            abi.encode(IOrigamiSwapper.RouteDataWithCallback({
                minBuyAmount: 0,
                router: address(bob),
                receiver: origamiMultisig,
                data: bytes("")
            }))
        );
    }

    function test_execute_success() public {
        uint256 sellTokenAmount = 1_000e18;
        doMint(sellToken, address(swapper), sellTokenAmount);

        vm.startPrank(address(callbackHandler));
        uint256 expectedBuyTokenAmount = 1_000e18;
        vm.expectEmit(address(swapper));
        emit Swap(address(sellToken), sellTokenAmount, address(buyToken), expectedBuyTokenAmount);
        
        uint256 buySupplyBefore = buyToken.totalSupply();

        vm.expectEmit(address(buyToken));
        emit Transfer(address(callbackHandler), address(0), expectedBuyTokenAmount);
        uint256 buyTokenAmount = swapper.execute(
            sellToken,
            sellTokenAmount,
            buyToken, 
            encode(sellTokenAmount, expectedBuyTokenAmount, expectedBuyTokenAmount)
        );

        assertEq(buyTokenAmount, expectedBuyTokenAmount);
        assertEq(sellToken.balanceOf(address(swapper)), 0);
        assertEq(sellToken.balanceOf(address(callbackHandler)), 0);

        assertEq(buyToken.totalSupply(), buySupplyBefore-expectedBuyTokenAmount);
        assertEq(buyToken.balanceOf(address(swapper)), 0);
        assertEq(buyToken.balanceOf(address(callbackHandler)), 0);
    }

    function test_execute_success_sellTokenSurplus() public {
        uint256 sellTokenAmount = 1_000e18;
        uint256 expectedBuyTokenAmount = 1_000e18;
        doMint(sellToken, address(swapper), sellTokenAmount*2);
        uint256 buySupplyBefore = buyToken.totalSupply();

        vm.startPrank(address(callbackHandler));
        uint256 buyTokenAmount = swapper.execute(
            sellToken,
            sellTokenAmount,
            buyToken, 
            encode(sellTokenAmount-1, expectedBuyTokenAmount, expectedBuyTokenAmount)
        );

        assertEq(buyTokenAmount, expectedBuyTokenAmount);
        assertEq(sellToken.balanceOf(address(swapper)), sellTokenAmount+1); // The surplus remains
        assertEq(sellToken.balanceOf(address(callbackHandler)), 0);

        assertEq(buyToken.totalSupply(), buySupplyBefore-expectedBuyTokenAmount);
        assertEq(buyToken.balanceOf(address(swapper)), 0);
        assertEq(buyToken.balanceOf(address(callbackHandler)), 0);
    }

    function test_execute_fail_sellTokenDefecit() public {
        uint256 sellTokenAmount = 1_000e18;
        uint256 expectedBuyTokenAmount = 1_000e18;
        doMint(sellToken, address(swapper), sellTokenAmount*2);

        vm.startPrank(address(callbackHandler));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.InvalidSwap.selector));    
        swapper.execute(
            sellToken,
            sellTokenAmount,
            buyToken, 
            encode(sellTokenAmount+1, expectedBuyTokenAmount, expectedBuyTokenAmount)
        );
    }

    function test_execute_differentReceiver_success() public {
        uint256 sellTokenAmount = 1_000e18;
        doMint(sellToken, address(swapper), sellTokenAmount);

        vm.startPrank(origamiMultisig); // <-- not the callback handler
        uint256 expectedBuyTokenAmount = 1_000e18;
        vm.expectEmit(address(swapper));
        emit Swap(address(sellToken), sellTokenAmount, address(buyToken), expectedBuyTokenAmount);
        
        uint256 buySupplyBefore = buyToken.totalSupply();

        vm.expectEmit(address(buyToken));
        emit Transfer(address(callbackHandler), address(0), expectedBuyTokenAmount);
        uint256 buyTokenAmount = swapper.execute(
            sellToken,
            sellTokenAmount,
            buyToken, 
            encode(sellTokenAmount, expectedBuyTokenAmount, expectedBuyTokenAmount)
        );

        assertEq(buyTokenAmount, expectedBuyTokenAmount);
        assertEq(sellToken.balanceOf(address(swapper)), 0);
        assertEq(sellToken.balanceOf(address(callbackHandler)), 0);

        assertEq(buyToken.totalSupply(), buySupplyBefore-expectedBuyTokenAmount);
        assertEq(buyToken.balanceOf(address(swapper)), 0);
        assertEq(buyToken.balanceOf(address(callbackHandler)), 0);
    }

    function test_execute_fail_slippageExceeded() public {
        uint256 sellTokenAmount = 1_000e18;
        uint256 expectedBuyTokenAmount = 1_000e18;
        uint256 buyTokenToReceiveAmount = expectedBuyTokenAmount - 1;
        doMint(sellToken, address(swapper), sellTokenAmount);
        uint256 buySupplyBefore = buyToken.totalSupply();

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, expectedBuyTokenAmount, buyTokenToReceiveAmount));
        swapper.execute(
            sellToken,
            sellTokenAmount, 
            buyToken, 
            encode(sellTokenAmount, expectedBuyTokenAmount, buyTokenToReceiveAmount)
        );

        assertEq(sellToken.balanceOf(address(swapper)), sellTokenAmount);
        assertEq(buyToken.totalSupply(), buySupplyBefore);
        assertEq(buyToken.balanceOf(address(swapper)), 0);
    }
}
