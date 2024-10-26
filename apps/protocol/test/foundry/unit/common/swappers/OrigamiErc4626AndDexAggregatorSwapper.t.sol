pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { OrigamiErc4626AndDexAggregatorSwapper } from "contracts/common/swappers/OrigamiErc4626AndDexAggregatorSwapper.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/* solhint-disable func-name-mixedcase, contract-name-camelcase, not-rely-on-time */
contract OrigamiErc4626AndDexAggregatorSwapperTestBase is OrigamiTest {
    OrigamiErc4626AndDexAggregatorSwapper public swapper;
    address public constant router = 0x111111125421cA6dc452d289314280a0f8842A65;

    IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC4626 public constant SUSDE = IERC4626(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
    IERC20 public constant USDE = IERC20(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3);
    IERC20 public constant SDAI = IERC20(0x83F20F44975D03b1b09e64809B757c47f942BEeA);

    event Swap(address indexed sellToken, uint256 sellTokenAmount, address indexed buyToken, uint256 buyTokenAmount);
    event RouterWhitelisted(address indexed router, bool allowed);

    error UnknownSwapAmount(uint256 amount);
    error SafeTransferFromFailed();

    function setUp() public {
        fork("mainnet", 19564742);
        swapper = new OrigamiErc4626AndDexAggregatorSwapper(origamiMultisig, address(SUSDE));

        vm.prank(origamiMultisig);
        swapper.whitelistRouter(router, true);
    }
}

contract OrigamiErc4626AndDexAggregatorSwapperTestAdmin is OrigamiErc4626AndDexAggregatorSwapperTestBase {

    function test_initialization() public {
        assertEq(swapper.owner(), origamiMultisig);
        assertEq(address(swapper.vault()), address(SUSDE));
        assertEq(address(swapper.vaultUnderlyingAsset()), address(USDE));
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
}

contract OrigamiErc4626AndDexAggregatorSwapperTestExecute_NonVault is OrigamiErc4626AndDexAggregatorSwapperTestBase {
    function getQuoteData(uint256 fromAmount) internal pure returns (uint256 toAmount, bytes memory swapData) {
        // REQUEST:
        /*
        curl -X GET \
"https://api.1inch.dev/swap/v6.0/1/swap?src=0x6B175474E89094C44Da98b954EedeAC495271d0F&dst=0x83F20F44975D03b1b09e64809B757c47f942BEeA&amount=1000000000000000000000&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true&connectorTokens=0x83F20F44975D03b1b09e64809B757c47f942BEeA" \
-H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
-H "accept: application/json" \
-H "content-type: application/json"
        */

        if (fromAmount == 1_000e18) {
            toAmount = 936.165904258299998815e18;
            swapData = hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000006b175474e89094c44da98b954eedeac495271d0f00000000000000000000000083f20f44975d03b1b09e64809b757c47f942beea000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003635c9adc5dea000000000000000000000000000000000000000000000000000195f87d1a06c64a92d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000bc00000000000000000000000000000000000000000000000000009e000070512083f20f44975d03b1b09e64809b757c47f942beea6b175474e89094c44da98b954eedeac495271d0f00046e553f650000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111125421ca6dc452d289314280a0f8842a650020d6bdbf7883f20f44975d03b1b09e64809b757c47f942beea111111125421ca6dc452d289314280a0f8842a65000000008b1ccac8";
        } else {
            revert UnknownSwapAmount(fromAmount);
        }

        swapData = encode(swapData);
    }

    function encode(bytes memory data) internal pure returns (bytes memory) {
        return abi.encode(OrigamiErc4626AndDexAggregatorSwapper.RouteData({
            routeType: OrigamiErc4626AndDexAggregatorSwapper.RouteType.VIA_DEX_AGGREGATOR_ONLY,
            router: router,
            data: data
        }));
    }

    function test_execute_fail_badEncoding() public {
        uint256 sellTokenAmount = 1_000e18;
        
        // Bad data - unknown function
        bytes memory data = hex"12345678";

        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectRevert();
        swapper.execute(DAI, sellTokenAmount, SDAI, data);
    }

    function test_execute_fail_invalidRouter() public {
        uint256 sellTokenAmount = 1_000e18;
        (, bytes memory data) = getQuoteData(sellTokenAmount);

        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.InvalidRouter.selector, alice));        
        swapper.execute(
            DAI, sellTokenAmount, SDAI, 
            abi.encode(OrigamiErc4626AndDexAggregatorSwapper.RouteData({
                routeType: OrigamiErc4626AndDexAggregatorSwapper.RouteType.VIA_DEX_AGGREGATOR_ONLY,
                router: alice,
                data: data
            }))
        );
    }

    function test_execute_success_normal() public {
        uint256 sellTokenAmount = 1_000e18;
        (uint256 expectedBuyTokenAmount, bytes memory data) = getQuoteData(sellTokenAmount);

        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectEmit(address(swapper));
        emit Swap(address(DAI), sellTokenAmount, address(SDAI), expectedBuyTokenAmount);
        uint256 buyTokenAmount = swapper.execute(DAI, sellTokenAmount, SDAI, data);

        assertEq(buyTokenAmount, expectedBuyTokenAmount);
        assertEq(DAI.balanceOf(alice), 0);
        assertEq(DAI.balanceOf(address(swapper)), 0);

        assertEq(SDAI.balanceOf(alice), expectedBuyTokenAmount);
        assertEq(SDAI.balanceOf(address(swapper)), 0);
    }

    function test_execute_fail_sellRemainder() public {
        (, bytes memory data) = getQuoteData(1_000e18);

        uint256 sellTokenAmount = 1_500e18;
        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.InvalidSwap.selector));
        swapper.execute(DAI, sellTokenAmount, SDAI, data);
    }

    function test_execute_fail_badBalance() public {
        uint256 sellTokenAmount = 1_000e18;
        (, bytes memory data) = getQuoteData(sellTokenAmount);

        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);
        DAI.approve(address(swapper), sellTokenAmount);

        // Swap expecting a different token (sDAI) vs what the swap data say
        // to swap to
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.InvalidSwap.selector));
        swapper.execute(DAI, sellTokenAmount, USDE, data);
    }

    function test_execute_success_donateBuyToken() public {
        uint256 sellTokenAmount = 1_000e18;
        (uint256 expectedBuyTokenAmount, bytes memory data) = getQuoteData(sellTokenAmount);

        // Send some extra buy tokens into the swapper
        uint256 donateAmount = 100e18;
        deal(address(SDAI), address(swapper), donateAmount, false);

        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, false);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectEmit(address(swapper));
        emit Swap(address(DAI), sellTokenAmount, address(SDAI), expectedBuyTokenAmount);
        uint256 buyTokenAmount = swapper.execute(DAI, sellTokenAmount, SDAI, data);

        assertEq(buyTokenAmount, expectedBuyTokenAmount);
        assertEq(DAI.balanceOf(alice), 0);
        assertEq(DAI.balanceOf(address(swapper)), 0);

        assertEq(SDAI.balanceOf(alice), expectedBuyTokenAmount);
        assertEq(SDAI.balanceOf(address(swapper)), donateAmount);
    }

    function test_execute_success_donateSellToken() public {
        uint256 sellTokenAmount = 1_000e18;
        (uint256 expectedBuyTokenAmount, bytes memory data) = getQuoteData(sellTokenAmount);

        // Send some extra sell tokens into the swapper
        uint256 donateAmount = 100e18;
        deal(address(DAI), address(swapper), donateAmount, false);

        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, false);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectEmit(address(swapper));
        emit Swap(address(DAI), sellTokenAmount, address(SDAI), expectedBuyTokenAmount);
        uint256 buyTokenAmount = swapper.execute(DAI, sellTokenAmount, SDAI, data);

        assertEq(buyTokenAmount, expectedBuyTokenAmount);
        assertEq(DAI.balanceOf(alice), 0);
        assertEq(DAI.balanceOf(address(swapper)), donateAmount);

        assertEq(SDAI.balanceOf(alice), expectedBuyTokenAmount);
        assertEq(SDAI.balanceOf(address(swapper)), 0);
    }

    function test_execute_failure_approvalsAtWrapper() public {
        uint256 sellTokenAmount = 1_000e18;
        (, bytes memory data) = getQuoteData(sellTokenAmount);
        
        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);

        // 1 less for approvals
        DAI.approve(address(swapper), sellTokenAmount-1);
        vm.expectRevert("Dai/insufficient-allowance");
        swapper.execute(DAI, sellTokenAmount, SDAI, data);
    }

    function test_execute_failure_balance() public {
        (, bytes memory data) = getQuoteData(1_000e18);

        uint256 sellTokenAmount = 500e18;        
        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);

        // The underlying quote is to swap for more than this amount
        DAI.approve(address(swapper), sellTokenAmount);
        vm.expectRevert(abi.encodeWithSelector(SafeTransferFromFailed.selector));
        swapper.execute(DAI, sellTokenAmount, SDAI, data);
    }

    function test_execute_failure_customError() public {
        // Bad data - unknown function
        bytes memory data = hex"12345678";
        data = encode(data);

        uint256 sellTokenAmount = 1_000e18;
        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.UnknownSwapError.selector, ""));
        swapper.execute(DAI, sellTokenAmount, SDAI, data);
    }

    function test_execute_failure_unknownError() public {
        bytes memory data = hex"12345678";
        data = encode(data);

        uint256 sellTokenAmount = 1_000e18;
        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.UnknownSwapError.selector, ""));
        swapper.execute(DAI, sellTokenAmount, SDAI, data);
    }
}

contract OrigamiErc4626AndDexAggregatorSwapperTestExecute_ToVaultDirect is OrigamiErc4626AndDexAggregatorSwapperTestBase {
    function getQuoteData(uint256 fromAmount) internal pure returns (uint256 toAmount, bytes memory swapData) {
        // REQUEST:
        /*
        curl -X GET \
"https://api.1inch.dev/swap/v6.0/1/swap?src=0x6B175474E89094C44Da98b954EedeAC495271d0F&dst=0x9D39A5DE30e57443BfF2A8307A4256c8797A3497&amount=1000000000000000000000&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true&connectorTokens=0x83F20F44975D03b1b09e64809B757c47f942BEeA" \
-H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
-H "accept: application/json" \
-H "content-type: application/json"
        */

        if (fromAmount == 1_000e18) {
            toAmount = 960.228222625097845353e18;
            swapData = hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000009d39a5de30e57443bff2a8307a4256c8797a3497000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003635c9adc5dea0000000000000000000000000000000000000000000000000001a05e4a42d177a25fd0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001b000000000000000000000000000000000000000000000000000019200016400a007e5c0d2000000000000000000000000000000000000000000000000000140000070512083f20f44975d03b1b09e64809b757c47f942beea6b175474e89094c44da98b954eedeac495271d0f00046e553f650000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd095120167478921b907422f8e88b43c4af2b8bea278d3a83f20f44975d03b1b09e64809b757c47f942beea0044ddc1f59d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001a05e4a42d177a25fd000000000000000000000000111111125421ca6dc452d289314280a0f8842a650020d6bdbf789d39a5de30e57443bff2a8307a4256c8797a3497111111125421ca6dc452d289314280a0f8842a65000000000000000000000000000000008b1ccac8";
        } else {
            revert UnknownSwapAmount(fromAmount);
        }

        swapData = encode(swapData);
    }

    function encode(bytes memory data) internal pure returns (bytes memory) {
        return abi.encode(OrigamiErc4626AndDexAggregatorSwapper.RouteData({
            routeType: OrigamiErc4626AndDexAggregatorSwapper.RouteType.VIA_DEX_AGGREGATOR_ONLY,
            router: router,
            data: data
        }));
    }

    function test_execute_fail_badEncoding() public {
        uint256 sellTokenAmount = 1_000e18;
        
        // Bad data - unknown function
        bytes memory data = hex"12345678";

        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectRevert();
        swapper.execute(DAI, sellTokenAmount, SUSDE, data);
    }

    function test_execute_success_normal() public {
        uint256 sellTokenAmount = 1_000e18;
        (uint256 expectedBuyTokenAmount, bytes memory data) = getQuoteData(sellTokenAmount);

        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectEmit(address(swapper));
        emit Swap(address(DAI), sellTokenAmount, address(SUSDE), expectedBuyTokenAmount);
        uint256 buyTokenAmount = swapper.execute(DAI, sellTokenAmount, SUSDE, data);

        assertEq(buyTokenAmount, expectedBuyTokenAmount);
        assertEq(DAI.balanceOf(alice), 0);
        assertEq(DAI.balanceOf(address(swapper)), 0);

        assertEq(SUSDE.balanceOf(alice), expectedBuyTokenAmount);
        assertEq(SUSDE.balanceOf(address(swapper)), 0);
    }

    function test_execute_fail_sellRemainder() public {
        (, bytes memory data) = getQuoteData(1_000e18);

        uint256 sellTokenAmount = 1_500e18;
        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.InvalidSwap.selector));
        swapper.execute(DAI, sellTokenAmount, SUSDE, data);
    }

    function test_execute_fail_badBalance() public {
        uint256 sellTokenAmount = 1_000e18;
        (, bytes memory data) = getQuoteData(sellTokenAmount);

        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);
        DAI.approve(address(swapper), sellTokenAmount);

        // Swap expecting a different token (SUSDE) vs what the swap data say
        // to swap to
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.InvalidSwap.selector));
        swapper.execute(DAI, sellTokenAmount, USDE, data);
    }

    function test_execute_success_donateBuyToken() public {
        uint256 sellTokenAmount = 1_000e18;
        (uint256 expectedBuyTokenAmount, bytes memory data) = getQuoteData(sellTokenAmount);

        // Send some extra buy tokens into the swapper
        uint256 donateAmount = 100e18;
        deal(address(SUSDE), address(swapper), donateAmount, false);

        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, false);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectEmit(address(swapper));
        emit Swap(address(DAI), sellTokenAmount, address(SUSDE), expectedBuyTokenAmount);
        uint256 buyTokenAmount = swapper.execute(DAI, sellTokenAmount, SUSDE, data);

        assertEq(buyTokenAmount, expectedBuyTokenAmount);
        assertEq(DAI.balanceOf(alice), 0);
        assertEq(DAI.balanceOf(address(swapper)), 0);

        assertEq(SUSDE.balanceOf(alice), expectedBuyTokenAmount);
        assertEq(SUSDE.balanceOf(address(swapper)), donateAmount);
    }

    function test_execute_success_donateSellToken() public {
        uint256 sellTokenAmount = 1_000e18;
        (uint256 expectedBuyTokenAmount, bytes memory data) = getQuoteData(sellTokenAmount);

        // Send some extra sell tokens into the swapper
        uint256 donateAmount = 100e18;
        deal(address(DAI), address(swapper), donateAmount, false);

        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, false);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectEmit(address(swapper));
        emit Swap(address(DAI), sellTokenAmount, address(SUSDE), expectedBuyTokenAmount);
        uint256 buyTokenAmount = swapper.execute(DAI, sellTokenAmount, SUSDE, data);

        assertEq(buyTokenAmount, expectedBuyTokenAmount);
        assertEq(DAI.balanceOf(alice), 0);
        assertEq(DAI.balanceOf(address(swapper)), donateAmount);

        assertEq(SUSDE.balanceOf(alice), expectedBuyTokenAmount);
        assertEq(SUSDE.balanceOf(address(swapper)), 0);
    }

    function test_execute_failure_approvalsAtWrapper() public {
        uint256 sellTokenAmount = 1_000e18;
        (, bytes memory data) = getQuoteData(sellTokenAmount);
        
        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);

        // 1 less for approvals
        DAI.approve(address(swapper), sellTokenAmount-1);
        vm.expectRevert("Dai/insufficient-allowance");
        swapper.execute(DAI, sellTokenAmount, SUSDE, data);
    }

    function test_execute_failure_balance() public {
        (, bytes memory data) = getQuoteData(1_000e18);

        uint256 sellTokenAmount = 500e18;        
        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);

        // The underlying quote is to swap for more than this amount
        DAI.approve(address(swapper), sellTokenAmount);
        vm.expectRevert(abi.encodeWithSelector(SafeTransferFromFailed.selector));
        swapper.execute(DAI, sellTokenAmount, SUSDE, data);
    }

    function test_execute_failure_customError() public {
        // Bad data - unknown function
        bytes memory data = hex"12345678";
        data = encode(data);

        uint256 sellTokenAmount = 1_000e18;
        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.UnknownSwapError.selector, ""));
        swapper.execute(DAI, sellTokenAmount, SUSDE, data);
    }

    function test_execute_failure_unknownError() public {
        bytes memory data = hex"12345678";
        data = encode(data);

        uint256 sellTokenAmount = 1_000e18;
        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.UnknownSwapError.selector, ""));
        swapper.execute(DAI, sellTokenAmount, SUSDE, data);
    }
}

contract OrigamiErc4626AndDexAggregatorSwapperTestExecute_ToVaultWithStake is OrigamiErc4626AndDexAggregatorSwapperTestBase {
    function getQuoteData(uint256 fromAmount) internal view returns (uint256 toAmount, bytes memory swapData) {
        // REQUEST:
        /*
        curl -X GET \
"https://api.1inch.dev/swap/v6.0/1/swap?src=0x6B175474E89094C44Da98b954EedeAC495271d0F&dst=0x4c9EDD5852cd905f086C759E8383e09bff1E68B3&amount=1000000000000000000000&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true&connectorTokens=0x83F20F44975D03b1b09e64809B757c47f942BEeA" \
-H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
-H "accept: application/json" \
-H "content-type: application/json"
        */

        if (fromAmount == 1_000e18) {
            toAmount = 997.594868994230759556e18; // USDe from the swap
            toAmount = SUSDE.previewDeposit(toAmount);
            swapData = hex"83800a8e0000000000000000000000006b175474e89094c44da98b954eedeac495271d0f00000000000000000000000000000000000000000000003635c9adc5dea0000000000000000000000000000000000000000000000000001b068852caf4e942af481000010008010802000000f36a4ba50c603204c3fc6d2da8b78a7b69cbc67d8b1ccac8";
        } else {
            revert UnknownSwapAmount(fromAmount);
        }

        swapData = encode(swapData);
    }

    function encode(bytes memory data) internal pure returns (bytes memory) {
        return abi.encode(OrigamiErc4626AndDexAggregatorSwapper.RouteData({
            routeType: OrigamiErc4626AndDexAggregatorSwapper.RouteType.VIA_DEX_AGGREGATOR_THEN_DEPOSIT_IN_VAULT,
            router: router,
            data: data
        }));
    }

    function test_execute_fail_badEncoding() public {
        uint256 sellTokenAmount = 1_000e18;
        
        // Bad data - unknown function
        bytes memory data = hex"12345678";

        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectRevert();
        swapper.execute(DAI, sellTokenAmount, SUSDE, data);
    }

    function test_execute_success_normal() public {
        uint256 sellTokenAmount = 1_000e18;
        (uint256 expectedBuyTokenAmount, bytes memory data) = getQuoteData(sellTokenAmount);

        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectEmit(address(swapper));
        emit Swap(address(DAI), sellTokenAmount, address(SUSDE), expectedBuyTokenAmount);
        uint256 buyTokenAmount = swapper.execute(DAI, sellTokenAmount, SUSDE, data);

        assertEq(buyTokenAmount, expectedBuyTokenAmount);
        assertEq(DAI.balanceOf(alice), 0);
        assertEq(DAI.balanceOf(address(swapper)), 0);

        assertEq(SUSDE.balanceOf(alice), expectedBuyTokenAmount);
        assertEq(SUSDE.balanceOf(address(swapper)), 0);
    }

    function test_execute_fail_sellRemainder() public {
        (, bytes memory data) = getQuoteData(1_000e18);

        uint256 sellTokenAmount = 1_500e18;
        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.InvalidSwap.selector));
        swapper.execute(DAI, sellTokenAmount, SUSDE, data);
    }

    function test_execute_fail_incorrectToken() public {
        uint256 sellTokenAmount = 1_000e18;
        (, bytes memory data) = getQuoteData(sellTokenAmount);

        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);
        DAI.approve(address(swapper), sellTokenAmount);

        // Swap expecting a different token (sDAI) vs what the swap data say
        // to swap to
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(USDE)));
        swapper.execute(DAI, sellTokenAmount, USDE, data);
    }

    function test_execute_success_donateBuyToken() public {
        uint256 sellTokenAmount = 1_000e18;
        (uint256 expectedBuyTokenAmount, bytes memory data) = getQuoteData(sellTokenAmount);

        // Send some extra buy tokens into the swapper
        uint256 donateAmount = 100e18;
        deal(address(SUSDE), address(swapper), donateAmount, false);

        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, false);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectEmit(address(swapper));
        emit Swap(address(DAI), sellTokenAmount, address(SUSDE), expectedBuyTokenAmount);
        uint256 buyTokenAmount = swapper.execute(DAI, sellTokenAmount, SUSDE, data);

        assertEq(buyTokenAmount, expectedBuyTokenAmount);
        assertEq(DAI.balanceOf(alice), 0);
        assertEq(DAI.balanceOf(address(swapper)), 0);

        assertEq(SUSDE.balanceOf(alice), expectedBuyTokenAmount);
        assertEq(SUSDE.balanceOf(address(swapper)), donateAmount);
    }

    function test_execute_success_donateSellToken() public {
        uint256 sellTokenAmount = 1_000e18;
        (uint256 expectedBuyTokenAmount, bytes memory data) = getQuoteData(sellTokenAmount);

        // Send some extra sell tokens into the swapper
        uint256 donateAmount = 100e18;
        deal(address(DAI), address(swapper), donateAmount, false);

        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, false);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectEmit(address(swapper));
        emit Swap(address(DAI), sellTokenAmount, address(SUSDE), expectedBuyTokenAmount);
        uint256 buyTokenAmount = swapper.execute(DAI, sellTokenAmount, SUSDE, data);

        assertEq(buyTokenAmount, expectedBuyTokenAmount);
        assertEq(DAI.balanceOf(alice), 0);
        assertEq(DAI.balanceOf(address(swapper)), donateAmount);

        assertEq(SUSDE.balanceOf(alice), expectedBuyTokenAmount);
        assertEq(SUSDE.balanceOf(address(swapper)), 0);
    }

    function test_execute_failure_approvalsAtWrapper() public {
        uint256 sellTokenAmount = 1_000e18;
        (, bytes memory data) = getQuoteData(sellTokenAmount);
        
        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);

        // 1 less for approvals
        DAI.approve(address(swapper), sellTokenAmount-1);
        vm.expectRevert("Dai/insufficient-allowance");
        swapper.execute(DAI, sellTokenAmount, SUSDE, data);
    }

    function test_execute_failure_balance() public {
        (, bytes memory data) = getQuoteData(1_000e18);

        uint256 sellTokenAmount = 500e18;        
        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);

        // The underlying quote is to swap for more than this amount
        DAI.approve(address(swapper), sellTokenAmount);
        vm.expectRevert(abi.encodeWithSelector(SafeTransferFromFailed.selector));
        swapper.execute(DAI, sellTokenAmount, SUSDE, data);
    }

    function test_execute_failure_customError() public {
        // Bad data - unknown function
        bytes memory data = hex"12345678";
        data = encode(data);

        uint256 sellTokenAmount = 1_000e18;
        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.UnknownSwapError.selector, ""));
        swapper.execute(DAI, sellTokenAmount, SUSDE, data);
    }

    function test_execute_failure_unknownError() public {
        bytes memory data = hex"12345678";
        data = encode(data);

        uint256 sellTokenAmount = 1_000e18;
        vm.startPrank(alice);
        deal(address(DAI), alice, sellTokenAmount, true);
        DAI.approve(address(swapper), sellTokenAmount);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.UnknownSwapError.selector, ""));
        swapper.execute(DAI, sellTokenAmount, SUSDE, data);
    }
}

contract OrigamiErc4626AndDexAggregatorSwapperTestExecute_FromVault is OrigamiErc4626AndDexAggregatorSwapperTestBase {
    function getQuoteData(uint256 fromAmount) internal pure returns (uint256 toAmount, bytes memory swapData) {
        // REQUEST:
        /*
        curl -X GET \
"https://api.1inch.dev/swap/v6.0/1/swap?src=0x9D39A5DE30e57443BfF2A8307A4256c8797A3497&dst=0x6B175474E89094C44Da98b954EedeAC495271d0F&amount=1000000000000000000000&from=0x0000000000000000000000000000000000000000&slippage=50&disableEstimate=true&connectorTokens=0x83F20F44975D03b1b09e64809B757c47f942BEeA" \
-H "Authorization: Bearer PinnqIP4n9rxYRndzIyWDVrMfmGKUbZG" \
-H "accept: application/json" \
-H "content-type: application/json"
        */

        if (fromAmount == 1_000e18) {
            toAmount = 1_040.975624642966570358e18;
            swapData = hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000009d39a5de30e57443bff2a8307a4256c8797a34970000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003635c9adc5dea0000000000000000000000000000000000000000000000000001c3855d50bf0e2784000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000019c00000000000000000000000000000000000000000000000000017e00015000a007e5c0d200000000000000000000000000000000000000000000000000012c0000b05120167478921b907422f8e88b43c4af2b8bea278d3a9d39a5de30e57443bff2a8307a4256c8797a349700443df0212400000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001a6aba033ef7aca8c6412083f20f44975d03b1b09e64809b757c47f942beea0004ba0876520000000000000000000000000000000000000000000000000000000000000000000000000000000000000000111111125421ca6dc452d289314280a0f8842a65000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090020d6bdbf786b175474e89094c44da98b954eedeac495271d0f111111125421ca6dc452d289314280a0f8842a65000000008b1ccac8";
        } else {
            revert UnknownSwapAmount(fromAmount);
        }

        swapData = encode(swapData);
    }

    function encode(bytes memory data) internal pure returns (bytes memory) {
        return abi.encode(OrigamiErc4626AndDexAggregatorSwapper.RouteData({
            routeType: OrigamiErc4626AndDexAggregatorSwapper.RouteType.VIA_DEX_AGGREGATOR_ONLY,
            router: router,
            data: data
        }));
    }

    function test_execute_fail_badEncoding() public {
        uint256 sellTokenAmount = 1_000e18;
        
        // Bad data - unknown function
        bytes memory data = hex"12345678";

        vm.startPrank(alice);
        deal(address(SUSDE), alice, sellTokenAmount, true);
        SUSDE.approve(address(swapper), sellTokenAmount);

        vm.expectRevert();
        swapper.execute(SUSDE, sellTokenAmount, DAI, data);
    }

    function test_execute_success_normal() public {
        uint256 sellTokenAmount = 1_000e18;
        (uint256 expectedBuyTokenAmount, bytes memory data) = getQuoteData(sellTokenAmount);

        vm.startPrank(alice);
        deal(address(SUSDE), alice, sellTokenAmount, false);
        SUSDE.approve(address(swapper), sellTokenAmount);

        vm.expectEmit(address(swapper));
        emit Swap(address(SUSDE), sellTokenAmount, address(DAI), expectedBuyTokenAmount);
        uint256 buyTokenAmount = swapper.execute(SUSDE, sellTokenAmount, DAI, data);

        assertEq(buyTokenAmount, expectedBuyTokenAmount);
        assertEq(SUSDE.balanceOf(alice), 0);
        assertEq(SUSDE.balanceOf(address(swapper)), 0);

        assertEq(DAI.balanceOf(alice), expectedBuyTokenAmount);
        assertEq(DAI.balanceOf(address(swapper)), 0);
    }

    function test_execute_fail_sellRemainder() public {
        (, bytes memory data) = getQuoteData(1_000e18);

        uint256 sellTokenAmount = 1_500e18;
        vm.startPrank(alice);
        deal(address(SUSDE), alice, sellTokenAmount, true);
        SUSDE.approve(address(swapper), sellTokenAmount);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.InvalidSwap.selector));
        swapper.execute(SUSDE, sellTokenAmount, DAI, data);
    }

    function test_execute_fail_badBalance() public {
        uint256 sellTokenAmount = 1_000e18;
        (, bytes memory data) = getQuoteData(sellTokenAmount);

        vm.startPrank(alice);
        deal(address(SUSDE), alice, sellTokenAmount, true);
        SUSDE.approve(address(swapper), sellTokenAmount);

        // Swap expecting a different token (sSUSDE) vs what the swap data say
        // to swap to
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.InvalidSwap.selector));
        swapper.execute(SUSDE, sellTokenAmount, USDE, data);
    }

    function test_execute_success_donateBuyToken() public {
        uint256 sellTokenAmount = 1_000e18;
        (uint256 expectedBuyTokenAmount, bytes memory data) = getQuoteData(sellTokenAmount);

        // Send some extra buy tokens into the swapper
        uint256 donateAmount = 100e18;
        deal(address(DAI), address(swapper), donateAmount, false);

        vm.startPrank(alice);
        deal(address(SUSDE), alice, sellTokenAmount, false);
        SUSDE.approve(address(swapper), sellTokenAmount);

        vm.expectEmit(address(swapper));
        emit Swap(address(SUSDE), sellTokenAmount, address(DAI), expectedBuyTokenAmount);
        uint256 buyTokenAmount = swapper.execute(SUSDE, sellTokenAmount, DAI, data);

        assertEq(buyTokenAmount, expectedBuyTokenAmount);
        assertEq(SUSDE.balanceOf(alice), 0);
        assertEq(SUSDE.balanceOf(address(swapper)), 0);

        assertEq(DAI.balanceOf(alice), expectedBuyTokenAmount);
        assertEq(DAI.balanceOf(address(swapper)), donateAmount);
    }

    function test_execute_success_donateSellToken() public {
        uint256 sellTokenAmount = 1_000e18;
        (uint256 expectedBuyTokenAmount, bytes memory data) = getQuoteData(sellTokenAmount);

        // Send some extra sell tokens into the swapper
        uint256 donateAmount = 100e18;
        deal(address(SUSDE), address(swapper), donateAmount, false);

        vm.startPrank(alice);
        deal(address(SUSDE), alice, sellTokenAmount, false);
        SUSDE.approve(address(swapper), sellTokenAmount);

        vm.expectEmit(address(swapper));
        emit Swap(address(SUSDE), sellTokenAmount, address(DAI), expectedBuyTokenAmount);
        uint256 buyTokenAmount = swapper.execute(SUSDE, sellTokenAmount, DAI, data);

        assertEq(buyTokenAmount, expectedBuyTokenAmount);
        assertEq(SUSDE.balanceOf(alice), 0);
        assertEq(SUSDE.balanceOf(address(swapper)), donateAmount);

        assertEq(DAI.balanceOf(alice), expectedBuyTokenAmount);
        assertEq(DAI.balanceOf(address(swapper)), 0);
    }

    function test_execute_failure_approvalsAtWrapper() public {
        uint256 sellTokenAmount = 1_000e18;
        (, bytes memory data) = getQuoteData(sellTokenAmount);
        
        vm.startPrank(alice);
        deal(address(SUSDE), alice, sellTokenAmount, true);

        // 1 less for approvals
        SUSDE.approve(address(swapper), sellTokenAmount-1);
        vm.expectRevert("ERC20: insufficient allowance");
        swapper.execute(SUSDE, sellTokenAmount, DAI, data);
    }

    function test_execute_failure_balance() public {
        (, bytes memory data) = getQuoteData(1_000e18);

        uint256 sellTokenAmount = 500e18;        
        vm.startPrank(alice);
        deal(address(SUSDE), alice, sellTokenAmount, true);

        // The underlying quote is to swap for more than this amount
        SUSDE.approve(address(swapper), sellTokenAmount);
        vm.expectRevert(abi.encodeWithSelector(SafeTransferFromFailed.selector));
        swapper.execute(SUSDE, sellTokenAmount, DAI, data);
    }

    function test_execute_failure_customError() public {
        // Bad data - unknown function
        bytes memory data = hex"12345678";
        data = encode(data);

        uint256 sellTokenAmount = 1_000e18;
        vm.startPrank(alice);
        deal(address(SUSDE), alice, sellTokenAmount, true);
        SUSDE.approve(address(swapper), sellTokenAmount);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.UnknownSwapError.selector, ""));
        swapper.execute(SUSDE, sellTokenAmount, DAI, data);
    }

    function test_execute_failure_unknownError() public {
        bytes memory data = hex"12345678";
        data = encode(data);

        uint256 sellTokenAmount = 1_000e18;
        vm.startPrank(alice);
        deal(address(SUSDE), alice, sellTokenAmount, true);
        SUSDE.approve(address(swapper), sellTokenAmount);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.UnknownSwapError.selector, ""));
        swapper.execute(SUSDE, sellTokenAmount, DAI, data);
    }
}
