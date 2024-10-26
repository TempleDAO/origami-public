pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiCowSwapper } from "contracts/common/swappers/OrigamiCowSwapper.sol";
import { IOrigamiCowSwapper } from "contracts/interfaces/common/swappers/IOrigamiCowSwapper.sol";
import { ICowSettlement } from "contracts/interfaces/external/cowprotocol/ICowSettlement.sol";
import { OrigamiFixedPriceOracle } from "contracts/common/oracle/OrigamiFixedPriceOracle.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { IConditionalOrder } from "contracts/interfaces/external/cowprotocol/IConditionalOrder.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { IWatchtowerErrors } from "contracts/interfaces/external/cowprotocol/IWatchtowerErrors.sol";
import { GPv2Order } from "contracts/external/cowprotocol/GPv2Order.sol";

contract MockCowSettlement is ICowSettlement {
    function domainSeparator() external pure returns (bytes32) {
        // from mainnet 0x9008D19f58AAbD9eD0D60971565AA8510560ab41
        return 0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943;
    }
}

contract OrigamiCowSwapperTestBase is OrigamiTest {
    OrigamiCowSwapper public swapper;
    OrigamiFixedPriceOracle public limitPriceOracle;

    ICowSettlement public cowSwapSettlement;
    address public cowSwapRelayer;

    address public DAI;
    address public USDC;

    uint16 public constant PRICE_PREMIUM_BPS = 30;
    uint16 public constant VERIFY_SLIPPAGE_BPS = 3;
    uint96 public constant ROUND_DOWN_DIVISOR = 10e6; // In buyToken decimals
    uint24 public constant EXPIRY_PERIOD_SECS = 5 minutes;
    bytes32 public constant APP_DATA = bytes32("{}");
    uint96 public constant DAI_SELL_AMOUNT = 1_000_000e18;

    function setUp() public {
        vm.warp(1704027600);
        cowSwapSettlement = new MockCowSettlement();
        cowSwapRelayer = makeAddr("cowSwapRelayer");

        DAI = address(new DummyMintableToken(origamiMultisig, "DAI", "DAI", 18));
        USDC = address(new DummyMintableToken(origamiMultisig, "USDC", "USDC", 6));

        swapper = new OrigamiCowSwapper(
            origamiMultisig, 
            cowSwapRelayer
        );
        limitPriceOracle = new OrigamiFixedPriceOracle(
            IOrigamiOracle.BaseOracleParams(
                "DAI/USDC",
                DAI,
                18,
                USDC,
                6
            ),
            0.95e18,
            address(0)
        );

        // Deal 1 gwei so it doesn't skip with PollTryAtEpoch
        deal(DAI, address(swapper), 1);
    }

    function defaultOrderConfig() internal view returns (IOrigamiCowSwapper.OrderConfig memory) {
        return IOrigamiCowSwapper.OrderConfig({
            maxSellAmount: DAI_SELL_AMOUNT,
            buyToken: IERC20(USDC),
            minBuyAmount: 1,
            limitPriceOracle: limitPriceOracle,
            recipient: address(swapper),
            roundDownDivisor: ROUND_DOWN_DIVISOR,
            partiallyFillable: true,
            useCurrentBalanceForSellAmount: false,
            limitPricePremiumBps: PRICE_PREMIUM_BPS,
            verifySlippageBps: VERIFY_SLIPPAGE_BPS,
            expiryPeriodSecs: EXPIRY_PERIOD_SECS,
            appData: APP_DATA
        });
    }

    function configureDai() internal virtual {
        vm.startPrank(origamiMultisig);
        swapper.setOrderConfig(
            DAI,
            defaultOrderConfig()
        );
    }

    function defaultConditionalOrderParams() internal view returns (IConditionalOrder.ConditionalOrderParams memory) {
        return IConditionalOrder.ConditionalOrderParams(
            address(0),
            bytes32(0),
            abi.encode(DAI)
        );
    }

    function getDefaultOrder() internal view returns (
        GPv2Order.Data memory order, 
        bytes memory signature
    ) {
        return swapper.getTradeableOrderWithSignature(
            address(swapper), 
            defaultConditionalOrderParams(),
            "",
            new bytes32[](0)
        );
    }
}

contract OrigamiCowSwapperTestAdmin is OrigamiCowSwapperTestBase {
    event OrderConfigSet(address indexed sellToken);
    event OrderConfigRemoved(address indexed sellToken);
    event PausedSet(bool paused);

    function test_initialization() public {
        assertEq(swapper.owner(), origamiMultisig);
        assertEq(swapper.isPaused(), false);
    }

    function test_setPaused() public {
        vm.startPrank(origamiMultisig);
        assertEq(swapper.isPaused(), false);

        vm.expectEmit(address(swapper));
        emit PausedSet(true);
        swapper.setPaused(true);
        assertEq(swapper.isPaused(), true);

        vm.expectEmit(address(swapper));
        emit PausedSet(false);
        swapper.setPaused(false);
        assertEq(swapper.isPaused(), false);
    }

    function test_setCowApproval() public {
        vm.startPrank(origamiMultisig);
        assertEq(IERC20(DAI).allowance(address(swapper), cowSwapRelayer), 0);

        // Still works even if token isn't configured.
        swapper.setCowApproval(DAI, 12345e18);
        assertEq(IERC20(DAI).allowance(address(swapper), cowSwapRelayer), 12345e18);

        configureDai();
        swapper.setCowApproval(DAI, 0.987e18);
        assertEq(IERC20(DAI).allowance(address(swapper), cowSwapRelayer), 0.987e18);
    }

    function test_setOrderConfig_failures() public {
        vm.startPrank(origamiMultisig);

        IOrigamiCowSwapper.OrderConfig memory config = defaultOrderConfig();

        // Zero sellToken
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        swapper.setOrderConfig(address(0), config);

        // Zero buyToken
        config.buyToken = IERC20(address(0));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        swapper.setOrderConfig(DAI, config);

        // buyToken same as sellToken
        config.buyToken = IERC20(DAI);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(DAI)));
        swapper.setOrderConfig(DAI, config);

        // Zero maxSellAmount
        config.buyToken = IERC20(USDC);
        config.maxSellAmount = 0;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        swapper.setOrderConfig(DAI, config);

        // Zero minBuyAmount
        config.maxSellAmount = DAI_SELL_AMOUNT;
        config.minBuyAmount = 0;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        swapper.setOrderConfig(DAI, config);

        // verifySlippageBps too big
        config.minBuyAmount = 1;
        config.verifySlippageBps = 10_001;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        swapper.setOrderConfig(DAI, config);

        // zero expiryPeriodSecs
        config.verifySlippageBps = VERIFY_SLIPPAGE_BPS;
        config.expiryPeriodSecs = 0;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        swapper.setOrderConfig(DAI, config);

        // expiryPeriodSecs too long
        config.expiryPeriodSecs = 7 days + 1;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        swapper.setOrderConfig(DAI, config);

        // Zero recipient
        config.expiryPeriodSecs = EXPIRY_PERIOD_SECS;
        config.recipient = address(0);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        swapper.setOrderConfig(DAI, config);

        // Zero oracle but non zero limitPricePremiumBps
        config.recipient = address(swapper);
        config.limitPriceOracle = OrigamiFixedPriceOracle(address(0));
        config.limitPricePremiumBps = 123;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        swapper.setOrderConfig(DAI, config);

        // Non matching price oracle
        config.limitPricePremiumBps = 0;
        config.limitPriceOracle = new OrigamiFixedPriceOracle(
            IOrigamiOracle.BaseOracleParams(
                "alice/USDC",
                alice,
                18,
                USDC,
                6
            ),
            0.95e18,
            address(0)
        );
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        swapper.setOrderConfig(DAI, config);
    }

    function test_setOrderConfig_success() public {
        vm.startPrank(origamiMultisig);
        
        // Unset to start
        IOrigamiCowSwapper.OrderConfig memory newConfig = swapper.orderConfig(DAI);
        assertEq(address(newConfig.buyToken), address(0));
        
        IOrigamiCowSwapper.OrderConfig memory config = defaultOrderConfig();
        vm.expectEmit(address(swapper));
        emit OrderConfigSet(DAI);
        swapper.setOrderConfig(DAI, config);

        newConfig = swapper.orderConfig(DAI);
        {
            assertEq(newConfig.maxSellAmount, DAI_SELL_AMOUNT);
            assertEq(address(newConfig.buyToken), USDC);
            assertEq(newConfig.minBuyAmount, 1);
            assertEq(newConfig.partiallyFillable, true);
            assertEq(newConfig.useCurrentBalanceForSellAmount, false);
            assertEq(address(newConfig.limitPriceOracle), address(limitPriceOracle));
            assertEq(newConfig.limitPricePremiumBps, PRICE_PREMIUM_BPS);
            assertEq(newConfig.roundDownDivisor, ROUND_DOWN_DIVISOR);
            assertEq(newConfig.verifySlippageBps, VERIFY_SLIPPAGE_BPS);
            assertEq(newConfig.expiryPeriodSecs, EXPIRY_PERIOD_SECS);
            assertEq(newConfig.recipient, address(swapper));
            assertEq(newConfig.appData, APP_DATA);
        }

        // Update in place
        config.maxSellAmount = 123e18;
        vm.expectEmit(address(swapper));
        emit OrderConfigSet(DAI);
        swapper.setOrderConfig(DAI, config);
        newConfig = swapper.orderConfig(DAI);
        {
            assertEq(newConfig.maxSellAmount, 123e18);
            assertEq(address(newConfig.buyToken), USDC);
            assertEq(newConfig.minBuyAmount, 1);
            assertEq(newConfig.partiallyFillable, true);
            assertEq(newConfig.useCurrentBalanceForSellAmount, false);
            assertEq(address(newConfig.limitPriceOracle), address(limitPriceOracle));
            assertEq(newConfig.limitPricePremiumBps, PRICE_PREMIUM_BPS);
            assertEq(newConfig.roundDownDivisor, ROUND_DOWN_DIVISOR);
            assertEq(newConfig.verifySlippageBps, VERIFY_SLIPPAGE_BPS);
            assertEq(newConfig.expiryPeriodSecs, EXPIRY_PERIOD_SECS);
            assertEq(newConfig.recipient, address(swapper));
            assertEq(newConfig.appData, APP_DATA);
        }
    }

    function test_removeOrderConfig() public {
        vm.startPrank(origamiMultisig);
        
        IOrigamiCowSwapper.OrderConfig memory newConfig = swapper.orderConfig(DAI);
        assertEq(address(newConfig.buyToken), address(0));

        vm.expectEmit(address(swapper));
        emit OrderConfigRemoved(DAI);
        swapper.removeOrderConfig(DAI);
        newConfig = swapper.orderConfig(DAI);
        assertEq(address(newConfig.buyToken), address(0));

        configureDai();
        newConfig = swapper.orderConfig(DAI);
        assertEq(address(newConfig.buyToken), USDC);
    
        vm.expectEmit(address(swapper));
        emit OrderConfigRemoved(DAI);
        swapper.removeOrderConfig(DAI);
        newConfig = swapper.orderConfig(DAI);
        assertEq(address(newConfig.buyToken), address(0));
    }

    function test_updateAmountsAndPremiumBps_failNotConfigured() public {
        vm.startPrank(origamiMultisig);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiCowSwapper.InvalidSellToken.selector, DAI));
        swapper.updateAmountsAndPremiumBps(DAI, 123, 123, 123);
    }

    function test_updateAmountsAndPremiumBps_failBadParams() public {
        configureDai();

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        swapper.updateAmountsAndPremiumBps(DAI, 0, 123, 123);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        swapper.updateAmountsAndPremiumBps(DAI, 123, 0, 123);
    }

    function test_updateAmountsAndPremiumBps_failLimitPricePremium() public {
        vm.startPrank(origamiMultisig);
        IOrigamiCowSwapper.OrderConfig memory config = defaultOrderConfig();
        config.limitPriceOracle = IOrigamiOracle(address(0));
        config.limitPricePremiumBps = 0;
        swapper.setOrderConfig(
            DAI,
            config
        );

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        swapper.updateAmountsAndPremiumBps(DAI, 123, 123, 123);

        // ok with zero premium
        swapper.updateAmountsAndPremiumBps(DAI, 123, 123, 0);
    }

    function test_updateAmountsAndPremiumBps_success() public {
        configureDai();
        vm.expectEmit(address(swapper));
        emit OrderConfigSet(DAI);
        swapper.updateAmountsAndPremiumBps(DAI, 123, 456, 789);
        
        IOrigamiCowSwapper.OrderConfig memory newConfig = swapper.orderConfig(DAI);
        assertEq(newConfig.maxSellAmount, 123);
        assertEq(newConfig.minBuyAmount, 456);
        assertEq(newConfig.limitPricePremiumBps, 789);
    }

    function test_recoverToken() public {
        check_recoverToken(address(swapper));
    }
}

contract OrigamiCowSwapperTestAccess is OrigamiCowSwapperTestBase {

    function test_access_setPaused() public {
        expectElevatedAccess();
        swapper.setPaused(true);
    }

    function test_access_setCowApproval() public {
        expectElevatedAccess();
        swapper.setCowApproval(DAI, 123e18);
    }

    function test_access_setOrderConfig() public {
        expectElevatedAccess();
        swapper.setOrderConfig(
            DAI,
            defaultOrderConfig()
        );
    }

    function test_access_removeOrderConfig() public {
        expectElevatedAccess();
        swapper.removeOrderConfig(DAI);
    }

    function test_access_updateLimitPricePremiumBps() public {
        expectElevatedAccess();
        swapper.updateAmountsAndPremiumBps(DAI, 123, 456, 789);
    }

    function test_access_recoverToken() public {
        expectElevatedAccess();
        swapper.recoverToken(DAI, origamiMultisig, 123e18);
    }

    function test_access_createConditionalOrder() public {
        expectElevatedAccess();
        swapper.createConditionalOrder(DAI);
    }
}

contract OrigamiCowSwapperTestLimitOrders is OrigamiCowSwapperTestBase {
    event ConditionalOrderCreated(address indexed owner, IConditionalOrder.ConditionalOrderParams params);

    function test_createConditionalOrder_fail_paused() public {
        vm.startPrank(origamiMultisig);
        swapper.setPaused(true);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.IsPaused.selector));
        swapper.createConditionalOrder(DAI);
    }

    function test_createConditionalOrder_fail_badSellToken() public {
        vm.startPrank(origamiMultisig);
        
        vm.expectRevert(abi.encodeWithSelector(IOrigamiCowSwapper.InvalidSellToken.selector, DAI));
        swapper.createConditionalOrder(DAI);
    }

    function test_createConditionalOrder_fail_success() public {
        configureDai();

        vm.expectEmit(address(swapper));
        emit ConditionalOrderCreated(
            address(swapper),
            defaultConditionalOrderParams()
        );
        swapper.createConditionalOrder(DAI);

        // Doing a second time is fine
        vm.expectEmit(address(swapper));
        emit ConditionalOrderCreated(
            address(swapper),
            defaultConditionalOrderParams()
        );
        swapper.createConditionalOrder(DAI);
    }
    
    function test_getTradeableOrderWithSignature_fail_isPaused() public {
        vm.startPrank(origamiMultisig);
        swapper.setPaused(true);

        vm.expectRevert(abi.encodeWithSelector(
            IWatchtowerErrors.PollTryAtEpoch.selector, 
            block.timestamp+300,
            "Paused"
        ));
        swapper.getTradeableOrderWithSignature(
            address(swapper), 
            defaultConditionalOrderParams(),
            "",
            new bytes32[](0)
        );
    }
    
    function test_getTradeableOrderWithSignature_fail_invalidOwner() public {
        vm.startPrank(origamiMultisig);

        vm.expectRevert(abi.encodeWithSelector(
            IWatchtowerErrors.OrderNotValid.selector, 
            "order owner must be self"
        ));
        swapper.getTradeableOrderWithSignature(
            alice, 
            defaultConditionalOrderParams(),
            "",
            new bytes32[](0)
        );
    }
    
    function test_getTradeableOrderWithSignature_fail_invalidHandler() public {
        vm.startPrank(origamiMultisig);

        vm.expectRevert(abi.encodeWithSelector(
            IWatchtowerErrors.OrderNotValid.selector, 
            "handler must be unset"
        ));

        swapper.getTradeableOrderWithSignature(
            address(swapper), 
            IConditionalOrder.ConditionalOrderParams(
                alice,
                bytes32(0),
                abi.encode(DAI)
            ),
            "",
            new bytes32[](0)
        );
    }
    
    function test_getTradeableOrderWithSignature_fail_invalidSalt() public {
        vm.startPrank(origamiMultisig);

        vm.expectRevert(abi.encodeWithSelector(
            IWatchtowerErrors.OrderNotValid.selector, 
            "salt must be unset"
        ));

        swapper.getTradeableOrderWithSignature(
            address(swapper), 
            IConditionalOrder.ConditionalOrderParams(
                address(0),
                bytes32(keccak256("xxx")),
                abi.encode(DAI)
            ),
            "",
            new bytes32[](0)
        );
    }
    
    function test_getTradeableOrderWithSignature_fail_notConfiguredToken() public {
        vm.startPrank(origamiMultisig);

        vm.expectRevert(abi.encodeWithSelector(
            IWatchtowerErrors.OrderNotValid.selector, 
            "sellToken not configured"
        ));

        swapper.getTradeableOrderWithSignature(
            address(swapper), 
            defaultConditionalOrderParams(),
            "",
            new bytes32[](0)
        );
    }
    
    function test_getTradeableOrderWithSignature_fail_zeroBalance() public {
        configureDai();
        deal(DAI, address(swapper), 0);

        vm.expectRevert(abi.encodeWithSelector(
            IWatchtowerErrors.PollTryAtEpoch.selector, 
            block.timestamp+300,
            "ZeroBalance"
        ));
        swapper.getTradeableOrderWithSignature(
            address(swapper), 
            defaultConditionalOrderParams(),
            "",
            new bytes32[](0)
        );
    }
    
    function test_getTradeableOrderWithSignature_success_1() public {
        configureDai();

        (GPv2Order.Data memory order, bytes memory signature) = getDefaultOrder();

        assertEq(address(order.sellToken), DAI);
        assertEq(address(order.buyToken), USDC);
        assertEq(order.receiver, address(swapper));
        assertEq(order.sellAmount, DAI_SELL_AMOUNT);
        assertEq(order.buyAmount, 952_850e6);
        // Was right at 00:00
        assertEq(order.validTo, block.timestamp + 5 minutes); 
        assertEq(order.appData, APP_DATA);
        assertEq(order.feeAmount, 0);
        assertEq(order.kind, GPv2Order.KIND_SELL);
        assertEq(order.partiallyFillable, true);
        assertEq(order.sellTokenBalance, GPv2Order.BALANCE_ERC20);
        assertEq(order.buyTokenBalance, GPv2Order.BALANCE_ERC20);

        assertEq(signature, abi.encode(order));
    }
    
    // Flip the params and make sure the resulting order changes.
    function test_getTradeableOrderWithSignature_success_2() public {
        vm.startPrank(origamiMultisig);
        IOrigamiCowSwapper.OrderConfig memory config = IOrigamiCowSwapper.OrderConfig({
            maxSellAmount: 123e6,
            buyToken: IERC20(DAI),
            minBuyAmount: 1,
            limitPriceOracle: limitPriceOracle,
            recipient: alice,
            roundDownDivisor: 5e18,
            partiallyFillable: false,
            useCurrentBalanceForSellAmount: false,
            limitPricePremiumBps: PRICE_PREMIUM_BPS,
            verifySlippageBps: VERIFY_SLIPPAGE_BPS,
            expiryPeriodSecs: EXPIRY_PERIOD_SECS*3/2,
            appData: bytes32("abc")
        });

        swapper.setOrderConfig(USDC, config);
        deal(USDC, address(swapper), 1);        

        (
            GPv2Order.Data memory order, 
            bytes memory signature
        ) = swapper.getTradeableOrderWithSignature(
            address(swapper), 
            IConditionalOrder.ConditionalOrderParams(
                address(0),
                bytes32(0),
                abi.encode(USDC)
            ),
            "",
            new bytes32[](0)
        );

        assertEq(address(order.sellToken), USDC);
        assertEq(address(order.buyToken), DAI);
        assertEq(order.receiver, alice);
        assertEq(order.sellAmount, 123e6);
        assertEq(order.buyAmount, 125e18);
        // Was right at 00:00
        assertEq(order.validTo, block.timestamp + 450); 
        assertEq(order.appData, bytes32("abc"));
        assertEq(order.feeAmount, 0);
        assertEq(order.kind, GPv2Order.KIND_SELL);
        assertEq(order.partiallyFillable, false);
        assertEq(order.sellTokenBalance, GPv2Order.BALANCE_ERC20);
        assertEq(order.buyTokenBalance, GPv2Order.BALANCE_ERC20);

        assertEq(signature, abi.encode(order));
    }

    function test_isValidSignature_fail_isPaused() public {
        vm.startPrank(origamiMultisig);
        swapper.setPaused(true);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.IsPaused.selector));
        swapper.isValidSignature(bytes32("123"), "");
    }

    function test_isValidSignature_fail_badSignature() public {
        // Can't abi decode the order
        vm.expectRevert();
        swapper.isValidSignature(bytes32("123"), "abc");
    }

    function test_isValidSignature_fail_notConfiguredToken() public {
        // First configure and get the order/sig
        configureDai();
        (GPv2Order.Data memory order, bytes memory signature) = getDefaultOrder();
        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());

        // Now remove the config
        swapper.removeOrderConfig(DAI);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiCowSwapper.InvalidSellToken.selector, DAI));
        swapper.isValidSignature(hash, signature);
    }
    
    function test_isValidSignature_success_lower() public {
        // First configure and get the order/sig
        configureDai();

        // Force an odd amount to see effects of rounding
        uint256 forcedAmount = 1_012_345.678912e6;
        vm.mockCall(
            address(limitPriceOracle),
            abi.encodeWithSelector(IOrigamiOracle.convertAmount.selector),
            abi.encode(forcedAmount)
        );

        (GPv2Order.Data memory order, bytes memory signature) = getDefaultOrder();
        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());

        // The forceAmount + price premium, rounded down to nearest 10e6
        assertEq(order.buyAmount, 1_015_380e6);

        // Move the price lower
        vm.mockCall(
            address(limitPriceOracle),
            abi.encodeWithSelector(IOrigamiOracle.convertAmount.selector),
            abi.encode(1_012_000e6)
        );

        assertEq(swapper.isValidSignature(hash, signature), swapper.isValidSignature.selector);
    }

    function test_isValidSignature_success_higherWithinSlippage() public {
        // First configure and get the order/sig
        configureDai();

        // Force an odd amount to see effects of rounding
        uint256 forcedAmount = 1_012_345.678912e6;
        vm.mockCall(
            address(limitPriceOracle),
            abi.encodeWithSelector(IOrigamiOracle.convertAmount.selector),
            abi.encode(forcedAmount)
        );

        (GPv2Order.Data memory order, bytes memory signature) = getDefaultOrder();
        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());
        assertEq(order.buyAmount, 1_015_380e6);

        // Move the price a little higher
        vm.mockCall(
            address(limitPriceOracle),
            abi.encodeWithSelector(IOrigamiOracle.convertAmount.selector),
            abi.encode(1_012_400e6)
        );

        assertEq(swapper.isValidSignature(hash, signature), swapper.isValidSignature.selector);
    }

    function test_isValidSignature_fail_slippage() public {
        // First configure and get the order/sig
        configureDai();

        // Force an odd amount to see effects of rounding
        uint256 forcedAmount = 1_012_345.678912e6;
        vm.mockCall(
            address(limitPriceOracle),
            abi.encodeWithSelector(IOrigamiOracle.convertAmount.selector),
            abi.encode(forcedAmount)
        );

        (GPv2Order.Data memory order, bytes memory signature) = getDefaultOrder();
        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());
        assertEq(order.buyAmount, 1_015_380e6);

        // Move the price a little higher
        vm.mockCall(
            address(limitPriceOracle),
            abi.encodeWithSelector(IOrigamiOracle.convertAmount.selector),
            abi.encode(1013687330762)
        );

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, 1_015_684.614e6, 1_016_720e6));
        swapper.isValidSignature(hash, signature);
    }
    
    function test_isValidSignature_fail_recipient() public {
        configureDai();

        (GPv2Order.Data memory order, bytes memory signature) = getDefaultOrder();
        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());

        // Update the config to a different recipient
        IOrigamiCowSwapper.OrderConfig memory config = defaultOrderConfig();
        config.recipient = alice;
        swapper.setOrderConfig(DAI, config);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiCowSwapper.OrderDoesNotMatchTradeableOrder.selector));
        swapper.isValidSignature(hash, signature);
    }
    
    function test_isValidSignature_fail_noHash() public {
        configureDai();

        (, bytes memory signature) = swapper.getTradeableOrderWithSignature(
            address(swapper), 
            defaultConditionalOrderParams(),
            "",
            new bytes32[](0)
        );

        // Still works fine.
        assertEq(swapper.isValidSignature(bytes32(""), signature), swapper.isValidSignature.selector);
    }
    
    function test_isValidSignature_fail_upatedField() public {
        configureDai();

        (
            GPv2Order.Data memory order,
            bytes memory signature
        ) = swapper.getTradeableOrderWithSignature(
            address(swapper), 
            defaultConditionalOrderParams(),
            "",
            new bytes32[](0)
        );
        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());

        // Update to be partially fillable
        IOrigamiCowSwapper.OrderConfig memory config = defaultOrderConfig();
        config.partiallyFillable = false;
        swapper.setOrderConfig(DAI, config);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiCowSwapper.OrderDoesNotMatchTradeableOrder.selector));
        swapper.isValidSignature(hash, signature);
    }
    
    function test_isValidSignature_success_noSlippage() public {
        configureDai();

        (
            GPv2Order.Data memory order,
            bytes memory signature
        ) = swapper.getTradeableOrderWithSignature(
            address(swapper), 
            defaultConditionalOrderParams(),
            "",
            new bytes32[](0)
        );

        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());
        assertEq(swapper.isValidSignature(hash, signature), swapper.isValidSignature.selector);
    }
    
    function test_isValidSignature_success_smallSlippage() public {
        configureDai();

        // Force an odd amount to see effects of rounding
        uint256 forcedAmount = 1_012_345.678912e6;
        vm.mockCall(
            address(limitPriceOracle),
            abi.encodeWithSelector(IOrigamiOracle.convertAmount.selector),
            abi.encode(forcedAmount)
        );

        (GPv2Order.Data memory order, bytes memory signature) = getDefaultOrder();

        // The forceAmount + price premium, rounded down to nearest 10e6
        assertEq(order.buyAmount, 1_015_380e6);

        // Move the price sufficiently lower such that it's still within
        // tolerance
        vm.mockCall(
            address(limitPriceOracle),
            abi.encodeWithSelector(IOrigamiOracle.convertAmount.selector),
            abi.encode(1_012_100e6)
        );
        
        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());
        assertEq(swapper.isValidSignature(hash, signature), swapper.isValidSignature.selector);
    }

    function test_isValidSignature_success_largerSellAmount() public {
        // First configure and get the order/sig
        configureDai();

        (GPv2Order.Data memory order, bytes memory signature) = getDefaultOrder();
        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());

        // Update to be slightly smaller sell amount
        IOrigamiCowSwapper.OrderConfig memory config = defaultOrderConfig();
        config.maxSellAmount = DAI_SELL_AMOUNT + 1e6;
        swapper.setOrderConfig(DAI, config);

        assertEq(swapper.isValidSignature(hash, signature), swapper.isValidSignature.selector);
    }

    function test_isValidSignature_success_smallerSellAmount() public {
        // First configure and get the order/sig
        configureDai();

        (GPv2Order.Data memory order, bytes memory signature) = getDefaultOrder();
        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());

        // Update to be slightly smaller sell amount
        IOrigamiCowSwapper.OrderConfig memory config = defaultOrderConfig();
        config.maxSellAmount = DAI_SELL_AMOUNT - 1e6;
        swapper.setOrderConfig(DAI, config);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiCowSwapper.OrderDoesNotMatchTradeableOrder.selector));
        swapper.isValidSignature(hash, signature);
    }
}

contract OrigamiCowSwapperTestLimitOrderViews is OrigamiCowSwapperTestBase {
    function test_getSellAmount_fail_badToken() public {
        vm.expectRevert(abi.encodeWithSelector(IOrigamiCowSwapper.InvalidSellToken.selector, DAI));
        swapper.getSellAmount(DAI);
    }

    function test_getSellAmount_success_zeroMax_notCurrentBal() public {
        vm.startPrank(origamiMultisig);
        swapper.setOrderConfig(
            DAI,
            IOrigamiCowSwapper.OrderConfig({
                maxSellAmount: DAI_SELL_AMOUNT,
                buyToken: IERC20(USDC),
                minBuyAmount: 1,
                limitPriceOracle: limitPriceOracle,
                recipient: address(swapper),
                roundDownDivisor: ROUND_DOWN_DIVISOR,
                partiallyFillable: true,
                useCurrentBalanceForSellAmount: false,
                limitPricePremiumBps: PRICE_PREMIUM_BPS,
                verifySlippageBps: VERIFY_SLIPPAGE_BPS,
                expiryPeriodSecs: EXPIRY_PERIOD_SECS,
                appData: APP_DATA
            })
        );

        deal(DAI, address(swapper), 0);
        assertEq(swapper.getSellAmount(DAI), DAI_SELL_AMOUNT);

        deal(DAI, address(swapper), 123e18);
        assertEq(swapper.getSellAmount(DAI), DAI_SELL_AMOUNT);
    }

    function test_getSellAmount_success_zeroMax_withCurrentBal() public {
        vm.startPrank(origamiMultisig);
        swapper.setOrderConfig(
            DAI,
            IOrigamiCowSwapper.OrderConfig({
                maxSellAmount: DAI_SELL_AMOUNT,
                buyToken: IERC20(USDC),
                minBuyAmount: 1,
                limitPriceOracle: limitPriceOracle,
                recipient: address(swapper),
                roundDownDivisor: ROUND_DOWN_DIVISOR,
                partiallyFillable: true,
                useCurrentBalanceForSellAmount: true,
                limitPricePremiumBps: PRICE_PREMIUM_BPS,
                verifySlippageBps: VERIFY_SLIPPAGE_BPS,
                expiryPeriodSecs: EXPIRY_PERIOD_SECS,
                appData: APP_DATA
            })
        );

        deal(DAI, address(swapper), 0);
        assertEq(swapper.getSellAmount(DAI), 0);

        deal(DAI, address(swapper), 123e18);
        assertEq(swapper.getSellAmount(DAI), 123e18);
    }

    function test_getSellAmount_success_fixed() public {
        vm.startPrank(origamiMultisig);
        swapper.setOrderConfig(
            DAI,
            IOrigamiCowSwapper.OrderConfig({
                maxSellAmount: 999e18,
                buyToken: IERC20(USDC),
                minBuyAmount: 1,
                limitPriceOracle: limitPriceOracle,
                recipient: address(swapper),
                roundDownDivisor: ROUND_DOWN_DIVISOR,
                partiallyFillable: true,
                useCurrentBalanceForSellAmount: false,
                limitPricePremiumBps: PRICE_PREMIUM_BPS,
                verifySlippageBps: VERIFY_SLIPPAGE_BPS,
                expiryPeriodSecs: EXPIRY_PERIOD_SECS,
                appData: APP_DATA
            })
        );

        deal(DAI, address(swapper), 0);
        assertEq(swapper.getSellAmount(DAI), 999e18);

        deal(DAI, address(swapper), 123e18);
        assertEq(swapper.getSellAmount(DAI), 999e18);
    }

    function test_getBuyAmount_fail_badToken() public {
        vm.expectRevert(abi.encodeWithSelector(IOrigamiCowSwapper.InvalidSellToken.selector, DAI));
        swapper.getBuyAmount(DAI);
    }

    function test_getBuyAmount_fail_zero() public {
        configureDai();
        vm.mockCall(
            address(limitPriceOracle),
            abi.encodeWithSelector(IOrigamiOracle.convertAmount.selector),
            abi.encode(0)
        );
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        swapper.getBuyAmount(DAI);
    }

    function test_getBuyAmount_success_nothingToRound() public {
        configureDai();
        (uint256 buyAmount, uint256 roundedBuyAmount) = swapper.getBuyAmount(DAI);
        assertEq(buyAmount, 952850000000);
        assertEq(roundedBuyAmount, 952850000000);
    }

    function test_getBuyAmount_success_somethingToRound_10() public {
        configureDai();

        // Force an odd amount to see effects of rounding
        uint256 forcedAmount = 1_012_345.678912e6;
        vm.mockCall(
            address(limitPriceOracle),
            abi.encodeWithSelector(IOrigamiOracle.convertAmount.selector),
            abi.encode(forcedAmount)
        );

        // limitPricePremiumBps are added on - this is the profit we expect to get
        (uint256 buyAmount, uint256 roundedBuyAmount) = swapper.getBuyAmount(DAI);
        assertEq(buyAmount, forcedAmount * (10_000 + PRICE_PREMIUM_BPS) / 10_000);
        assertEq(roundedBuyAmount, 1_015_380e6);
    }

    function test_getBuyAmount_success_somethingToRound_point5() public {
        vm.startPrank(origamiMultisig);
        swapper.setOrderConfig(
            DAI,
            IOrigamiCowSwapper.OrderConfig({
                maxSellAmount: DAI_SELL_AMOUNT,
                buyToken: IERC20(USDC),
                minBuyAmount: 1,
                limitPriceOracle: limitPriceOracle,
                recipient: address(swapper),
                roundDownDivisor: 0.5e6,
                partiallyFillable: true,
                useCurrentBalanceForSellAmount: false,
                limitPricePremiumBps: PRICE_PREMIUM_BPS,
                verifySlippageBps: VERIFY_SLIPPAGE_BPS,
                expiryPeriodSecs: EXPIRY_PERIOD_SECS,
                appData: APP_DATA
            })
        );

        // Force an odd amount to see effects of rounding
        uint256 forcedAmount = 1_012_345.678912e6;
        vm.mockCall(
            address(limitPriceOracle),
            abi.encodeWithSelector(IOrigamiOracle.convertAmount.selector),
            abi.encode(forcedAmount)
        );

        // Rounded down to the nearest 0.5e6
        (uint256 buyAmount, uint256 roundedBuyAmount) = swapper.getBuyAmount(DAI);
        assertEq(buyAmount, 1_015_382.715948e6);
        assertEq(roundedBuyAmount, 1_015_382.5e6);
    }

    function test_supportsInterface() public {
        assertEq(swapper.supportsInterface(type(IOrigamiCowSwapper).interfaceId), true);
        assertEq(swapper.supportsInterface(type(IConditionalOrder).interfaceId), true);
        assertEq(swapper.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(swapper.supportsInterface(type(IERC1271).interfaceId), true);
        assertEq(swapper.supportsInterface(type(IOrigamiOracle).interfaceId), false);
    }
}

contract OrigamiCowSwapperTestMarketOrdersSellToken is OrigamiCowSwapperTestBase {
    uint96 public constant USDC_BUY_AMOUNT = 5_000.789e6;
    uint96 public constant DAI_BALANCE = 6_001e18;

    function marketOrderConfig() internal view returns (IOrigamiCowSwapper.OrderConfig memory) {
        return IOrigamiCowSwapper.OrderConfig({
            maxSellAmount: DAI_SELL_AMOUNT,
            buyToken: IERC20(USDC),
            minBuyAmount: USDC_BUY_AMOUNT,
            limitPriceOracle: IOrigamiOracle(address(0)),
            recipient: address(swapper),
            roundDownDivisor: 0,
            partiallyFillable: false,
            useCurrentBalanceForSellAmount: true,
            limitPricePremiumBps: 0,
            verifySlippageBps: 100,
            expiryPeriodSecs: EXPIRY_PERIOD_SECS,
            appData: APP_DATA
        });
    }

    function configureDai() internal override {
        vm.startPrank(origamiMultisig);
        swapper.setOrderConfig(
            DAI,
            marketOrderConfig()
        );
    }

    function test_getTradeableOrderWithSignature_success_1() public {
        configureDai();
        deal(DAI, address(swapper), DAI_BALANCE);

        (GPv2Order.Data memory order, bytes memory signature) = getDefaultOrder();

        assertEq(address(order.sellToken), DAI);
        assertEq(address(order.buyToken), USDC);
        assertEq(order.receiver, address(swapper));
        assertEq(order.sellAmount, DAI_BALANCE);
        assertEq(order.buyAmount, USDC_BUY_AMOUNT);
        // Was right at 00:00
        assertEq(order.validTo, block.timestamp + 5 minutes); 
        assertEq(order.appData, APP_DATA);
        assertEq(order.feeAmount, 0);
        assertEq(order.kind, GPv2Order.KIND_SELL);
        assertEq(order.partiallyFillable, false);
        assertEq(order.sellTokenBalance, GPv2Order.BALANCE_ERC20);
        assertEq(order.buyTokenBalance, GPv2Order.BALANCE_ERC20);

        assertEq(signature, abi.encode(order));
    }
    
    // Flip the params and make sure the resulting order changes.
    function test_getTradeableOrderWithSignature_success_2() public {
        vm.startPrank(origamiMultisig);
        IOrigamiCowSwapper.OrderConfig memory config = IOrigamiCowSwapper.OrderConfig({
            maxSellAmount: DAI_SELL_AMOUNT,
            buyToken: IERC20(DAI),
            minBuyAmount: 111.456e18,
            limitPriceOracle: IOrigamiOracle(address(0)),
            recipient: alice,
            roundDownDivisor: 5e18,
            partiallyFillable: false,
            useCurrentBalanceForSellAmount: true,
            limitPricePremiumBps: 0,
            verifySlippageBps: VERIFY_SLIPPAGE_BPS,
            expiryPeriodSecs: EXPIRY_PERIOD_SECS*3/2,
            appData: bytes32("abc")
        });

        swapper.setOrderConfig(USDC, config);
        deal(USDC, address(swapper), 123e6);
        
        (
            GPv2Order.Data memory order, 
            bytes memory signature
        ) = swapper.getTradeableOrderWithSignature(
            address(swapper), 
            IConditionalOrder.ConditionalOrderParams(
                address(0),
                bytes32(0),
                abi.encode(USDC)
            ),
            "",
            new bytes32[](0)
        );

        assertEq(address(order.sellToken), USDC);
        assertEq(address(order.buyToken), DAI);
        assertEq(order.receiver, alice);
        assertEq(order.sellAmount, 123e6);
        assertEq(order.buyAmount, 110e18);
        // Was right at 00:00
        assertEq(order.validTo, block.timestamp + 450); 
        assertEq(order.appData, bytes32("abc"));
        assertEq(order.feeAmount, 0);
        assertEq(order.kind, GPv2Order.KIND_SELL);
        assertEq(order.partiallyFillable, false);
        assertEq(order.sellTokenBalance, GPv2Order.BALANCE_ERC20);
        assertEq(order.buyTokenBalance, GPv2Order.BALANCE_ERC20);

        assertEq(signature, abi.encode(order));
    }
    
    function test_isValidSignature_success_noSlippage() public {
        configureDai();
        deal(DAI, address(swapper), 123e18);

        (
            GPv2Order.Data memory order,
            bytes memory signature
        ) = swapper.getTradeableOrderWithSignature(
            address(swapper), 
            defaultConditionalOrderParams(),
            "",
            new bytes32[](0)
        );

        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());
        assertEq(swapper.isValidSignature(hash, signature), swapper.isValidSignature.selector);
    }
    
    function test_isValidSignature_success_lower() public {
        // First configure and get the order/sig
        configureDai();
        deal(DAI, address(swapper), 123e18);

        (GPv2Order.Data memory order, bytes memory signature) = getDefaultOrder();
        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());

        assertEq(order.buyAmount, USDC_BUY_AMOUNT);

        // Update so the new min buy amount is LOWER
        swapper.updateAmountsAndPremiumBps(DAI, DAI_SELL_AMOUNT, USDC_BUY_AMOUNT*0.8e6/1e6, 0);

        assertEq(swapper.isValidSignature(hash, signature), swapper.isValidSignature.selector);
    }

    function test_isValidSignature_success_higherWithinSlippage() public {
        // First configure and get the order/sig
        configureDai();
        deal(DAI, address(swapper), 123e18);

        (GPv2Order.Data memory order, bytes memory signature) = getDefaultOrder();
        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());
        assertEq(order.buyAmount, USDC_BUY_AMOUNT);

        // Update so the new min buy amount is a little higher
        swapper.updateAmountsAndPremiumBps(DAI, DAI_SELL_AMOUNT, USDC_BUY_AMOUNT*1.009e6/1e6, 0);

        assertEq(swapper.isValidSignature(hash, signature), swapper.isValidSignature.selector);
    }

    function test_isValidSignature_success_higherAtSlippage() public {
        // First configure and get the order/sig
        configureDai();
        deal(DAI, address(swapper), 123e18);

        (GPv2Order.Data memory order, bytes memory signature) = getDefaultOrder();
        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());
        assertEq(order.buyAmount, USDC_BUY_AMOUNT);

        // Update so the new min buy amount is a little higher
        swapper.updateAmountsAndPremiumBps(DAI, DAI_SELL_AMOUNT, USDC_BUY_AMOUNT*1.01e6/1e6, 0);

        assertEq(swapper.isValidSignature(hash, signature), swapper.isValidSignature.selector);
    }

    function test_isValidSignature_fail_slippage() public {
        // First configure and get the order/sig
        configureDai();
        deal(DAI, address(swapper), 123e18);

        (GPv2Order.Data memory order, bytes memory signature) = getDefaultOrder();
        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());

        assertEq(order.buyAmount, USDC_BUY_AMOUNT);

        // Update so the new min buy amount is a LOT higher
        swapper.updateAmountsAndPremiumBps(DAI, DAI_SELL_AMOUNT, USDC_BUY_AMOUNT*1.0101e6/1e6, 0);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, 5_050.796890e6, 5_051.296968e6));
        swapper.isValidSignature(hash, signature);
    }
    
    function test_isValidSignature_fail_recipient() public {
        configureDai();
        deal(DAI, address(swapper), 123e18);

        (
            GPv2Order.Data memory order,
            bytes memory signature
        ) = swapper.getTradeableOrderWithSignature(
            address(swapper), 
            defaultConditionalOrderParams(),
            "",
            new bytes32[](0)
        );
        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());

        // Update the config to a different recipient
        IOrigamiCowSwapper.OrderConfig memory config = marketOrderConfig();
        config.recipient = alice;
        swapper.setOrderConfig(DAI, config);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiCowSwapper.OrderDoesNotMatchTradeableOrder.selector));
        swapper.isValidSignature(hash, signature);
    }
    
    function test_isValidSignature_fail_upatedField() public {
        configureDai();
        deal(DAI, address(swapper), 123e18);

        (
            GPv2Order.Data memory order,
            bytes memory signature
        ) = swapper.getTradeableOrderWithSignature(
            address(swapper), 
            defaultConditionalOrderParams(),
            "",
            new bytes32[](0)
        );
        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());

        // Update to be partially fillable
        IOrigamiCowSwapper.OrderConfig memory config = marketOrderConfig();
        config.partiallyFillable = true;
        swapper.setOrderConfig(DAI, config);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiCowSwapper.OrderDoesNotMatchTradeableOrder.selector));
        swapper.isValidSignature(hash, signature);
    }

    function test_isValidSignature_fail_forgedSignature() public {
        configureDai();
        deal(DAI, address(swapper), 123e18);

        (
            GPv2Order.Data memory order,
            // bytes memory signature
        ) = swapper.getTradeableOrderWithSignature(
            address(swapper), 
            defaultConditionalOrderParams(),
            "",
            new bytes32[](0)
        );
        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());

        // Keep the order but hand craft a signature with a bogus buyAmount
        order.receiver = alice;
        bytes memory forgedSignature = abi.encode(order);       
        vm.expectRevert(abi.encodeWithSelector(IOrigamiCowSwapper.OrderDoesNotMatchTradeableOrder.selector));
        swapper.isValidSignature(hash, forgedSignature);
    }

    function test_isValidSignature_success_largerSellAmount() public {
        // First configure and get the order/sig
        configureDai();
        deal(DAI, address(swapper), 123e18);

        (GPv2Order.Data memory order, bytes memory signature) = getDefaultOrder();
        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());

        deal(DAI, address(swapper), 123e18 + 1e18);

        assertEq(swapper.isValidSignature(hash, signature), swapper.isValidSignature.selector);
    }

    function test_isValidSignature_success_smallerSellAmount() public {
        // First configure and get the order/sig
        configureDai();
        deal(DAI, address(swapper), 123e18);

        (GPv2Order.Data memory order, bytes memory signature) = getDefaultOrder();
        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());

        deal(DAI, address(swapper), 123e18 - 1e18);

        assertEq(swapper.isValidSignature(hash, signature), swapper.isValidSignature.selector);
    }
}

/// @dev Specified where it's an exact sell amount with a min USDC buy amount
contract OrigamiCowSwapperTestMarketOrdersBuyToken is OrigamiCowSwapperTestBase {
    uint96 public constant USDC_BUY_AMOUNT = 9_500e6;
    uint96 public constant EXACT_DAI_SELL_AMOUNT = 10_000e18;

    function marketOrderConfig() internal view returns (IOrigamiCowSwapper.OrderConfig memory) {
        return IOrigamiCowSwapper.OrderConfig({
            maxSellAmount: EXACT_DAI_SELL_AMOUNT,
            buyToken: IERC20(USDC),
            minBuyAmount: USDC_BUY_AMOUNT,
            limitPriceOracle: IOrigamiOracle(address(0)),
            recipient: address(swapper),
            roundDownDivisor: 0,
            partiallyFillable: false,
            useCurrentBalanceForSellAmount: false,
            limitPricePremiumBps: 0,
            verifySlippageBps: 0,
            expiryPeriodSecs: EXPIRY_PERIOD_SECS,
            appData: APP_DATA
        });
    }

    function configureDai() internal override {
        vm.startPrank(origamiMultisig);
        swapper.setOrderConfig(
            DAI,
            marketOrderConfig()
        );
    }

    function test_getTradeableOrderWithSignature_success_1() public {
        configureDai();

        (GPv2Order.Data memory order, bytes memory signature) = getDefaultOrder();

        assertEq(address(order.sellToken), DAI);
        assertEq(address(order.buyToken), USDC);
        assertEq(order.receiver, address(swapper));
        assertEq(order.sellAmount, EXACT_DAI_SELL_AMOUNT);
        assertEq(order.buyAmount, USDC_BUY_AMOUNT);
        // Was right at 00:00
        assertEq(order.validTo, block.timestamp + 5 minutes); 
        assertEq(order.appData, APP_DATA);
        assertEq(order.feeAmount, 0);
        assertEq(order.kind, GPv2Order.KIND_SELL);
        assertEq(order.partiallyFillable, false);
        assertEq(order.sellTokenBalance, GPv2Order.BALANCE_ERC20);
        assertEq(order.buyTokenBalance, GPv2Order.BALANCE_ERC20);

        assertEq(signature, abi.encode(order));
    }
    
    // Flip the params and make sure the resulting order changes.
    function test_getTradeableOrderWithSignature_success_2() public {
        vm.startPrank(origamiMultisig);
        IOrigamiCowSwapper.OrderConfig memory config = IOrigamiCowSwapper.OrderConfig({
            maxSellAmount: DAI_SELL_AMOUNT,
            buyToken: IERC20(DAI),
            minBuyAmount: 111.456e18,
            limitPriceOracle: IOrigamiOracle(address(0)),
            recipient: alice,
            roundDownDivisor: 5e18,
            partiallyFillable: false,
            useCurrentBalanceForSellAmount: true,
            limitPricePremiumBps: 0,
            verifySlippageBps: VERIFY_SLIPPAGE_BPS,
            expiryPeriodSecs: EXPIRY_PERIOD_SECS*3/2,
            appData: bytes32("abc")
        });

        swapper.setOrderConfig(USDC, config);
        deal(USDC, address(swapper), 123e6);
        
        (
            GPv2Order.Data memory order, 
            bytes memory signature
        ) = swapper.getTradeableOrderWithSignature(
            address(swapper), 
            IConditionalOrder.ConditionalOrderParams(
                address(0),
                bytes32(0),
                abi.encode(USDC)
            ),
            "",
            new bytes32[](0)
        );

        assertEq(address(order.sellToken), USDC);
        assertEq(address(order.buyToken), DAI);
        assertEq(order.receiver, alice);
        assertEq(order.sellAmount, 123e6);
        assertEq(order.buyAmount, 110e18);
        // Was right at 00:00
        assertEq(order.validTo, block.timestamp + 450); 
        assertEq(order.appData, bytes32("abc"));
        assertEq(order.feeAmount, 0);
        assertEq(order.kind, GPv2Order.KIND_SELL);
        assertEq(order.partiallyFillable, false);
        assertEq(order.sellTokenBalance, GPv2Order.BALANCE_ERC20);
        assertEq(order.buyTokenBalance, GPv2Order.BALANCE_ERC20);

        assertEq(signature, abi.encode(order));
    }
    
    function test_getTradeableOrderWithSignature_orderExpiries() public {
        configureDai();

        (GPv2Order.Data memory order,) = getDefaultOrder();
        // Was right at 00:00
        assertEq(block.timestamp, 1704027600);
        assertEq(order.validTo, 1704027900);

        // Still just in the same expiry window
        skip(299);
        (order,) = getDefaultOrder();
        assertEq(block.timestamp, 1704027600 + 299);
        assertEq(order.validTo, 1704027900);

        // Moves into the next window
        skip(1);
        (order,) = getDefaultOrder();
        assertEq(block.timestamp, 1704027600 + 300);
        assertEq(order.validTo, 1704028200);

        // Still in that same next window
        skip(180);
        (order,) = getDefaultOrder();
        assertEq(block.timestamp, 1704027600 + 300 + 180);
        assertEq(order.validTo, 1704028200);
    }

    function test_isValidSignature_success_noSlippage() public {
        configureDai();

        (
            GPv2Order.Data memory order,
            bytes memory signature
        ) = swapper.getTradeableOrderWithSignature(
            address(swapper), 
            defaultConditionalOrderParams(),
            "",
            new bytes32[](0)
        );

        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());
        assertEq(swapper.isValidSignature(hash, signature), swapper.isValidSignature.selector);
    }
    
    function test_isValidSignature_success_lower() public {
        // First configure and get the order/sig
        configureDai();

        (GPv2Order.Data memory order, bytes memory signature) = getDefaultOrder();
        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());

        assertEq(order.buyAmount, USDC_BUY_AMOUNT);

        // Update so the new min buy amount is LOWER
        swapper.updateAmountsAndPremiumBps(DAI, DAI_SELL_AMOUNT, USDC_BUY_AMOUNT*0.8e6/1e6, 0);

        assertEq(swapper.isValidSignature(hash, signature), swapper.isValidSignature.selector);
    }

    function test_isValidSignature_fail_slippage() public {
        // First configure and get the order/sig
        configureDai();

        (GPv2Order.Data memory order, bytes memory signature) = getDefaultOrder();
        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());

        assertEq(order.buyAmount, USDC_BUY_AMOUNT);

        // Update so the new min buy amount is a LOT higher
        swapper.updateAmountsAndPremiumBps(DAI, DAI_SELL_AMOUNT, USDC_BUY_AMOUNT*1.0101e6/1e6, 0);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, 9_500e6, 9_595.95e6));
        swapper.isValidSignature(hash, signature);
    }
    
    function test_isValidSignature_fail_recipient() public {
        configureDai();

        (
            GPv2Order.Data memory order,
            bytes memory signature
        ) = swapper.getTradeableOrderWithSignature(
            address(swapper), 
            defaultConditionalOrderParams(),
            "",
            new bytes32[](0)
        );
        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());

        // Update the config to a different recipient
        IOrigamiCowSwapper.OrderConfig memory config = marketOrderConfig();
        config.recipient = alice;
        swapper.setOrderConfig(DAI, config);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiCowSwapper.OrderDoesNotMatchTradeableOrder.selector));
        swapper.isValidSignature(hash, signature);
    }
    
    function test_isValidSignature_fail_upatedField() public {
        configureDai();

        (
            GPv2Order.Data memory order,
            bytes memory signature
        ) = swapper.getTradeableOrderWithSignature(
            address(swapper), 
            defaultConditionalOrderParams(),
            "",
            new bytes32[](0)
        );
        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());

        // Update to be partially fillable
        IOrigamiCowSwapper.OrderConfig memory config = marketOrderConfig();
        config.partiallyFillable = true;
        swapper.setOrderConfig(DAI, config);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiCowSwapper.OrderDoesNotMatchTradeableOrder.selector));
        swapper.isValidSignature(hash, signature);
    }

    function test_isValidSignature_fail_forgedSignature() public {
        configureDai();

        (
            GPv2Order.Data memory order,
            // bytes memory signature
        ) = swapper.getTradeableOrderWithSignature(
            address(swapper), 
            defaultConditionalOrderParams(),
            "",
            new bytes32[](0)
        );
        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());

        // Keep the order but hand craft a signature with a bogus buyAmount
        order.receiver = alice;
        bytes memory forgedSignature = abi.encode(order);       
        vm.expectRevert(abi.encodeWithSelector(IOrigamiCowSwapper.OrderDoesNotMatchTradeableOrder.selector));
        swapper.isValidSignature(hash, forgedSignature);
    }

    function test_isValidSignature_success_largerSellAmount() public {
        // First configure and get the order/sig
        configureDai();

        (GPv2Order.Data memory order, bytes memory signature) = getDefaultOrder();
        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());

        assertEq(swapper.isValidSignature(hash, signature), swapper.isValidSignature.selector);
    }

    function test_isValidSignature_success_smallerSellAmount() public {
        // First configure and get the order/sig
        configureDai();

        (GPv2Order.Data memory order, bytes memory signature) = getDefaultOrder();
        bytes32 hash = GPv2Order.hash(order, cowSwapSettlement.domainSeparator());

        assertEq(swapper.isValidSignature(hash, signature), swapper.isValidSignature.selector);
    }
}