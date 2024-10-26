pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IOrigamiFlashLoanProvider } from "contracts/interfaces/common/flashLoan/IOrigamiFlashLoanProvider.sol";
import { IOrigamiFlashLoanReceiver } from "contracts/interfaces/common/flashLoan/IOrigamiFlashLoanReceiver.sol";
import { OrigamiMorphoFlashLoanProvider } from "contracts/common/flashLoan/OrigamiMorphoFlashLoanProvider.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

contract MockClient is IOrigamiFlashLoanProvider, IOrigamiFlashLoanReceiver {
    using SafeERC20 for IERC20;

    OrigamiMorphoFlashLoanProvider public flProvider;
    uint256 public transientBalance;
    bytes public transientParams;

    constructor(OrigamiMorphoFlashLoanProvider _flProvider) {
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
    constructor(OrigamiMorphoFlashLoanProvider _flProvider) MockClient(_flProvider) {}
    
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

contract OrigamiMorphoFlashLoanProviderTestBase is OrigamiTest {
    OrigamiMorphoFlashLoanProvider public flProvider;
    IERC20 public wethToken;
    MockClient public mockClient;

    address public constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address public constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function setUp() public virtual {
        fork("mainnet", 19238000);
        vm.warp(1708056616);
        flProvider = new OrigamiMorphoFlashLoanProvider(MORPHO);
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

        vm.expectRevert(abi.encodeWithSelector(OrigamiMorphoFlashLoanProvider.CallbackFailure.selector));
        mockClient.flashLoan(
            wethToken,
            50e18,
            bytes("")
        );
    }

    function test_onMorphoFlashLoan_fail_notMorpho() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        flProvider.onMorphoFlashLoan(0, bytes(""));
    }
    
    function test_onMorphoFlashLoan_fail_notSendingEthBack() public {
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

    function test_flashloan_withParams() public {
        mockClient.flashLoan(wethToken, 5e18, bytes("abcdef"));
        assertEq(mockClient.transientBalance(), 5e18);
        assertEq(mockClient.transientParams(), bytes("abcdef"));
        assertEq(wethToken.balanceOf(address(mockClient)), 0);
        assertEq(wethToken.balanceOf(address(flProvider)), 0);
    }
}
