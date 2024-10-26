pragma solidity >=0.8.0 <0.9.0;
// SPDX-License-Identifier: MIT

interface ICowSettlement {
    function domainSeparator() external view returns (bytes32);
}
