pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/bundler/plugins/IOrigamiBundlerPluginEulerFlash.sol)

import { IEulerFlashLoan } from "contracts/interfaces/external/euler/IEulerFlashLoan.sol";
import {
    IOrigamiBundlerPluginMultiAccess
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginMultiAccess.sol";

/// @title Origami Bundler - Plugin for Euler Flashloans
interface IOrigamiBundlerPluginEulerFlash is IOrigamiBundlerPluginMultiAccess, IEulerFlashLoan {
    /****** BUNDLER PLUGIN ACTIONS ******/

    /// @notice Initiate a flashloan for a single token from an Euler Vault
    /// @dev
    ///  - Reentered plugins need to ensure the flashToken amount is in this contract after
    ///    execution such that the flash can be repaid.
    ///  - Plugins can use `flashloanTotalAmountT()` to determine the total amount.
    ///  - Euler does not add a fee to the flashloan.
    ///  - Surplus funds should not be left in this contract at the end of the transaction as they
    ///    can potentially skimmed afterwards via the bundler.
    ///  - Euler vault functions to borrow/repay/etc cannot be reentered during a flash loan. If other
    ///    nested Euler operations are required, then the EVC callThroughEVC needs to be used instead.
    /// @param vault The Euler EVault address to flashloan from
    /// @param amount The amount of the vault asset to flashloan
    /// @param callbackData The abi encoded OrigamiBundler.Call[] to execute on receipt of the funds.
    function flashLoan(address vault, uint256 amount, bytes calldata callbackData) external;

    /****** VIEWS ******/

    /// @notice The fee (basis points) per token flashloaned
    function flashloanFeeBps() external view returns (uint256);

    /****** TRANSIENT VIEWS ******/

    /// @notice Transient storage representing the flashloan amount required to be repaid
    /// @dev The requested amount plus any fees
    function flashloanTotalAmountT() external view returns (uint256);
}
