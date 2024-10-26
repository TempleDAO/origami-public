pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiCowSwapper } from "contracts/common/swappers/OrigamiCowSwapper.sol";
import { IOrigamiCowSwapper } from "contracts/interfaces/common/swappers/IOrigamiCowSwapper.sol";
import { ICowSettlement } from "contracts/interfaces/external/cowprotocol/ICowSettlement.sol";
import { OrigamiErc4626Oracle } from "contracts/common/oracle/OrigamiErc4626Oracle.sol";
import { OrigamiCrossRateOracle } from "contracts/common/oracle/OrigamiCrossRateOracle.sol";

import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IConditionalOrder } from "contracts/interfaces/external/cowprotocol/IConditionalOrder.sol";
import { GPv2Order } from "contracts/external/cowprotocol/GPv2Order.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

contract MockCowSettlement is ICowSettlement {
    function domainSeparator() external pure returns (bytes32) {
        // from mainnet 0x9008D19f58AAbD9eD0D60971565AA8510560ab41
        return 0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943;
    }
}

contract OrigamiCowSwapperForkTestBase is OrigamiTest {
    OrigamiCowSwapper public swapper;
    IOrigamiOracle public sdaiOracle;
    IOrigamiOracle public susdeOracle;
    IOrigamiOracle public limitPriceOracle;

    ICowSettlement public cowSwapSettlement;
    address public cowSwapRelayer;

    address public sDAI;
    address public DAI;
    address public sUSDe;
    address public USDe;

    address public constant INTERNAL_USD_ADDRESS = 0x000000000000000000000000000000000000115d;

    uint16 public constant PRICE_PREMIUM_BPS = 30;
    uint16 public constant VERIFY_SLIPPAGE_BPS = 3;
    uint96 public constant ROUND_DOWN_DIVISOR = 10e18; // In buyToken decimals
    uint24 public constant EXPIRY_PERIOD_SECS = 5 minutes;
    bytes32 public constant APP_DATA = bytes32("{}");
    uint96 public constant SDAI_SELL_AMOUNT = 1_000_000e18;

    function setUp() public {
        fork("mainnet", 20682077);

        cowSwapSettlement = MockCowSettlement(0x9008D19f58AAbD9eD0D60971565AA8510560ab41);
        cowSwapRelayer = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;

        sDAI = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
        DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        sUSDe = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
        USDe = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;

        swapper = new OrigamiCowSwapper(
            origamiMultisig, 
            cowSwapRelayer
        );

        sdaiOracle = new OrigamiErc4626Oracle(
            IOrigamiOracle.BaseOracleParams(
                "sDAI/USD",
                sDAI,
                18,
                INTERNAL_USD_ADDRESS,
                18
            ),
            address(0)
        );
        susdeOracle = new OrigamiErc4626Oracle(
            IOrigamiOracle.BaseOracleParams(
                "sUSDe/USD",
                sUSDe,
                18,
                INTERNAL_USD_ADDRESS,
                18
            ),
            address(0)
        );
        
        limitPriceOracle = new OrigamiCrossRateOracle(
            IOrigamiOracle.BaseOracleParams(
                "sDAI/sUSDe",
                sDAI,
                18,
                sUSDe,
                18
            ),
            address(sdaiOracle),
            address(susdeOracle),
            address(0)
        );

        // Deal 1 gwei so it doesn't skip with PollTryAtEpoch
        deal(sDAI, address(swapper), 1);
    }

    function defaultOrderConfig() internal view returns (IOrigamiCowSwapper.OrderConfig memory) {
        return IOrigamiCowSwapper.OrderConfig({
            maxSellAmount: SDAI_SELL_AMOUNT,
            buyToken: IERC20(sUSDe),
            minBuyAmount: 1,
            partiallyFillable: true,
            useCurrentBalanceForSellAmount: false,
            limitPriceOracle: limitPriceOracle,
            limitPricePremiumBps: PRICE_PREMIUM_BPS,
            roundDownDivisor: ROUND_DOWN_DIVISOR,
            verifySlippageBps: VERIFY_SLIPPAGE_BPS,
            expiryPeriodSecs: EXPIRY_PERIOD_SECS,
            recipient: address(swapper),
            appData: APP_DATA
        });
    }

    function configureOrder() internal {
        vm.startPrank(origamiMultisig);
        swapper.setOrderConfig(
            sDAI,
            defaultOrderConfig()
        );
    }

    function defaultConditionalOrderParams() internal view returns (IConditionalOrder.ConditionalOrderParams memory) {
        return IConditionalOrder.ConditionalOrderParams(
            address(0),
            bytes32(0),
            abi.encode(sDAI)
        );
    }

    function test_oracle() public {
        assertEq(
            sdaiOracle.convertAmount(sDAI, 1e18, IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            1.106391098015661527e18
        );
        assertEq(
            susdeOracle.convertAmount(sUSDe, 1e18, IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN),
            1.099454915539319362e18
        );
        assertEq(
            limitPriceOracle.convertAmount(sDAI, 1e18, IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            1.006308746614625608e18
        );
    }

    function test_getTradeableOrderWithSignature_success_1() public {
        configureOrder();

        (
            GPv2Order.Data memory order, 
            bytes memory signature
        ) = swapper.getTradeableOrderWithSignature(
            address(swapper), 
            defaultConditionalOrderParams(),
            "",
            new bytes32[](0)
        );

        assertEq(address(order.sellToken), sDAI);
        assertEq(address(order.buyToken), sUSDe);
        assertEq(order.receiver, address(swapper));
        assertEq(order.sellAmount, SDAI_SELL_AMOUNT);
        assertEq(order.buyAmount, 1_009_320e18);
        assertEq(order.validTo, 1725511500); 
        assertEq(order.appData, APP_DATA);
        assertEq(order.feeAmount, 0);
        assertEq(order.kind, GPv2Order.KIND_SELL);
        assertEq(order.partiallyFillable, true);
        assertEq(order.sellTokenBalance, GPv2Order.BALANCE_ERC20);
        assertEq(order.buyTokenBalance, GPv2Order.BALANCE_ERC20);

        assertEq(signature, abi.encode(order));
    }
}
