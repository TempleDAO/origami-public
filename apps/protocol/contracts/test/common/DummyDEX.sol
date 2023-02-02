pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later

import {IAggregatorV3Interface} from "../../interfaces/external/chainlink/IAggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CommonEventsAndErrors} from "../../common/CommonEventsAndErrors.sol";

contract DummyDex {
    IERC20 public gmxToken;
    IERC20 public wrappedNativeToken;
    uint256 public gmxPrice;
    uint256 public wrappedNativePrice;

    constructor(
        address _gmxToken, 
        address _wrappedNativeToken, 
        uint256 _gmxPrice, 
        uint256 _wrappedNativePrice
    ) {
        gmxToken = IERC20(_gmxToken);
        wrappedNativeToken = IERC20(_wrappedNativeToken);
        gmxPrice = _gmxPrice;
        wrappedNativePrice = _wrappedNativePrice;
    }

    function setPrices(uint256 _gmxPrice, uint256 _wrappedNativePrice) external {
        gmxPrice = _gmxPrice;
        wrappedNativePrice = _wrappedNativePrice;
    }

    function swapToGMX(uint256 _amount) external {
        gmxToken.transfer(msg.sender, _amount * wrappedNativePrice / gmxPrice);
        wrappedNativeToken.transferFrom(msg.sender, address(this), _amount);
    }

    function swapToWrappedNative(uint256 _amount) external {
        wrappedNativeToken.transfer(msg.sender, _amount * gmxPrice / wrappedNativePrice);
        gmxToken.transferFrom(msg.sender, address(this), _amount);
    }

    function revertNoMessage() external pure {
        assembly {
            revert(0,0)
        }
    }

    function revertCustom() external pure {
        revert CommonEventsAndErrors.InvalidParam();
    }
}