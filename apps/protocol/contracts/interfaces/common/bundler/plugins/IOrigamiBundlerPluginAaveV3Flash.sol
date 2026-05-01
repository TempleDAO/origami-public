pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/bundler/plugins/IOrigamiBundlerPluginAaveV3Flash.sol)

import { IFlashLoanReceiver } from "@aave/core-v3/contracts/misc/flashloan/interfaces/IFlashLoanReceiver.sol";
import {
    IOrigamiBundlerPluginMultiAccess
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginMultiAccess.sol";

/// @title Origami Bundler - Plugin for Aave V3 Flashloans
interface IOrigamiBundlerPluginAaveV3Flash is IOrigamiBundlerPluginMultiAccess, IFlashLoanReceiver {
    /****** BUNDLER PLUGIN ACTIONS ******/

    /// @notice Initiate a flashloan for a single token
    /// @dev Reentered plugins need to ensure the amount and the fee are in this contract after
    /// execution. These plugins can use `flashloanTotalAmountT()` to determine the total amount + fee
    /// @param token The token address to flashloan
    /// @param amount The amount of `token` to flashloan
    /// @param referralCode The Aave referral code. Use 0 if unknown
    /// @param callbackData The abi encoded OrigamiBundler.Call[] to execute on receipt of the funds.
    function flashLoan(address token, uint256 amount, uint16 referralCode, bytes calldata callbackData) external;

    /****** VIEWS ******/

    /// @notice The fee (basis points) per token flashloaned
    function flashloanFeeBps() external view returns (uint256);

    /****** TRANSIENT VIEWS ******/

    /// @notice Transient storage representing the flashloan amount required to be repaid
    /// @dev The requested amount plus any fees
    function flashloanTotalAmountT() external view returns (uint256);
}
