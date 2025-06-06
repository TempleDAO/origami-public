pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { IOrigamiSwapperWithLiquidityManagement } from
    "contracts/interfaces/common/swappers/IOrigamiSwapperWithLiquidityManagement.sol";
import { OrigamiSwapperWithLiquidityManagement } from
    "contracts/common/swappers/OrigamiSwapperWithLiquidityManagement.sol";
import { IOrigamiSwapCallback } from "contracts/interfaces/common/swappers/IOrigamiSwapCallback.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { IBalancerVault } from "contracts/interfaces/external/balancer/IBalancerVault.sol";
import { IKodiakIsland } from "contracts/interfaces/external/kodiak/IKodiakIsland.sol";
import { IKodiakIslandRouter } from "contracts/interfaces/external/kodiak/IKodiakIslandRouter.sol";
import { DummyDexRouter } from "contracts/test/common/swappers/DummyDexRouter.sol";

contract MockToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function allowance(address, address) public pure override returns (uint256) {
        return type(uint256).max;
    }
}

contract MockBalancerVault {
    using SafeERC20 for IERC20;
    using SafeERC20 for MockToken;

    MockToken public lpToken;
    IERC20 public tokenA;
    IERC20 public tokenB;

    bytes32 public poolId;

    struct UserJoinData {
        uint256 tokenAIn;
        uint256 tokenBIn;
        uint256 lpTokenOut;
    }

    constructor(bytes32 _poolId, MockToken _lpToken, IERC20 _tokenA, IERC20 _tokenB) {
        poolId = _poolId;
        lpToken = _lpToken;
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function joinPool(
        bytes32 _poolId,
        address sender,
        address recipient,
        IBalancerVault.JoinPoolRequest memory request
    )
        external
    {
        require(_poolId == poolId, "Invalid pool ID");
        UserJoinData memory userData = abi.decode(request.userData, (UserJoinData));

        if (userData.tokenAIn > 0) {
            tokenA.safeTransferFrom(sender, address(this), userData.tokenAIn);
        }
        if (userData.tokenBIn > 0) {
            tokenB.safeTransferFrom(sender, address(this), userData.tokenBIn);
        }

        // Mint LP tokens to recipient
        lpToken.mint(recipient, userData.lpTokenOut);
    }
}

contract MockOrigamiSwapCallback is IOrigamiSwapCallback {
    event SwapCallback();

    function swapCallback() external override {
        emit SwapCallback();
    }
}

// Mock implementation of OrigamiSwapperWithLiquidityManagement for testing
contract OrigamiSwapperWithLiquidityManagementTest is OrigamiTest {
    IERC20 internal rewardToken;
    IERC20 internal lpToken;
    IERC20 internal tokenA;
    IERC20 internal tokenB;

    OrigamiSwapperWithLiquidityManagement public swapper;
    MockOrigamiSwapCallback internal receiver;

    event SwapCallback();
    event Swap(address indexed sellToken, uint256 sellTokenAmount, address indexed buyToken, uint256 buyTokenAmount);
    event RouterWhitelisted(address indexed router, bool allowed);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function encodeSwap(
        address router,
        address sellToken,
        uint256 sellAmount,
        address buyToken,
        uint256 minBuyAmount,
        uint256 buyTokenToReceiveAmount
    )
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(
            IOrigamiSwapperWithLiquidityManagement.SwapParams({
                router: router,
                minBuyAmount: minBuyAmount,
                swapData: abi.encodeCall(
                    DummyDexRouter.doExactSwap, (sellToken, sellAmount, buyToken, buyTokenToReceiveAmount)
                )
            })
        );
    }

    function mockJoinPoolRequest(
        uint256 tokenAIn,
        uint256 tokenBIn,
        uint256 lpTokenOut
    )
        internal
        pure
        returns (IBalancerVault.JoinPoolRequest memory request)
    {
        return IBalancerVault.JoinPoolRequest({
            assets: new address[](2),
            maxAmountsIn: new uint256[](2),
            userData: abi.encode(
                MockBalancerVault.UserJoinData({ tokenAIn: tokenAIn, tokenBIn: tokenBIn, lpTokenOut: lpTokenOut })
            ),
            fromInternalBalance: false
        });
    }

    /// @dev helpful function to create a TokenAmount[] for the mock tokens
    function createTokenAmounts(
        uint256 amountA,
        uint256 amountB
    )
        internal
        view
        returns (IOrigamiSwapperWithLiquidityManagement.TokenAmount[] memory)
    {
        IOrigamiSwapperWithLiquidityManagement.TokenAmount[] memory tokenAmounts =
            new IOrigamiSwapperWithLiquidityManagement.TokenAmount[](2);
        tokenAmounts[0] =
            IOrigamiSwapperWithLiquidityManagement.TokenAmount({ token: address(tokenA), amount: amountA });
        tokenAmounts[1] =
            IOrigamiSwapperWithLiquidityManagement.TokenAmount({ token: address(tokenB), amount: amountB });
        return tokenAmounts;
    }
}

contract OrigamiSwapperWithLiquidityManagementTest_Basic is OrigamiSwapperWithLiquidityManagementTest {
    MockBalancerVault public mockBalancerVault;
    DummyDexRouter public swapRouter;

    // Pool ID for the mock pool
    bytes32 internal poolId = 0x2c4a603a2aa5596287a06886862dc29d56dbc35400010000000000000000000a;

    function setUp() public virtual {
        MockToken mockLpToken = new MockToken("LP Token", "LP");
        lpToken = mockLpToken;
        rewardToken = new MockToken("Reward Token", "REWARD");
        tokenA = new MockToken("Token A", "TOKENA");
        tokenB = new MockToken("Token B", "TOKENB");

        // Create swapper with mock tokens
        swapRouter = new DummyDexRouter();
        swapper = new OrigamiSwapperWithLiquidityManagement(origamiMultisig, address(mockLpToken));
        mockBalancerVault = new MockBalancerVault(poolId, mockLpToken, tokenA, tokenB);
        receiver = new MockOrigamiSwapCallback();

        doMint(tokenA, address(swapRouter), 1_000_000e18);
        doMint(tokenB, address(swapRouter), 1_000_000e18);

        vm.startPrank(origamiMultisig);
        swapper.whitelistRouter(address(mockBalancerVault), true);
        swapper.whitelistRouter(address(swapRouter), true);
        vm.stopPrank();
    }

    function test_initialization() public view {
        assertEq(swapper.owner(), origamiMultisig);
        assertEq(swapper.whitelistedRouters(address(mockBalancerVault)), true);
        assertEq(swapper.whitelistedRouters(address(alice)), false);
    }

    function test_access_execute() public {
        expectElevatedAccess();
        swapper.execute(
            rewardToken,
            100e18,
            tokenA,
            encodeSwap(address(swapRouter), address(rewardToken), 100e18, address(tokenA), 100e18, 100e18)
        );
    }

    function test_access_whitelistRouter() public {
        expectElevatedAccess();
        swapper.whitelistRouter(alice, true);
    }

    function test_access_recoverToken() public {
        expectElevatedAccess();
        swapper.recoverToken(alice, alice, 100e18);
    }

    function test_access_addLiquidity() public {
        expectElevatedAccess();
        swapper.addLiquidity(new IOrigamiSwapperWithLiquidityManagement.TokenAmount[](2), bytes(""));
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

    function test_execute_fail_invalidRouter() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.InvalidRouter.selector, bob));
        swapper.execute(
            rewardToken,
            1,
            tokenA,
            abi.encode(
                IOrigamiSwapperWithLiquidityManagement.SwapParams({ router: bob, minBuyAmount: 0, swapData: bytes("") })
            )
        );
    }

    function test_addLiquidity_fail_invalidRouter() public {
        bytes memory addLiquidityParams = abi.encode(
            IOrigamiSwapperWithLiquidityManagement.AddLiquidityParams({
                liquidityRouter: alice,
                receiver: alice,
                minLpOutputAmount: 0,
                callData: bytes("")
            })
        );

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.InvalidRouter.selector, alice));
        swapper.addLiquidity(new IOrigamiSwapperWithLiquidityManagement.TokenAmount[](0), addLiquidityParams);
    }
}

contract OrigamiSwapperWithLiquidityManagementTest_Swap is OrigamiSwapperWithLiquidityManagementTest_Basic {
    function test_execute_success() public {
        uint256 sellTokenAmount = 1000e18;
        doMint(rewardToken, address(swapper), sellTokenAmount);

        uint256 expectedBuyTokenAmount = 1000e18;

        vm.expectEmit(address(tokenA));
        emit Transfer(address(swapRouter), address(swapper), expectedBuyTokenAmount);

        vm.expectEmit(address(swapper));
        emit Swap(address(rewardToken), sellTokenAmount, address(tokenA), expectedBuyTokenAmount);

        vm.startPrank(origamiMultisig);
        uint256 buyTokenAmount = swapper.execute(
            rewardToken,
            sellTokenAmount,
            tokenA,
            encodeSwap(
                address(swapRouter),
                address(rewardToken),
                sellTokenAmount,
                address(tokenA),
                expectedBuyTokenAmount,
                expectedBuyTokenAmount
            )
        );

        assertEq(buyTokenAmount, expectedBuyTokenAmount);
        assertEq(rewardToken.balanceOf(address(swapper)), 0);
        assertEq(tokenA.balanceOf(address(swapper)), expectedBuyTokenAmount);
    }

    function test_execute_fail_slippageExceeded() public {
        uint256 sellTokenAmount = 1000e18;
        uint256 expectedBuyTokenAmount = 1000e18;
        uint256 buyTokenToReceiveAmount = expectedBuyTokenAmount - 1;
        doMint(rewardToken, address(swapper), sellTokenAmount);

        vm.startPrank(origamiMultisig);
        vm.expectRevert(
            abi.encodeWithSelector(
                CommonEventsAndErrors.Slippage.selector, expectedBuyTokenAmount, buyTokenToReceiveAmount
            )
        );
        swapper.execute(
            rewardToken,
            sellTokenAmount,
            tokenA,
            encodeSwap(
                address(swapRouter),
                address(rewardToken),
                sellTokenAmount,
                address(tokenA),
                expectedBuyTokenAmount,
                buyTokenToReceiveAmount
            )
        );

        assertEq(rewardToken.balanceOf(address(swapper)), sellTokenAmount);
        assertEq(tokenA.balanceOf(address(swapper)), 0);
    }

    function test_execute_fail_sellTokenSurplus() public {
        uint256 sellTokenAmount = 1_000e18;
        uint256 expectedBuyTokenAmount = 1000e6;
        bytes memory data = abi.encodeCall(
            DummyDexRouter.doExactSwap, 
            (address(rewardToken), sellTokenAmount-1, address(tokenA), expectedBuyTokenAmount)
        );

        deal(address(rewardToken), address(swapper), sellTokenAmount*2, true);
        vm.startPrank(origamiMultisig);

        // vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.InvalidSwap.selector));
        uint256 buyTokenAmount = swapper.execute(
            rewardToken,
            sellTokenAmount,
            tokenA,
            abi.encode(
                IOrigamiSwapperWithLiquidityManagement.SwapParams({
                    router: address(swapRouter),
                    minBuyAmount: 0,
                    swapData: data
                })
            )
        );

        assertEq(buyTokenAmount, expectedBuyTokenAmount);
        assertEq(rewardToken.balanceOf(address(swapper)), sellTokenAmount+1);
        assertEq(tokenA.balanceOf(address(swapper)), expectedBuyTokenAmount);
    }

    function test_execute_fail_sellTokenDefecit() public {
        uint256 sellTokenAmount = 1_000e18;
        bytes memory data = abi.encodeCall(
            DummyDexRouter.doExactSwap, 
            (address(rewardToken), sellTokenAmount+1, address(tokenA), 1000e6)
        );

        deal(address(rewardToken), address(swapper), sellTokenAmount*2, true);
        vm.startPrank(origamiMultisig);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.InvalidSwap.selector));
        swapper.execute(
            rewardToken,
            sellTokenAmount,
            tokenA,
            abi.encode(
                IOrigamiSwapperWithLiquidityManagement.SwapParams({
                    router: address(swapRouter),
                    minBuyAmount: 0,
                    swapData: data
                })
            )
        );
    }

    function test_execute_success_multicall() public {
        uint256 sellTokenAmount = 2000e18;
        doMint(rewardToken, address(swapper), sellTokenAmount);

        // split in half and buy 3000 tokenA and 4000 tokenB
        vm.expectEmit(address(tokenA));
        emit Transfer(address(swapRouter), address(swapper), 3000e18);

        vm.expectEmit(address(swapper));
        emit Swap(address(rewardToken), 1000e18, address(tokenA), 3000e18);

        vm.expectEmit(address(tokenB));
        emit Transfer(address(swapRouter), address(swapper), 4000e18);

        vm.expectEmit(address(swapper));
        emit Swap(address(rewardToken), 1000e18, address(tokenB), 4000e18);

        vm.startPrank(origamiMultisig);
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(
            OrigamiSwapperWithLiquidityManagement.execute.selector,
            rewardToken,
            1000e18,
            tokenA,
            encodeSwap(address(swapRouter), address(rewardToken), 1000e18, address(tokenA), 3000e18, 3000e18)
        );
        data[1] = abi.encodeWithSelector(
            OrigamiSwapperWithLiquidityManagement.execute.selector,
            rewardToken,
            1000e18,
            tokenB,
            encodeSwap(address(swapRouter), address(rewardToken), 1000e18, address(tokenB), 4000e18, 4000e18)
        );
        swapper.multicall(data);

        assertEq(rewardToken.balanceOf(address(swapper)), 0);
        assertEq(tokenA.balanceOf(address(swapper)), 3000e18);
        assertEq(tokenB.balanceOf(address(swapper)), 4000e18);
    }

    function test_execute_fail_multicallAtomic() public {
        uint256 sellTokenAmount = 2000e18;
        doMint(rewardToken, address(swapper), sellTokenAmount);

        vm.startPrank(origamiMultisig);
        bytes[] memory data = new bytes[](2);

        // fail on the first swap
        uint256 expectedBuyTokenA = 3000e18;
        uint256 tokenAToReceive = expectedBuyTokenA - 1;
        data[0] = abi.encodeWithSelector(
            OrigamiSwapperWithLiquidityManagement.execute.selector,
            rewardToken,
            1000e18,
            tokenA,
            encodeSwap(
                address(swapRouter), address(rewardToken), 1000e18, address(tokenA), expectedBuyTokenA, tokenAToReceive
            )
        );
        data[1] = abi.encodeWithSelector(
            OrigamiSwapperWithLiquidityManagement.execute.selector,
            rewardToken,
            1000e18,
            tokenB,
            encodeSwap(address(swapRouter), address(rewardToken), 1000e18, address(tokenB), 4000e18, 4000e18)
        );
        // error is bubbled up
        vm.expectRevert(
            abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, expectedBuyTokenA, tokenAToReceive)
        );
        swapper.multicall(data);

        // no tokens were exchanged
        assertEq(rewardToken.balanceOf(address(swapper)), 2000e18);
        assertEq(tokenA.balanceOf(address(swapper)), 0);
        assertEq(tokenB.balanceOf(address(swapper)), 0);

        // fail on the second swap
        uint256 expectedBuyTokenB = 4000e18;
        uint256 tokenBToReceive = expectedBuyTokenB - 1;
        data[0] = abi.encodeWithSelector(
            OrigamiSwapperWithLiquidityManagement.execute.selector,
            rewardToken,
            1000e18,
            tokenA,
            encodeSwap(address(swapRouter), address(rewardToken), 1000e18, address(tokenA), 3000e18, 3000e18)
        );
        data[1] = abi.encodeWithSelector(
            OrigamiSwapperWithLiquidityManagement.execute.selector,
            rewardToken,
            1000e18,
            tokenB,
            encodeSwap(
                address(swapRouter), address(rewardToken), 1000e18, address(tokenB), expectedBuyTokenB, tokenBToReceive
            )
        );
        // error is bubbled up
        vm.expectRevert(
            abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, expectedBuyTokenB, tokenBToReceive)
        );
        swapper.multicall(data);

        // no tokens were exchanged
        assertEq(rewardToken.balanceOf(address(swapper)), 2000e18);
        assertEq(tokenA.balanceOf(address(swapper)), 0);
        assertEq(tokenB.balanceOf(address(swapper)), 0);

        // fail on second swap for a different reason
        data[0] = abi.encodeWithSelector(
            OrigamiSwapperWithLiquidityManagement.execute.selector,
            rewardToken,
            1000e18,
            tokenA,
            encodeSwap(address(swapRouter), address(rewardToken), 1000e18, address(tokenA), 3000e18, 3000e18)
        );
        data[1] = abi.encodeWithSelector(
            OrigamiSwapperWithLiquidityManagement.execute.selector,
            rewardToken,
            1000e18,
            tokenA, // put the wrong buy token here
            encodeSwap(address(swapRouter), address(rewardToken), 1000e18, address(tokenB), 4000e18, 4000e18)
        );
        // error is bubbled up
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSwapper.InvalidSwap.selector));
        swapper.multicall(data);

        // no tokens were exchanged
        assertEq(rewardToken.balanceOf(address(swapper)), 2000e18);
        assertEq(tokenA.balanceOf(address(swapper)), 0);
        assertEq(tokenB.balanceOf(address(swapper)), 0);
    }

    function test_execute_fail_multicallPermissions() public {
        uint256 sellTokenAmount = 2000e18;
        doMint(rewardToken, address(swapper), sellTokenAmount);

        vm.startPrank(alice);
        bytes[] memory data = new bytes[](2);

        data[0] = abi.encodeWithSelector(
            OrigamiSwapperWithLiquidityManagement.execute.selector,
            rewardToken,
            1000e18,
            tokenA,
            encodeSwap(address(swapRouter), address(rewardToken), 1000e18, address(tokenA), 4000, 4000)
        );
        data[1] = abi.encodeWithSelector(
            OrigamiSwapperWithLiquidityManagement.execute.selector,
            rewardToken,
            1000e18,
            tokenB,
            encodeSwap(address(swapRouter), address(rewardToken), 1000e18, address(tokenB), 4000e18, 4000e18)
        );
        // error is bubbled up
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        swapper.multicall(data);
    }
}

contract OrigamiSwapperWithLiquidityManagementTest_AddLiquidity is OrigamiSwapperWithLiquidityManagementTest_Basic {
    function setUp() public override {
        super.setUp();
    }

    function test_addLiquidity_success() public {
        // mint LP addLiquidity tokens to origamiMultisig
        uint256 wBeraAmount = 100e18;
        uint256 honeyAmount = 250e18;
        doMint(tokenA, address(swapper), wBeraAmount);
        doMint(tokenB, address(swapper), honeyAmount);

        // dictate the mockBalancerVault to release a certain amount of LP tokens
        uint256 expectedLpAmount = 100e18;

        // Prepare addLiquidity parameters
        bytes memory addLiquidityParams = abi.encode(
            IOrigamiSwapperWithLiquidityManagement.AddLiquidityParams({
                liquidityRouter: address(mockBalancerVault),
                receiver: address(receiver), // <--- different to the caller
                minLpOutputAmount: 0,
                callData: abi.encodeWithSignature(
                    "joinPool(bytes32,address,address,(address[],uint256[],bytes,bool))",
                    poolId,
                    address(swapper),
                    address(swapper), // via swapper so that it can check output amount
                    mockJoinPoolRequest(wBeraAmount, honeyAmount, expectedLpAmount)
                )
            })
        );

        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(receiver));
        emit SwapCallback();
        uint256 lpAmount = swapper.addLiquidity(createTokenAmounts(wBeraAmount, honeyAmount), addLiquidityParams);

        // check that the correct amount of LP tokens were sent to the receiver
        assertEq(lpToken.balanceOf(address(swapper)), 0);
        assertEq(lpToken.balanceOf(address(receiver)), lpAmount);
        assertEq(lpAmount, expectedLpAmount);
    }

    function test_addLiquidity_successWithDonation() public {
        // mint LP addLiquidity tokens to origamiMultisig
        uint256 wBeraAmount = 100e18;
        uint256 honeyAmount = 250e18;
        doMint(tokenA, address(swapper), wBeraAmount);
        doMint(tokenB, address(swapper), honeyAmount);

        // dictate the mockBalancerVault to release a certain amount of LP tokens
        uint256 expectedLpAmount = 100e18;

        // Prepare addLiquidity parameters
        bytes memory addLiquidityParams = abi.encode(
            IOrigamiSwapperWithLiquidityManagement.AddLiquidityParams({
                liquidityRouter: address(mockBalancerVault),
                receiver: address(receiver), // <--- different to the caller
                minLpOutputAmount: 0,
                callData: abi.encodeWithSignature(
                    "joinPool(bytes32,address,address,(address[],uint256[],bytes,bool))",
                    poolId,
                    address(swapper),
                    address(swapper), // via swapper so that it can check output amount
                    mockJoinPoolRequest(wBeraAmount, honeyAmount, expectedLpAmount)
                )
            })
        );

        doMint(lpToken, address(swapper), 123_456e18);

        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(receiver));
        emit SwapCallback();
        uint256 lpAmount = swapper.addLiquidity(createTokenAmounts(wBeraAmount, honeyAmount), addLiquidityParams);

        // check that the correct amount of LP tokens were sent to the receiver
        assertEq(lpToken.balanceOf(address(swapper)), 123_456e18);
        assertEq(lpToken.balanceOf(address(receiver)), lpAmount);
        assertEq(lpAmount, expectedLpAmount);
    }

    function test_addLiquidity_fail_insufficientOutputLp() public {
        // mint LP addLiquidity tokens to origamiMultisig
        uint256 wBeraAmount = 100e18;
        uint256 honeyAmount = 250e18;
        doMint(tokenA, address(swapper), wBeraAmount);
        doMint(tokenB, address(swapper), honeyAmount);

        // dictate the mockBalancerVault to release a certain amount of LP tokens
        uint256 expectedLpAmount = 100e18;
        uint256 minLpOutputAmount = expectedLpAmount + 1;

        // Prepare addLiquidity parameters
        bytes memory addLiquidityParams = abi.encode(
            IOrigamiSwapperWithLiquidityManagement.AddLiquidityParams({
                liquidityRouter: address(mockBalancerVault),
                receiver: address(receiver),
                minLpOutputAmount: minLpOutputAmount,
                callData: abi.encodeWithSignature(
                    "joinPool(bytes32,address,address,(address[],uint256[],bytes,bool))",
                    poolId,
                    address(swapper),
                    address(swapper), // via swapper so that it can check output amount
                    mockJoinPoolRequest(wBeraAmount, honeyAmount, expectedLpAmount)
                )
            })
        );

        vm.expectRevert(
            abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, minLpOutputAmount, expectedLpAmount)
        );
        vm.startPrank(origamiMultisig);
        uint256 lpAmount = swapper.addLiquidity(createTokenAmounts(wBeraAmount, honeyAmount), addLiquidityParams);

        assertEq(tokenA.balanceOf(address(swapper)), wBeraAmount);
        assertEq(tokenB.balanceOf(address(swapper)), honeyAmount);
        assertEq(lpToken.balanceOf(address(swapper)), 0);
        assertEq(lpAmount, 0);
    }

    function test_addLiquidity_fail_insufficientOutputLpWithDonation() public {
        // mint LP addLiquidity tokens to origamiMultisig
        uint256 wBeraAmount = 100e18;
        uint256 honeyAmount = 250e18;
        doMint(tokenA, address(swapper), wBeraAmount);
        doMint(tokenB, address(swapper), honeyAmount);

        // dictate the mockBalancerVault to release a certain amount of LP tokens
        uint256 expectedLpAmount = 100e18;
        uint256 minLpOutputAmount = expectedLpAmount + 1;

        // Prepare addLiquidity parameters
        bytes memory addLiquidityParams = abi.encode(
            IOrigamiSwapperWithLiquidityManagement.AddLiquidityParams({
                liquidityRouter: address(mockBalancerVault),
                receiver: address(receiver),
                minLpOutputAmount: minLpOutputAmount,
                callData: abi.encodeWithSignature(
                    "joinPool(bytes32,address,address,(address[],uint256[],bytes,bool))",
                    poolId,
                    address(swapper),
                    address(swapper), // via swapper so that it can check output amount
                    mockJoinPoolRequest(wBeraAmount, honeyAmount, expectedLpAmount)
                )
            })
        );

        vm.expectRevert(
            abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, minLpOutputAmount, expectedLpAmount)
        );
        vm.startPrank(origamiMultisig);
        uint256 lpAmount = swapper.addLiquidity(createTokenAmounts(wBeraAmount, honeyAmount), addLiquidityParams);

        assertEq(tokenA.balanceOf(address(swapper)), wBeraAmount);
        assertEq(tokenB.balanceOf(address(swapper)), honeyAmount);
        assertEq(lpToken.balanceOf(address(swapper)), 0);
        assertEq(lpAmount, 0);
    }
}

/**
 * Bepolia testnet forked tests for BexVaults
 */
contract OrigamiSwapperWithLiquidityManagementForkedTest_AddLiquidity_Balancer is
    OrigamiSwapperWithLiquidityManagementTest
{
    IBalancerVault public bexVault = IBalancerVault(0x708cA656b68A6b7384a488A36aD33505a77241FE);
    bytes32 public constant poolId = 0xe48463c7c26287133d86485985f71f8f52d5dd9c000200000000000000000003; // WBERA |
        // HONEY
    uint8 public constant EXACT_TOKENS_IN_FOR_BPT_OUT = 1;

    function setUp() public {
        fork("berachain_bepolia_testnet", 1_395_164);

        lpToken = IERC20(0xE48463c7C26287133d86485985f71F8F52d5Dd9c); // WBERA | HONEY LP
        receiver = new MockOrigamiSwapCallback();
        tokenA = IERC20(0x6969696969696969696969696969696969696969); // WBERA
        tokenB = IERC20(0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce); // HONEY

        swapper = new OrigamiSwapperWithLiquidityManagement(origamiMultisig, address(lpToken));
        receiver = new MockOrigamiSwapCallback();

        vm.prank(origamiMultisig);
        swapper.whitelistRouter(address(bexVault), true);
    }

    function joinPoolRequest(
        uint256 tokenAAmount,
        uint256 tokenBAmount
    )
        internal
        view
        returns (IBalancerVault.JoinPoolRequest memory request)
    {
        address[] memory assets = new address[](2);
        assets[0] = address(tokenA);
        assets[1] = address(tokenB);

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = tokenAAmount;
        maxAmountsIn[1] = tokenBAmount;

        // userData
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = tokenAAmount;
        amountsIn[1] = tokenBAmount;
        uint256 minimumBptOut = 0;
        bytes memory userData = abi.encode(EXACT_TOKENS_IN_FOR_BPT_OUT, amountsIn, minimumBptOut);

        return IBalancerVault.JoinPoolRequest({
            assets: assets,
            maxAmountsIn: maxAmountsIn,
            userData: userData,
            fromInternalBalance: false
        });
    }

    // NOTE(chachlex): tokens in the pool are highly imbalanced at the moment, may be worth updating the snapshot later
    function test_getPoolBalances() public view {
        (address[] memory tokens, uint256[] memory balances,) = bexVault.getPoolTokens(poolId);
        assertEq(tokens.length, 2);
        assertEq(tokens[0], address(tokenA));
        assertEq(tokens[1], address(tokenB));
        assertEq(balances[0], 78_894.136517022017253284e18);
        assertEq(balances[1], 363_289_966_956_184);
    }

    function test_addLiquidity_success() public {
        // addLiquidity tokens to the swapper
        uint256 tokenAAmount = 100e18;
        uint256 tokenBAmount = 250e18;

        doMint(tokenA, address(swapper), tokenAAmount);
        doMint(tokenB, address(swapper), tokenBAmount);

        // Prepare addLiquidity parameters
        bytes memory addLiquidityParams = abi.encode(
            IOrigamiSwapperWithLiquidityManagement.AddLiquidityParams({
                liquidityRouter: address(bexVault),
                receiver: address(receiver),
                minLpOutputAmount: 0,
                callData: abi.encodeWithSignature(
                    "joinPool(bytes32,address,address,(address[],uint256[],bytes,bool))",
                    poolId,
                    address(swapper),
                    address(swapper), // via swapper so that it can check output amount
                    joinPoolRequest(tokenAAmount, tokenBAmount)
                )
            })
        );

        vm.startPrank(origamiMultisig);
        uint256 lpAmount = swapper.addLiquidity(createTokenAmounts(tokenAAmount, tokenBAmount), addLiquidityParams);
        assertEq(lpAmount, 8797.205511899380203628e18);
        assertEq(lpToken.balanceOf(address(receiver)), lpAmount);
        assertEq(tokenA.balanceOf(address(swapper)), 0);
        assertEq(tokenB.balanceOf(address(swapper)), 0);
    }
}

contract MockKodiakRouter {
    using SafeERC20 for IERC20;

    IKodiakIslandRouter internal constant KODIAK_ROUTER = IKodiakIslandRouter(0x679a7C63FC83b6A4D9C1F931891d705483d4791F);

    uint128 internal amount0Pct = 100;
    uint128 internal amount1Pct = 100;

    function setPcts(uint128 amount0Pct_, uint128 amount1Pct_) external {
        amount0Pct = amount0Pct_;
        amount1Pct = amount1Pct_;
    }

    function addLiquidity(
        IKodiakIsland island,
        uint256 amount0Max,
        uint256 amount1Max,
        uint256 amount0Min,
        uint256 amount1Min,
        uint256 amountSharesMin,
        address receiver
    ) external returns (uint256 amount0, uint256 amount1, uint256 mintAmount) {
        // Do slightly less so there's left over allowance
        amount0 = amount0Max*amount0Pct/100;
        amount1 = amount1Max*amount1Pct/100;

        IERC20 t0 = island.token0();
        IERC20 t1 = island.token1();
        t0.safeTransferFrom(msg.sender, address(this), amount0);
        t0.forceApprove(address(KODIAK_ROUTER), amount0);
        t1.safeTransferFrom(msg.sender, address(this), amount1);
        t1.forceApprove(address(KODIAK_ROUTER), amount1);
        return KODIAK_ROUTER.addLiquidity(address(island), amount0, amount1, amount0Min, amount1Min, amountSharesMin, receiver);
    }
}

/**
 * Bera mainnet forked tests for Kodiak Vaults
 */
contract OrigamiSwapperWithLiquidityManagementForkedTest_AddLiquidity_Kodiak is OrigamiSwapperWithLiquidityManagementTest {
    using OrigamiMath for uint256;

    IKodiakIslandRouter internal kodiakRouter = IKodiakIslandRouter(0x679a7C63FC83b6A4D9C1F931891d705483d4791F);
    IKodiakIsland internal kodiakIsland = IKodiakIsland(0x98bDEEde9A45C28d229285d9d6e9139e9F505391);
    address[] internal tokens;

    function setUp() public {
        fork("berachain_mainnet", 3_063_463);
        tokenA = IERC20(0x18878Df23e2a36f81e820e4b47b4A40576D3159C); // OHM
        tokenB = IERC20(0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce); // HONEY

        swapper = new OrigamiSwapperWithLiquidityManagement(origamiMultisig, address(kodiakIsland));
        receiver = new MockOrigamiSwapCallback();

        vm.prank(origamiMultisig);
        swapper.whitelistRouter(address(kodiakRouter), true);
    }

    function test_addLiquidity_success() public {
        // mint tokens to the swapper (simulate after swaps have occurred)
        uint256 tokenAAmount = 1e18;
        uint256 tokenBAmount = 25e18; // roughly in proportion to the price at snapshot
        doMint(tokenA, address(swapper), tokenAAmount);
        doMint(tokenB, address(swapper), tokenBAmount);

        (uint256 amount0, uint256 amount1, uint256 expectedMintAmount) =
            kodiakIsland.getMintAmounts(tokenAAmount, tokenBAmount);

        uint256 slippageBps = 100; // 1%
        uint256 minLpOutputAmount = expectedMintAmount.subtractBps(slippageBps, OrigamiMath.Rounding.ROUND_DOWN);

        // Prepare addLiquidity parameters
        bytes memory addLiquidityParams = abi.encode(
            IOrigamiSwapperWithLiquidityManagement.AddLiquidityParams({
                liquidityRouter: address(kodiakRouter),
                receiver: address(receiver),
                minLpOutputAmount: minLpOutputAmount,
                callData: abi.encodeWithSignature(
                    "addLiquidity(address,uint256,uint256,uint256,uint256,uint256,address)",
                    address(kodiakIsland),
                    amount0,
                    amount1,
                    0, // slippage covered by minLpOutputAmount in KodiakRouter and OrigamiSwapper
                    0,
                    minLpOutputAmount,
                    address(swapper)
                )
            })
        );

        vm.startPrank(origamiMultisig);
        uint256 lpAmount = swapper.addLiquidity(createTokenAmounts(amount0, amount1), addLiquidityParams);

        // Check that tokens were transferred and LP tokens were received, dust amounts of the LP tokens are expected
        assertEq(tokenA.balanceOf(address(swapper)), 999_999_997_447_600_815);
        assertEq(tokenB.balanceOf(address(swapper)), 19_568);
        assertEq(kodiakIsland.balanceOf(address(receiver)), lpAmount);
        assertEq(lpAmount, expectedMintAmount); // on a snapshot there should be no slippage
        assertEq(lpAmount, 427_348_193_446_140); // on a snapshot there should be no slippage
    }

    function test_addLiquidity_fail_insufficientOutputLp() public {
        // mint tokens to the swapper (simulate after swaps have occurred)
        uint256 tokenAAmount = 1e18;
        uint256 tokenBAmount = 25e18; // roughly in proportion to the price at snapshot
        doMint(tokenA, address(swapper), tokenAAmount);
        doMint(tokenB, address(swapper), tokenBAmount);

        (uint256 amount0, uint256 amount1, uint256 expectedMintAmount) =
            kodiakIsland.getMintAmounts(tokenAAmount, tokenBAmount);

        // expect more than was quoted
        uint256 slippageBps = 100; // 1%
        uint256 minLpOutputAmount = expectedMintAmount.addBps(slippageBps, OrigamiMath.Rounding.ROUND_UP);

        // Prepare addLiquidity parameters
        bytes memory addLiquidityParams = abi.encode(
            IOrigamiSwapperWithLiquidityManagement.AddLiquidityParams({
                liquidityRouter: address(kodiakRouter),
                receiver: address(receiver),
                minLpOutputAmount: minLpOutputAmount,
                callData: abi.encodeWithSignature(
                    "addLiquidity(address,uint256,uint256,uint256,uint256,uint256,address)",
                    address(kodiakIsland),
                    amount0,
                    amount1,
                    0, // slippage covered by minLpOutputAmount in KodiakRouter and OrigamiSwapper
                    0,
                    minLpOutputAmount,
                    address(swapper)
                )
            })
        );

        vm.startPrank(origamiMultisig);

        // underlying kodiak router provides slippage protection
        vm.expectRevert("below min amounts");
        swapper.addLiquidity(createTokenAmounts(amount0, amount1), addLiquidityParams);

        // even if it didn't, the origami swapper reverts
        addLiquidityParams = abi.encode(
            IOrigamiSwapperWithLiquidityManagement.AddLiquidityParams({
                liquidityRouter: address(kodiakRouter),
                receiver: address(receiver),
                minLpOutputAmount: minLpOutputAmount,
                callData: abi.encodeWithSignature(
                    "addLiquidity(address,uint256,uint256,uint256,uint256,uint256,address)",
                    address(kodiakIsland),
                    amount0,
                    amount1,
                    0, // slippage covered by minLpOutputAmount in KodiakRouter and OrigamiSwapper
                    0,
                    0, // no slippage protection from the kodiak router
                    address(swapper)
                )
            })
        );
        vm.expectRevert(
            abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, minLpOutputAmount, expectedMintAmount)
        );
        swapper.addLiquidity(createTokenAmounts(amount0, amount1), addLiquidityParams);
    }

    function test_addLiquidity_fail_slippageProtectionUnaffectedByDonations() public {
        // mint tokens to the swapper (simulate after swaps have occurred)
        uint256 tokenAAmount = 1e18;
        uint256 tokenBAmount = 25e18; // roughly in proportion to the price at snapshot
        doMint(tokenA, address(swapper), tokenAAmount);
        doMint(tokenB, address(swapper), tokenBAmount);

        // donate a bunch of the lp token to the swapper (this should not affect the slippage protection)
        uint256 donationAmount = 100e18;
        doMint(kodiakIsland, address(swapper), donationAmount);

        (uint256 amount0, uint256 amount1, uint256 expectedMintAmount) =
            kodiakIsland.getMintAmounts(tokenAAmount, tokenBAmount);

        // expect more than was quoted
        uint256 slippageBps = 100; // 1%
        uint256 minLpOutputAmount = expectedMintAmount.addBps(slippageBps, OrigamiMath.Rounding.ROUND_UP);

        vm.startPrank(origamiMultisig);
        // even if it didn't, the origami swapper reverts
        bytes memory addLiquidityParams = abi.encode(
            IOrigamiSwapperWithLiquidityManagement.AddLiquidityParams({
                liquidityRouter: address(kodiakRouter),
                receiver: address(receiver),
                minLpOutputAmount: minLpOutputAmount,
                callData: abi.encodeWithSignature(
                    "addLiquidity(address,uint256,uint256,uint256,uint256,uint256,address)",
                    address(kodiakIsland),
                    amount0,
                    amount1,
                    0, // slippage covered by minLpOutputAmount in KodiakRouter and OrigamiSwapper
                    0,
                    0, // no slippage protection from the kodiak router
                    address(swapper)
                )
            })
        );
        vm.expectRevert(
            abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, minLpOutputAmount, expectedMintAmount)
        );
        swapper.addLiquidity(createTokenAmounts(amount0, amount1), addLiquidityParams);

        assertEq(kodiakIsland.balanceOf(address(swapper)), donationAmount);
    }

    function test_addLiquidity_twice_leftOverApproval() public {
        // Use a mock router to only pull a portion of the token's
        MockKodiakRouter mockRouter = new MockKodiakRouter();
        mockRouter.setPcts(99, 99);
        vm.startPrank(origamiMultisig);
        swapper.whitelistRouter(address(mockRouter), true);

        // mint tokens to the swapper (simulate after swaps have occurred)
        uint256 tokenAAmount = 1e18;
        uint256 tokenBAmount = 25e18; // roughly in proportion to the price at snapshot
        doMint(tokenA, address(swapper), tokenAAmount);
        doMint(tokenB, address(swapper), tokenBAmount);

        (uint256 amount0, uint256 amount1, uint256 expectedMintAmount) =
            kodiakIsland.getMintAmounts(tokenAAmount, tokenBAmount);

        // Prepare addLiquidity parameters
        bytes memory addLiquidityParams = abi.encode(
            IOrigamiSwapperWithLiquidityManagement.AddLiquidityParams({
                liquidityRouter: address(mockRouter),
                receiver: address(receiver),
                minLpOutputAmount: 0,
                callData: abi.encodeWithSignature(
                    "addLiquidity(address,uint256,uint256,uint256,uint256,uint256,address)",
                    address(kodiakIsland),
                    amount0,
                    amount1,
                    0, // slippage covered by minLpOutputAmount in KodiakRouter and OrigamiSwapper
                    0,
                    0,
                    address(swapper)
                )
            })
        );

        uint256 lpAmount = swapper.addLiquidity(createTokenAmounts(amount0, amount1), addLiquidityParams);
        
        // Check that tokens were transferred and LP tokens were received, dust amounts of the LP tokens are expected
        assertEq(tokenA.balanceOf(address(swapper)), 0.999999997473124807e18);
        assertEq(tokenB.balanceOf(address(swapper)), 0.250000000000019373e18);
        assertEq(kodiakIsland.balanceOf(address(receiver)), lpAmount);
        assertEq(lpAmount, 0.000423074711511678e18);

        // Add liqiquidity again to ensure it works after left over approvals
        {
            mockRouter.setPcts(100, 100);
            doMint(tokenA, address(swapper), tokenAAmount);
            doMint(tokenB, address(swapper), tokenBAmount);
            (amount0, amount1, expectedMintAmount) =
                kodiakIsland.getMintAmounts(tokenAAmount, tokenBAmount);

            addLiquidityParams = abi.encode(
                IOrigamiSwapperWithLiquidityManagement.AddLiquidityParams({
                    liquidityRouter: address(mockRouter),
                    receiver: address(receiver),
                    minLpOutputAmount: 0,
                    callData: abi.encodeWithSignature(
                        "addLiquidity(address,uint256,uint256,uint256,uint256,uint256,address)",
                        address(kodiakIsland),
                        amount0,
                        amount1,
                        0, // slippage covered by minLpOutputAmount in KodiakRouter and OrigamiSwapper
                        0,
                        0,
                        address(swapper)
                    )
                })
            );
            lpAmount = swapper.addLiquidity(createTokenAmounts(amount0, amount1), addLiquidityParams);

            // Check that tokens were transferred and LP tokens were received, dust amounts of the LP tokens are expected
            assertEq(tokenA.balanceOf(address(swapper)), 1.999999994920725622e18);
            assertEq(tokenB.balanceOf(address(swapper)), 0.250000000000038941e18);
            assertEq(kodiakIsland.balanceOf(address(receiver)), 0.000850422904957818e18);
            assertEq(lpAmount, expectedMintAmount); // on a snapshot there should be no slippage
            assertEq(lpAmount, 0.000427348193446140e18); // on a snapshot there should be no slippage
        }
    }
}
