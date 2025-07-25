pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/sky/ISkyLockstakeEngine.sol)

interface ISkyLockstakeEngine {
    enum FarmStatus { UNSUPPORTED, ACTIVE, DELETED }

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, address data);
    event AddFarm(address farm);
    event DelFarm(address farm);
    event Open(address indexed owner, uint256 indexed index, address urn);
    event Hope(address indexed owner, uint256 indexed index, address indexed usr);
    event Nope(address indexed owner, uint256 indexed index, address indexed usr);
    event SelectVoteDelegate(address indexed owner, uint256 indexed index, address indexed voteDelegate);
    event SelectFarm(address indexed owner, uint256 indexed index, address indexed farm, uint16 ref);
    event Lock(address indexed owner, uint256 indexed index, uint256 wad, uint16 ref);
    event Free(address indexed owner, uint256 indexed index, address to, uint256 wad, uint256 freed);
    event FreeNoFee(address indexed owner, uint256 indexed index, address to, uint256 wad);
    event Draw(address indexed owner, uint256 indexed index, address to, uint256 wad);
    event Wipe(address indexed owner, uint256 indexed index, uint256 wad);
    event GetReward(address indexed owner, uint256 indexed index, address indexed farm, address to, uint256 amt);
    event OnKick(address indexed urn, uint256 wad);
    event OnTake(address indexed urn, address indexed who, uint256 wad);
    event OnRemove(address indexed urn, uint256 sold, uint256 burn, uint256 refund);

    // --- Constants ---
    function WAD() external pure returns (uint256);
    function RAY() external pure returns (uint256);

    // --- Immutable Getters ---
    function voteDelegateFactory() external view returns (address);
    function vat() external view returns (address);
    function usdsJoin() external view returns (address);
    function usds() external view returns (address);
    function ilk() external view returns (bytes32);
    function sky() external view returns (address);
    function lssky() external view returns (address);
    function urnImplementation() external view returns (address);
    function fee() external view returns (uint256);

    // --- Storage Getters ---
    function wards(address usr) external view returns (uint256 allowed);
    function farms(address farm) external view returns (FarmStatus);
    function ownerUrnsCount(address owner) external view returns (uint256 count);
    function ownerUrns(address owner, uint256 index) external view returns (address urn);
    function urnOwners(address urn) external view returns (address owner);
    function urnCan(address urn, address usr) external view returns (uint256 allowed);
    function urnVoteDelegates(address urn) external view returns (address voteDelegate);
    function urnFarms(address urn) external view returns (address farm);
    function urnAuctions(address urn) external view returns (uint256 auctionsCount);
    function jug() external view returns (address);

    // --- Admin ---
    function rely(address usr) external;
    function deny(address usr) external;
    function file(bytes32 what, address data) external;
    function addFarm(address farm) external;
    function delFarm(address farm) external;

    // --- Getters ---
    function isUrnAuth(address owner, uint256 index, address usr) external view returns (bool ok);

    // --- Urn Management ---
    function open(uint256 index) external returns (address urn);
    function hope(address owner, uint256 index, address usr) external;
    function nope(address owner, uint256 index, address usr) external;

    // --- Delegation / Staking ---
    function selectVoteDelegate(address owner, uint256 index, address voteDelegate) external;
    function selectFarm(address owner, uint256 index, address farm, uint16 ref) external;

    // --- Collateral ---
    function lock(address owner, uint256 index, uint256 wad, uint16 ref) external;
    function free(address owner, uint256 index, address to, uint256 wad) external returns (uint256 freed);
    function freeNoFee(address owner, uint256 index, address to, uint256 wad) external;

    // --- Loan ---
    function draw(address owner, uint256 index, address to, uint256 wad) external;
    function wipe(address owner, uint256 index, uint256 wad) external;
    function wipeAll(address owner, uint256 index) external returns (uint256 wad);

    // --- Rewards ---
    function getReward(address owner, uint256 index, address farm, address to) external returns (uint256 amt);

    // --- Liquidation ---
    function onKick(address urn, uint256 wad) external;
    function onTake(address urn, address who, uint256 wad) external;
    function onRemove(address urn, uint256 sold, uint256 left) external;
}
