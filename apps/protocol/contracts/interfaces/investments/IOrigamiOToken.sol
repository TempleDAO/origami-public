pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/IOrigamiOToken.sol)

import { IMintableToken } from "contracts/interfaces/common/IMintableToken.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiOTokenManager } from "contracts/interfaces/investments/IOrigamiOTokenManager.sol";

/**
 * @title Origami oToken (no native ETH support for deposits/exits)
 * 
 * @notice Users deposit with an accepted token and are minted oTokens
 * Generally speaking this oToken will represent the underlying protocol it is wrapping, 1:1
 *
 * @dev The logic on how to handle the deposits/exits is delegated to a manager contract.
 */
interface IOrigamiOToken is IOrigamiInvestment, IMintableToken {
    event AmoMint(address indexed to, uint256 amount);
    event AmoBurn(address indexed account, uint256 amount);

    /**
     * @notice Set the Origami oToken Manager.
     */
    function setManager(address _manager) external;

    /**
     * @notice Protocol mint for AMO capabilities
     */
    function amoMint(address _to, uint256 _amount) external;

    /**
     * @notice Protocol burn for AMO capabilities
     * @dev Cannot burn more AMO tokens than were AMO minted.
     */
    function amoBurn(address _account, uint256 _amount) external;
    
    /**
     * @notice The Origami contract managing the deposits/exits and the application of
     * the deposit tokens into the underlying protocol
     */
    function manager() external view returns (IOrigamiOTokenManager);

    /**
     * @notice Protocol can mint/burn oToken's for the AMO purposes. This amount is tracked
     * in order to calculate circulating vs non-circulating supply.
     */
    function amoMinted() external view returns (uint256);

    /**
     * @notice The amount of non-AMO owned circulating supply
     */
    function circulatingSupply() external view returns (uint256);

}
