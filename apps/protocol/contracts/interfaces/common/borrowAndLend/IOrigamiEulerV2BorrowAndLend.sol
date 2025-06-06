pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/borrowAndLend/IOrigamiEulerV2BorrowAndLend.sol)

import { IOrigamiBorrowAndLendWithLeverage } from "contracts/interfaces/common/borrowAndLend/IOrigamiBorrowAndLendWithLeverage.sol";
import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";

import { IEVC } from "contracts/interfaces/external/ethereum-vault-connector/IEthereumVaultConnector.sol";
import { IEVKEVault as IEVault } from "contracts/interfaces/external/euler/IEVKEVault.sol";

/**
 * @notice An Origami abstraction over a borrow/lend money market for
 * a single `supplyToken` and a single `borrowToken`.
 * This is an EulerV2 specific interface
 */
interface IOrigamiEulerV2BorrowAndLend is IOrigamiBorrowAndLendWithLeverage {
    event SwapperSet(address indexed swapper);

    error MaxBorrowNotSupported();

    /**
     * @notice Set the swapper responsible for `borrowToken` <--> `supplyToken` swaps
     */
    function setSwapper(address _swapper) external;

    /**
     * @notice Toggles whitelisting an operator to claim rewards, for a given Merkl distributor
     */
    function merklToggleOperator(address distributor, address operator) external;

    /**
     * @notice Sets an address to receive Merkl rewards on behalf of this contract
     */
    function merklSetClaimRecipient(address distributor, address recipient, address token) external;

    /**
     * @notice The swapper for `borrowToken` <--> `supplyToken`
     */
    function swapper() external view returns (IOrigamiSwapper);

    /**
     * @notice Euler's (Ethereum Vault Connector)
     */
    function eulerEVC() external view returns (IEVC);

    /**
     * @notice The Euler EVault where `supplyToken` is deposited as collateral
     */
    function supplyVault() external view returns (IEVault);

    /**
     * @notice The Euler EVault where `borrowToken` is borrowed from
     */
    function borrowVault() external view returns (IEVault);

    /**
     * @notice Returns the curent Euler position data
     * @dev
     *   - The collateralValueInUnitOfAcct will not correspond to the IEVault.accountLiquidity() output,
     *     as Euler's is "risk-adjusted" by the liquidationLtv.
     *
     *     For instance, if an account deposits 10k worth of collateral on a vault with
     *     LiquidationLTV of 95%, the risk-adjusted collateral value would be 9.5k.
     *
     *     However, this Origami function will return the actual value of the collateral
     *     in the unit of acccount of the Euler vault, 10k.
     *     The currentLtv and healthFactor follow Aave's standards.
     *
     *   - currentLtv = (borrowed / supplied) scaled by 1e4, where `supplied` is NOT risk-adjusted.
     *     Example, if an account deposits 10k worth of collateral and borrows 8k, the currentLtv would be 80%.
     *
     *   - healthFactor = liquidationLtv / currentLtv, scaled by 1e18.
     */
    function debtAccountData()
        external
        view
        returns (
            uint256 supplied,
            uint256 borrowed,
            uint256 collateralValueInUnitOfAcct,
            uint256 liabilityValueInUnitOfAcct,
            uint256 currentLtv,
            uint256 liquidationLtv,
            uint256 healthFactor
        );
}
