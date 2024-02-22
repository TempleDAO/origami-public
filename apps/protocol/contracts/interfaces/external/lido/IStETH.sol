pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (external/lido/IStETH.sol)

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IStETH is IERC20Metadata {
    /**
     * @return the amount of shares that corresponds to `_ethAmount` protocol-controlled Ether.
     */
    function getSharesByPooledEth(uint256 _ethAmount) external view returns (uint256);

    /**
     * @return the amount of Ether that corresponds to `_sharesAmount` token shares.
     */
    function getPooledEthByShares(uint256 _sharesAmount) external view returns (uint256);
}
