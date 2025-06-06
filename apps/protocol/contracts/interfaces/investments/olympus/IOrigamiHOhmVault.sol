pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/olympus/IOrigamiHOhmVault.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IOrigamiTokenizedBalanceSheetVault } from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";
import { ITokenPrices } from "contracts/interfaces/common/ITokenPrices.sol";

interface IOrigamiHOhmVault is IOrigamiTokenizedBalanceSheetVault {
    event DebtTokenSet(address indexed debtToken);

    /**
     * @notice Set the helper to calculate current off-chain/subgraph integration
     */
    function setTokenPrices(address tokenPrices) external;

    /**
     * @notice Set the Origami delegated manager 
     */
    function setManager(address manager) external;

    /**
     * @notice Change gOHM voting power delegation for the msg.sender
     *  - An account can delegate their (proportionally owned) gOHM balance to one address.
     *  - If `to` is address(0), then this undelegates the entire balance.
     *  - An account's 'proportionally owned' gOHM balance is the total vault gOHM collateral scaled
     *    by the number of shares they own proportional to the total supply.
     *  - If account exits or transfers their vault shares to another address (and they have an 
     *    existing delegation), that proportional amount of gOHM is automatically removed 
     *    from their delegated balance.
     *  - If account joins or vault shares are transferred into their address (and they have an 
     *    existing delegation), then that new proportional amount of gOHM is automatically 
     *    delegated to the same address.
     */
    function delegateVotingPower(address to) external;

    /**
     * @notice Sync the delegation amount for any account based on
     * their proportional gOHM balance, and to that account's existing delegate
     * nomination.
     * @dev Provided in case gOHM balances of the vault increase.
     */
    function syncDelegation(address account) external;

    /**
     * @dev Receives and executes a batch of function calls on this contract.
     */
    function multicall(bytes[] calldata data) external returns (bytes[] memory results);

    /**
     * @notice The Olympus Governance token (gOHM)
     */
    function collateralToken() external view returns (IERC20);

    /**
     * @notice The cooler debt token
     */
    function debtToken() external view returns (IERC20);

    /**
     * @notice The helper contract to retrieve Origami USD prices
     * @dev Required for off-chain/subgraph integration
     */
    function tokenPrices() external view returns (ITokenPrices);

    /**
     * @notice The Origami contract managing the application of
     * the deposit tokens into the underlying protocol
     */
    function manager() external view returns (address);
    
    /**
     * @notice Given an account, calculate the proportional amount of gOHM collateral
     * that account is eligable to delegate, and their current delegate and delegated amount
     */
    function accountDelegationBalances(address account) external view returns (
        uint256 totalCollateral,
        address delegateAddress,
        uint256 delegatedCollateral
    );
}
