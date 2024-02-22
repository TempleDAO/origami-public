pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { RepricingToken } from "contracts/common/RepricingToken.sol";

contract DummyRepricingToken is RepricingToken {
    using SafeERC20 for IERC20;

    constructor(
        address _initialOwner,
        string memory _name,
        string memory _symbol,
        address _reserveToken,
        uint256 _reservesActualisationDuration
    ) RepricingToken(_name, _symbol, _reserveToken, _reservesActualisationDuration, _initialOwner) {}

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external {
        _burn(_from, _amount);
    }

    function issueSharesFromReserves(
        uint256 reserveTokenAmount, 
        address recipient, 
        uint256 minSharesAmount
    ) external returns (uint256 sharesAmount) {
        IERC20(reserveToken).safeTransferFrom(msg.sender, address(this), reserveTokenAmount);
        sharesAmount = _issueSharesFromReserves(reserveTokenAmount, recipient, minSharesAmount);
    }

    function redeemReservesFromShares(
        uint256 sharesAmount, 
        address recipient, 
        uint256 minReserveTokenAmount
    ) external returns (uint256 reserveTokenAmount) {
        reserveTokenAmount = _redeemReservesFromShares(sharesAmount, msg.sender, minReserveTokenAmount, recipient);
    }
}
