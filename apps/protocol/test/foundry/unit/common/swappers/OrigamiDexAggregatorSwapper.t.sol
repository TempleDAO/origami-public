pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { OrigamiDexAggregatorSwapper } from "contracts/common/swappers/OrigamiDexAggregatorSwapper.sol";

/* solhint-disable func-name-mixedcase, contract-name-camelcase, not-rely-on-time */
contract OrigamiDexAggregatorSwapperTest is OrigamiTest {
    OrigamiDexAggregatorSwapper public swapper;
    address public constant router = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 public constant SDAI = IERC20(0x83F20F44975D03b1b09e64809B757c47f942BEeA);

    event Swap(address indexed sellToken, uint256 sellTokenAmount, address indexed buyToken, uint256 buyTokenAmount);

    function setUp() public {
        fork("mainnet", 18725488);
        swapper = new OrigamiDexAggregatorSwapper(origamiMultisig, router);
    }

    function test_initialization() public {
        assertEq(swapper.owner(), origamiMultisig);
        assertEq(swapper.router(), router);
    }

    function test_access_recoverToken() public {
        expectElevatedAccess();
        swapper.recoverToken(alice, alice, 100e18);
    }

    function test_recoverToken() public {
        check_recoverToken(address(swapper));
    }

    function getQuoteData() internal pure returns (bytes memory) {
        // REQUEST:
        /*
curl -X GET \
"https://api.1inch.dev/swap/v5.2/1/swap?src=0x6b175474e89094c44da98b954eedeac495271d0f&dst=0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48&amount=1000000000000000000000&from=0x1111111254eeb25477b68fb85ed929f73a960582&slippage=0.5&disableEstimate=true" \
-H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
-H "accept: application/json" \
-H "content-type: application/json"
        */

        // RESPONSE:
        /*
{
    "toAmount": "999903781",
    "tx": {
        "from": "0x1111111254eeb25477b68fb85ed929f73a960582",
        "to": "0x1111111254eeb25477b68fb85ed929f73a960582",
        "data": "0xe449022e00000000000000000000000000000000000000000000003635c9adc5dea00000000000000000000000000000000000000000000000000000000000003b4d08c6000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000010000000000000000000000005777d92f208679db4b9778590fa3cab3ac9e21688b1ccac8",
        "value": "0",
        "gas": 0,
        "gasPrice": "45510051129"
    }
}
        */
 
        // Pulled from the quote data above
        return hex"e449022e00000000000000000000000000000000000000000000003635c9adc5dea00000000000000000000000000000000000000000000000000000000000003b4d08c6000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000010000000000000000000000005777d92f208679db4b9778590fa3cab3ac9e21688b1ccac8";
    }

    function test_execute_success() public {
        bytes memory data = getQuoteData();

        uint256 sellTokenAmount = 1_000e18;
        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);
        DAI.approve(address(swapper), sellTokenAmount);

        uint256 expectedBuyTokenAmount = 999.903956e6;
        vm.expectEmit(address(swapper));
        emit Swap(address(DAI), sellTokenAmount, address(USDC), expectedBuyTokenAmount);
        uint256 buyTokenAmount = swapper.execute(DAI, sellTokenAmount, USDC, data);

        assertEq(buyTokenAmount, expectedBuyTokenAmount);
        assertEq(DAI.balanceOf(alice), 0);
        assertEq(DAI.balanceOf(address(swapper)), 0);

        assertEq(USDC.balanceOf(alice), expectedBuyTokenAmount);
        assertEq(USDC.balanceOf(address(swapper)), 0);
    }

    function test_execute_fail_sellRemainder() public {
        bytes memory data = getQuoteData();

        uint256 sellTokenAmount = 1_500e18;
        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.InvalidSwap.selector));
        swapper.execute(DAI, sellTokenAmount, USDC, data);
    }

    function test_execute_fail_badBalance() public {
        bytes memory data = getQuoteData();

        // Send some extra buy tokens into the swapper
        deal(address(USDC), address(swapper), 100e6, true);

        uint256 sellTokenAmount = 1_000e18;
        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.InvalidSwap.selector));
        swapper.execute(DAI, sellTokenAmount, SDAI, data);
    }

    function test_execute_failure_approvalsAtWrapper() public {
        bytes memory data = getQuoteData();

        uint256 sellTokenAmount = 1_000e18;
        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);

        // 1 less for approvals
        DAI.approve(address(swapper), sellTokenAmount-1);
        vm.expectRevert("Dai/insufficient-allowance");
        swapper.execute(DAI, sellTokenAmount, USDC, data);
    }

    function test_execute_failure_balance() public {
        bytes memory data = getQuoteData();

        uint256 sellTokenAmount = 500e18;
        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);

        // The underlying quote is to swap for more than this amount
        DAI.approve(address(swapper), sellTokenAmount);
        vm.expectRevert("Dai/insufficient-balance");
        swapper.execute(DAI, sellTokenAmount, USDC, data);
    }

    function test_execute_failure_customError() public {
        // Bad data - unknown function
        bytes memory data = hex"12345678";

        uint256 sellTokenAmount = 1_000e18;
        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.UnknownSwapError.selector, ""));
        swapper.execute(DAI, sellTokenAmount, USDC, data);
    }

    function test_execute_failure_unknownError() public {
        // Set the proxy to another contract (DAI) to force an unknown error from the `call()`
        swapper = new OrigamiDexAggregatorSwapper(origamiMultisig, address(DAI));
        bytes memory data = hex"12345678";

        uint256 sellTokenAmount = 1_000e18;
        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.UnknownSwapError.selector, ""));
        swapper.execute(DAI, sellTokenAmount, USDC, data);
    }
}
