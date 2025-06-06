pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

interface IDaiUsds {
    function daiToUsds(address usr, uint256 wad) external;

    function usdsToDai(address usr, uint256 wad) external;
}