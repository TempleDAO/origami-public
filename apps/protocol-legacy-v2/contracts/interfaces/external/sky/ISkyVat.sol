pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/sky/ISkyVat.sol)

interface ISkyVat {
    // Art == Total Normalised Debt      [wad]
    // rate == Accumulated Rates         [ray]
    // spot == Price with Safety Margin  [ray]
    // line == Debt Ceiling              [rad]
    // dust == Urn Debt Floor            [rad]
    function ilks(bytes32 ilk) external view returns (uint256 Art, uint256 rate, uint256 spot, uint256 line, uint256 dust);

    // ink == Locked Collateral  [wad]
    // art == Normalised Debt    [wad]
    function urns(bytes32 ilk, address urn) external view returns (uint256 ink, uint256 art);

    function hope(address usr) external;
    function slip(bytes32 ilk, address usr, int256 wad) external;
    function frob(bytes32 i, address u, address v, address w, int256 dink, int256 dart) external;
    function grab(bytes32 i, address u, address v, address w, int256 dink, int256 dart) external;
}
