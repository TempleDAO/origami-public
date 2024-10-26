pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/flashLoan/OrigamiMorphoFlashLoanProvider.sol)

import { IMorpho } from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";
import { IMorphoFlashLoanCallback } from "@morpho-org/morpho-blue/src/interfaces/IMorphoCallbacks.sol";

import { IOrigamiFlashLoanProvider } from "contracts/interfaces/common/flashLoan/IOrigamiFlashLoanProvider.sol";
import { IOrigamiFlashLoanReceiver } from "contracts/interfaces/common/flashLoan/IOrigamiFlashLoanReceiver.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/**
 * @title OrigamiMorphoFlashLoanProvider
 * @notice A permisionless flashloan wrapper over Morpho
 * @dev The caller needs to implement the IOrigamiFlashLoanReceiver interface to receive the callback
 */ 
contract OrigamiMorphoFlashLoanProvider is IOrigamiFlashLoanProvider, IMorphoFlashLoanCallback {
    using SafeERC20 for IERC20;
    
    error CallbackFailure();

    /**
     * @notice The morpho singleton contract
     */
    IMorpho public immutable morpho;

    constructor(address _morphoAddress) {
        morpho = IMorpho(_morphoAddress);   
    }

    /**
     * @notice Initiate a flashloan for a single token
     * The caller must implement the `IOrigamiFlashLoanReceiver()` interface
     * and must repay the loaned tokens to this contract within that function call. 
     * The loaned amount is always repaid to Morpho within the same transaction.
     * @dev Upon FL success, Morpho will call the `onMorphoFlashLoan()` callback
     */
    function flashLoan(IERC20 token, uint256 amount, bytes calldata params) external override {
        // Encode:
        //  The msg.sender, which also doubles as the IOrigamiFlashLoanReceiver.
        //  The asset token.
        bytes memory _params = abi.encode(msg.sender, address(token), params);

        morpho.flashLoan(address(token), amount, _params);
    }

    /**
    * @notice Callback from Morpho after receiving the flash-borrowed assets
    * @dev After validation, flashLoanCallback() is called on the caller of flashLoan().
    * @param amount The amount of the flash-borrowed assets
    * @param params The byte-encoded params passed when initiating the flashloan
    */
    function onMorphoFlashLoan(uint256 amount, bytes calldata params) external {
        // Can only be called by the Morpho pool, and the FL can only ever be initiated by this contract.
        if (msg.sender != address(morpho)) revert CommonEventsAndErrors.InvalidAccess();

        (IOrigamiFlashLoanReceiver flReceiver, IERC20 token, bytes memory _params) = abi.decode(
            params, (IOrigamiFlashLoanReceiver, IERC20, bytes)
        );

        // Transfer the asset to the Origami FL receiver, and approve the repayment to Morpho in full
        token.safeTransfer(address(flReceiver), amount);
        token.forceApprove(address(morpho), amount);

        // Finally have the receiver handle the callback
        bool success = flReceiver.flashLoanCallback(token, amount, 0, _params);
        if (!success) revert CallbackFailure();
    }
}
