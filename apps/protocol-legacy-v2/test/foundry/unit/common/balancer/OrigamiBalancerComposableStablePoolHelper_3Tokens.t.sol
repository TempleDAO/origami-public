pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

import { IBalancerVault } from "contracts/interfaces/external/balancer/IBalancerVault.sol";
import { IBalancerQueries } from "contracts/interfaces/external/balancer/IBalancerQueries.sol";
import { IBalancerBptToken } from "contracts/interfaces/external/balancer/IBalancerBptToken.sol";

import { OrigamiBalancerComposableStablePoolHelper } from "contracts/common/balancer/OrigamiBalancerComposableStablePoolHelper.sol";
import { IOrigamiBalancerPoolHelper } from "contracts/interfaces/common/balancer/IOrigamiBalancerPoolHelper.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

abstract contract OrigamiBalancerStablePoolHelperTestBase_3Tokens is OrigamiTest {
    IBalancerVault internal constant balancerVault = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IBalancerQueries internal constant balancerQueries = IBalancerQueries(0xE39B5e3B6D74016b2F6A9673D7d7493B6DF549d5);

    bytes32 internal immutable poolId;
    IERC20 internal token0;
    IERC20 internal token1;
    IERC20 internal token2;
    IERC20 internal token3;
    IBalancerBptToken internal lpToken;
    OrigamiBalancerComposableStablePoolHelper internal balancerPoolHelper;

    uint256 internal immutable pairTokenAIndex;
    uint256 internal immutable pairTokenBIndex;
    uint256 internal immutable pairTokenCIndex;
    IERC20 internal pairTokenA;
    IERC20 internal pairTokenB;
    IERC20 internal pairTokenC;

    constructor(bytes32 _poolId, uint256 _pairTokenAIndex, uint256 _pairTokenBIndex, uint256 _pairTokenCIndex) {
        poolId = _poolId;
        pairTokenAIndex = _pairTokenAIndex;
        pairTokenBIndex = _pairTokenBIndex;
        pairTokenCIndex = _pairTokenCIndex;
    }

    function setUp() public virtual {
        fork("mainnet", 20682077);
        balancerPoolHelper = new OrigamiBalancerComposableStablePoolHelper(
            origamiMultisig,
            address(balancerVault),
            address(balancerQueries),
            poolId
        );

        (address[] memory addresses,,) = balancerVault.getPoolTokens(poolId);
        token0 = IERC20Metadata(addresses[0]);
        token1 = IERC20Metadata(addresses[1]);
        token2 = IERC20Metadata(addresses[2]);
        token3 = IERC20Metadata(addresses[3]);

        (address lpTokenAddr,) = balancerVault.getPool(poolId);
        lpToken = IBalancerBptToken(lpTokenAddr);

        pairTokenA = IERC20(addresses[pairTokenAIndex]);
        pairTokenB = IERC20(addresses[pairTokenBIndex]);
        pairTokenC = IERC20(addresses[pairTokenCIndex]);
    }

    function checkAddLiquidityRequestData(
        IBalancerVault.JoinPoolRequest memory requestData,
        uint256[] memory tokenAmounts,
        uint256 expectedMinBptAmount
    ) internal view {
        address[] memory tokens = balancerPoolHelper.poolTokens();
        assertEq(requestData.fromInternalBalance, false, "fromInternalBalance");
        assertEq(requestData.assets.length, 4, "assets.length");
        assertEq(requestData.assets[0], tokens[0], "assets[0]");
        assertEq(requestData.assets[1], tokens[1], "assets[1]");
        assertEq(requestData.assets[2], tokens[2], "assets[2]");
        assertEq(requestData.assets[3], tokens[3], "assets[3]");
        assertEq(requestData.maxAmountsIn.length, 4, "maxAmountsIn.length");
        assertEq(requestData.maxAmountsIn[0], tokenAmounts[0], "maxAmountsIn[0]");
        assertEq(requestData.maxAmountsIn[1], tokenAmounts[1], "maxAmountsIn[1]");
        assertEq(requestData.maxAmountsIn[2], tokenAmounts[2], "maxAmountsIn[2]");
        assertEq(requestData.maxAmountsIn[3], tokenAmounts[3], "maxAmountsIn[3]");

        (uint256 jtype, uint256[] memory amountsIn, uint256 minBpt) = abi.decode(requestData.userData, (uint256, uint256[], uint256));
        assertEq(jtype, 1, "jtype");
        assertEq(amountsIn.length, 3, "amountsIn.length");
        assertEq(amountsIn[0], requestData.maxAmountsIn[pairTokenAIndex], "amountsIn[0]");
        assertEq(amountsIn[1], requestData.maxAmountsIn[pairTokenBIndex], "amountsIn[1]");
        assertEq(amountsIn[2], requestData.maxAmountsIn[pairTokenCIndex], "amountsIn[2]");
        assertEq(minBpt, expectedMinBptAmount, "expectedMinBptAmount");
    }

    function checkRemoveLiquidityRequestData(
        IBalancerVault.ExitPoolRequest memory requestData,
        uint256[] memory expectedMinTokenAmounts,
        uint256 expectedBptAmount
    ) internal view {
        address[] memory tokens = balancerPoolHelper.poolTokens();
        assertEq(requestData.toInternalBalance, false, "toInternalBalance");
        assertEq(requestData.assets.length, 4, "assets.length");
        assertEq(requestData.assets[0], tokens[0], "assets[0]");
        assertEq(requestData.assets[1], tokens[1], "assets[1]");
        assertEq(requestData.assets[2], tokens[2], "assets[2]");
        assertEq(requestData.assets[3], tokens[3], "assets[3]");
        assertEq(requestData.minAmountsOut.length, 4, "minAmountsOut.length");
        assertEq(requestData.minAmountsOut[0], expectedMinTokenAmounts[0], "minAmountsOut[0]");
        assertEq(requestData.minAmountsOut[1], expectedMinTokenAmounts[1], "minAmountsOut[1]");
        assertEq(requestData.minAmountsOut[2], expectedMinTokenAmounts[2], "minAmountsOut[2]");
        assertEq(requestData.minAmountsOut[3], expectedMinTokenAmounts[3], "minAmountsOut[3]");

        (uint256 etype, uint256 bptAmount) = abi.decode(requestData.userData, (uint256, uint256));
        assertEq(etype, 0, "etype");
        assertEq(bptAmount, expectedBptAmount, "bptAmount");
    }

    function addLiquidity() public returns (uint256 lpTokenReceived){
        vm.startPrank(alice);

        uint256 tokenAAmount = 10_000 * 10 ** IERC20Metadata(address(pairTokenA)).decimals();
        IBalancerVault.JoinPoolRequest memory requestData;

        uint256[] memory tokenAmounts;
        (
            tokenAmounts, 
            /*expectedBptAmount*/,
            /*minBptAmount*/,
            requestData
        ) = balancerPoolHelper.addLiquidityQuote(
            pairTokenAIndex,
            tokenAAmount,
            0
        );

        assertEq(tokenAAmount, tokenAmounts[pairTokenAIndex]);
        uint256 tokenBAmount = tokenAmounts[pairTokenBIndex];

        deal(address(pairTokenA), alice, tokenAAmount, false);
        pairTokenA.approve(address(balancerPoolHelper), tokenAAmount);

        deal(address(pairTokenB), alice, tokenBAmount, false);
        pairTokenB.approve(address(balancerPoolHelper), tokenBAmount);

        balancerPoolHelper.addLiquidity(alice, requestData);
        return lpToken.balanceOf(alice);
    }

    function tokenIndex(address token) internal view returns (uint256) {
        address[] memory ts = balancerPoolHelper.poolTokens();
        if (ts[0] == token) return 0;
        if (ts[1] == token) return 1;
        return 2;
    }
}

/** Setup for a gho/USDT/USDc pool on mainnet where getBptIndex is 1 */
abstract contract OrigamiBalancerStablePoolHelperTestBase_3Tokens_ghoUsdtUsdc is OrigamiBalancerStablePoolHelperTestBase_3Tokens { 
    constructor() OrigamiBalancerStablePoolHelperTestBase_3Tokens(
        // https://balancer.fi/pools/ethereum/v2/0x8353157092ed8be69a9df8f95af097bbf33cb2af0000000000000000000005d9
        bytes32(0x8353157092ed8be69a9df8f95af097bbf33cb2af0000000000000000000005d9), // poolId
        0, // pairTokenA index
        2, // pairTokenB index
        3  // pairTokenC index
    ) {}
}

abstract contract OrigamiBalancerStablePoolHelperTestViews is OrigamiBalancerStablePoolHelperTestBase_3Tokens {
    function test_initialization() public view{
        assertEq(address(balancerPoolHelper.balancerVault()), address(balancerVault));
        assertEq(address(balancerPoolHelper.balancerQueries()), address(balancerQueries));
        assertEq(balancerPoolHelper.poolId(), poolId);
        assertEq(address(balancerPoolHelper.poolTokens()[0]), address(token0));
        assertEq(address(balancerPoolHelper.poolTokens()[1]), address(token1));
        assertEq(address(balancerPoolHelper.poolTokens()[2]), address(token2));
    }

    function test_poolBalances() public view virtual {
        uint256[] memory tokenBalances = balancerPoolHelper.poolBalances();

        check_getTokenBalances(tokenBalances);
    }

    function check_getTokenBalances(uint256[] memory tokenBalances) public view virtual;

    function test_tokenAmountsForLpTokens_zeroAmount() public view {
        uint256[] memory tokenAmounts = balancerPoolHelper.tokenAmountsForLpTokens(0);
        assertEq(tokenAmounts[0], 0);
        assertEq(tokenAmounts[1], 0);
        assertEq(tokenAmounts[2], 0);
    }

    function test_tokenAmountsForLpTokens_zeroSupply() public {
        vm.mockCall(
            address(lpToken),
            abi.encodeWithSelector(IBalancerBptToken.getActualSupply.selector),
            abi.encode(0)
        );
        uint256[] memory tokenAmounts = balancerPoolHelper.tokenAmountsForLpTokens(100e18);
        assertEq(tokenAmounts[0], 0);
        assertEq(tokenAmounts[1], 0);
        assertEq(tokenAmounts[2], 0);
    }

    function test_tokenAmountsForLpTokens() public view {
        uint256[] memory tokenAmounts = balancerPoolHelper.tokenAmountsForLpTokens(100e18);
        assertEq(tokenAmounts.length, 4);
        check_tokenAmountsForLpTokens(tokenAmounts);
    }
    function check_tokenAmountsForLpTokens(uint256[] memory tokenAmounts) public pure virtual;
}

contract OrigamiBalancerStablePoolHelperSnapshotViews_ghoUsdtUsdc is OrigamiBalancerStablePoolHelperTestViews, OrigamiBalancerStablePoolHelperTestBase_3Tokens_ghoUsdtUsdc {
    function check_getTokenBalances(uint256[] memory tokenBalances) public pure override {
        assertEq(tokenBalances[0], 1_140_517.638896811302797083e18);
        assertEq(tokenBalances[1], 2_596_148_429_276_553.509067931744531765e18);
        assertEq(tokenBalances[2], 4_163_698.429461e6);
        assertEq(tokenBalances[3], 4_605_135.468094e6);
    }

    function check_tokenAmountsForLpTokens(uint256[] memory tokenAmounts) public pure override {
        assertEq(tokenAmounts[0], 11.633191011292796423e18);
        assertEq(tokenAmounts[1], 26_480_511_604.059815845668220921e18);
        assertEq(tokenAmounts[2], 42.469399e6);
        assertEq(tokenAmounts[3], 46.972022e6);
    }
}

abstract contract OrigamiBalancerStablePoolHelperTestAddLiquidity is OrigamiBalancerStablePoolHelperTestBase_3Tokens {
    function test_addLiquidityQuote_zeroBalances() public {
        (address[] memory addresses, , uint256 lastChangeBlock) = balancerVault.getPoolTokens(poolId);
        vm.mockCall(
            address(balancerVault),
            abi.encodeWithSelector(IBalancerVault.getPoolTokens.selector),
            abi.encode(addresses, new uint256[](4), lastChangeBlock)
        );

        vm.expectRevert("BAL#004"); // ZERO_DIVISION
        balancerPoolHelper.addLiquidityQuote(
            pairTokenAIndex,
            1e18,
            100 // 1%
        );
    }

    function test_addLiquidityQuote_zeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        balancerPoolHelper.addLiquidityQuote(
            pairTokenAIndex,
            0,
            100 // 1%
        );
    }

    function test_addLiquidityQuote_withSlippage() public {
        (
            uint256[] memory tokenAmounts, 
            uint256 expectedBptAmount,
            uint256 minBptAmount,
            IBalancerVault.JoinPoolRequest memory requestData
        ) = balancerPoolHelper.addLiquidityQuote(
            pairTokenAIndex,
            100e18,
            100 // 1%
        );
        checkAddLiquidityRequestData(requestData, tokenAmounts, minBptAmount);
        check_addLiquidityQuote_withSlippage(tokenAmounts, expectedBptAmount, minBptAmount);
    }
    function check_addLiquidityQuote_withSlippage(
        uint256[] memory tokenAmounts, 
        uint256 expectedBptAmount,
        uint256 minBptAmount
    ) public pure virtual;

    function test_addLiquidityQuote_noSlippage() public {
        (
            uint256[] memory tokenAmounts, 
            uint256 expectedBptAmount,
            uint256 minBptAmount,
            IBalancerVault.JoinPoolRequest memory requestData
        ) = balancerPoolHelper.addLiquidityQuote(
            pairTokenAIndex,
            100e18,
            0
        );
        checkAddLiquidityRequestData(requestData, tokenAmounts, minBptAmount);
        check_addLiquidityQuote_noSlippage(tokenAmounts, expectedBptAmount, minBptAmount);
    }
    function check_addLiquidityQuote_noSlippage(
        uint256[] memory tokenAmounts, 
        uint256 expectedBptAmount,
        uint256 minBptAmount
    ) public pure virtual;

    function test_addLiquidity_failJoinKind() public {
        IBalancerVault.JoinPoolRequest memory requestData;
        requestData.assets = new address[](4);
        requestData.assets[0] = address(token0);
        requestData.assets[1] = address(token1);
        requestData.assets[2] = address(token2);
        requestData.assets[3] = address(token3);
        requestData.userData = abi.encode(uint256(2));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBalancerPoolHelper.InvalidJoinKind.selector));
        balancerPoolHelper.addLiquidity(alice, requestData);
    }

    function test_addLiquidity_failBptAmount() public {
        IBalancerVault.JoinPoolRequest memory requestData;
        requestData.assets = new address[](4);
        requestData.assets[0] = address(token0);
        requestData.assets[1] = address(token1);
        requestData.assets[2] = address(token2);
        requestData.assets[3] = address(token3);
        requestData.userData = abi.encode(uint256(1));
        requestData.maxAmountsIn = new uint256[](4);
        requestData.maxAmountsIn[0] = 123;
        requestData.maxAmountsIn[1] = 123;
        requestData.maxAmountsIn[2] = 123;
        requestData.maxAmountsIn[3] = 123;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        balancerPoolHelper.addLiquidity(alice, requestData);
    }
    
    function test_addLiquidity_failTransferFrom() public {
        vm.startPrank(alice);

        uint256 pairTokenAAmount = 1_000e18;
        (
            uint256[] memory tokenAmounts, 
            /*uint256 expectedBptAmount*/,
            /*uint256 minBptAmount*/,
            IBalancerVault.JoinPoolRequest memory requestData
        ) = balancerPoolHelper.addLiquidityQuote(
            pairTokenAIndex,
            pairTokenAAmount,
            0
        );

        assertEq(tokenAmounts[pairTokenAIndex], pairTokenAAmount);
        deal(address(pairTokenA), alice, pairTokenAAmount, false);
        pairTokenA.approve(address(balancerPoolHelper), 0);

        vm.expectRevert(); // different token implementations revert with custom error messages
        balancerPoolHelper.addLiquidity(alice, requestData);
    }

    function test_addLiquidity_nonZeroBptAmount() public {
        vm.startPrank(alice);

        uint256 pairTokenAAmount = 1e18;
        (
            uint256[] memory tokenAmounts, 
            /*uint256 expectedBptAmount*/,
            /*uint256 minBptAmount*/,
            IBalancerVault.JoinPoolRequest memory requestData
        ) = balancerPoolHelper.addLiquidityQuote(
            pairTokenAIndex,
            pairTokenAAmount,
            0
        );

        deal(address(pairTokenA), alice, pairTokenAAmount, false);
        pairTokenA.approve(address(balancerPoolHelper), pairTokenAAmount);
        deal(address(pairTokenB), alice, tokenAmounts[pairTokenBIndex], false);
        pairTokenB.approve(address(balancerPoolHelper), tokenAmounts[pairTokenBIndex]);

        requestData.maxAmountsIn[balancerPoolHelper.bptIndex()] = 1;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        balancerPoolHelper.addLiquidity(alice, requestData);
    }

    function test_addLiquidity_success() public {
        vm.startPrank(alice);

        uint256[] memory tokenBalancesBefore = balancerPoolHelper.poolBalances();

        uint256 pairTokenAAmount = 1e18;
        (
            uint256[] memory tokenAmounts, 
            uint256 expectedBptAmount,
            /*uint256 minBptAmount*/,
            IBalancerVault.JoinPoolRequest memory requestData
        ) = balancerPoolHelper.addLiquidityQuote(
            pairTokenAIndex,
            pairTokenAAmount,
            0
        );

        assertEq(tokenAmounts[pairTokenAIndex], pairTokenAAmount);

        deal(address(pairTokenA), alice, pairTokenAAmount, false);
        pairTokenA.approve(address(balancerPoolHelper), pairTokenAAmount);

        deal(address(pairTokenB), alice, tokenAmounts[pairTokenBIndex], false);
        pairTokenB.approve(address(balancerPoolHelper), tokenAmounts[pairTokenBIndex]);

        balancerPoolHelper.addLiquidity(alice, requestData);

        assertEq(pairTokenA.balanceOf(alice), 0);
        assertEq(pairTokenB.balanceOf(alice), 0);
        assertEq(lpToken.balanceOf(alice), expectedBptAmount);

        // No surplus in balancer
        assertEq(pairTokenA.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenB.balanceOf(address(balancerPoolHelper)), 0);

        uint256[] memory tokenBalancesAfter = balancerPoolHelper.poolBalances();

        // only balance of the deposited token increases in the pool
        for(uint256 i; i < tokenBalancesBefore.length; ++i) {
            if(i == pairTokenAIndex) {
                assertEq(tokenBalancesBefore[i] + pairTokenAAmount, tokenBalancesAfter[i]);
            } else {
                assertEq(tokenBalancesBefore[i], tokenBalancesAfter[i]);
            }
        }
    }

    function test_addLiquidity_failSlippage() public {
        vm.startPrank(alice);

        uint256 pairTokenAAmount = 1e18;
        (
            /*uint256[] memory tokenAmounts*/, 
            /*uint256 expectedBptAmount*/,
            /*uint256 minBptAmount*/,
            IBalancerVault.JoinPoolRequest memory requestData
        ) = balancerPoolHelper.addLiquidityQuote(
            pairTokenAIndex,
            pairTokenAAmount,
            0
        );

        requestData.maxAmountsIn[pairTokenAIndex] = requestData.maxAmountsIn[pairTokenAIndex] * 9 / 10;

        deal(address(pairTokenA), alice, pairTokenAAmount*2, false);
        pairTokenA.approve(address(balancerPoolHelper), pairTokenAAmount*2);

        vm.expectRevert("BAL#506"); // JOIN_ABOVE_MAX
        balancerPoolHelper.addLiquidity(alice, requestData);
    }
}

contract OrigamiBalancerStablePoolHelperSnapshotAddLiquidity_ghoUsdtUsdc is OrigamiBalancerStablePoolHelperTestAddLiquidity, OrigamiBalancerStablePoolHelperTestBase_3Tokens_ghoUsdtUsdc {
    function check_addLiquidityQuote_withSlippage(
        uint256[] memory tokenAmounts, 
        uint256 expectedBptAmount,
        uint256 minBptAmount
    ) public pure override {
        assertEq(tokenAmounts[0], 100e18);
        assertEq(tokenAmounts[1], 0);
        assertEq(tokenAmounts[2], 0);
        assertEq(expectedBptAmount, 99.201258716047478068e18);
        assertEq(minBptAmount,      98.209246128887003287e18);
        assertEq(minBptAmount, OrigamiMath.subtractBps(expectedBptAmount, 100, OrigamiMath.Rounding.ROUND_DOWN));
    }

    function check_addLiquidityQuote_noSlippage(
        uint256[] memory tokenAmounts, 
        uint256 expectedBptAmount,
        uint256 minBptAmount
    ) public pure override {
        assertEq(tokenAmounts[0], 100e18);
        assertEq(tokenAmounts[1], 0);
        assertEq(tokenAmounts[2], 0);
        assertEq(expectedBptAmount, 99.201258716047478068e18);
        assertEq(minBptAmount, expectedBptAmount);
    }
}

abstract contract OrigamiBalancerStablePoolHelperTestRemoveLiquidity is OrigamiBalancerStablePoolHelperTestBase_3Tokens {
    function test_removeLiquidityQuote_zeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        balancerPoolHelper.removeLiquidityQuote(pairTokenAIndex, 0, 0);
    }


    function test_removeLiquidity_failSlippage() public {
        uint256 bptAmount = addLiquidity();

        vm.startPrank(alice);
        (
            /*uint256[] memory expectedTokenAmounts*/,
            /*uint256[] memory minTokenAmounts*/,
            IBalancerVault.ExitPoolRequest memory requestData
        ) = balancerPoolHelper.removeLiquidityQuote(
            pairTokenAIndex,
            bptAmount,
            0
        );
        
        requestData.minAmountsOut[0] += 1;

        lpToken.approve(address(balancerPoolHelper), bptAmount);

        vm.expectRevert("BAL#505"); // EXIT_BELOW_MIN
        balancerPoolHelper.removeLiquidity(bptAmount, alice, requestData);
    }

   function test_removeLiquidity_failTransferFrom() public {
        vm.startPrank(alice);

        uint256 bptAmount = 100e18;
        (
            /*uint256[] memory expectedTokenAmounts*/,
            /*uint256[] memory minTokenAmounts*/,
            IBalancerVault.ExitPoolRequest memory requestData
        ) = balancerPoolHelper.removeLiquidityQuote(
            pairTokenAIndex,
            bptAmount,
            0
        );

        deal(address(lpToken), alice, bptAmount, false);
        lpToken.approve(address(balancerPoolHelper), bptAmount-1);

        vm.expectRevert("BAL#414"); // ERC20_TRANSFER_EXCEEDS_ALLOWANCE
        balancerPoolHelper.removeLiquidity(bptAmount, alice, requestData);
    }

    function test_removeLiquidityQuote_withSlippage() public {
        deal(address(lpToken), address(balancerPoolHelper), 10e18, false);

        (
            uint256[] memory expectedTokenAmounts,
            uint256[] memory minTokenAmounts,
            IBalancerVault.ExitPoolRequest memory requestData
        ) = balancerPoolHelper.removeLiquidityQuote(
            pairTokenAIndex,
            10e18,
            100
        );

        checkRemoveLiquidityRequestData(requestData, minTokenAmounts, 10e18);
        check_removeLiquidityQuote_withSlippage(expectedTokenAmounts, minTokenAmounts);
    }
    function check_removeLiquidityQuote_withSlippage(
        uint256[] memory expectedTokenAmounts,
        uint256[] memory minTokenAmounts
    ) public pure virtual;

    function test_removeLiquidityQuote_noSlippage() public {
        (
            uint256[] memory expectedTokenAmounts,
            uint256[] memory minTokenAmounts,
            IBalancerVault.ExitPoolRequest memory requestData
        ) = balancerPoolHelper.removeLiquidityQuote(
            pairTokenAIndex,
            10e18,
            0
        );

        checkRemoveLiquidityRequestData(requestData, minTokenAmounts, 10e18);
        check_removeLiquidityQuote_noSlippage(expectedTokenAmounts, minTokenAmounts);
    }
    function check_removeLiquidityQuote_noSlippage(
        uint256[] memory expectedTokenAmounts,
        uint256[] memory minTokenAmounts
    ) public pure virtual;

    function test_removeLiquidity_failExitKind() public {
        IBalancerVault.ExitPoolRequest memory requestData;
        requestData.assets = new address[](4);
        requestData.assets[0] = address(token0);
        requestData.assets[1] = address(token1);
        requestData.assets[2] = address(token2);
        requestData.assets[3] = address(token3);
        requestData.userData = abi.encode(uint256(1), 123);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBalancerPoolHelper.InvalidExitKind.selector));
        balancerPoolHelper.removeLiquidity(100e18, alice, requestData);
    }

    function test_removeLiquidity_success_partialExit() public {
        addLiquidity();
        vm.startPrank(alice);

        uint256 bptAmount = 5_000e18;
        (
            /*uint256[] memory expectedTokenAmounts*/,
            /*uint256[] memory minTokenAmounts*/,
            IBalancerVault.ExitPoolRequest memory requestData
        ) = balancerPoolHelper.removeLiquidityQuote(
            pairTokenAIndex,
            bptAmount,
            0
        );

        check_removeLiquidity_success_partialExit_pre();

        lpToken.approve(address(balancerPoolHelper), bptAmount);
        balancerPoolHelper.removeLiquidity(bptAmount, alice, requestData);

        check_removeLiquidity_success_partialExit_post();
    }
    function check_removeLiquidity_success_partialExit_pre() public view virtual;
    function check_removeLiquidity_success_partialExit_post() public view virtual;

    function test_removeLiquidity_success_fullExit() public {
        addLiquidity();
        vm.startPrank(alice);

        uint256 bptAmount = lpToken.balanceOf(alice);
        (
            /*uint256[] memory expectedTokenAmounts*/,
            /*uint256[] memory minTokenAmounts*/,
            IBalancerVault.ExitPoolRequest memory requestData
        ) = balancerPoolHelper.removeLiquidityQuote(
            pairTokenAIndex,
            bptAmount,
            0
        );

        check_removeLiquidity_success_fullExit_pre();
        
        lpToken.approve(address(balancerPoolHelper), bptAmount);
        balancerPoolHelper.removeLiquidity(bptAmount, alice, requestData);

        check_removeLiquidity_success_fullExit_post();
    }
    function check_removeLiquidity_success_fullExit_pre() public view virtual;
    function check_removeLiquidity_success_fullExit_post() public view virtual;
}


contract OrigamiBalancerStablePoolHelperSnapshotRemoveLiquidity_ghoUsdtUsdc is OrigamiBalancerStablePoolHelperTestRemoveLiquidity, OrigamiBalancerStablePoolHelperTestBase_3Tokens_ghoUsdtUsdc {
    function check_removeLiquidityQuote_withSlippage(
        uint256[] memory expectedTokenAmounts,
        uint256[] memory minTokenAmounts
    ) public pure override {
        assertEq(expectedTokenAmounts.length, 4);
        assertEq(expectedTokenAmounts[0], 10.071596076606134669e18);
        assertEq(expectedTokenAmounts[1], 0);
        assertEq(expectedTokenAmounts[2], 0);
        assertEq(expectedTokenAmounts[3], 0);

        assertEq(minTokenAmounts[0], OrigamiMath.subtractBps(expectedTokenAmounts[0], 100, OrigamiMath.Rounding.ROUND_DOWN));
        assertEq(minTokenAmounts[1], 0);
        assertEq(minTokenAmounts[2], 0);
        assertEq(minTokenAmounts[3], 0);
    }

    function check_removeLiquidityQuote_noSlippage(
        uint256[] memory expectedTokenAmounts,
        uint256[] memory minTokenAmounts
    ) public pure override {
        assertEq(expectedTokenAmounts.length, 4);
        assertEq(expectedTokenAmounts[0], 10.071596076606134669e18);
        assertEq(expectedTokenAmounts[1], 0);
        assertEq(expectedTokenAmounts[2], 0);
        assertEq(expectedTokenAmounts[3], 0);
        assertEq(minTokenAmounts[0], expectedTokenAmounts[0]);
        assertEq(minTokenAmounts[1], expectedTokenAmounts[1]);
        assertEq(minTokenAmounts[2], expectedTokenAmounts[2]);
        assertEq(minTokenAmounts[3], expectedTokenAmounts[3]);
    }

    function check_removeLiquidity_success_partialExit_pre() public view override {
        assertEq(lpToken.balanceOf(alice), 9_919.875545342346423530e18);
        assertEq(pairTokenA.balanceOf(alice), 0);
        assertEq(pairTokenB.balanceOf(alice), 0);
        assertEq(pairTokenC.balanceOf(alice), 0);

        assertEq(lpToken.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenA.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenB.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenC.balanceOf(address(balancerPoolHelper)), 0);
    }

    function check_removeLiquidity_success_partialExit_post() public view override {
        assertEq(lpToken.balanceOf(alice), 9_919.875545342346423530e18 - 5_000e18);
        assertEq(pairTokenA.balanceOf(alice), 5_035.993424204267960797e18);
        assertEq(pairTokenB.balanceOf(alice), 0);
        assertEq(pairTokenC.balanceOf(alice), 0);

        assertEq(lpToken.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenA.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenB.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenC.balanceOf(address(balancerPoolHelper)), 0);
    }
    
    function check_removeLiquidity_success_fullExit_pre() public view override {
        assertEq(lpToken.balanceOf(alice), 9_919.875545342346423530e18);
        assertEq(pairTokenA.balanceOf(alice), 0);
        assertEq(pairTokenB.balanceOf(alice), 0);
        assertEq(pairTokenC.balanceOf(alice), 0);

        assertEq(lpToken.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenA.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenB.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenC.balanceOf(address(balancerPoolHelper)), 0);
    }

    function check_removeLiquidity_success_fullExit_post() public view override {
        assertEq(lpToken.balanceOf(alice), 0);
        // Just a tiny bit of dust lost from initial amounts.
        assertEq(pairTokenA.balanceOf(alice), 9_991.159826547588404629e18);
        assertEq(pairTokenB.balanceOf(alice), 0);
        assertEq(pairTokenC.balanceOf(alice), 0);

        assertEq(lpToken.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenA.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenB.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenC.balanceOf(address(balancerPoolHelper)), 0);
    }
}
