pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiLendingBorrower } from "contracts/interfaces/investments/lending/IOrigamiLendingBorrower.sol";
import { IOrigamiLovTokenErc4626Manager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenErc4626Manager.sol";
import { OrigamiLovTokenTestBase } from "test/foundry/unit/investments/lovToken/OrigamiLovTokenBase.t.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { Range } from "contracts/libraries/Range.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiLovTokenErc4626Manager } from "contracts/investments/lovToken/managers/OrigamiLovTokenErc4626Manager.sol";
import { OrigamiDebtToken } from "contracts/investments/lending/OrigamiDebtToken.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { MockSDaiToken } from "contracts/test/external/maker/MockSDaiToken.m.sol";
import { OrigamiLovToken } from "contracts/investments/lovToken/OrigamiLovToken.sol";
import { DummyLendingClerk } from "test/foundry/mocks/investments/lending/DummyLendingClerk.m.sol";
import { DummyOracle } from "contracts/test/common/DummyOracle.sol";
import { OrigamiStableChainlinkOracle } from "contracts/common/oracle/OrigamiStableChainlinkOracle.sol";
import { OrigamiCrossRateOracle } from "contracts/common/oracle/OrigamiCrossRateOracle.sol";
import { DummyLovTokenSwapper } from "contracts/test/investments/lovToken/DummyLovTokenSwapper.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";

contract TestERC4626 is MockSDaiToken {
    uint256 public maxRedeemOverride;

    constructor(IERC20 _asset) MockSDaiToken(_asset) {}

    function setMaxRedeemOverride(uint256 value) external {
        maxRedeemOverride = value;
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        if (maxRedeemOverride != 0) return maxRedeemOverride;

        return balanceOf(owner);
    }
}

contract OrigamiLovTokenErc4626ManagerTestBase is OrigamiLovTokenTestBase {
    using OrigamiMath for uint256;

    event OracleSet(address indexed oracle);
    event SwapperSet(address indexed swapper);
    event LendingClerkSet(address indexed lendingClerk);

    OrigamiLovTokenErc4626Manager public managerImpl;
    DummyMintableToken public usdcToken;
    DummyLendingClerk public lendingClerk;
    DummyLovTokenSwapper public swapper;

    DummyOracle internal daiUsdOracle;
    DummyOracle internal usdcUsdOracle;
    OrigamiStableChainlinkOracle public origamiDaiUsdOracle;
    OrigamiStableChainlinkOracle public origamiUsdcUsdOracle; // 6dp USDC
    OrigamiStableChainlinkOracle public origamiIUsdcUsdOracle; // 18dp iUSDC
    OrigamiCrossRateOracle public daiUsdcOracle;  // 6dp USDC
    OrigamiCrossRateOracle public daiIUsdcOracle; // 18dp iUSDC

    function setUp() public override {
        daiToken = new DummyMintableToken(origamiMultisig, "DAI", "DAI", 18);
        usdcToken = new DummyMintableToken(origamiMultisig, "USDC", "USDC", 6);
        sDaiToken = new TestERC4626(daiToken);
        sDaiToken.setInterestRate(SDAI_INTEREST_RATE);
        doMint(daiToken, address(sDaiToken), 100_000_000e18);

        tokenPrices = new TokenPrices(30);
        lovToken = new OrigamiLovToken(
            origamiMultisig, 
            "Origami LOV TOKEN", 
            "lovToken", 
            500, 
            feeCollector, 
            address(tokenPrices),
            type(uint256).max
        );
        managerImpl = new OrigamiLovTokenErc4626Manager(origamiMultisig, address(daiToken), address(usdcToken), address(sDaiToken), address(lovToken));
        OrigamiDebtToken iUsdc = new OrigamiDebtToken("Origami iUSDC", "iUSDC", origamiMultisig);
        lendingClerk = new DummyLendingClerk(address(usdcToken), address(iUsdc));
        swapper = new DummyLovTokenSwapper();

        // Oracles
        {
            daiUsdOracle = new DummyOracle(
                DummyOracle.Answer({
                    roundId: 1,
                    answer: 1.00044127e8,
                    startedAt: 0,
                    updatedAtLag: 0,
                    answeredInRound: 1
                }),
                8
            );

            usdcUsdOracle = new DummyOracle(
                DummyOracle.Answer({
                    roundId: 1,
                    answer: 1.00006620e8,
                    startedAt: 0,
                    updatedAtLag: 0,
                    answeredInRound: 1
                }),
                8
            );

            origamiDaiUsdOracle = new OrigamiStableChainlinkOracle(
                origamiMultisig,
                IOrigamiOracle.BaseOracleParams(
                    "DAI/USD",
                    address(daiToken),
                    18, 
                    INTERNAL_USD_ADDRESS,
                    18
                ),
                1e18,
                address(daiUsdOracle),
                365 days,
                Range.Data(0.95e18, 1.05e18),
                true,
                true
            );
            origamiUsdcUsdOracle = new OrigamiStableChainlinkOracle(
                origamiMultisig,
                IOrigamiOracle.BaseOracleParams(
                    "USDC/USD",
                    address(usdcToken),
                    6, 
                    INTERNAL_USD_ADDRESS,
                    18
                ),
                1e18,
                address(usdcUsdOracle),
                365 days,
                Range.Data(0.95e18, 1.05e18),
                true,
                true
            );
            origamiIUsdcUsdOracle = new OrigamiStableChainlinkOracle(
                origamiMultisig,
                IOrigamiOracle.BaseOracleParams(
                    "IUSDC/USD",
                    address(usdcToken),
                    18, 
                    INTERNAL_USD_ADDRESS,
                    18
                ),
                1e18,
                address(usdcUsdOracle),
                365 days,
                Range.Data(0.95e18, 1.05e18),
                true,
                true
            );

            daiUsdcOracle = new OrigamiCrossRateOracle(
                IOrigamiOracle.BaseOracleParams(
                    "DAI/USDC",
                    address(daiToken),
                    18,
                    address(usdcToken),
                    6
                ),
                address(origamiDaiUsdOracle),
                address(origamiUsdcUsdOracle),
                address(0)
            );
            daiIUsdcOracle = new OrigamiCrossRateOracle(
                IOrigamiOracle.BaseOracleParams(
                    "DAI/IUSDC",
                    address(daiToken),
                    18,
                    address(usdcToken),
                    18
                ),
                address(origamiDaiUsdOracle),
                address(origamiIUsdcUsdOracle),
                address(0)
            );
        }

        // Link up and set policy
        {
            vm.startPrank(origamiMultisig);

            userALRange = Range.Data(1.001e18, type(uint128).max);
            rebalanceALRange = Range.Data(1.05e18, 1.15e18);

            managerImpl.setLendingClerk(address(lendingClerk));
            managerImpl.setOracle(address(daiIUsdcOracle));
            managerImpl.setUserALRange(userALRange.floor, userALRange.ceiling);
            managerImpl.setRebalanceALRange(rebalanceALRange.floor, rebalanceALRange.ceiling);
            managerImpl.setSwapper(address(swapper));
            managerImpl.setFeeConfig(MIN_DEPOSIT_FEE_BPS, MIN_EXIT_FEE_BPS, FEE_LEVERAGE_FACTOR);

            lovToken.setManager(address(managerImpl));

            vm.stopPrank();
        }

        // Fund the mocks
        {
            // LendingClerk gets 5mm USDC
            deal(address(usdcToken), address(lendingClerk), 500_000_000e6, true);

            // Swapper gets 5mm USDC + 5mm DAI
            deal(address(daiToken), address(swapper), 500_000_000e18, true);
            deal(address(usdcToken), address(swapper), 500_000_000e6, true);
        }
    }

    // Increase liabilities to lower A/L
    function doRebalanceDown(uint256 targetAL) internal override returns (uint256 reservesAmount) {
        // reserves (sDAI) amount
        reservesAmount = solveRebalanceDownAmount(address(managerImpl), targetAL);
        doRebalanceDownFor(reservesAmount);
    }

    function doRebalanceDownFor(uint256 reservesAmount) internal {
        // How much DAI to get that much reserves
        uint256 daiDepositAmount = sDaiToken.previewMint(reservesAmount);

        uint256 usdcBorrowAmount = daiUsdcOracle.convertAmount(
            address(daiToken),
            daiDepositAmount,
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN
        );

        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: daiDepositAmount // USDC->DAI using the oracle price
        });

        vm.startPrank(origamiMultisig);
        managerImpl.rebalanceDown(
            IOrigamiLovTokenErc4626Manager.RebalanceDownParams(
                usdcBorrowAmount, 
                abi.encode(swapData), 
                reservesAmount,
                0,
                type(uint128).max
            )
        );
    }
}

contract OrigamiLovTokenErc4626ManagerTestAdmin is OrigamiLovTokenErc4626ManagerTestBase {
    function test_initialization() public {
        assertEq(managerImpl.owner(), origamiMultisig);
        assertEq(managerImpl.name(), "lovToken");
        assertEq(managerImpl.version(), "1.0.0");
        assertEq(address(managerImpl.lovToken()), address(lovToken));

        assertEq(address(managerImpl.depositAsset()), address(daiToken));
        assertEq(address(managerImpl.debtToken()), address(usdcToken));
        assertEq(address(managerImpl.reserveToken()), address(sDaiToken));
        assertEq(address(managerImpl.lendingClerk()), address(lendingClerk));
        assertEq(address(managerImpl.swapper()), address(swapper));
        assertEq(address(managerImpl.baseToken()), address(sDaiToken));
        assertEq(address(managerImpl.debtAssetToDepositAssetOracle()), address(daiIUsdcOracle));

        (uint64 minDepositFee, uint64 minExitFee, uint64 feeLeverageFactor) = managerImpl.getFeeConfig();
        assertEq(minDepositFee, MIN_DEPOSIT_FEE_BPS);
        assertEq(minExitFee, MIN_EXIT_FEE_BPS);
        assertEq(feeLeverageFactor, FEE_LEVERAGE_FACTOR);

        (uint128 floor, uint128 ceiling) = managerImpl.userALRange();
        assertEq(floor, 1.001e18);
        assertEq(ceiling, type(uint128).max);

        (floor, ceiling) = managerImpl.rebalanceALRange();
        assertEq(floor, 1.05e18);
        assertEq(ceiling, 1.15e18);

        assertEq(managerImpl.areInvestmentsPaused(), false);
        assertEq(managerImpl.areExitsPaused(), false);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        assertEq(managerImpl.reservesBalance(), 0);
        assertEq(managerImpl.assetToLiabilityRatio(), type(uint128).max);
        assertEq(managerImpl.effectiveExposure(IOrigamiOracle.PriceType.SPOT_PRICE), type(uint128).max);
        assertEq(managerImpl.effectiveExposure(IOrigamiOracle.PriceType.HISTORIC_PRICE), type(uint128).max);
        assertEq(managerImpl.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(managerImpl.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);

        address[] memory tokens = managerImpl.acceptedInvestTokens();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], address(daiToken));
        assertEq(tokens[1], address(sDaiToken));

        tokens = managerImpl.acceptedExitTokens();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], address(daiToken));
        assertEq(tokens[1], address(sDaiToken));
    }

    function test_setLendingClerk_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        managerImpl.setLendingClerk(address(0));
    }

    function test_setLendingClerk_success() public {
        vm.startPrank(origamiMultisig);

        vm.expectEmit(address(managerImpl));
        emit LendingClerkSet(alice);
        managerImpl.setLendingClerk(alice);
        assertEq(address(managerImpl.lendingClerk()), alice);
        assertEq(usdcToken.allowance(address(managerImpl), alice), type(uint256).max);

        vm.expectEmit(address(managerImpl));
        emit LendingClerkSet(bob);
        managerImpl.setLendingClerk(bob);
        assertEq(address(managerImpl.lendingClerk()), bob);
        assertEq(usdcToken.allowance(address(managerImpl), alice), 0);
        assertEq(usdcToken.allowance(address(managerImpl), bob), type(uint256).max);
    }

    function test_setSwapper_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        managerImpl.setSwapper(address(0));
    }

    function test_setSwapper_success() public {
        vm.startPrank(origamiMultisig);

        vm.expectEmit(address(managerImpl));
        emit SwapperSet(alice);
        managerImpl.setSwapper(alice);
        assertEq(address(managerImpl.swapper()), alice);
        assertEq(daiToken.allowance(address(managerImpl), alice), type(uint256).max);
        assertEq(usdcToken.allowance(address(managerImpl), alice), type(uint256).max);

        vm.expectEmit(address(managerImpl));
        emit SwapperSet(bob);
        managerImpl.setSwapper(bob);
        assertEq(address(managerImpl.swapper()), bob);
        assertEq(daiToken.allowance(address(managerImpl), alice), 0);
        assertEq(daiToken.allowance(address(managerImpl), bob), type(uint256).max);
        assertEq(usdcToken.allowance(address(managerImpl), alice), 0);
        assertEq(usdcToken.allowance(address(managerImpl), bob), type(uint256).max);
    }

    function test_setOracleConfig_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        managerImpl.setOracle(address(0));

        OrigamiStableChainlinkOracle badOracle = new OrigamiStableChainlinkOracle(
            origamiMultisig,
            IOrigamiOracle.BaseOracleParams(
                "alice/IUSDC",
                alice,
                18, 
                address(usdcToken),
                18
            ),
            1e18,
            address(usdcUsdOracle),
            365 days,
            Range.Data(0.95e18, 1.05e18),
            true,
            true
        );

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        managerImpl.setOracle(address(badOracle));

        badOracle = new OrigamiStableChainlinkOracle(
            origamiMultisig,
            IOrigamiOracle.BaseOracleParams(
                "DAI/alice",
                address(daiToken),
                18, 
                alice,
                18
            ),
            1e18,
            address(usdcUsdOracle),
            365 days,
            Range.Data(0.95e18, 1.05e18),
            true,
            true
        );

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        managerImpl.setOracle(address(badOracle));
    }

    function test_setOracle() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(managerImpl));
        emit OracleSet(address(daiUsdcOracle));
        managerImpl.setOracle(address(daiUsdcOracle));      
        assertEq(address(managerImpl.debtAssetToDepositAssetOracle()), address(daiUsdcOracle));

        OrigamiCrossRateOracle oracle = new OrigamiCrossRateOracle(
            IOrigamiOracle.BaseOracleParams(
                "DAI/IUSDC",
                address(daiToken),
                18,
                address(usdcToken),
                18
            ),
            address(origamiDaiUsdOracle),
            address(origamiIUsdcUsdOracle),
            address(0)
        );

        vm.expectEmit(address(managerImpl));
        emit OracleSet(address(oracle));
        managerImpl.setOracle(address(oracle));
        assertEq(address(managerImpl.debtAssetToDepositAssetOracle()), address(oracle));
    }

    function test_recoverToken_nonReserves() public {
        check_recoverToken(address(managerImpl));
    }

    function test_recoverToken_fail_reservesOver() public {
        uint256 amount = 5e18;

        bootstrapSDai(123_456e18);
        investWithSDai(100e18, alice);

        // Mint just less than the amount as a donation
        uint256 donationAmount = amount-1;
        mintSDai(donationAmount, address(managerImpl));

        uint256 balanceBefore = sDaiToken.balanceOf(address(managerImpl));
        uint256 reservesBalanceBefore = managerImpl.reservesBalance();
        assertEq(balanceBefore, 100e18 + donationAmount);
        assertEq(reservesBalanceBefore, 100e18);

        vm.startPrank(origamiMultisig);
        
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAmount.selector, address(sDaiToken), amount));
        managerImpl.recoverToken(address(sDaiToken), alice, amount);
    }

    function test_recoverToken_success_reservesUnder() public {
        uint256 amount = 5e18;

        bootstrapSDai(123_456e18);
        investWithSDai(100e18, alice);

        // Mint the exact amount as a donation
        uint256 donationAmount = amount;
        mintSDai(donationAmount, address(managerImpl));

        uint256 balanceBefore = sDaiToken.balanceOf(address(managerImpl));
        uint256 reservesBalanceBefore = managerImpl.reservesBalance();
        assertEq(balanceBefore, 100e18 + donationAmount);
        assertEq(reservesBalanceBefore, 100e18);

        vm.startPrank(origamiMultisig);

        vm.expectEmit();
        emit CommonEventsAndErrors.TokenRecovered(bob, address(sDaiToken), amount);
        managerImpl.recoverToken(address(sDaiToken), bob, amount);

        assertEq(sDaiToken.balanceOf(bob), amount);
        assertEq(sDaiToken.balanceOf(address(managerImpl)), 100e18);
        assertEq(managerImpl.reservesBalance(), 100e18);
    }
}

contract OrigamiLovTokenErc4626ManagerTestAccess is OrigamiLovTokenErc4626ManagerTestBase {
    function test_access_setLendingClerk() public {
        expectElevatedAccess();
        managerImpl.setLendingClerk(alice);
    }

    function test_access_setSwapper() public {
        expectElevatedAccess();
        managerImpl.setSwapper(alice);
    }

    function test_access_setOracle() public {
        expectElevatedAccess();
        managerImpl.setOracle(alice);
    }

    function test_access_rebalanceUp() public {
        expectElevatedAccess();
        managerImpl.rebalanceUp(
            IOrigamiLovTokenErc4626Manager.RebalanceUpParams(
                0, 0, "", 0, 0, type(uint128).max
            )
        );
    }

    function test_access_forceRebalanceUp() public {
        expectElevatedAccess();
        managerImpl.forceRebalanceUp(
            IOrigamiLovTokenErc4626Manager.RebalanceUpParams(
                0, 0, "", 0, 0, type(uint128).max
            )
        );
    }

    function test_access_rebalanceDown() public {
        expectElevatedAccess();
        managerImpl.rebalanceDown(
            IOrigamiLovTokenErc4626Manager.RebalanceDownParams(
                0, "", 0, 0, type(uint128).max
            )
        );
    }

    function test_access_forceRebalanceDown() public {
        expectElevatedAccess();
        managerImpl.forceRebalanceDown(
            IOrigamiLovTokenErc4626Manager.RebalanceDownParams(
                0, "", 0, 0, type(uint128).max
            )
        );
    }

    function test_access_recoverToken() public {
        expectElevatedAccess();
        managerImpl.recoverToken(alice, alice, 0);
    }
}

contract OrigamiLovTokenErc4626ManagerTestRebalanceDown is OrigamiLovTokenErc4626ManagerTestBase {
    using OrigamiMath for uint256;

    event Rebalance(
        int256 collateralChange,
        int256 debtChange,
        uint256 alRatioBefore,
        uint256 alRatioAfter
    );

    function test_rebalanceDown_fail_fresh() public {
        doMint(usdcToken, address(lendingClerk), 100e6);

        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: 100e18
        });

        // If no reserves, the A/L would be < 1 (but the floor has to be > 1)
        vm.startPrank(origamiMultisig);       
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, type(uint128).max, 1.000375045172009611e18, 1.05e18));
        managerImpl.rebalanceDown(
            IOrigamiLovTokenErc4626Manager.RebalanceDownParams(
                100e6, abi.encode(swapData), 0, 0, type(uint128).max
            )
        );
    }

    function test_rebalanceDown_fail_slippage() public {
        investWithSDai(100e18, alice);

        uint256 targetAL = 1.111e18;

        // reserves (sDAI) amount
        uint256 reservesAmount = solveRebalanceDownAmount(address(managerImpl), targetAL);

        // How much DAI to get that much reserves
        uint256 daiDepositAmount = sDaiToken.previewMint(reservesAmount);

        // Use the oracle price (and scale for USDC)
        // Round down to be conservative on how much is borrowed
        uint256 usdcBorrowAmount = daiUsdcOracle.convertAmount(
            address(daiToken),
            daiDepositAmount,
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN
        );

        assertEq(managerImpl.reservesBalance(), 100e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        
        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: daiDepositAmount // USDC->DAI using the oracle price
        });

        vm.startPrank(origamiMultisig);
        
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, reservesAmount+1, reservesAmount));
        managerImpl.rebalanceDown(
            IOrigamiLovTokenErc4626Manager.RebalanceDownParams(
                usdcBorrowAmount, abi.encode(swapData), reservesAmount+1, 0, type(uint128).max
            )
        );
    }

    function test_rebalanceDown_fail_al_validation() public {
        investWithSDai(100e18, alice);

        uint256 targetAL = 1.111e18;

        // reserves (sDAI) amount
        uint256 reservesAmount = solveRebalanceDownAmount(address(managerImpl), targetAL);

        // How much DAI to get that much reserves
        uint256 daiDepositAmount = sDaiToken.previewMint(reservesAmount);

        // Use the oracle price (and scale for USDC)
        // Round down to be conservative on how much is borrowed
        uint256 usdcBorrowAmount = daiUsdcOracle.convertAmount(
            address(daiToken),
            daiDepositAmount,
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN
        );
        
        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData(daiDepositAmount);

        vm.startPrank(origamiMultisig);
        
        // Can't be < minNewAL
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, type(uint128).max, 1.111000000535311913e18, 1.112e18));
        managerImpl.rebalanceDown(
            IOrigamiLovTokenErc4626Manager.RebalanceDownParams(
                usdcBorrowAmount, abi.encode(swapData), reservesAmount, uint128(1.112e18), type(uint128).max
            )
        );

        // Can't be > maxNewAL
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, type(uint128).max, 1.111000000535311913e18, 1.11e18));
        managerImpl.rebalanceDown(
            IOrigamiLovTokenErc4626Manager.RebalanceDownParams(
                usdcBorrowAmount, abi.encode(swapData), reservesAmount, uint128(1.111e18), uint128(1.11e18)
            )
        );

        // A successful rebalance, just above the real target
        doRebalanceDown(1.1112e18);

        // Now do another rebalance, but we get a 20% BETTER swap when going
        // USDC->DAI
        // Meaning we have more reserves, so A/L is higher than we started out.
        {

            reservesAmount = solveRebalanceDownAmount(address(managerImpl), targetAL);
            daiDepositAmount = sDaiToken.previewMint(reservesAmount);
            usdcBorrowAmount = daiUsdcOracle.convertAmount(
                address(daiToken),
                daiDepositAmount,
                IOrigamiOracle.PriceType.SPOT_PRICE,
                OrigamiMath.Rounding.ROUND_DOWN
            );
            swapData = DummyLovTokenSwapper.SwapData(daiDepositAmount*1.2e18/1e18);

            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, 1.111200000466539707e18, 1.111359714099955673e18, 1.111200000466539707e18));
            managerImpl.rebalanceDown(
                IOrigamiLovTokenErc4626Manager.RebalanceDownParams(
                    usdcBorrowAmount, abi.encode(swapData), reservesAmount, 0, type(uint128).max
                )
            );
        }
    }

    function test_rebalanceDown_fail_al_floor() public {
        investWithSDai(100e18, alice);

        vm.startPrank(origamiMultisig);
        managerImpl.setRebalanceALRange(1.12e18, 1.5e18);

        uint256 targetAL = 1.111e18;

        // reserves (sDAI) amount
        uint256 reservesAmount = solveRebalanceDownAmount(address(managerImpl), targetAL);

        // How much DAI to get that much reserves
        uint256 daiDepositAmount = sDaiToken.previewMint(reservesAmount);

        // Use the oracle price (and scale for USDC)
        // Round down to be conservative on how much is borrowed
        uint256 usdcBorrowAmount = daiUsdcOracle.convertAmount(
            address(daiToken),
            daiDepositAmount,
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN
        );

        assertEq(managerImpl.reservesBalance(), 100e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        
        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: daiDepositAmount // USDC->DAI using the oracle price
        });

        vm.startPrank(origamiMultisig);
        
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, type(uint128).max, 1.111000000535311913e18, 1.12e18));
        managerImpl.rebalanceDown(
            IOrigamiLovTokenErc4626Manager.RebalanceDownParams(
                usdcBorrowAmount, abi.encode(swapData), reservesAmount, 0, type(uint128).max
            )
        );
    }

    function test_rebalanceDown_success() public {
        investWithSDai(100e18, alice);

        uint256 targetAL = 1.111e18;

        // reserves (sDAI) amount
        uint256 reservesAmount = solveRebalanceDownAmount(address(managerImpl), targetAL);

        // How much DAI to get that much reserves
        uint256 daiDepositAmount = sDaiToken.previewMint(reservesAmount);

        // Use the oracle price (and scale for USDC)
        // Round down to be conservative on how much is borrowed
        uint256 usdcBorrowAmount = daiUsdcOracle.convertAmount(
            address(daiToken),
            daiDepositAmount,
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN
        );

        assertEq(managerImpl.reservesBalance(), 100e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        
        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: daiDepositAmount // USDC->DAI using the oracle price
        });

        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(managerImpl));
        emit Rebalance(
            int256(daiDepositAmount),
            int256(usdcBorrowAmount),
            type(uint128).max,
            1.111000000535311913e18 // Close to but not exactly the target A/L
        );
        uint256 alRatioAfter = managerImpl.rebalanceDown(
            IOrigamiLovTokenErc4626Manager.RebalanceDownParams(
                usdcBorrowAmount, abi.encode(swapData), reservesAmount, 0, type(uint128).max
            )
        );
        
        assertEq(reservesAmount, 900.900900900900900901e18);
        assertEq(daiDepositAmount, 900.900900900900900901e18);
        assertEq(usdcBorrowAmount, 901.238779e6);
        assertEq(managerImpl.reservesBalance(), 100e18 + 900.900900900900900901e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 900.900900466820806851e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 901.238779e18);
        assertEq(alRatioAfter, 1.111000000535311913e18);

        assertEq(daiToken.balanceOf(address(managerImpl)), 0);
        assertEq(usdcToken.balanceOf(address(managerImpl)), 0);
        assertEq(sDaiToken.balanceOf(address(managerImpl)), 100e18 + 900.900900900900900901e18);
    }

    function test_rebalanceDown_success_al_floor_force() public {
        investWithSDai(100e18, alice);

        // Set the floor - but force mode allows it anyway
        vm.startPrank(origamiMultisig);
        managerImpl.setRebalanceALRange(1.12e18, 1.5e18);

        uint256 targetAL = 1.111e18;

        // reserves (sDAI) amount
        uint256 reservesAmount = solveRebalanceDownAmount(address(managerImpl), targetAL);

        // How much DAI to get that much reserves
        uint256 daiDepositAmount = sDaiToken.previewMint(reservesAmount);

        // Use the oracle price (and scale for USDC)
        // Round down to be conservative on how much is borrowed
        uint256 usdcBorrowAmount = daiUsdcOracle.convertAmount(
            address(daiToken),
            daiDepositAmount,
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN
        );

        assertEq(managerImpl.reservesBalance(), 100e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        
        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: daiDepositAmount // USDC->DAI using the oracle price
        });

        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(managerImpl));
        emit Rebalance(
            int256(reservesAmount),
            int256(usdcBorrowAmount),
            type(uint128).max,
            1.111000000535311913e18 // Close to but not exactly the target A/L
        );
        uint256 alRatioAfter = managerImpl.forceRebalanceDown(
            IOrigamiLovTokenErc4626Manager.RebalanceDownParams(
                usdcBorrowAmount, abi.encode(swapData), reservesAmount, 0, type(uint128).max
            )
        );
        
        assertEq(reservesAmount, 900.900900900900900901e18);
        assertEq(daiDepositAmount, 900.900900900900900901e18);
        assertEq(usdcBorrowAmount, 901.238779e6);
        assertEq(managerImpl.reservesBalance(), 100e18 + 900.900900900900900901e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 900.900900466820806851e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 901.238779e18);
        assertEq(alRatioAfter, 1.111000000535311913e18);

        assertEq(daiToken.balanceOf(address(managerImpl)), 0);
        assertEq(usdcToken.balanceOf(address(managerImpl)), 0);
        assertEq(sDaiToken.balanceOf(address(managerImpl)), 100e18 + 900.900900900900900901e18);
    }
}

contract OrigamiLovTokenErc4626ManagerTestRebalanceUp is OrigamiLovTokenErc4626ManagerTestBase {
    using OrigamiMath for uint256;

    event Rebalance(
        int256 collateralChange,
        int256 debtChange,
        uint256 alRatioBefore,
        uint256 alRatioAfter
    );

    function test_rebalanceUp_fail_insufficientBalance() public {
        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: 100e6
        });

        // The vault holds no sDAI, so can't withdraw from the reserves
        vm.startPrank(origamiMultisig);       
        vm.expectRevert("ERC4626: withdraw more than max");
        managerImpl.rebalanceUp(
            IOrigamiLovTokenErc4626Manager.RebalanceUpParams(
                100e6, 0, abi.encode(swapData), 0, 0, type(uint128).max
            )
        );

        // Mint sDAI to the manager
        {
            mintSDai(100e18, address(managerImpl));
            doMint(daiToken, address(swapper), 200e18);
            doMint(usdcToken, address(swapper), 200e6);
            doMint(usdcToken, address(lendingClerk), 200e6);
        }

        // Still fails since less than the internally tracked balance
        vm.startPrank(origamiMultisig);       
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InsufficientBalance.selector, address(sDaiToken), 100e18, 0));
        managerImpl.rebalanceUp(
            IOrigamiLovTokenErc4626Manager.RebalanceUpParams(
                100e18, 0, abi.encode(swapData), 0, 0, type(uint128).max
            )
        );
    }

    function test_rebalanceUp_fail_slippage() public {
        investWithSDai(100e18, alice);
        doRebalanceDown(1.11e18);

        assertEq(managerImpl.reservesBalance(), 1_009.090909090909090910e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 909.090908843720332405e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 909.431859e18);
        
        uint256 targetAL = 1.15e18;

        // reserves (sDAI) amount
        uint256 reservesAmount = solveRebalanceUpAmount(address(managerImpl), targetAL);

        // How much DAI to sell for that reserves amount
        uint256 daiSellAmount = sDaiToken.previewRedeem(reservesAmount);

        // Use the oracle price (and scale for USDC)
        // Round down to be conservative on how much is borrowed
        uint256 minUsdcRepayAmount = daiUsdcOracle.convertAmount(
            address(daiToken),
            daiSellAmount,
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN
        );

        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: minUsdcRepayAmount
        });
        
        vm.startPrank(origamiMultisig);
        
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, reservesAmount+1, reservesAmount));
        managerImpl.rebalanceUp(
            IOrigamiLovTokenErc4626Manager.RebalanceUpParams(
                daiSellAmount, reservesAmount+1, abi.encode(swapData), minUsdcRepayAmount, 0, type(uint128).max
            )
        );

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, minUsdcRepayAmount+1, minUsdcRepayAmount));
        managerImpl.rebalanceUp(
            IOrigamiLovTokenErc4626Manager.RebalanceUpParams(
                daiSellAmount, reservesAmount, abi.encode(swapData), minUsdcRepayAmount+1, 0, type(uint128).max
            )
        );
    }

    function test_rebalanceUp_fail_al_validation() public {
        investWithSDai(100e18, alice);
        uint256 targetAL = 1.10e18;
        doRebalanceDown(targetAL);
        
        targetAL = 1.13e18;

        // reserves (sDAI) amount
        uint256 reservesAmount = solveRebalanceUpAmount(address(managerImpl), targetAL);

        // How much DAI to sell for that reserves amount
        uint256 daiSellAmount = sDaiToken.previewRedeem(reservesAmount);

        // Use the oracle price (and scale for USDC)
        // Round down to be conservative on how much is borrowed
        uint256 minUsdcRepayAmount = daiUsdcOracle.convertAmount(
            address(daiToken),
            daiSellAmount,
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN
        );

        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: minUsdcRepayAmount
        });
        
        vm.startPrank(origamiMultisig);
        
        // Can't be < minNewAL
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, 1.100000000189139637e18, 1.129999999765167550e18, 1.14e18));
        managerImpl.rebalanceUp(
            IOrigamiLovTokenErc4626Manager.RebalanceUpParams(
                daiSellAmount, reservesAmount, abi.encode(swapData), minUsdcRepayAmount, 1.14e18, type(uint128).max
            )
        );

        // Can't be > maxNewAL
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, 1.100000000189139637e18, 1.129999999765167550e18, 1.12e18));
        managerImpl.rebalanceUp(
            IOrigamiLovTokenErc4626Manager.RebalanceUpParams(
                daiSellAmount, reservesAmount, abi.encode(swapData), minUsdcRepayAmount, 0, 1.12e18
            )
        );

        // Now do another rebalance, but we get a 10% WORSE swap when going
        // DAI->USDC
        // Meaning A/L is lower than we started out.
        {
            targetAL = 1.1002e18;

            reservesAmount = solveRebalanceUpAmount(address(managerImpl), targetAL);
            daiSellAmount = sDaiToken.previewRedeem(reservesAmount);
            minUsdcRepayAmount = daiUsdcOracle.convertAmount(
                address(daiToken),
                daiSellAmount,
                IOrigamiOracle.PriceType.SPOT_PRICE,
                OrigamiMath.Rounding.ROUND_DOWN
            );

            swapData = DummyLovTokenSwapper.SwapData(minUsdcRepayAmount*90/100);

            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, 1.100000000189139637e18, 1.099980002864106193e18, 1.100000000189139637e18));
            managerImpl.rebalanceUp(
                IOrigamiLovTokenErc4626Manager.RebalanceUpParams(
                    daiSellAmount, reservesAmount, abi.encode(swapData), minUsdcRepayAmount*90/100, 0, type(uint128).max
                )
            );
        }
    }

    function test_rebalanceUp_fail_al_ceiling() public {
        investWithSDai(100e18, alice);
        doRebalanceDown(1.11e18);

        vm.startPrank(origamiMultisig);
        managerImpl.setRebalanceALRange(1.12e18, 1.14e18);

        assertEq(managerImpl.reservesBalance(), 1_009.090909090909090910e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 909.090908843720332405e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 909.431859e18);
        
        uint256 targetAL = 1.15e18;

        // reserves (sDAI) amount
        uint256 reservesAmount = solveRebalanceUpAmount(address(managerImpl), targetAL);

        // How much DAI to sell for that reserves amount
        uint256 daiSellAmount = sDaiToken.previewRedeem(reservesAmount);

        // Use the oracle price (and scale for USDC)
        // Round down to be conservative on how much is borrowed
        uint256 minUsdcRepayAmount = daiUsdcOracle.convertAmount(
            address(daiToken),
            daiSellAmount,
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN
        );

        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: minUsdcRepayAmount
        });
        
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, 1.110000000301817474e18, 1.149999999016916610e18, 1.14e18));
        managerImpl.rebalanceUp(
            IOrigamiLovTokenErc4626Manager.RebalanceUpParams(
                daiSellAmount, reservesAmount, abi.encode(swapData), minUsdcRepayAmount, 0, type(uint128).max
            )
        );
    }

    function test_rebalanceUp_success() public {
        investWithSDai(100e18, alice);
        doRebalanceDown(1.11e18);

        assertEq(managerImpl.reservesBalance(), 1_009.090909090909090910e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 909.090908843720332405e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 909.431859e18);
        
        uint256 targetAL = 1.15e18;

        // reserves (sDAI) amount
        uint256 reservesAmount = solveRebalanceUpAmount(address(managerImpl), targetAL);

        // How much DAI to sell for that reserves amount
        uint256 daiSellAmount = sDaiToken.previewRedeem(reservesAmount);

        // Use the oracle price (and scale for USDC)
        // Round down to be conservative on how much is borrowed
        uint256 minUsdcRepayAmount = daiUsdcOracle.convertAmount(
            address(daiToken),
            daiSellAmount,
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN
        );

        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: minUsdcRepayAmount
        });
        
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(managerImpl));
        emit Rebalance(
            -int256(daiSellAmount),
            -int256(minUsdcRepayAmount * 10 ** 12),
            1.110000000301817474e18, // Close to but not exactly the target A/L
            1.149999999016916610e18 // Close to but not exactly the target A/L
        );
        uint256 alRatioAfter = managerImpl.rebalanceUp(
            IOrigamiLovTokenErc4626Manager.RebalanceUpParams(
                daiSellAmount, reservesAmount, abi.encode(swapData), minUsdcRepayAmount, 0, type(uint128).max
            )
        );

        assertEq(reservesAmount, 242.424240529128609040e18);
        assertEq(daiSellAmount, 242.424240529128609040e18);
        assertEq(reservesAmount, 242.424240529128609040e18);
        assertEq(minUsdcRepayAmount, 242.515160e6);
        assertEq(managerImpl.reservesBalance(), 1_009.090909090909090910e18 - 242.424240529128609040e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 666.666668884495139473e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 666.916699e18);
        assertEq(alRatioAfter, 1.149999999016916610e18);

        assertEq(daiToken.balanceOf(address(managerImpl)), 0);
        assertEq(usdcToken.balanceOf(address(managerImpl)), 0);
        assertEq(sDaiToken.balanceOf(address(managerImpl)), 1_009.090909090909090910e18 - 242.424240529128609040e18);
    }

    function test_rebalanceUp_al_ceiling_force() public {
        investWithSDai(100e18, alice);
        doRebalanceDown(1.11e18);

        vm.startPrank(origamiMultisig);
        managerImpl.setRebalanceALRange(1.12e18, 1.14e18);

        assertEq(managerImpl.reservesBalance(), 1_009.090909090909090910e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 909.090908843720332405e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 909.431859e18);
        
        uint256 targetAL = 1.15e18;

        // reserves (sDAI) amount
        uint256 reservesAmount = solveRebalanceUpAmount(address(managerImpl), targetAL);

        // How much DAI to sell for that reserves amount
        uint256 daiSellAmount = sDaiToken.previewRedeem(reservesAmount);

        // Use the oracle price (and scale for USDC)
        // Round down to be conservative on how much is borrowed
        uint256 minUsdcRepayAmount = daiUsdcOracle.convertAmount(
            address(daiToken),
            daiSellAmount,
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN
        );

        DummyLovTokenSwapper.SwapData memory swapData = DummyLovTokenSwapper.SwapData({
            buyTokenAmount: minUsdcRepayAmount
        });
        
        vm.startPrank(origamiMultisig);

        vm.expectEmit(address(managerImpl));
        emit Rebalance(
            -int256(reservesAmount),
            -int256(minUsdcRepayAmount * 10**12),
            1.110000000301817474e18, // Close to but not exactly the target A/L
            1.149999999016916610e18 // Close to but not exactly the target A/L
        );
        uint256 alRatioAfter = managerImpl.forceRebalanceUp(
            IOrigamiLovTokenErc4626Manager.RebalanceUpParams(
                daiSellAmount, reservesAmount, abi.encode(swapData), minUsdcRepayAmount, 0, type(uint128).max
            )
        );

        assertEq(reservesAmount, 242.424240529128609040e18);
        assertEq(daiSellAmount, 242.424240529128609040e18);
        assertEq(reservesAmount, 242.424240529128609040e18);
        assertEq(minUsdcRepayAmount, 242.515160e6);
        assertEq(managerImpl.reservesBalance(), 1_009.090909090909090910e18 - 242.424240529128609040e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 666.666668884495139473e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 666.916699e18);
        assertEq(alRatioAfter, 1.149999999016916610e18);

        assertEq(daiToken.balanceOf(address(managerImpl)), 0);
        assertEq(usdcToken.balanceOf(address(managerImpl)), 0);
        assertEq(sDaiToken.balanceOf(address(managerImpl)), 1_009.090909090909090910e18 - 242.424240529128609040e18);
    }
}

contract OrigamiLovTokenErc4626ManagerTestInvest is OrigamiLovTokenErc4626ManagerTestBase {
    using OrigamiMath for uint256;

    function test_maxInvest_badAsset() public {
        assertEq(managerImpl.maxInvest(alice), 0);
    }

    function exitToSDai(uint256 amount, address to) internal returns (uint256) {
        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovToken.exitQuote(
            amount,
            address(sDaiToken),
            0,
            0
        );

        vm.startPrank(to);
        return lovToken.exitToToken(quoteData, to);
    }

    function test_maxInvest_depositAsset() public {
        vm.startPrank(origamiMultisig);
        managerImpl.setFeeConfig(500, 0, FEE_LEVERAGE_FACTOR);

        bootstrapSDai(123_456e18);

        // No token supply no reserves
        assertEq(managerImpl.reservesBalance(), 0);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        assertEq(managerImpl.maxInvest(address(daiToken)), type(uint256).max);

        // with reserves, no liabilities
        uint256 totalSupply = 20e18;
        investWithSDai(totalSupply / 2, alice);
        assertEq(managerImpl.reservesBalance(), 10e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        assertEq(managerImpl.maxInvest(address(daiToken)), type(uint256).max);

        // with reserves and liability of 1
        doRebalanceDownFor(1e12);
        uint256 expectedReserves = 10e18 + 1e12;
        assertEq(managerImpl.reservesBalance(), expectedReserves);
        // Close to: usdcDaiPrice.mulDiv(1e12, sDaiPrice, OrigamiMath.Rounding.ROUND_UP))
        // but different order of operations before rounding
        uint256 expectedLiabilities = 0.000000952023900415e18;
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.000000952380952381e18);
        assertEq(
            managerImpl.maxInvest(address(daiToken)),
            sDaiToken.previewMint(
                expectedLiabilities.mulDiv(type(uint128).max, 1e18, OrigamiMath.Rounding.ROUND_DOWN)
                - expectedReserves
            )
        );

        // Add a chunk more so A/L is super high
        investWithSDai(1_000_000e18, alice);
        expectedReserves += 1_000_000e18;
        assertEq(managerImpl.reservesBalance(), expectedReserves);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.000000952380952381e18);
        // Very high, but not bigger than uint(128).max
        assertEq(managerImpl.assetToLiabilityRatio(), 1_050_404_301_367.940673477109787377e18);
        assertEq(managerImpl.maxInvest(address(daiToken)), 340_154_792_458_435.510413478806428735e18);

        doRebalanceDown(1.111111111111111111e18);
        expectedReserves = 10_000_100.000000479769995935e18;
        expectedLiabilities = 9_000_089.999999752865726199e18;
        assertEq(managerImpl.reservesBalance(), expectedReserves);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 9_003_465.440301904761904762e18);
        // Share price isn't accurate for full precision, so fully recalculate sdai from first principles
        uint256 expectedFreeShares = ((expectedLiabilities) * type(uint128).max / 1e18) - expectedReserves;
        uint256 expectedFreeAssets = expectedFreeShares.mulDiv(sDaiToken.totalAssets(), sDaiToken.totalSupply(), OrigamiMath.Rounding.ROUND_UP);
        assertEq(managerImpl.maxInvest(address(daiToken)), expectedFreeAssets);

        // Only a small amount of capacity if the user A/L is capped
        vm.startPrank(origamiMultisig);
        managerImpl.setUserALRange(1e18+1, 1.2e18);
        uint256 expectedMaxInvest = 840_008.399999184852319279e18;
        assertEq(managerImpl.maxInvest(address(daiToken)), expectedMaxInvest);

        // Cannot invest more than the maxInvest amount
        // Note maxInvest() intentionally conservatively rounds down through the calcs,
        // so a little more dust is required to actually tip it over.
        {
            uint256 investAmount = expectedMaxInvest+1e7;
            doMint(daiToken, alice, investAmount);
            vm.startPrank(alice);

            daiToken.approve(address(lovToken), investAmount);

            (IOrigamiInvestment.InvestQuoteData memory quoteData,) = lovToken.investQuote(
                investAmount,
                address(daiToken),
                0,
                0
            );

            vm.startPrank(alice);
            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, 1.111111111111194928e18, 1.200000000000000001e18, 1.2e18));
            lovToken.investWithToken(quoteData);
        }

        investWithDai(expectedMaxInvest, alice);
    }

    function test_maxInvest_depositAsset_withMaxTotalSupply() public {
        vm.startPrank(origamiMultisig);
        managerImpl.setFeeConfig(500, 0, FEE_LEVERAGE_FACTOR);
        uint256 maxTotalSupply = 2_000_000e18;
        lovToken.setMaxTotalSupply(maxTotalSupply);

        bootstrapSDai(123_456e18);

        // No token supply no reserves
        assertEq(managerImpl.reservesBalance(), 0);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        // share price = 1, sDAI->DAI = 1.05, +fees
        assertEq(managerImpl.maxInvest(address(daiToken)), 2_210_526.315789473684210527e18);

        // with reserves, no liabilities
        uint256 totalSupply = 20e18;
        investWithSDai(totalSupply / 2, alice);
        assertEq(managerImpl.reservesBalance(), 10e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        // share price > 1, +fees
        assertEq(managerImpl.maxInvest(address(daiToken)), 2_326_858.753462603878116344e18);

        // with reserves and liability of 1
        doRebalanceDownFor(1e12);
        uint256 expectedReserves = 10e18 + 1e12;
        assertEq(managerImpl.reservesBalance(), expectedReserves);
        // Close to: usdcDaiPrice.mulDiv(1e12, sDaiPrice, OrigamiMath.Rounding.ROUND_UP))
        // but different order of operations before rounding
        uint256 expectedLiabilities = 0.000000952023900415e18;
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.000000952380952381e18);
        // share price > 1, +fees
        assertEq(managerImpl.maxInvest(address(daiToken)), 2_326_858.764625964605751428e18);

        // Add a chunk more so A/L is super high
        investWithSDai(1_000_000e18, alice);
        expectedReserves += 1_000_000e18;
        assertEq(managerImpl.reservesBalance(), expectedReserves);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.000000952380952381e18);
        // Very high, but not bigger than uint(128).max
        assertEq(managerImpl.assetToLiabilityRatio(), 1_050_404_301_367.940673477109787377e18);
        assertEq(managerImpl.maxInvest(address(daiToken)), 1_344_061.150107480596298090e18); // restricted by total supply

        doRebalanceDown(1.111111111111111111e18);
        expectedReserves = 10_000_100.000000479769995935e18;
        expectedLiabilities = 9_000_089.999999752865726199e18;
        assertEq(managerImpl.reservesBalance(), expectedReserves);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 9_003_465.440301904761904762e18);
        assertEq(managerImpl.maxInvest(address(daiToken)), 1_344_061.150108393108150186e18); // restricted by total supply

        // Only a small amount of capacity if the user A/L is capped
        vm.startPrank(origamiMultisig);
        managerImpl.setUserALRange(1e18+1, 1.2e18);
        uint256 expectedMaxInvest = 840_008.399999184852319279e18;
        assertEq(managerImpl.maxInvest(address(daiToken)), expectedMaxInvest);

        // Cannot invest more than the maxInvest amount
        // Note maxInvest() intentionally conservatively rounds down through the calcs,
        // so a little more dust is required to actually tip it over.
        {
            uint256 investAmount = expectedMaxInvest+1e7;
            doMint(daiToken, alice, investAmount);
            vm.startPrank(alice);

            daiToken.approve(address(lovToken), investAmount);

            (IOrigamiInvestment.InvestQuoteData memory quoteData,) = lovToken.investQuote(
                investAmount,
                address(daiToken),
                0,
                0
            );

            vm.startPrank(alice);
            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, 1.111111111111194928e18, 1.200000000000000001e18, 1.2e18));
            lovToken.investWithToken(quoteData);
        }

        investWithDai(expectedMaxInvest, alice);
    }

    function test_maxInvest_reserveToken() public {
        vm.startPrank(origamiMultisig);
        managerImpl.setFeeConfig(500, 0, FEE_LEVERAGE_FACTOR);

        bootstrapSDai(123_456e18);

        // No token supply no reserves
        assertEq(managerImpl.reservesBalance(), 0);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        assertEq(managerImpl.maxInvest(address(sDaiToken)), type(uint256).max);

        // with reserves, no liabilities
        uint256 totalSupply = 20e18;
        investWithSDai(totalSupply / 2, alice);
        assertEq(managerImpl.reservesBalance(), 10e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        assertEq(managerImpl.maxInvest(address(sDaiToken)), type(uint256).max);

        // with reserves and liability of 1
        doRebalanceDownFor(1e12);
        uint256 expectedReserves = 10e18 + 1e12;
        assertEq(managerImpl.reservesBalance(), expectedReserves);
        // Close to: usdcDaiPrice.mulDiv(1e12, sDaiPrice, OrigamiMath.Rounding.ROUND_UP))
        // but different order of operations before rounding
        uint256 expectedLiabilities = 0.000000952023900415e18;
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.000000952380952381e18);
        assertEq(
            managerImpl.maxInvest(address(sDaiToken)), 
            (
                expectedLiabilities.mulDiv(type(uint128).max, 1e18, OrigamiMath.Rounding.ROUND_DOWN) 
                - expectedReserves
            )
        );

        // Add a chunk more so A/L is super high
        investWithSDai(1_000_000e18, alice);
        expectedReserves += 1_000_000e18;
        assertEq(managerImpl.reservesBalance(), expectedReserves);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.000000952380952381e18);
        // Very high, but not bigger than uint(128).max
        assertEq(managerImpl.assetToLiabilityRatio(), 1_050_404_301_367.940673477109787377e18);
        assertEq(managerImpl.maxInvest(address(sDaiToken)), 323_956_945_198_510.009917598863265461e18);

        doRebalanceDown(1.111111111111111111e18);
        expectedReserves = 10_000_100.000000479769995935e18;
        expectedLiabilities = 9_000_089.999999752865726199e18;
        assertEq(managerImpl.reservesBalance(), expectedReserves);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 9_003_465.440301904761904762e18);
        // Share price isn't accurate for full precision, so fully recalculate sdai from first principles
        uint256 expectedFreeShares = (expectedLiabilities * type(uint128).max / 1e18) - expectedReserves;
        assertEq(managerImpl.maxInvest(address(sDaiToken)), expectedFreeShares);

        // Only a small amount of capacity if the user A/L is capped
        vm.startPrank(origamiMultisig);
        managerImpl.setUserALRange(1e18+1, 1.2e18);

        uint256 expectedMaxInvest = 800_007.999999223668875503e18;
        assertEq(managerImpl.maxInvest(address(sDaiToken)), expectedMaxInvest);

        // Cannot invest more than the maxInvest amount
        // Note maxInvest() intentionally conservatively rounds down through the calcs,
        // so a little more dust is required to actually tip it over.
        {
            uint256 investAmount = expectedMaxInvest+1e7;
            mintSDai(investAmount, alice);
            vm.startPrank(alice);

            sDaiToken.approve(address(lovToken), investAmount);

            (IOrigamiInvestment.InvestQuoteData memory quoteData,) = lovToken.investQuote(
                investAmount,
                address(sDaiToken),
                0,
                0
            );

            vm.startPrank(alice);
            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, 1.111111111111194928e18, 1.200000000000000001e18, 1.2e18));
            lovToken.investWithToken(quoteData);
        }

        investWithDai(expectedMaxInvest, alice);
    }

    function test_maxInvest_reserveToken_withMaxTotalSupply() public {
        vm.startPrank(origamiMultisig);
        managerImpl.setFeeConfig(500, 0, FEE_LEVERAGE_FACTOR);
        uint256 maxTotalSupply = 2_000_000e18;
        lovToken.setMaxTotalSupply(maxTotalSupply);

        bootstrapSDai(123_456e18);

        // No token supply no reserves
        assertEq(managerImpl.reservesBalance(), 0);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        // share price = 1, +fees
        assertEq(managerImpl.maxInvest(address(sDaiToken)), 2_105_263.157894736842105263e18);

        // with reserves, no liabilities
        uint256 totalSupply = 20e18;
        investWithSDai(totalSupply / 2, alice);
        assertEq(managerImpl.reservesBalance(), 10e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        assertEq(lovToken.reservesPerShare(), 1.052631578947368421e18);
        // share price > 1, +fees
        assertEq(managerImpl.maxInvest(address(sDaiToken)), 2_216_055.955678670360110803e18);

        // with reserves and liability of 1
        // Still capped to the total supply amount
        doRebalanceDownFor(1e12);
        uint256 expectedReserves = 10e18 + 1e12;
        assertEq(managerImpl.reservesBalance(), expectedReserves);
        uint256 expectedLiabilities = 0.000000952023900415e18;
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.000000952380952381e18);
        // share price > 1, +fees
        assertEq(managerImpl.maxInvest(address(sDaiToken)), 2_216_055.966310442481668026e18);

        // Add a chunk more so A/L is super high
        investWithSDai(1_000_000e18, alice);
        expectedReserves += 1_000_000e18;
        assertEq(managerImpl.reservesBalance(), expectedReserves);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.000000952380952381e18);
        // Very high, but not bigger than uint(128).max
        assertEq(managerImpl.assetToLiabilityRatio(), 1_050_404_301_367.940673477109787377e18);
        // restricted by total supply
        assertEq(managerImpl.maxInvest(address(sDaiToken)), 1_280_058.238197600567902942e18);

        doRebalanceDown(1.111111111111111111e18);
        expectedReserves = 10_000_100.000000479769995935e18;
        expectedLiabilities = 9_000_089.999999752865726199e18;
        assertEq(managerImpl.reservesBalance(), expectedReserves);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 9_003_465.440301904761904762e18);
        // restricted by total supply, +fees
        assertEq(managerImpl.maxInvest(address(sDaiToken)), 1_280_058.238198469626809700e18);

        // Only a small amount of capacity if the user A/L is capped
        vm.startPrank(origamiMultisig);
        managerImpl.setUserALRange(1e18+1, 1.2e18);
        uint256 expectedMaxInvest = 800_007.999999223668875503e18;
        assertEq(managerImpl.maxInvest(address(sDaiToken)), expectedMaxInvest);

        // Cannot invest more than the maxInvest amount
        // Note maxInvest() intentionally conservatively rounds down through the calcs,
        // so a little more dust is required to actually tip it over.
        {
            uint256 investAmount = expectedMaxInvest+1e7;
            mintSDai(investAmount, alice);
            vm.startPrank(alice);

            sDaiToken.approve(address(lovToken), investAmount);

            (IOrigamiInvestment.InvestQuoteData memory quoteData,) = lovToken.investQuote(
                investAmount,
                address(sDaiToken),
                0,
                0
            );

            vm.startPrank(alice);
            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, 1.111111111111194928e18, 1.200000000000000001e18, 1.2e18));
            lovToken.investWithToken(quoteData);
        }

        investWithDai(expectedMaxInvest, alice);
    }

    function test_investQuote_badToken_gives0() public {
        (IOrigamiInvestment.InvestQuoteData memory quoteData, uint256[] memory investFeeBps) = managerImpl.investQuote(
            100,
            alice,
            100,
            123
        );

        assertEq(quoteData.fromToken, address(alice));
        assertEq(quoteData.fromTokenAmount, 100);
        assertEq(quoteData.maxSlippageBps, 100);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedInvestmentAmount, 0);
        assertEq(quoteData.minInvestmentAmount, 0);
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));
        assertEq(investFeeBps.length, 1);
        assertEq(investFeeBps[0], 10);
    }

    function test_investQuote_depositToken_success_fresh() public {
        vm.startPrank(origamiMultisig);

        uint256 sharePrice = bootstrapSDai(123_456e18);
        uint256 slippageBps = 100;
        uint256 depositAmount = 20e18;

        (IOrigamiInvestment.InvestQuoteData memory quoteData, uint256[] memory investFeeBps) = managerImpl.investQuote(
            depositAmount,
            address(daiToken),
            slippageBps,
            123
        );

        assertEq(quoteData.fromToken, address(daiToken));
        assertEq(quoteData.fromTokenAmount, depositAmount);
        assertEq(quoteData.maxSlippageBps, slippageBps);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedInvestmentAmount, depositAmount * 0.999e18 / sharePrice);
        assertEq(quoteData.minInvestmentAmount, quoteData.expectedInvestmentAmount.subtractBps(slippageBps, OrigamiMath.Rounding.ROUND_UP));
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));
        assertEq(investFeeBps.length, 1);
        assertEq(investFeeBps[0], 10);
    }

    function test_investQuote_depositToken_success_afterFirstSupply() public {
        bootstrapSDai(123_456e18);
        uint256 slippageBps = 100;
        uint256 depositAmount = 20e18;

        investWithSDai(100e18, alice);
        doRebalanceDown(1.111111111111111111e18);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, uint256[] memory investFeeBps) = managerImpl.investQuote(
            depositAmount,
            address(daiToken),
            slippageBps,
            123
        );

        assertEq(quoteData.fromToken, address(daiToken));
        assertEq(quoteData.fromTokenAmount, depositAmount);
        assertEq(quoteData.maxSlippageBps, slippageBps);
        assertEq(quoteData.deadline, 123);
        // Almost (depositAmount * 1e18 / sharePrice)
        // but rounding from the USDC->DAI liabilities when calculating the shares
        assertEq(quoteData.expectedInvestmentAmount, 19.009542732713393349e18);
        assertEq(quoteData.minInvestmentAmount, quoteData.expectedInvestmentAmount.subtractBps(slippageBps, OrigamiMath.Rounding.ROUND_UP));
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));
        assertEq(investFeeBps.length, 1);
        assertEq(investFeeBps[0], 10);
    }

    function test_investQuote_reserveToken_success_fresh() public {
        vm.startPrank(origamiMultisig);

        bootstrapSDai(123_456e18);
        uint256 slippageBps = 100;
        uint256 depositAmount = 20e18;

        (IOrigamiInvestment.InvestQuoteData memory quoteData, uint256[] memory investFeeBps) = managerImpl.investQuote(
            depositAmount,
            address(sDaiToken),
            slippageBps,
            123
        );

        assertEq(quoteData.fromToken, address(sDaiToken));
        assertEq(quoteData.fromTokenAmount, depositAmount);
        assertEq(quoteData.maxSlippageBps, slippageBps);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedInvestmentAmount, 19.98e18);
        assertEq(quoteData.minInvestmentAmount, quoteData.expectedInvestmentAmount.subtractBps(slippageBps, OrigamiMath.Rounding.ROUND_UP));
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));
        assertEq(investFeeBps.length, 1);
        assertEq(investFeeBps[0], 10);
    }

    function test_investQuote_reserveToken_success_afterFirstSupply() public {
        bootstrapSDai(123_456e18);
        uint256 slippageBps = 100;
        uint256 depositAmount = 20e18;

        investWithSDai(100e18, alice);
        doRebalanceDown(1.111111111111111111e18);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, uint256[] memory investFeeBps) = managerImpl.investQuote(
            depositAmount,
            address(sDaiToken),
            slippageBps,
            123
        );

        assertEq(quoteData.fromToken, address(sDaiToken));
        assertEq(quoteData.fromTokenAmount, depositAmount);
        assertEq(quoteData.maxSlippageBps, slippageBps);
        assertEq(quoteData.deadline, 123);
        // Almost (depositAmount * 1e18 / sharePrice)
        // but rounding from the USDC->DAI liabilities when calculating the shares
        assertEq(quoteData.expectedInvestmentAmount, 19.960019869349063016e18);
        assertEq(quoteData.minInvestmentAmount, quoteData.expectedInvestmentAmount.subtractBps(slippageBps, OrigamiMath.Rounding.ROUND_UP));
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));
        assertEq(investFeeBps.length, 1);
        assertEq(investFeeBps[0], 10);
    }

    function test_investWithToken_fail_badToken() public {
        uint256 slippageBps = 100;
        uint256 depositAmount = 20e18;

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = managerImpl.investQuote(
            depositAmount,
            address(sDaiToken),
            slippageBps,
            123
        );

        quoteData.fromToken = alice;
        vm.startPrank(address(lovToken));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, alice));
        managerImpl.investWithToken(alice, quoteData);
    }

    function test_investWithToken_success_depositAsset() public {
        bootstrapSDai(123_456e18);
        uint256 slippageBps = 100;
        uint256 depositAmount = 20e18;

        investWithSDai(100e18, alice);
        assertEq(lovToken.reservesPerShare(), 1.001001001001001001e18);
        doRebalanceDown(1.111111111111111111e18);
        assertEq(lovToken.reservesPerShare(), 0.997622222222222231e18);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = managerImpl.investQuote(
            depositAmount,
            address(daiToken),
            slippageBps,
            123
        );

        doMint(daiToken, address(managerImpl), depositAmount);
        vm.startPrank(address(lovToken));
        uint256 shares = managerImpl.investWithToken(alice, quoteData);
        uint256 expectedShares = 19.009542732713393349e18;
        assertEq(shares, expectedShares);

        // lovToken does this itself after the manager returns
        assertEq(lovToken.totalSupply(), 99.9e18);
        assertEq(lovToken.balanceOf(alice), 99.9e18);

        assertEq(daiToken.balanceOf(address(managerImpl)), 0);
        assertEq(daiToken.balanceOf(alice), 0);
        assertEq(daiToken.balanceOf(address(lovToken)), 0);

        // initial deposit 1:1 + rebalance down + new deposit (DAI=>sDAI)
        uint256 expectedReserves = 100e18 + 900e18 + 19.047619047619048520e18;
        assertEq(managerImpl.reservesBalance(), expectedReserves);
        assertEq(sDaiToken.balanceOf(address(managerImpl)), expectedReserves);
    }

    function test_investWithToken_success_reserveToken() public {
        bootstrapSDai(123_456e18);
        uint256 slippageBps = 100;
        uint256 depositAmount = 20e18;

        investWithSDai(100e18, alice);
        assertEq(lovToken.reservesPerShare(), 1.001001001001001001e18);
        doRebalanceDown(1.111111111111111111e18);
        assertEq(lovToken.reservesPerShare(), 0.997622222222222231e18);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = managerImpl.investQuote(
            depositAmount,
            address(sDaiToken),
            slippageBps,
            123
        );

        mintSDai(depositAmount, address(managerImpl));
        vm.startPrank(address(lovToken));
        uint256 shares = managerImpl.investWithToken(alice, quoteData);
        // about 1.05x the DAI version (sDAI share price)
        uint256 expectedShares = 19.960019869349063016e18;
        assertEq(shares, expectedShares);

        // lovToken does this itself after the manager returns
        assertEq(lovToken.totalSupply(), 99.9e18);
        assertEq(lovToken.balanceOf(alice), 99.9e18);

        assertEq(daiToken.balanceOf(address(managerImpl)), 0);
        assertEq(daiToken.balanceOf(alice), 0);
        assertEq(daiToken.balanceOf(address(lovToken)), 0);

        // initial deposit 1:1 + rebalance down + new deposit (sDAI)
        uint256 expectedReserves = 100e18 + (900e18 + 901) + depositAmount;
        assertEq(managerImpl.reservesBalance(), expectedReserves);
        assertEq(sDaiToken.balanceOf(address(managerImpl)), expectedReserves);
    }
}

contract OrigamiLovTokenErc4626ManagerTestExit is OrigamiLovTokenErc4626ManagerTestBase {
    using OrigamiMath for uint256;

    function test_maxExit_badAsset() public {
        assertEq(managerImpl.maxExit(alice), 0);
    }

    // Not testing the mock manager implementation here - just that it passes through to the manager.
    function test_maxExit_depositAsset() public {
        vm.startPrank(origamiMultisig);
        managerImpl.setFeeConfig(0, 500, FEE_LEVERAGE_FACTOR);
        bootstrapSDai(123_456e18);

        // No token supply no reserves
        assertEq(managerImpl.reservesBalance(), 0);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        assertEq(managerImpl.maxExit(address(daiToken)), 0);

        // with reserves, no liabilities. Capped at total supply (10e18)
        uint256 totalSupply = 20e18;
        investWithSDai(totalSupply / 2, alice);
        assertEq(managerImpl.reservesBalance(), 10e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        assertEq(managerImpl.maxExit(address(daiToken)), 10e18);

        // with reserves and liability of 1. Still capped at total supply (10e18)
        doRebalanceDownFor(1e12);
        uint256 expectedReserves = 10e18 + 1e12;
        uint256 expectedLiabilities = 0.000000952023900415e18;

        assertEq(managerImpl.reservesBalance(), expectedReserves);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.000000952380952381e18);
        assertEq(managerImpl.maxExit(address(daiToken)), 10e18);

        // Add a chunk more so A/L is super high
        investWithSDai(1_000_000e18, alice);
        expectedReserves += 1_000_000e18;
        assertEq(managerImpl.reservesBalance(), expectedReserves);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.000000952380952381e18);
        // Very high, but not bigger than uint(128).max
        assertEq(managerImpl.assetToLiabilityRatio(), 1_050_404_301_367.940673477109787377e18);
        // Capped at the total supply
        assertEq(managerImpl.maxExit(address(daiToken)), lovToken.totalSupply());
       
        doRebalanceDown(1.111111111111111111e18);
        expectedReserves = 10_000_100.000000479769995935e18;
        expectedLiabilities = 9_000_089.999999752865726199e18;
        assertEq(managerImpl.reservesBalance(), expectedReserves);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 9_003_465.440301904761904762e18);
        assertEq(managerImpl.maxExit(address(daiToken)), lovToken.totalSupply());

        // Set the A/L such that there's not much capacity - less
        // than the total supply
        vm.startPrank(origamiMultisig);
        managerImpl.setUserALRange(1.05e18, 100e18);
        // This also includes on the exit fee amount
        assertEq(managerImpl.maxExit(address(daiToken)), 578_953.155117530525387184e18);

        TestERC4626(address(sDaiToken)).setMaxRedeemOverride(1e18);
        assertEq(managerImpl.maxExit(address(daiToken)), 1.052631573896538045e18);
    }

    // Not testing the mock manager implementation here - just that it passes through to the manager.
    function test_maxExit_reserveToken() public {
        vm.startPrank(origamiMultisig);
        managerImpl.setFeeConfig(0, 500, FEE_LEVERAGE_FACTOR);
        bootstrapSDai(123_456e18);

        // No token supply no reserves
        assertEq(managerImpl.reservesBalance(), 0);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        assertEq(managerImpl.maxExit(address(sDaiToken)), 0);

        // with reserves, no liabilities. Capped at total supply (10e18)
        uint256 totalSupply = 20e18;
        investWithSDai(totalSupply / 2, alice);
        assertEq(managerImpl.reservesBalance(), 10e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        assertEq(managerImpl.maxExit(address(sDaiToken)), 10e18);

        // with reserves and liability of 1. Still capped at total supply (10e18)
        doRebalanceDownFor(1e12);
        uint256 expectedReserves = 10e18 + 1e12;
        uint256 expectedLiabilities = 0.000000952023900415e18;

        assertEq(managerImpl.reservesBalance(), expectedReserves);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.000000952380952381e18);
        assertEq(managerImpl.maxExit(address(sDaiToken)), 10e18);

        // Add a chunk more so A/L is super high
        investWithSDai(1_000_000e18, alice);
        expectedReserves += 1_000_000e18;
        assertEq(managerImpl.reservesBalance(), expectedReserves);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.000000952380952381e18);
        // Very high, but not bigger than uint(128).max
        assertEq(managerImpl.assetToLiabilityRatio(), 1_050_404_301_367.940673477109787377e18);
        // Capped at the total supply
        assertEq(managerImpl.maxExit(address(sDaiToken)), lovToken.totalSupply());
       
        doRebalanceDown(1.111111111111111111e18);
        expectedReserves = 10_000_100.000000479769995935e18;
        expectedLiabilities = 9_000_089.999999752865726199e18;
        assertEq(managerImpl.reservesBalance(), expectedReserves);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 9_003_465.440301904761904762e18);
        assertEq(managerImpl.maxExit(address(sDaiToken)), lovToken.totalSupply());

        // Set the A/L such that there's not much capacity - less
        // than the total supply
        vm.startPrank(origamiMultisig);
        managerImpl.setUserALRange(1.05e18, 100e18);
        // This also includes on the exit fee amount
        assertEq(managerImpl.maxExit(address(sDaiToken)), 578_953.155117530525387184e18);
    }

    function test_exitQuote_badAsset_gives0() public {
        (IOrigamiInvestment.ExitQuoteData memory quoteData, uint256[] memory exitFeeBps) = managerImpl.exitQuote(
            100,
            alice,
            100,
            123
        );
        assertEq(quoteData.investmentTokenAmount, 100);
        assertEq(quoteData.toToken, alice);
        assertEq(quoteData.maxSlippageBps, 100);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedToTokenAmount, 0);
        assertEq(quoteData.minToTokenAmount, 0);
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));

        assertEq(exitFeeBps.length, 1);
        uint256 expectedSpotPrice = 1.000375045172e18;
        uint256 expectedFee = (
            15 * 
            1e18*(expectedSpotPrice-1e18)/expectedSpotPrice /
            (10**(18-4))
        ) + 1; // rounded up
        assertEq(exitFeeBps[0], expectedFee);
    }

    function test_exitQuote_depositAsset_noDeposits() public {
        // No lovToken's minted yet -- sharesToReserves is zero so the quote comes back zero
        bootstrapSDai(123_456e18);
        uint256 slippageBps = 100;
        uint256 exitAmount = 15e18;

        (IOrigamiInvestment.ExitQuoteData memory quoteData, uint256[] memory exitFeeBps) = managerImpl.exitQuote(
            exitAmount,
            address(daiToken),
            slippageBps,
            123
        );

        uint256 expectedFeeBps = 57;
        uint256 expectedAmount = sDaiToken.previewRedeem(
            lovToken.sharesToReserves(
                exitAmount.subtractBps(expectedFeeBps, OrigamiMath.Rounding.ROUND_DOWN)
            )
        );

        assertEq(quoteData.investmentTokenAmount, exitAmount);
        assertEq(quoteData.toToken, address(daiToken));
        assertEq(quoteData.maxSlippageBps, slippageBps);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedToTokenAmount, expectedAmount);
        assertEq(quoteData.minToTokenAmount, expectedAmount.subtractBps(slippageBps, OrigamiMath.Rounding.ROUND_UP));
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));

        assertEq(exitFeeBps.length, 1);
        assertEq(exitFeeBps[0], expectedFeeBps);
    }

    function test_exitQuote_depositAsset() public {
        bootstrapSDai(123_456e18);
        uint256 slippageBps = 100;
        uint256 depositAmount = 20e18;
        investWithSDai(depositAmount, alice);

        uint256 exitAmount = 15e18;
        (IOrigamiInvestment.ExitQuoteData memory quoteData, uint256[] memory exitFeeBps) = managerImpl.exitQuote(
            exitAmount,
            address(daiToken),
            slippageBps,
            123
        );

        uint256 expectedFeeBps = 57;
        uint256 expectedAmount = sDaiToken.previewRedeem(
            lovToken.sharesToReserves(
                exitAmount.subtractBps(expectedFeeBps, OrigamiMath.Rounding.ROUND_DOWN)
            )
        );

        assertEq(quoteData.investmentTokenAmount, exitAmount);
        assertEq(quoteData.toToken, address(daiToken));
        assertEq(quoteData.maxSlippageBps, slippageBps);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedToTokenAmount, expectedAmount);
        assertEq(quoteData.minToTokenAmount, expectedAmount.subtractBps(slippageBps, OrigamiMath.Rounding.ROUND_UP));
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));
        assertEq(exitFeeBps.length, 1);
        assertEq(exitFeeBps[0], expectedFeeBps);
    }

    function test_exitQuote_reserveToken_noDeposits() public {
        // No lovToken's minted yet -- sharesToReserves is zero so the quote comes back zero
        bootstrapSDai(123_456e18);
        uint256 slippageBps = 100;
        uint256 exitAmount = 15e18;

        (IOrigamiInvestment.ExitQuoteData memory quoteData, uint256[] memory exitFeeBps) = managerImpl.exitQuote(
            exitAmount,
            address(sDaiToken),
            slippageBps,
            123
        );

        uint256 expectedFeeBps = 57;
        uint256 expectedAmount = lovToken.sharesToReserves(
            exitAmount.subtractBps(expectedFeeBps, OrigamiMath.Rounding.ROUND_DOWN)
        );

        assertEq(quoteData.investmentTokenAmount, exitAmount);
        assertEq(quoteData.toToken, address(sDaiToken));
        assertEq(quoteData.maxSlippageBps, slippageBps);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedToTokenAmount, expectedAmount);
        assertEq(quoteData.minToTokenAmount, expectedAmount.subtractBps(slippageBps, OrigamiMath.Rounding.ROUND_UP));
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));

        assertEq(exitFeeBps.length, 1);
        assertEq(exitFeeBps[0], expectedFeeBps);
    }

    function test_exitQuote_reserveToken() public {
        bootstrapSDai(123_456e18);
        uint256 slippageBps = 100;
        uint256 depositAmount = 20e18;
        investWithSDai(depositAmount, alice);

        uint256 exitAmount = 15e18;
        (IOrigamiInvestment.ExitQuoteData memory quoteData, uint256[] memory exitFeeBps) = managerImpl.exitQuote(
            exitAmount,
            address(sDaiToken),
            slippageBps,
            123
        );

        uint256 expectedFeeBps = 57;
        uint256 expectedAmount = lovToken.sharesToReserves(
            exitAmount.subtractBps(expectedFeeBps, OrigamiMath.Rounding.ROUND_DOWN)
        );

        assertEq(quoteData.investmentTokenAmount, exitAmount);
        assertEq(quoteData.toToken, address(sDaiToken));
        assertEq(quoteData.maxSlippageBps, slippageBps);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedToTokenAmount, expectedAmount);
        assertEq(quoteData.minToTokenAmount, expectedAmount.subtractBps(slippageBps, OrigamiMath.Rounding.ROUND_UP));
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));
        assertEq(exitFeeBps.length, 1);
        assertEq(exitFeeBps[0], expectedFeeBps);
    }

    function test_exitToToken_fail_badToken() public {
        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = managerImpl.exitQuote(
            100e18,
            address(daiToken),
            100,
            123
        );

        quoteData.toToken = alice;
        vm.startPrank(address(lovToken));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, alice));
        managerImpl.exitToToken(alice, quoteData, alice);
    }

    function test_exitToToken_success_depositToken() public {
        uint256 sDaiSharePrice0 = bootstrapSDai(123_456e18);
        assertEq(sDaiSharePrice0, 1.05e18);
        investWithSDai(100e18, alice);
        assertEq(managerImpl.sharesToReserves(1e18, IOrigamiOracle.PriceType.SPOT_PRICE), 1.001001001001001001e18);
        assertEq(managerImpl.sharesToReserves(1e18, IOrigamiOracle.PriceType.HISTORIC_PRICE), 1.001001001001001001e18);
        assertEq(managerImpl.reservesBalance(), 100e18);

        doRebalanceDown(1.111111111111111111e18);
        uint256 expectedRebalanceReserves = 900e18 + 901;

        // The reserves/share is now slightly off 1:1 because
        // the of the DAI/USDC rate on the liabilities
        uint256 lovSharePrice = 1.001001007553184794e18;
        assertEq(managerImpl.sharesToReserves(1e18, IOrigamiOracle.PriceType.SPOT_PRICE), lovSharePrice);
        assertEq(managerImpl.sharesToReserves(1e18, IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.997622222222222231e18);
        assertEq(managerImpl.reservesBalance(), 100e18 + expectedRebalanceReserves);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 899.999999345436839954e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 900.337540000000000000e18);

        // Move forward in time so the sDAI is now worth more
        vm.warp(block.timestamp + 100 days);

        // A bit over 1.06 now
        uint256 sDaiSharePrice = sDaiToken.convertToAssets(1e18);
        assertEq(sDaiSharePrice, 1.064383561643835616e18);
        
        // Liabilities (in sdai terms) are less since the sDAI is worth more
        // So the lovDSR share price increases
        lovSharePrice = 1.122744372451250000e18;
        assertEq(managerImpl.sharesToReserves(1e18, IOrigamiOracle.PriceType.SPOT_PRICE), lovSharePrice);
        assertEq(managerImpl.sharesToReserves(1e18, IOrigamiOracle.PriceType.HISTORIC_PRICE), 1.119411246381516660e18);
        assertEq(managerImpl.reservesBalance(), 100e18 + expectedRebalanceReserves);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 887.837837192120125900e18); // previous liabilities * sDaiSharePrice0 / sDaiSharePrice
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 888.170816486486486487e18);

        uint256 slippageBps = 100;
        uint256 exitAmount = 15e18;
        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = managerImpl.exitQuote(
            exitAmount,
            address(daiToken),
            slippageBps,
            123
        );

        // Very close to:
        // (exitAmount * sDaiSharePrice / 1e18).subtractBps(MIN_EXIT_FEE_BPS) * lovSharePrice / 1e18
        // but order of operations is different
        uint256 expectedDaiAmount = 17.823284688564491278e18;

        vm.startPrank(address(lovToken));
        (
            uint256 toTokenAmount,
            uint256 toBurnAmount
        ) = managerImpl.exitToToken(alice, quoteData, alice);
        assertEq(toTokenAmount, expectedDaiAmount);
        assertEq(toBurnAmount, exitAmount);

        // lovToken does this itself after the manager returns
        assertEq(lovToken.totalSupply(), 99.9e18);
        assertEq(lovToken.balanceOf(alice), 99.9e18);

        assertEq(daiToken.balanceOf(address(managerImpl)), 0);
        assertEq(daiToken.balanceOf(alice), toTokenAmount);
        assertEq(daiToken.balanceOf(address(lovToken)), 0);
        // initial deposit 1:1 + rebalance down - exit (sDAI)
        assertEq(managerImpl.reservesBalance(), 983.254829057075832776e18);
        assertEq(sDaiToken.balanceOf(address(managerImpl)), managerImpl.reservesBalance());
    }

    function test_exitToToken_success_reserveToken() public {
        uint256 sDaiSharePrice0 = bootstrapSDai(123_456e18);
        assertEq(sDaiSharePrice0, 1.05e18);
        investWithSDai(100e18, alice);
        assertEq(managerImpl.sharesToReserves(1e18, IOrigamiOracle.PriceType.SPOT_PRICE), 1.001001001001001001e18);
        assertEq(managerImpl.sharesToReserves(1e18, IOrigamiOracle.PriceType.HISTORIC_PRICE), 1.001001001001001001e18);
        assertEq(managerImpl.reservesBalance(), 100e18);

        doRebalanceDown(1.111111111111111111e18);
        uint256 expectedRebalanceReserves = 900e18 + 901;

        // The reserves/share is now slightly off 1:1 because
        // the of the DAI/USDC rate on the liabilities
        uint256 lovSharePrice = 1.001001007553184794e18;
        assertEq(managerImpl.sharesToReserves(1e18, IOrigamiOracle.PriceType.SPOT_PRICE), lovSharePrice);
        assertEq(managerImpl.sharesToReserves(1e18, IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.997622222222222231e18);
        assertEq(managerImpl.reservesBalance(), 100e18 + expectedRebalanceReserves);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 899.999999345436839954e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 900.337540000000000000e18);

        // Move forward in time so the sDAI is now worth more
        vm.warp(block.timestamp + 100 days);

        // A bit over 1.06 now
        uint256 sDaiSharePrice = sDaiToken.convertToAssets(1e18);
        assertEq(sDaiSharePrice, 1.064383561643835616e18);

        // Liabilities (in sdai terms) are less since the sDAI is worth more
        // So the lovDSR share price increases
        lovSharePrice = 1.122744372451250000e18;
        assertEq(managerImpl.sharesToReserves(1e18, IOrigamiOracle.PriceType.SPOT_PRICE), lovSharePrice);
        assertEq(managerImpl.sharesToReserves(1e18, IOrigamiOracle.PriceType.HISTORIC_PRICE), 1.119411246381516660e18);
        assertEq(managerImpl.reservesBalance(), 100e18 + expectedRebalanceReserves);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 887.837837192120125900e18); // previous liabilities * sDaiSharePrice0 / sDaiSharePrice
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 888.170816486486486487e18);

        uint256 slippageBps = 100;
        uint256 exitAmount = 15e18;
        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = managerImpl.exitQuote(
            exitAmount,
            address(sDaiToken),
            slippageBps,
            123
        );

        // Very close to:
        // exitAmount.subtractBps(MIN_EXIT_FEE_BPS) * lovSharePrice / 1e18
        // but order of operations is different
        uint256 expectedSDaiAmount = 16.745170942924168125e18;

        vm.startPrank(address(lovToken));
        (
            uint256 toTokenAmount,
            uint256 toBurnAmount
        ) = managerImpl.exitToToken(alice, quoteData, bob);
        assertEq(toTokenAmount, expectedSDaiAmount);
        assertEq(toBurnAmount, exitAmount);

        // lovToken does this itself after the manager returns
        assertEq(lovToken.totalSupply(), 99.9e18);
        assertEq(lovToken.balanceOf(alice), 99.9e18);

        assertEq(daiToken.balanceOf(address(managerImpl)), 0);
        assertEq(daiToken.balanceOf(bob), 0);
        assertEq(sDaiToken.balanceOf(bob), toTokenAmount);
        assertEq(daiToken.balanceOf(address(lovToken)), 0);
        // initial deposit 1:1 + rebalance down - exit (sDAI)
        assertEq(managerImpl.reservesBalance(), 983.254829057075832776e18);
        assertEq(sDaiToken.balanceOf(address(managerImpl)), managerImpl.reservesBalance());
    }
}

contract OrigamiLovTokenErc4626ManagerTestViews is OrigamiLovTokenErc4626ManagerTestBase {
    function test_liabilities_zeroDebt() public {
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
    }

    function test_liabilities_withDebt_isPricingToken() public {
        investWithSDai(100e18, alice);
        uint256 borrowAmount = doRebalanceDown(1.11e18);
        assertEq(borrowAmount, 909.090909090909090910e18);

        // A very small diff -- the actual USDC that's borrowed is rounded down (and scaled down)
        // but then the liabilities is rounded up (but has higher precision)
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 909.090908843720332405e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 909.431859e18);
    }

    function _flipPricingToken() private {
        // Setup the oracle so it's the inverse (USDC/DAI)
        vm.startPrank(origamiMultisig);

        daiUsdcOracle = new OrigamiCrossRateOracle(
            IOrigamiOracle.BaseOracleParams(
                "USDC/DAI",
                address(usdcToken),
                6,
                address(daiToken),
                18
            ),
            address(origamiIUsdcUsdOracle),
            address(origamiDaiUsdOracle),
            address(0)
        );
        daiIUsdcOracle = new OrigamiCrossRateOracle(
            IOrigamiOracle.BaseOracleParams(
                "IUSDC/DAI",
                address(usdcToken),
                18,
                address(daiToken),
                18
            ),
            address(origamiIUsdcUsdOracle),
            address(origamiDaiUsdOracle),
            address(0)
        );
        managerImpl.setOracle(address(daiIUsdcOracle));

        vm.stopPrank();
    }

    function test_liabilities_withDebt_notPricingToken() public {
        _flipPricingToken();

        investWithSDai(100e18, alice);
        uint256 borrowAmount = doRebalanceDown(1.11e18);
        assertEq(borrowAmount, 909.090909090909090910e18);

        // A very small diff -- the actual USDC that's borrowed is rounded down (and scaled down)
        // but then the liabilities is rounded up (but has higher precision)
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 909.090908843720332419e18);
        assertEq(managerImpl.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 909.431859e18);
    }

    function test_getDynamicFeesBps_notPricingToken() public {
        (uint256 depositFeeBps, uint256 exitFeeBps) = managerImpl.getDynamicFeesBps();
        assertEq(depositFeeBps, 10);
        assertEq(exitFeeBps, 57);

        _flipPricingToken();
        (depositFeeBps, exitFeeBps) = managerImpl.getDynamicFeesBps();
        assertEq(depositFeeBps, 10);
        assertEq(exitFeeBps, 57);
    }

    function test_assetBalances() public {
        investWithSDai(100e18, alice);
        doRebalanceDown(1.11e18);

        IOrigamiLendingBorrower.AssetBalance[] memory assetBalances = managerImpl.latestAssetBalances();
        assertEq(assetBalances.length, 1);
        assertEq(assetBalances[0].asset, address(sDaiToken));
        assertEq(assetBalances[0].balance, 1_009.090909090909090910e18);

        assetBalances = managerImpl.checkpointAssetBalances();
        assertEq(assetBalances.length, 1);
        assertEq(assetBalances[0].asset, address(sDaiToken));
        assertEq(assetBalances[0].balance, 1_009.090909090909090910e18);
    }

    function test_dynamicDepositFeeBps_spotEqualHist() public {
        daiUsdOracle.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1e8,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        usdcUsdOracle.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1e8,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        (uint256 depositFee,) = managerImpl.getDynamicFeesBps();
        assertEq(depositFee, MIN_DEPOSIT_FEE_BPS);

        vm.startPrank(origamiMultisig);
        managerImpl.setFeeConfig(0, 0, 15);
        (depositFee,) = managerImpl.getDynamicFeesBps();
        assertEq(depositFee, 0);
    }

    function test_dynamicDepositFeeBps_spotGtHist() public {
        daiUsdOracle.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.01e8,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        usdcUsdOracle.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1e8,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        (uint256 depositFee,) = managerImpl.getDynamicFeesBps();
        assertEq(depositFee, MIN_DEPOSIT_FEE_BPS);

        vm.startPrank(origamiMultisig);
        managerImpl.setFeeConfig(0, 0, 15);
        (depositFee,) = managerImpl.getDynamicFeesBps();
        assertEq(depositFee, 0);
    }

    function test_dynamicDepositFeeBps_spotLtHist() public {
        daiUsdOracle.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 0.99e8,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        usdcUsdOracle.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1e8,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        (uint256 depositFee,) = managerImpl.getDynamicFeesBps();
        assertEq(depositFee, 1500);

        vm.startPrank(origamiMultisig);
        managerImpl.setFeeConfig(0, 0, 15e4);
        (depositFee,) = managerImpl.getDynamicFeesBps();
        assertEq(depositFee, 1500);
    }

    function test_dynamicExitFeeBps_spotEqualHist() public {
        daiUsdOracle.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1e8,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        usdcUsdOracle.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1e8,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));

        (, uint256 exitFeeBps) = managerImpl.getDynamicFeesBps();
        assertEq(exitFeeBps, MIN_EXIT_FEE_BPS);

        vm.startPrank(origamiMultisig);
        managerImpl.setFeeConfig(0, 0, 15);
        (, exitFeeBps) = managerImpl.getDynamicFeesBps();
        assertEq(exitFeeBps, 0);
    }

    function test_dynamicExitFeeBps_spotGtHist() public {
        daiUsdOracle.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.01e8,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        usdcUsdOracle.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1e8,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));

        (, uint256 exitFeeBps) = managerImpl.getDynamicFeesBps();
        assertEq(exitFeeBps, 1500);

        vm.startPrank(origamiMultisig);
        managerImpl.setFeeConfig(0, 0, 15e4);
        (, exitFeeBps) = managerImpl.getDynamicFeesBps();
        assertEq(exitFeeBps, 1500);
    }

    function test_dynamicExitFeeBps_spotLtHist() public {
        daiUsdOracle.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 0.99e8,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        usdcUsdOracle.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1e8,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        (, uint256 exitFeeBps) = managerImpl.getDynamicFeesBps();
        assertEq(exitFeeBps, MIN_EXIT_FEE_BPS);

        vm.startPrank(origamiMultisig);
        managerImpl.setFeeConfig(0, 0, 15);
        (, exitFeeBps) = managerImpl.getDynamicFeesBps();
        assertEq(exitFeeBps, 0);
    }
}
