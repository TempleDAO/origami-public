// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface GMX_IHandlerTarget {
    function isHandler(address _account) external returns (bool);
    function setHandler(address _handler, bool _isActive) external;
}
