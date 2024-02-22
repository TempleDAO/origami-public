// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface GMX_IChainlinkFlags {
  function getFlag(address) external view returns (bool);
}
