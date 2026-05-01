pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { OrigamiHOhmVault } from "contracts/investments/olympus/OrigamiHOhmVault.sol";
import { IMonoCooler } from "contracts/interfaces/external/olympus/IMonoCooler.sol";
import { IGOHM } from "contracts/interfaces/external/olympus/IGOHM.sol";
import { IOlympusStaking } from "contracts/interfaces/external/olympus/IOlympusStaking.sol";
import { Call } from "contracts/interfaces/common/bundler/IOrigamiBundler.sol";
import { OrigamiBundlerTestUtils } from "test/foundry/unit/common/bundler/OrigamiBundlerTestUtils.t.sol";
import { OrigamiBundler } from "contracts/common/bundler/OrigamiBundler.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";

import { MockSwapPlugin } from "test/foundry/mocks/common/bundler/plugins/MockSwapPlugin.m.sol";
import { OrigamiBundlerPluginOhmStaking } from "contracts/common/bundler/plugins/OrigamiBundlerPluginOhmStaking.sol";
import { OrigamiBundlerPluginAaveV3Flash } from "contracts/common/bundler/plugins/OrigamiBundlerPluginAaveV3Flash.sol";
import { OrigamiBundlerPluginTbsV1 } from "contracts/common/bundler/plugins/OrigamiBundlerPluginTbsV1.sol";
import { IOrigamiBundlerPlugin } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { ITokenPrices } from "contracts/interfaces/common/ITokenPrices.sol";
import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { OrigamiBundlerPluginEntryPoint } from "contracts/common/bundler/plugins/OrigamiBundlerPluginEntryPoint.sol";
import {
    IOrigamiBundlerPluginEntryPoint
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginEntryPoint.sol";

import "forge-std/console.sol";

contract OrigamiHOhmZapTest is OrigamiTest, OrigamiBundlerTestUtils {
    using OrigamiMath for uint256;

    OrigamiBundler internal bundler;

    Call[] internal bundle;
    Call[] internal flCallbackBundle;

    MockSwapPlugin internal mockSwapPlugin;
    OrigamiBundlerPluginOhmStaking internal ohmStakingPlugin;
    OrigamiBundlerPluginAaveV3Flash internal aaveFlashPlugin;
    OrigamiBundlerPluginTbsV1 internal tbsPlugin;
    OrigamiBundlerPluginEntryPoint internal entryPointPlugin;

    OrigamiHOhmVault internal constant HOHM_VAULT = OrigamiHOhmVault(0x1DB1591540d7A6062Be0837ca3C808aDd28844F6);

    IMonoCooler internal constant COOLER = IMonoCooler(0xdb591Ea2e5Db886dA872654D58f6cc584b68e7cC);
    IERC20 internal constant OHM = IERC20(0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5);
    IGOHM internal constant GOHM = IGOHM(0x0ab87046fBb341D058F17CBC4c1133F25a20a52f);
    IERC20 internal constant USDS = IERC20(0xdC035D45d973E3EC169d2276DDab16f1e407384F);
    IOlympusStaking internal constant OLYMPUS_STAKING = IOlympusStaking(0xB63cac384247597756545b500253ff8E607a8020);
    ITokenPrices internal constant TOKEN_PRICES = ITokenPrices(0xD6c68aAc3C46E754cA54a551560ce07cB89dc20b);

    IERC20 internal constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 internal constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // Aave has a 5 bps flash loan fee
    address internal constant AAVE_POOL_ADDRESS_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    uint16 internal constant AAVE_REFERRAL_CODE = 0;

    function setUp() public {
        fork("mainnet", 23_416_146);

        bundler = new OrigamiBundler();
        ohmStakingPlugin = new OrigamiBundlerPluginOhmStaking(origamiMultisig, address(OLYMPUS_STAKING));
        aaveFlashPlugin = new OrigamiBundlerPluginAaveV3Flash(origamiMultisig, AAVE_POOL_ADDRESS_PROVIDER);
        tbsPlugin = new OrigamiBundlerPluginTbsV1(origamiMultisig);
        entryPointPlugin = new OrigamiBundlerPluginEntryPoint(origamiMultisig, PERMIT2, address(WETH));

        mockSwapPlugin = new MockSwapPlugin(address(bundler));

        vm.startPrank(origamiMultisig);
        aaveFlashPlugin.setBundlerApproved(address(bundler), true);
        ohmStakingPlugin.setBundlerApproved(address(bundler), true);
        tbsPlugin.setBundlerApproved(address(bundler), true);
        tbsPlugin.trustVault(address(HOHM_VAULT));
        entryPointPlugin.setBundlerApproved(address(bundler), true);
        vm.stopPrank();
    }

    struct QuoteInputs {
        uint256 USDS_per_USDC;
        uint256 USDC_per_WETH;
        uint256 USDS_per_WETH;
        uint256 OHM_per_WETH;
        uint256 USDS_per_OHM;
        uint256 OHM_per_gOHM;
        uint256 gOHM_per_hOHM; // collateral only
        uint256 USDS_per_hOHM; // debt only
        uint256 USD_value_of_hOHM; // net collateral - debt
    }

    struct ItemizedSlippageBps {
        uint256 USDC_to_OHM;
        uint256 WETH_to_OHM;
        uint256 gOHM_to_hOHM;
        uint256 hOHM_to_USDS;
        uint256 USDS_to_WETH;
    }

    struct AllInputs {
        address user;
        uint256 usdcZapAmountIn;

        QuoteInputs mktQuotes;
        ItemizedSlippageBps itemizedSlippageActual;
        ItemizedSlippageBps itemizedSlippageTolerance;

        uint256 flashLoanFeeBps; // derived from the underlying flash loan provider
        uint256 aggregateSlippageToleranceBps;
    }

    function fillTestData() internal view returns (AllInputs memory allInputs) {
        allInputs.user = alice;
        allInputs.usdcZapAmountIn = 5000e6;

        allInputs.mktQuotes.USDC_per_WETH = 4200e18;
        allInputs.mktQuotes.USDS_per_USDC = 0.9998e18;
        allInputs.mktQuotes.USDS_per_WETH = allInputs.mktQuotes.USDC_per_WETH * allInputs.mktQuotes.USDS_per_USDC / 1e18;
        allInputs.mktQuotes.OHM_per_WETH = 188e18;
        allInputs.mktQuotes.USDS_per_OHM = 1e18 * allInputs.mktQuotes.USDS_per_WETH / allInputs.mktQuotes.OHM_per_WETH;
        allInputs.mktQuotes.OHM_per_gOHM = 269.238508004e18; // constant conversion factor
        allInputs.mktQuotes.USD_value_of_hOHM = TOKEN_PRICES.tokenPrice(address(HOHM_VAULT)) / 1e12;

        (uint256[] memory assets, uint256[] memory liabilities) = HOHM_VAULT.convertFromShares(1e18);
        allInputs.mktQuotes.gOHM_per_hOHM = assets[0];
        allInputs.mktQuotes.USDS_per_hOHM = liabilities[0];

        allInputs.itemizedSlippageActual.USDC_to_OHM = 10;
        allInputs.itemizedSlippageActual.WETH_to_OHM = 50;
        allInputs.itemizedSlippageActual.gOHM_to_hOHM = 0; // @todo mock real slippage?
        allInputs.itemizedSlippageActual.hOHM_to_USDS = 0; // @todo mock real slippage?
        allInputs.itemizedSlippageActual.USDS_to_WETH = 15;

        allInputs.itemizedSlippageTolerance.USDC_to_OHM = 30;
        allInputs.itemizedSlippageTolerance.WETH_to_OHM = 40;
        allInputs.itemizedSlippageTolerance.gOHM_to_hOHM = 50;
        allInputs.itemizedSlippageTolerance.hOHM_to_USDS = 70;
        allInputs.itemizedSlippageTolerance.USDS_to_WETH = 80;

        allInputs.aggregateSlippageToleranceBps = 240; // 2.4% total est

        // Free if using Spark, 5bps if using Aave
        allInputs.flashLoanFeeBps = IPool(aaveFlashPlugin.POOL()).FLASHLOAN_PREMIUM_TOTAL();
    }

    function dumpAllInputs(AllInputs memory allInputs) internal pure {
        console.log("---- INPUTS ----");
        console.log("user:", allInputs.user);
        console.log("usdcZapAmountIn = %6e", allInputs.usdcZapAmountIn);
        console.log("flashLoanFeeBps = %i", allInputs.flashLoanFeeBps);
        console.log("");
        console.log("mktQuotes");
        console.log("\tUSDC_per_WETH = %18e", allInputs.mktQuotes.USDC_per_WETH);
        console.log("\tUSDS_per_USDC = %18e", allInputs.mktQuotes.USDS_per_USDC);
        console.log("\tUSDS_per_WETH = %18e", allInputs.mktQuotes.USDS_per_WETH);
        console.log("\tOHM_per_WETH = %18e", allInputs.mktQuotes.OHM_per_WETH);
        console.log("\tUSDS_per_OHM = %18e", allInputs.mktQuotes.USDS_per_OHM);
        console.log("\tOHM_per_gOHM = %18e", allInputs.mktQuotes.OHM_per_gOHM);
        console.log("\tgOHM_per_hOHM = %18e", allInputs.mktQuotes.gOHM_per_hOHM);
        console.log("\tUSDS_per_hOHM = %18e", allInputs.mktQuotes.USDS_per_hOHM);
        console.log("\tUSD_value_of_hOHM = %18e", allInputs.mktQuotes.USD_value_of_hOHM);
        console.log("");
        console.log("aggregate slippage = %i", allInputs.aggregateSlippageToleranceBps);
        console.log("itemized slippage");
        console.log("\tUSDC_to_OHM = %i", allInputs.itemizedSlippageTolerance.USDC_to_OHM);
        console.log("\tWETH_to_OHM = %i", allInputs.itemizedSlippageTolerance.WETH_to_OHM);
        console.log("\tgOHM_to_hOHM = %i", allInputs.itemizedSlippageTolerance.gOHM_to_hOHM);
        console.log("\thOHM_to_USDS = %i", allInputs.itemizedSlippageTolerance.hOHM_to_USDS);
        console.log("\tUSDS_to_WETH = %i", allInputs.itemizedSlippageTolerance.USDS_to_WETH);
        console.log("");
        console.log("actual slippage");
        console.log("\tUSDC_to_OHM = %i", allInputs.itemizedSlippageActual.USDC_to_OHM);
        console.log("\tWETH_to_OHM = %i", allInputs.itemizedSlippageActual.WETH_to_OHM);
        console.log("\tgOHM_to_hOHM = %i", allInputs.itemizedSlippageActual.gOHM_to_hOHM);
        console.log("\thOHM_to_USDS = %i", allInputs.itemizedSlippageActual.hOHM_to_USDS);
        console.log("\tUSDS_to_WETH = %i", allInputs.itemizedSlippageActual.USDS_to_WETH);
        console.log("");
    }

    /**
     * @dev Conceptually: We convert the user’s deposit into OHM, discount it for entry slippage, and run it through
     * the shared
     * collateral/debt pipeline to see how much WETH it can ultimately repay. This is the numerator.
     * The denominator is the net burden of each borrowed WETH: the fee-inclusive obligation minus the loan’s own
     * contribution
     * back through the same pipeline.
     * Their ratio gives the maximum flash loan size.
     */
    function solveForFlashLoanAmountSingleSlippage(AllInputs memory allInputs)
        internal
        pure
        returns (uint256 flashLoanWeth)
    {
        // This is the effective conversion rate of OHM to WETH, when swapping via the hOHM/USDS pipeline.
        /*
            effectiveOhmToWeth = (
                ((1-maxSlippagePct) * usdsPerHohm) /
                    (OhmPerGOhm * gOhmPerHohm * usdsPerWeth)
                )
        */
        uint256 effectiveOhmToWeth =
            ( /* [OHM/WETH] 18dp */
            (1e32
                    * (10_000 - allInputs.aggregateSlippageToleranceBps) /* bps */
                    * allInputs.mktQuotes.USDS_per_hOHM /* [USDS/hOHM] 18dp */
                )
                / (allInputs.mktQuotes.OHM_per_gOHM /* [OHM/gOHM] 18dp */
                    * allInputs.mktQuotes.gOHM_per_hOHM /* [gOHM/hOHM] 18dp */
                    * allInputs.mktQuotes.USDS_per_WETH /* [USDS/WETH] 18dp */
                    / 1e18)
        );

        /*
            flashLoanWeth = (
                (effectiveOhmToWeth * (userDepositInUSDC * UsdsPerUsdc / UsdsPerOhm)) /
                ((1 + flashFeePct) - effectiveOhmToWeth * OhmPerWeth)
            )

            - Numerator: “Repayment capacity created by the deposit alone.”
            - Denominator: “Net cost of borrowing one more unit of WETH” (cost minus self-financing).
            - Result: The maximum flash size is “how much capacity you start with” divided by “how expensive each extra unit is, net.”
        */
        flashLoanWeth =
        (( // [OHM^2 / WETH] 36dp
                    1e12
                    * effectiveOhmToWeth /* [OHM/WETH] 18dp */
                    * allInputs.usdcZapAmountIn /* [USDC] 6dp */
                    * allInputs.mktQuotes.USDS_per_USDC /* [USDS/USDC] 18dp */
                    / allInputs.mktQuotes.USDS_per_OHM /* [USDS/OHM] 18dp */
                )
                / ( // [OHM^2 / WETH^2] 18dp
                    ((1e18 * (10_000 + allInputs.flashLoanFeeBps) / 10_000) /* 18dp*/
                        - (effectiveOhmToWeth /* [OHM/WETH] 18dp */
                            * allInputs.mktQuotes.OHM_per_WETH /* [OHM/WETH] 18dp */
                            / 1e18))
                ));
    }

    /**
     * @dev Conceptually: We convert the user’s deposit into OHM, discount it for entry slippage, and run it through
     * the shared
     * collateral/debt pipeline to see how much WETH it can ultimately repay. This is the numerator.
     * The denominator is the net burden of each borrowed WETH: the fee-inclusive obligation minus the loan’s own
     * contribution
     * back through the same pipeline.
     * Their ratio gives the maximum flash loan size.
     */
    function solveForFlashLoanAmountSeparateSlippage(AllInputs memory allInputs)
        internal
        pure
        returns (uint256 flashLoanWeth)
    {
        // This is the effective conversion rate of OHM to WETH, when swapping via the hOHM/USDS pipeline.
        /*
            effectiveOhmToWeth = (
                (
                    (1 - maxSlippageGohmToHohmPct)
                    * (usdsPerHohm)
                    * (1 - maxSlippageHohmToUsdsPct)
                ) *
                (1 - maxSlippageUsdsToWethPct) /
                (OhmPerGOhm * gOhmPerHohm * usdsPerWeth)
            )
        */
        uint256 effectiveOhmToWeth =
            ( /* [OHM/WETH] 18dp */
            ( // 54 dp
                    1e24
                    * allInputs.mktQuotes.USDS_per_hOHM /* [USDS/hOHM] 18dp */
                    * (10_000 - allInputs.itemizedSlippageTolerance.USDS_to_WETH) /* bps */
                    * (10_000 - allInputs.itemizedSlippageTolerance.gOHM_to_hOHM) /* bps */
                    * (10_000 - allInputs.itemizedSlippageTolerance.hOHM_to_USDS) /* bps */
                )
                / ( // 36dp
                    allInputs.mktQuotes.OHM_per_gOHM /* [OHM/gOHM] 18dp */
                    * allInputs.mktQuotes.gOHM_per_hOHM /* [gOHM/hOHM] 18dp */
                    * allInputs.mktQuotes.USDS_per_WETH /* [USDS/WETH] 18dp */
                    / 1e18
                )
        );

        /*
            flashLoanWeth = (
                ( effectiveOhmToWeth * (userDepositInUSDC * UsdsPerUsdc / UsdsPerOhm) * (1 - maxSlippageUsdcToOhmPct) ) /
                ( (1 + flashFeePct) - effectiveOhmToWeth * OhmPerWeth * (1 - maxSlippageWethToOhmPct) )
            )

            - Numerator: “Repayment capacity created by the deposit alone.”
            - Denominator: “Net cost of borrowing one more unit of WETH” (cost minus self-financing).
            - Result: The maximum flash size is “how much capacity you start with” divided by “how expensive each extra unit is, net.”
        */
        flashLoanWeth =
        (( // [OHM^2 / WETH] 36dp
                    1e8
                    * (10_000 - allInputs.itemizedSlippageTolerance.USDC_to_OHM) /* bps */
                    * effectiveOhmToWeth /* [OHM/WETH] 18dp */
                    * allInputs.usdcZapAmountIn /* [USDC] 6dp */
                    * allInputs.mktQuotes.USDS_per_USDC /* [USDS/USDC] 18dp */
                    / allInputs.mktQuotes.USDS_per_OHM /* [USDS/OHM] 18dp */
                )
                / ( // [OHM^2 / WETH^2] 18dp
                    ((1e18 * (10_000 + allInputs.flashLoanFeeBps) / 10_000) /* 18dp*/
                        - ((10_000 - allInputs.itemizedSlippageTolerance.WETH_to_OHM) /* bps */
                            * effectiveOhmToWeth /* [OHM/WETH] 18dp */
                            * allInputs.mktQuotes.OHM_per_WETH /* [OHM/WETH] 18dp */
                            / 1e22))
                ));
    }

    /*
    For a zap, this can be better solved using a Flashloan, so the process would be:
        1/ User zaps to hOHM with 5k USDC
        2/ Swap 5k USDC from (1) -> 255.25 OHM (via a DEX)
        3/ Flashloan 2.4 WETH
            4/ Swap 2.4 WETH from (3)  -> 324.75 OHM (via a DEX)
            5/ Stake total 580 OHM from (2+4) -> 2.154 gOHM (via Olympus staking)
            6/ Use 2.154 gOHM from (5) to mint 580k hOHM, and also receive 6,380 USDS
            7/ Swap 6,380 USDS -> 2.4 WETH (via a DEX)
            8/ Repay 2.4 WETH flashloan
        9/ Return 580k hOHM to user + any surplus WETH

    See: https://docs.google.com/spreadsheets/d/1b18JksnTSYudn1sCcVgKKO7esYHb_g1B7MLXKrAqd1E/edit?gid=355034419#gid=355034419
    */
    function test_fuzz_zapIntoHohm(bool unifiedMaxSlippage) public {
        AllInputs memory allInputs = fillTestData();
        dumpAllInputs(allInputs);

        // if separate slippage tolerances are preferred
        uint256 flashLoanWethAmount = unifiedMaxSlippage
            ? solveForFlashLoanAmountSingleSlippage(allInputs)
            : solveForFlashLoanAmountSeparateSlippage(allInputs);

        assertEq(
            flashLoanWethAmount,
            unifiedMaxSlippage ? 1.107584119065157517e18 : 1.109157168610082094e18,
            "flashLoanWethAmount"
        );

        // 1: Pull tokens from USER into the first plugin step
        bundle.push(
            createCall(
                entryPointPlugin,
                abi.encodeCall(
                    IOrigamiBundlerPluginEntryPoint.erc20TransferFromInitiator,
                    (address(USDC), address(mockSwapPlugin), allInputs.usdcZapAmountIn)
                )
            )
        );

        // 2: Swap USDC for OHM ==> OHM staking plugin
        uint256 step2__boughtOhm =
            ( /* [OHM] 1e9 */
            (10_000 - allInputs.itemizedSlippageActual.USDC_to_OHM) /* bps */
                * allInputs.usdcZapAmountIn /* [USDC] 1e6 */
                * allInputs.mktQuotes.USDS_per_USDC /* [USDS/USDC] 1e18 */
                / (allInputs.mktQuotes.USDS_per_OHM /* [USDS/OHM] 1e18 */
                    * 10 // to get to 1e9
                )
        );
        assertEq(step2__boughtOhm, 223.585714285e9, "step2__boughtOhm");
        deal(address(OHM), address(mockSwapPlugin), OHM.balanceOf(address(mockSwapPlugin)) + step2__boughtOhm);

        bundle.push(
            createCall(
                mockSwapPlugin,
                abi.encodeCall(
                    MockSwapPlugin.swap,
                    (
                        address(USDC),
                        allInputs.usdcZapAmountIn,
                        address(OHM),
                        step2__boughtOhm,
                        address(ohmStakingPlugin)
                    )
                )
            )
        );

        // Nested in the flashloan
        uint256 step3_4__expectedHohmShares;
        uint256 step3_4__expectedUsds;
        uint256 step3_5__boughtWeth;
        {
            // 3.1: Send the flashloan amount to the swap plugin
            flCallbackBundle.push(
                createCall(
                    aaveFlashPlugin,
                    abi.encodeCall(
                        IOrigamiBundlerPlugin.erc20TransferBalance,
                        (address(WETH), address(mockSwapPlugin), flashLoanWethAmount)
                    )
                )
            );

            // 3.2: Swap all WETH for OHM ==> OHM staking plugin
            uint256 step3_2__boughtOhm =
                ( /* [OHM] 1e9 */
                flashLoanWethAmount /* [WETH 18dp] */
                    * allInputs.mktQuotes.OHM_per_WETH /* [OHM/WETH 18dp] */
                    * (10_000 - allInputs.itemizedSlippageActual.WETH_to_OHM) /* bps */
                    / 1e31 // to get to 1e9
            );
            assertEq(step3_2__boughtOhm, unifiedMaxSlippage ? 207.184685312e9 : 207.47893996e9, "step3_2__boughtOhm");
            deal(address(OHM), address(mockSwapPlugin), OHM.balanceOf(address(mockSwapPlugin)) + step3_2__boughtOhm);

            flCallbackBundle.push(
                createCall(
                    mockSwapPlugin,
                    abi.encodeCall(
                        MockSwapPlugin.swap,
                        (
                            address(WETH),
                            flashLoanWethAmount,
                            address(OHM),
                            step3_2__boughtOhm,
                            address(ohmStakingPlugin)
                        )
                    )
                )
            );

            // 3.3: Stake all OHM from (2) + (3.3) (via Olympus staking)
            // @note: This might be possible as part of the swap in (3.2) rather than 2 steps
            // however its not guaranteed different swap providers route it ok.
            uint256 step3_3__expectedGohm =
                (1e27 * (step2__boughtOhm + step3_2__boughtOhm) /* [OHM] 1e9 */
                    / allInputs.mktQuotes.OHM_per_gOHM /* [OHM/gOHM] 1e18 */
            );
            assertEq(
                step3_3__expectedGohm,
                unifiedMaxSlippage ? 1.599958352133641175e18 : 1.6010512665543214e18,
                "step3_3__expectedGohm"
            );
            flCallbackBundle.push(
                createCall(
                    ohmStakingPlugin,
                    abi.encodeCall(OrigamiBundlerPluginOhmStaking.stakeBalanceToGOhm, (address(tbsPlugin)))
                )
            );

            // 3.4: Use all gOHM from (3.3) to mint hOHM, and also receive USDS liabilities
            {
                (uint256 expectedShares,/*uint256[] memory assets*/, uint256[] memory expectedLiabilities) =
                    HOHM_VAULT.previewJoinWithToken(address(GOHM), step3_3__expectedGohm);
                step3_4__expectedUsds = expectedLiabilities[0];
                step3_4__expectedHohmShares = expectedShares;
            }
            assertEq(
                step3_4__expectedHohmShares,
                unifiedMaxSlippage ? 429_943.59384158700612299e18 : 430_237.283707427528299933e18,
                "step3_4__expectedHohmShares"
            );
            assertEq(
                step3_4__expectedUsds,
                unifiedMaxSlippage ? 4753.713458226281277598e18 : 4756.960668994829585477e18,
                "step3_4__expectedUsds"
            );

            flCallbackBundle.push(
                createCall(
                    tbsPlugin,
                    abi.encodeCall(
                        OrigamiBundlerPluginTbsV1.joinWithAssetBalance,
                        (address(HOHM_VAULT), address(GOHM), address(mockSwapPlugin))
                    )
                )
            );

            // 3.5: Swap all USDS -> WETH (via a DEX)
            step3_5__boughtWeth =
            ( /* [WETH] 1e18 */
                1e14 * step3_4__expectedUsds /* [USDS] 18dp */
                    * (10_000 - allInputs.itemizedSlippageActual.USDS_to_WETH)
                    / /* bps */ allInputs.mktQuotes.USDS_per_WETH /* [USDS/WETH] 18dp */
            );
            assertEq(
                step3_5__boughtWeth,
                unifiedMaxSlippage ? 1.130364855837582243e18 : 1.131136995968559745e18,
                "step3_5__boughtWeth"
            );
            deal(address(WETH), address(mockSwapPlugin), WETH.balanceOf(address(mockSwapPlugin)) + step3_5__boughtWeth);

            flCallbackBundle.push(
                createCall(
                    mockSwapPlugin,
                    abi.encodeCall(
                        MockSwapPlugin.swap,
                        (address(USDS), type(uint256).max, address(WETH), step3_5__boughtWeth, address(aaveFlashPlugin))
                    )
                )
            );
        }

        // 3: Flashloan WETH
        bundle.push(
            createCall(
                aaveFlashPlugin,
                abi.encodeCall(
                    OrigamiBundlerPluginAaveV3Flash.flashLoan,
                    (address(WETH), flashLoanWethAmount, AAVE_REFERRAL_CODE, abi.encode(flCallbackBundle))
                ),
                keccak256(abi.encode(flCallbackBundle))
            )
        );

        // 4: Refund any left over WETH
        bundle.push(
            createCall(
                aaveFlashPlugin,
                abi.encodeCall(IOrigamiBundlerPlugin.erc20TransferBalance, (address(WETH), allInputs.user, 0))
            )
        );

        // 5: Send hOHM to user
        bundle.push(
            createCall(
                mockSwapPlugin,
                abi.encodeCall(
                    IOrigamiBundlerPlugin.erc20TransferBalance,
                    (address(HOHM_VAULT), allInputs.user, step3_4__expectedHohmShares)
                )
            )
        );

        vm.startPrank(allInputs.user);

        // Deal and approve the first step in the bundle
        deal(address(USDC), allInputs.user, allInputs.usdcZapAmountIn);
        USDC.approve(address(entryPointPlugin), allInputs.usdcZapAmountIn);
        bundler.multicall(bundle);

        assertEq(HOHM_VAULT.balanceOf(alice), step3_4__expectedHohmShares, "Alice gets expected hOHM shares");
        assertEq(HOHM_VAULT.balanceOf(address(mockSwapPlugin)), 0);
        assertEq(HOHM_VAULT.balanceOf(address(ohmStakingPlugin)), 0);
        assertEq(HOHM_VAULT.balanceOf(address(aaveFlashPlugin)), 0);
        assertEq(HOHM_VAULT.balanceOf(address(tbsPlugin)), 0);

        assertEq(USDC.balanceOf(alice), 0);
        // Came from the initial user balance which was swapped for OHM
        assertEq(USDC.balanceOf(address(mockSwapPlugin)), allInputs.usdcZapAmountIn, "Swapper gets expected USDC in");
        assertEq(USDC.balanceOf(address(ohmStakingPlugin)), 0);
        assertEq(USDC.balanceOf(address(aaveFlashPlugin)), 0);
        assertEq(USDC.balanceOf(address(tbsPlugin)), 0);

        assertEq(USDS.balanceOf(alice), 0);
        // Came from the hOHM debt which was swapped for WETH
        assertEq(USDS.balanceOf(address(mockSwapPlugin)), step3_4__expectedUsds, "Swapper gets expected USDS in");
        assertEq(USDS.balanceOf(address(ohmStakingPlugin)), 0);
        assertEq(USDS.balanceOf(address(aaveFlashPlugin)), 0);
        assertEq(USDS.balanceOf(address(tbsPlugin)), 0);

        assertEq(OHM.balanceOf(alice), 0);
        assertEq(OHM.balanceOf(address(mockSwapPlugin)), 0);
        assertEq(OHM.balanceOf(address(ohmStakingPlugin)), 0);
        assertEq(OHM.balanceOf(address(aaveFlashPlugin)), 0);
        assertEq(OHM.balanceOf(address(tbsPlugin)), 0);

        assertEq(GOHM.balanceOf(alice), 0);
        assertEq(GOHM.balanceOf(address(mockSwapPlugin)), 0);
        assertEq(GOHM.balanceOf(address(ohmStakingPlugin)), 0);
        assertEq(GOHM.balanceOf(address(aaveFlashPlugin)), 0);
        assertEq(GOHM.balanceOf(address(tbsPlugin)), 0);

        // Surplus WETH was refunded to Alice
        uint256 expectedWethSurplus =
            (step3_5__boughtWeth - flashLoanWethAmount.addBps(allInputs.flashLoanFeeBps, OrigamiMath.Rounding.ROUND_UP));
        assertEq(WETH.balanceOf(alice), expectedWethSurplus, "Alice gets refunded expected WETH");
        // Came from the flashloan WETH which was swapped for OHM
        assertEq(WETH.balanceOf(address(mockSwapPlugin)), flashLoanWethAmount, "Swapper gets expected WETH in");
        assertEq(WETH.balanceOf(address(ohmStakingPlugin)), 0);
        assertEq(WETH.balanceOf(address(aaveFlashPlugin)), 0);
        assertEq(WETH.balanceOf(address(tbsPlugin)), 0);

        uint256 usdValueIn = allInputs.usdcZapAmountIn * 1e12;
        assertEq(usdValueIn, 5000e18);
        uint256 usdValueOut =
            ((step3_4__expectedHohmShares * allInputs.mktQuotes.USD_value_of_hOHM / 1e18)
                + (expectedWethSurplus * allInputs.mktQuotes.USDC_per_WETH / 1e18));
        assertEq(usdValueOut, unifiedMaxSlippage ? 4997.1819478417791174e18 : 4997.164577836859218327e18);
        uint256 priceImpact = (1e18 * (usdValueIn - usdValueOut) / usdValueIn);
        assertEq(priceImpact, unifiedMaxSlippage ? 0.000563610431644176e18 : 0.000567084432628156e18); // 0.056%
    }
}
