pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IOrigamiFlashLoanProvider } from "contracts/interfaces/common/flashLoan/IOrigamiFlashLoanProvider.sol";
import { IOrigamiFlashLoanReceiver } from "contracts/interfaces/common/flashLoan/IOrigamiFlashLoanReceiver.sol";
import { OrigamiAaveV3FlashLoanProvider } from "contracts/common/flashLoan/OrigamiAaveV3FlashLoanProvider.sol";
import { Errors as AaveErrors } from "@aave/core-v3/contracts/protocol/libraries/helpers/Errors.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

contract MockClient is IOrigamiFlashLoanProvider, IOrigamiFlashLoanReceiver {
    using SafeERC20 for IERC20;

    OrigamiAaveV3FlashLoanProvider public flProvider;
    uint256 public transientBalance;
    bytes public transientParams;

    constructor(OrigamiAaveV3FlashLoanProvider _flProvider) {
        flProvider = _flProvider;
    }

    function flashLoan(
        IERC20 token,
        uint256 amount,
        bytes memory params
    ) external {
        flProvider.flashLoan(token, amount, params);
    }

    function flashLoanCallback(
        IERC20 token,
        uint256 amount,
        uint256 fee,
        bytes calldata params
    ) external virtual override returns (bool) {
        transientBalance = token.balanceOf(address(this));
        transientParams = params;
        token.safeTransfer(address(flProvider), amount+fee);
        return true;
    }
}

contract MockClientBad is MockClient {
    constructor(OrigamiAaveV3FlashLoanProvider _flProvider) MockClient(_flProvider) {}
    
    function flashLoanCallback(
        IERC20 /*token*/,
        uint256 /*amount*/,
        uint256 /*fee*/,
        bytes calldata /*params*/
    ) external override pure returns (bool) {
        // Doesn't send the funds back to the flProvider
        return true;
    }
}

contract OrigamiAaveV3FlashLoanProviderTestBase is OrigamiTest {
    OrigamiAaveV3FlashLoanProvider public flProvider;
    IERC20 public wethToken;
    MockClient public mockClient;

    address public constant SPARK_POOL_ADDRESS_PROVIDER = 0x02C3eA4e34C0cBd694D2adFa2c690EECbC1793eE;
    address public constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function setUp() public virtual {
        fork("mainnet", 19238000);
        vm.warp(1708056616);
        flProvider = new OrigamiAaveV3FlashLoanProvider(SPARK_POOL_ADDRESS_PROVIDER);
        wethToken = IERC20(WETH_ADDRESS);
        mockClient = new MockClient(flProvider);
    }

    function test_flashloan_fail_noCallbackDefined() public {
        vm.expectRevert();
        flProvider.flashLoan(
            wethToken,
            50e18,
            bytes("")
        );
    }

    function test_flashloan_fail_returnFalse() public {
        vm.mockCall(
            address(mockClient),
            abi.encodeWithSelector(MockClient.flashLoanCallback.selector),
            abi.encode(false)
        );

        vm.expectRevert(bytes(AaveErrors.INVALID_FLASHLOAN_EXECUTOR_RETURN));
        mockClient.flashLoan(
            wethToken,
            50e18,
            bytes("")
        );
    }

    function test_executeOperation_fail_notPool() public {
        address[] memory tokens = new address[](0);
        uint256[] memory amounts = new uint256[](0);
        uint256[] memory fees = new uint256[](0);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        flProvider.executeOperation(tokens, amounts, fees, address(0), bytes(""));
    }

    function test_executeOperation_fail_badInitiator() public {
        address[] memory tokens = new address[](0);
        uint256[] memory amounts = new uint256[](0);
        uint256[] memory fees = new uint256[](0);
        vm.startPrank(address(flProvider.POOL()));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, alice));
        flProvider.executeOperation(tokens, amounts, fees, alice, bytes(""));
    }

    function test_executeOperation_fail_badLength() public {
        address[] memory tokens = new address[](0);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory fees = new uint256[](1);
        vm.startPrank(address(flProvider.POOL()));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        flProvider.executeOperation(tokens, amounts, fees, address(flProvider), bytes(""));

        tokens = new address[](1);
        amounts = new uint256[](0);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        flProvider.executeOperation(tokens, amounts, fees, address(flProvider), bytes(""));

        amounts = new uint256[](1);
        fees = new uint256[](0);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        flProvider.executeOperation(tokens, amounts, fees, address(flProvider), bytes(""));

        fees = new uint256[](1);
        vm.expectRevert(); // zero token
        flProvider.executeOperation(tokens, amounts, fees, address(flProvider), bytes(""));
    }
    
    function test_executeOperation_fail_notSendingEthBack() public {
        mockClient = new MockClientBad(flProvider);
        vm.expectRevert(); // weth error since no approval
        mockClient.flashLoan(wethToken, 5e18, bytes(""));
    }

    function test_flashloan_success() public {
        mockClient.flashLoan(wethToken, 5e18, bytes(""));
        assertEq(mockClient.transientBalance(), 5e18);
        assertEq(wethToken.balanceOf(address(mockClient)), 0);
        assertEq(wethToken.balanceOf(address(flProvider)), 0);
    }

    function test_flashloan_withFees() public {
        vm.startPrank(IPoolAddressesProvider(SPARK_POOL_ADDRESS_PROVIDER).getPoolConfigurator());
        flProvider.POOL().updateFlashloanPremiums(10 /*bps*/, 0);
        vm.stopPrank();

        vm.expectRevert(); // weth error since not enough
        mockClient.flashLoan(wethToken, 5e18, bytes(""));

        // Deal extra fees
        deal(address(wethToken), address(mockClient), 0.005e18);
        mockClient.flashLoan(wethToken, 5e18, bytes(""));
        assertEq(mockClient.transientBalance(), 5.005e18);
        assertEq(mockClient.transientParams(), bytes(""));
        assertEq(wethToken.balanceOf(address(mockClient)), 0);
        assertEq(wethToken.balanceOf(address(flProvider)), 0);
    }

    function test_flashloan_withParams() public {
        mockClient.flashLoan(wethToken, 5e18, bytes("abcdef"));
        assertEq(mockClient.transientBalance(), 5e18);
        assertEq(mockClient.transientParams(), bytes("abcdef"));
        assertEq(wethToken.balanceOf(address(mockClient)), 0);
        assertEq(wethToken.balanceOf(address(flProvider)), 0);
    }

}