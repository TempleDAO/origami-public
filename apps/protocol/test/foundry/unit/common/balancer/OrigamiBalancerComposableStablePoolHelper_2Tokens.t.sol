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

abstract contract OrigamiBalancerStablePoolHelperTestBase_2Tokens is OrigamiTest {
    IBalancerVault internal constant balancerVault = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IBalancerQueries internal constant balancerQueries = IBalancerQueries(0xE39B5e3B6D74016b2F6A9673D7d7493B6DF549d5);

    bytes32 internal immutable poolId;
    IERC20 internal token0;
    IERC20 internal token1;
    IERC20 internal token2;
    IBalancerBptToken internal lpToken;
    OrigamiBalancerComposableStablePoolHelper internal balancerPoolHelper;

    uint256 internal immutable pairTokenAIndex;
    uint256 internal immutable pairTokenBIndex;
    IERC20 internal pairTokenA;
    IERC20 internal pairTokenB;

    constructor(bytes32 _poolId, uint256 _pairTokenAIndex, uint256 _pairTokenBIndex) {
        poolId = _poolId;
        pairTokenAIndex = _pairTokenAIndex;
        pairTokenBIndex = _pairTokenBIndex;
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

        (address lpTokenAddr,) = balancerVault.getPool(poolId);
        lpToken = IBalancerBptToken(lpTokenAddr);

        pairTokenA = IERC20(addresses[pairTokenAIndex]);
        pairTokenB = IERC20(addresses[pairTokenBIndex]);
    }

    function checkAddLiquidityRequestData(
        IBalancerVault.JoinPoolRequest memory requestData,
        uint256[] memory tokenAmounts,
        uint256 expectedMinBptAmount
    ) internal view {
        address[] memory tokens = balancerPoolHelper.poolTokens();
        assertEq(requestData.fromInternalBalance, false, "fromInternalBalance");
        assertEq(requestData.assets.length, 3, "assets.length");
        assertEq(requestData.assets[0], tokens[0], "assets[0]");
        assertEq(requestData.assets[1], tokens[1], "assets[1]");
        assertEq(requestData.assets[2], tokens[2], "assets[2]");
        assertEq(requestData.maxAmountsIn.length, 3, "maxAmountsIn.length");
        assertEq(requestData.maxAmountsIn[0], tokenAmounts[0], "maxAmountsIn[0]");
        assertEq(requestData.maxAmountsIn[1], tokenAmounts[1], "maxAmountsIn[1]");
        assertEq(requestData.maxAmountsIn[2], tokenAmounts[2], "maxAmountsIn[2]");

        (uint256 jtype, uint256[] memory amountsIn, uint256 minBpt) = abi.decode(requestData.userData, (uint256, uint256[], uint256));
        assertEq(jtype, 1, "jtype");
        assertEq(amountsIn.length, 2, "amountsIn.length");
        assertEq(amountsIn[0], requestData.maxAmountsIn[pairTokenAIndex], "amountsIn[0]");
        assertEq(amountsIn[1], requestData.maxAmountsIn[pairTokenBIndex], "amountsIn[1]");
        assertEq(minBpt, expectedMinBptAmount, "expectedMinBptAmount");
    }

    function checkRemoveLiquidityRequestData(
        IBalancerVault.ExitPoolRequest memory requestData,
        uint256[] memory expectedMinTokenAmounts,
        uint256 expectedBptAmount
    ) internal view {
        address[] memory tokens = balancerPoolHelper.poolTokens();
        assertEq(requestData.toInternalBalance, false, "toInternalBalance");
        assertEq(requestData.assets.length, 3, "assets.length");
        assertEq(requestData.assets[0], tokens[0], "assets[0]");
        assertEq(requestData.assets[1], tokens[1], "assets[1]");
        assertEq(requestData.assets[2], tokens[2], "assets[1]");
        assertEq(requestData.minAmountsOut.length, 3, "minAmountsOut.length");
        assertEq(requestData.minAmountsOut[0], expectedMinTokenAmounts[0], "minAmountsOut[0]");
        assertEq(requestData.minAmountsOut[1], expectedMinTokenAmounts[1], "minAmountsOut[1]");
        assertEq(requestData.minAmountsOut[2], expectedMinTokenAmounts[2], "minAmountsOut[2]");

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

/** Setup for a rsETH/WETH pool on mainnet where getBptIndex is 0 */
abstract contract OrigamiBalancerStablePoolHelperTestBase_2Tokens_rsEthWeth is OrigamiBalancerStablePoolHelperTestBase_2Tokens { 
    constructor() OrigamiBalancerStablePoolHelperTestBase_2Tokens(
        bytes32(0x58aadfb1afac0ad7fca1148f3cde6aedf5236b6d00000000000000000000067f), // poolId
        1, // pairTokenA index
        2  // pairTokenB index
    ) {}
}

/** Setup for a osETH/wETH pool on mainnet where getBptIndex is 1 */
abstract contract OrigamiBalancerStablePoolHelperTestBase_2Tokens_osEthWeth is OrigamiBalancerStablePoolHelperTestBase_2Tokens {
    constructor() OrigamiBalancerStablePoolHelperTestBase_2Tokens(
        bytes32(0xdacf5fa19b1f720111609043ac67a9818262850c000000000000000000000635), // poolId
        0, // pairTokenA index
        2  // pairTokenB index
    ) {}
}

/** Setup for a sUSDe/USDC pool on mainnet where getBptIndex is 2 */
abstract contract OrigamiBalancerStablePoolHelperTestBase_2Tokens_sUsdeUsdc is OrigamiBalancerStablePoolHelperTestBase_2Tokens {   
    constructor() OrigamiBalancerStablePoolHelperTestBase_2Tokens(
        bytes32(0xb819feef8f0fcdc268afe14162983a69f6bf179e000000000000000000000689), // poolId
        0, // pairTokenA index
        1  // pairTokenB index
    ) {}
}

abstract contract OrigamiBalancerStablePoolHelperTestViews is OrigamiBalancerStablePoolHelperTestBase_2Tokens {
    function test_initialization() public view{
        assertEq(address(balancerPoolHelper.owner()), origamiMultisig);
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
        assertEq(tokenAmounts.length, 3);
        check_tokenAmountsForLpTokens(tokenAmounts);
    }
    function check_tokenAmountsForLpTokens(uint256[] memory tokenAmounts) public pure virtual;
}

contract OrigamiBalancerStablePoolHelperAdmin is OrigamiBalancerStablePoolHelperTestBase_2Tokens_sUsdeUsdc {
    function test_access_recoverToken() public {
        expectElevatedAccess();
        balancerPoolHelper.recoverToken(alice, alice, 100e18);
    }

    function test_recoverToken() public {
        check_recoverToken(address(balancerPoolHelper));
    }
}

contract OrigamiBalancerStablePoolHelperSnapshotViews_sUsdeUsdc is OrigamiBalancerStablePoolHelperTestViews, OrigamiBalancerStablePoolHelperTestBase_2Tokens_sUsdeUsdc {
    function check_getTokenBalances(uint256[] memory tokenBalances) public pure override {
        assertEq(tokenBalances[0], 1_811_944.381646288884125083e18);
        assertEq(tokenBalances[1], 1_834_981.571084e6);
        assertEq(tokenBalances[2], 2_596_148_429_353_729.983720872608976515e18);
    }

    function check_tokenAmountsForLpTokens(uint256[] memory tokenAmounts) public pure override {
        assertEq(tokenAmounts[0], 49.582992301860708513e18);
        assertEq(tokenAmounts[1], 50.213393e6);
        assertEq(tokenAmounts[2], 71_042_361_394.215375076631979670e18);
    }
}

contract OrigamiBalancerStablePoolHelperSnapshotViews_rsEthWeth is OrigamiBalancerStablePoolHelperTestViews, OrigamiBalancerStablePoolHelperTestBase_2Tokens_rsEthWeth {
    function check_getTokenBalances(uint256[] memory tokenBalances) public pure override {
        // Ratio at snapshot approximately 70:30 rsETH:WETH
        assertEq(tokenBalances[0], 2_596_148_429_267_438.797679994891661268e18);
        assertEq(tokenBalances[1], 4_219.599105728327998680e18);
        assertEq(tokenBalances[2], 2_313.777674297262752130e18);
    }

    function check_tokenAmountsForLpTokens(uint256[] memory tokenAmounts) public pure override {
        assertEq(tokenAmounts[0], 39_691_006_463_868.462188842827916373e18);
        assertEq(tokenAmounts[1], 64.511001563826189268e18);
        assertEq(tokenAmounts[2], 35.374003886365162919e18);
    }
}

contract OrigamiBalancerStablePoolHelperSnapshotViews_osEthWeth is OrigamiBalancerStablePoolHelperTestViews, OrigamiBalancerStablePoolHelperTestBase_2Tokens_osEthWeth {
    function check_getTokenBalances(uint256[] memory tokenBalances) public pure override {
        assertEq(tokenBalances[0], 13_228.528063462071248023e18);
        assertEq(tokenBalances[1], 2_596_148_429_267_417.478839148414808856e18);
        assertEq(tokenBalances[2], 6_667.971939521325377189e18);
    }

    function check_tokenAmountsForLpTokens(uint256[] memory tokenAmounts) public pure override {
        assertEq(tokenAmounts[0], 66.661127624394610874e18);
        assertEq(tokenAmounts[1], 13_082_497_232_120.198886672096793862e18);
        assertEq(tokenAmounts[2], 33.601208412902089511e18);
    }
}

abstract contract OrigamiBalancerStablePoolHelperTestAddLiquidity is OrigamiBalancerStablePoolHelperTestBase_2Tokens {
    function test_addLiquidityQuote_zeroBalances() public {
        (address[] memory addresses, , uint256 lastChangeBlock) = balancerVault.getPoolTokens(poolId);
        vm.mockCall(
            address(balancerVault),
            abi.encodeWithSelector(IBalancerVault.getPoolTokens.selector),
            abi.encode(addresses, new uint256[](3), lastChangeBlock)
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

    function test_addLiquidityQuote_failBptIndex() public {
        uint256 bptIndex = balancerPoolHelper.bptIndex();
        address bptToken = address(balancerPoolHelper.poolTokens()[bptIndex]);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, bptToken));
        balancerPoolHelper.addLiquidityQuote(bptIndex, 100, 0);
    }

    function test_addLiquidity_failInternalBalance() public {
        uint256 pairTokenAAmount = 1_000e18;
        (,,, IBalancerVault.JoinPoolRequest memory requestData) = balancerPoolHelper.addLiquidityQuote(
            pairTokenAIndex,
            pairTokenAAmount,
            0
        );

        requestData.fromInternalBalance = true;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        balancerPoolHelper.addLiquidity(alice, requestData);
    }

    function test_addLiquidity_failJoinKind() public {
        IBalancerVault.JoinPoolRequest memory requestData;
        requestData.assets = new address[](3);
        requestData.assets[0] = address(token0);
        requestData.assets[1] = address(token1);
        requestData.assets[2] = address(token2);
        requestData.userData = abi.encode(uint256(2));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBalancerPoolHelper.InvalidJoinKind.selector));
        balancerPoolHelper.addLiquidity(alice, requestData);
    }

    function test_addLiquidity_failBptAmount() public {
        IBalancerVault.JoinPoolRequest memory requestData;
        requestData.assets = new address[](3);
        requestData.assets[0] = address(token0);
        requestData.assets[1] = address(token1);
        requestData.assets[2] = address(token2);
        requestData.userData = abi.encode(uint256(1));
        requestData.maxAmountsIn = new uint256[](3);
        requestData.maxAmountsIn[0] = 123;
        requestData.maxAmountsIn[1] = 123;
        requestData.maxAmountsIn[2] = 123;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        balancerPoolHelper.addLiquidity(alice, requestData);
    }

    function test_addLiquidity_failTokensMismatch() public {
        uint256 pairTokenAAmount = 1e18;
        (,,, IBalancerVault.JoinPoolRequest memory requestData) = balancerPoolHelper.addLiquidityQuote(
            pairTokenAIndex,
            pairTokenAAmount,
            0
        );
        requestData.assets[pairTokenBIndex] = alice;

        vm.startPrank(alice);
        deal(address(pairTokenA), alice, pairTokenAAmount, false);
        pairTokenA.approve(address(balancerPoolHelper), pairTokenAAmount);
        
        vm.expectRevert("BAL#520");
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
            uint256[] memory tokenAmounts, 
            /*uint256 expectedBptAmount*/,
            /*uint256 minBptAmount*/,
            IBalancerVault.JoinPoolRequest memory requestData
        ) = balancerPoolHelper.addLiquidityQuote(
            pairTokenAIndex,
            pairTokenAAmount,
            0
        );

        uint256 pairTokenBAmount = tokenAmounts[pairTokenBIndex];
        requestData.maxAmountsIn[pairTokenAIndex] = requestData.maxAmountsIn[pairTokenAIndex] * 9 / 10;

        deal(address(pairTokenA), alice, pairTokenAAmount*2, false);
        pairTokenA.approve(address(balancerPoolHelper), pairTokenAAmount*2);
        deal(address(pairTokenB), alice, pairTokenBAmount*2, false);
        pairTokenB.approve(address(balancerPoolHelper), pairTokenBAmount*2);

        vm.expectRevert("BAL#506"); // JOIN_ABOVE_MAX
        balancerPoolHelper.addLiquidity(alice, requestData);
    }
}

contract OrigamiBalancerStablePoolHelperSnapshotAddLiquidity_sUsdeUsdc is OrigamiBalancerStablePoolHelperTestAddLiquidity, OrigamiBalancerStablePoolHelperTestBase_2Tokens_sUsdeUsdc {
    function check_addLiquidityQuote_withSlippage(
        uint256[] memory tokenAmounts, 
        uint256 expectedBptAmount,
        uint256 minBptAmount
    ) public pure override {
        assertEq(tokenAmounts[0], 100e18);
        assertEq(tokenAmounts[1], 0);
        assertEq(tokenAmounts[2], 0);
        assertEq(expectedBptAmount, 104.840743485855390930e18);
        assertEq(minBptAmount,      103.792336050996837020e18);
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
        assertEq(expectedBptAmount, 104.840743485855390930e18);
        assertEq(minBptAmount, expectedBptAmount);
    }
}

contract OrigamiBalancerStablePoolHelperSnapshotAddLiquidity_rsEthWeth is OrigamiBalancerStablePoolHelperTestAddLiquidity, OrigamiBalancerStablePoolHelperTestBase_2Tokens_rsEthWeth {
    function check_addLiquidityQuote_withSlippage(
        uint256[] memory tokenAmounts, 
        uint256 expectedBptAmount,
        uint256 minBptAmount
    ) public pure virtual override {
        assertEq(tokenAmounts[0], 0);
        assertEq(tokenAmounts[1], 100e18);
        assertEq(tokenAmounts[2], 0);
        assertEq(expectedBptAmount, 100.869199665296076139e18);
        assertEq(minBptAmount,       99.860507668643115377e18);
        assertEq(minBptAmount, OrigamiMath.subtractBps(expectedBptAmount, 100, OrigamiMath.Rounding.ROUND_DOWN));
    }

    function check_addLiquidityQuote_noSlippage(
        uint256[] memory tokenAmounts, 
        uint256 expectedBptAmount,
        uint256 minBptAmount
    ) public pure override {
        assertEq(tokenAmounts[0], 0);
        assertEq(tokenAmounts[1], 100e18);
        assertEq(tokenAmounts[2], 0);
        assertEq(expectedBptAmount, 100.869199665296076139e18);
        assertEq(minBptAmount, expectedBptAmount);
    }
}

contract OrigamiBalancerStablePoolHelperSnapshotAddLiquidity_osEthWeth is OrigamiBalancerStablePoolHelperTestAddLiquidity, OrigamiBalancerStablePoolHelperTestBase_2Tokens_osEthWeth {
    function check_addLiquidityQuote_noSlippage(
        uint256[] memory tokenAmounts, 
        uint256 expectedBptAmount,
        uint256 minBptAmount
    ) public pure override {
        assertEq(tokenAmounts[0], 100e18);
        assertEq(tokenAmounts[1], 0);
        assertEq(tokenAmounts[2], 0);
        assertEq(expectedBptAmount, 98752553771233022232);
        assertEq(minBptAmount, expectedBptAmount);
    }

    function check_addLiquidityQuote_withSlippage(
        uint256[] memory tokenAmounts, 
        uint256 expectedBptAmount,
        uint256 minBptAmount
    ) public pure virtual override {
        assertEq(tokenAmounts[0], 100e18);
        assertEq(tokenAmounts[1], 0);
        assertEq(tokenAmounts[2], 0);
        assertEq(expectedBptAmount, 98752553771233022232);
        assertEq(minBptAmount, 97765028233520692009);
        assertEq(minBptAmount, OrigamiMath.subtractBps(expectedBptAmount, 100, OrigamiMath.Rounding.ROUND_DOWN));
    }
}

abstract contract OrigamiBalancerStablePoolHelperTestRemoveLiquidity is OrigamiBalancerStablePoolHelperTestBase_2Tokens {
    function test_removeLiquidityQuote_zeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        balancerPoolHelper.removeLiquidityQuote(pairTokenAIndex, 0, 0);
    }


    function test_removeLiquidityQuote_failBptIndex() public {
        uint256 bptIndex = balancerPoolHelper.bptIndex();
        address bptToken = address(balancerPoolHelper.poolTokens()[bptIndex]);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, bptToken));
        balancerPoolHelper.removeLiquidityQuote(bptIndex, 100, 0);
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

    function test_removeLiquidity_failInternalBalance() public {
        vm.startPrank(alice);

        uint256 bptAmount = 5_000e18;
        (,, IBalancerVault.ExitPoolRequest memory requestData) = balancerPoolHelper.removeLiquidityQuote(
            pairTokenAIndex,
            bptAmount,
            0
        );

        requestData.toInternalBalance = true;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        balancerPoolHelper.removeLiquidity(bptAmount, alice, requestData);
    }

    function test_removeLiquidity_failWrongBptAmount() public {
        vm.startPrank(alice);

        uint256 bptAmount = 5_000e18;
        (,, IBalancerVault.ExitPoolRequest memory requestData) = balancerPoolHelper.removeLiquidityQuote(
            pairTokenAIndex,
            bptAmount,
            0
        );

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAmount.selector, address(lpToken), bptAmount+1));
        balancerPoolHelper.removeLiquidity(bptAmount+1, alice, requestData);
    }

    function test_removeLiquidity_failExitKind() public {
        IBalancerVault.ExitPoolRequest memory requestData;
        requestData.assets = new address[](3);
        requestData.assets[0] = address(token0);
        requestData.assets[1] = address(token1);
        requestData.assets[2] = address(token2);
        requestData.userData = abi.encode(uint256(1), 123);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBalancerPoolHelper.InvalidExitKind.selector));
        balancerPoolHelper.removeLiquidity(100e18, alice, requestData);
    }

    function test_removeLiquidity_failTokensMismatch() public {
        addLiquidity();
        vm.startPrank(alice);
        
        uint256 bptAmount = lpToken.balanceOf(alice);
        (,,IBalancerVault.ExitPoolRequest memory requestData) = balancerPoolHelper.removeLiquidityQuote(
            pairTokenAIndex,
            bptAmount,
            0
        );
        requestData.assets[pairTokenBIndex] = alice;

        lpToken.approve(address(balancerPoolHelper), bptAmount);
        
        vm.expectRevert("BAL#520");
        balancerPoolHelper.removeLiquidity(bptAmount, alice, requestData);
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


contract OrigamiBalancerStablePoolHelperSnapshotRemoveLiquidity_sUsdeUsdc is OrigamiBalancerStablePoolHelperTestRemoveLiquidity, OrigamiBalancerStablePoolHelperTestBase_2Tokens_sUsdeUsdc {
    function check_removeLiquidityQuote_withSlippage(
        uint256[] memory expectedTokenAmounts,
        uint256[] memory minTokenAmounts
    ) public pure override {
        assertEq(expectedTokenAmounts.length, 3);
        assertEq(expectedTokenAmounts[0], 9.519990763356280907e18);
        assertEq(expectedTokenAmounts[1], 0);
        assertEq(expectedTokenAmounts[2], 0);

        assertEq(minTokenAmounts[0], OrigamiMath.subtractBps(expectedTokenAmounts[0], 100, OrigamiMath.Rounding.ROUND_DOWN));
        assertEq(minTokenAmounts[1], 0);
        assertEq(minTokenAmounts[2], 0);
    }

    function check_removeLiquidityQuote_noSlippage(
        uint256[] memory expectedTokenAmounts,
        uint256[] memory minTokenAmounts
    ) public pure override {
        assertEq(expectedTokenAmounts.length, 3);
        assertEq(expectedTokenAmounts[0], 9.519990763356280907e18);
        assertEq(expectedTokenAmounts[1], 0);
        assertEq(expectedTokenAmounts[2], 0);
        assertEq(minTokenAmounts[0], expectedTokenAmounts[0]);
        assertEq(minTokenAmounts[1], expectedTokenAmounts[1]);
        assertEq(minTokenAmounts[2], expectedTokenAmounts[2]);
    }

    function check_removeLiquidity_success_partialExit_pre() public view override {
        assertEq(lpToken.balanceOf(alice), 1_0483.937664508792742989e18);
        assertEq(pairTokenA.balanceOf(alice), 0);
        assertEq(pairTokenB.balanceOf(alice), 0);

        assertEq(lpToken.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenA.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenB.balanceOf(address(balancerPoolHelper)), 0);
    }

    function check_removeLiquidity_success_partialExit_post() public view override {
        assertEq(lpToken.balanceOf(alice), 1_0483.937664508792742989e18 - 5_000e18);
        assertEq(pairTokenA.balanceOf(alice), 4_760.110620739558656243e18);
        assertEq(pairTokenB.balanceOf(alice), 0);

        assertEq(lpToken.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenA.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenB.balanceOf(address(balancerPoolHelper)), 0);
    }
    
    function check_removeLiquidity_success_fullExit_pre() public view override {
        assertEq(lpToken.balanceOf(alice), 10_483.937664508792742989e18);
        assertEq(pairTokenA.balanceOf(alice), 0);
        assertEq(pairTokenB.balanceOf(alice), 0);

        assertEq(lpToken.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenA.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenB.balanceOf(address(balancerPoolHelper)), 0);
    }

    function check_removeLiquidity_success_fullExit_post() public view override {
        assertEq(lpToken.balanceOf(alice), 0);
        // Just a tiny bit of dust lost from initial amounts.
        assertEq(pairTokenA.balanceOf(alice), 9_980.871936679384740980e18);
        assertEq(pairTokenB.balanceOf(alice), 0);

        assertEq(lpToken.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenA.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenB.balanceOf(address(balancerPoolHelper)), 0);
    }
}

contract OrigamiBalancerStablePoolHelperSnapshotRemoveLiquidity_rsEthWeth is OrigamiBalancerStablePoolHelperTestRemoveLiquidity, OrigamiBalancerStablePoolHelperTestBase_2Tokens_rsEthWeth {
    function check_removeLiquidityQuote_withSlippage(
        uint256[] memory expectedTokenAmounts,
        uint256[] memory minTokenAmounts
    ) public pure override {
        assertEq(expectedTokenAmounts.length, 3);
        assertEq(expectedTokenAmounts[0], 0);
        assertEq(expectedTokenAmounts[1], 0);
        assertEq(expectedTokenAmounts[2], 10.127711302121226594e18);

        assertEq(minTokenAmounts[0], 0);
        assertEq(minTokenAmounts[1], 0);
        assertEq(minTokenAmounts[2], OrigamiMath.subtractBps(expectedTokenAmounts[2], 100, OrigamiMath.Rounding.ROUND_DOWN));
    }

    function check_removeLiquidityQuote_noSlippage(
        uint256[] memory expectedTokenAmounts,
        uint256[] memory minTokenAmounts
    ) public pure override {
        assertEq(expectedTokenAmounts.length, 3);
        assertEq(expectedTokenAmounts[0], 0);
        assertEq(expectedTokenAmounts[1], 0);
        assertEq(expectedTokenAmounts[2], 10.127711302121226594e18);

        assertEq(minTokenAmounts[0], expectedTokenAmounts[0]);
        assertEq(minTokenAmounts[1], expectedTokenAmounts[1]);
        assertEq(minTokenAmounts[2], expectedTokenAmounts[2]);
    }

    function check_removeLiquidity_success_partialExit_pre() public view override {
        assertEq(lpToken.balanceOf(alice), 10_081.175948299010291497e18);
        assertEq(pairTokenA.balanceOf(alice), 0);
        assertEq(pairTokenB.balanceOf(alice), 0);

        assertEq(lpToken.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenA.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenB.balanceOf(address(balancerPoolHelper)), 0);
    }

    function check_removeLiquidity_success_partialExit_post() public view override {
        assertEq(lpToken.balanceOf(alice), 10_081.175948299010291497e18 - 5_000e18);
        assertEq(pairTokenA.balanceOf(alice), 0);
        assertEq(pairTokenB.balanceOf(alice), 2_308.514282094980167011e18);

        assertEq(lpToken.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenA.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenB.balanceOf(address(balancerPoolHelper)), 0);
    }
    
    function check_removeLiquidity_success_fullExit_pre() public view override {
        assertEq(lpToken.balanceOf(alice), 10_081.175948299010291497e18);
        assertEq(pairTokenA.balanceOf(alice), 0);
        assertEq(pairTokenB.balanceOf(alice), 0);

        assertEq(lpToken.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenA.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenB.balanceOf(address(balancerPoolHelper)), 0);
    }

    function check_removeLiquidity_success_fullExit_post() public view override {
        assertEq(lpToken.balanceOf(alice), 0);
        // Just a tiny bit of dust lost from initial amounts.
        assertEq(pairTokenA.balanceOf(alice), 0);
        assertEq(pairTokenB.balanceOf(alice), 2_313.261779484171184067e18);

        assertEq(lpToken.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenA.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenB.balanceOf(address(balancerPoolHelper)), 0);
    }
}

contract OrigamiBalancerStablePoolHelperSnapshotRemoveLiquidity_osEthWeth is OrigamiBalancerStablePoolHelperTestRemoveLiquidity, OrigamiBalancerStablePoolHelperTestBase_2Tokens_osEthWeth {
    function check_removeLiquidityQuote_withSlippage(
        uint256[] memory expectedTokenAmounts,
        uint256[] memory minTokenAmounts
    ) public pure override {
        assertEq(expectedTokenAmounts.length, 3);
        assertEq(expectedTokenAmounts[0], 10.125515207415690838e18);
        assertEq(expectedTokenAmounts[1], 0);
        assertEq(expectedTokenAmounts[2], 0);

        assertEq(minTokenAmounts[0], 10.024260055341533929e18);
        assertEq(minTokenAmounts[1], 0);
        assertEq(minTokenAmounts[2], 0);
    }

    function check_removeLiquidityQuote_noSlippage(
        uint256[] memory expectedTokenAmounts,
        uint256[] memory minTokenAmounts
    ) public pure override {
        assertEq(expectedTokenAmounts.length, 3);
        assertEq(expectedTokenAmounts[0], 10.125515207415690838e18);
        assertEq(expectedTokenAmounts[1], 0);
        assertEq(expectedTokenAmounts[2], 0);

        assertEq(minTokenAmounts[0], expectedTokenAmounts[0]);
        assertEq(minTokenAmounts[1], expectedTokenAmounts[1]);
        assertEq(minTokenAmounts[2], expectedTokenAmounts[2]);
    }

    function check_removeLiquidity_success_partialExit_pre() public view override {
        assertEq(lpToken.balanceOf(alice), 9_865.723933495061747193e18);
        assertEq(pairTokenA.balanceOf(alice), 0);
        assertEq(pairTokenB.balanceOf(alice), 0);

        assertEq(lpToken.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenA.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenB.balanceOf(address(balancerPoolHelper)), 0);
    }

    function check_removeLiquidity_success_partialExit_post() public view override {
        assertEq(lpToken.balanceOf(alice), 9_865.723933495061747193e18 - 5_000e18);
        assertEq(pairTokenA.balanceOf(alice), 5_070.181455114480057322e18);
        assertEq(pairTokenB.balanceOf(alice), 0);

        assertEq(lpToken.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenA.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenB.balanceOf(address(balancerPoolHelper)), 0);
    }
    
    function check_removeLiquidity_success_fullExit_pre() public view override {
        assertEq(lpToken.balanceOf(alice), 9_865.723933495061747193e18);
        assertEq(pairTokenA.balanceOf(alice), 0);
        assertEq(pairTokenB.balanceOf(alice), 0);

        assertEq(lpToken.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenA.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenB.balanceOf(address(balancerPoolHelper)), 0);
    }

    function check_removeLiquidity_success_fullExit_post() public view override {
        assertEq(lpToken.balanceOf(alice), 0);
        // Just a tiny bit of dust lost from initial amounts.
        assertEq(pairTokenA.balanceOf(alice), 9_999.488888437666476003e18);
        assertEq(pairTokenB.balanceOf(alice), 0);

        assertEq(lpToken.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenA.balanceOf(address(balancerPoolHelper)), 0);
        assertEq(pairTokenB.balanceOf(address(balancerPoolHelper)), 0);
    }
}