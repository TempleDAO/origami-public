pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/opal/IOpalAdapterFactory.sol)

interface IOpalAdapterFactory {
    error AlreadyRegistered();
    error NotRegistered();

    event ImplementationAdded(address indexed implementation, bytes32 indexed implTypeAndVersion);

    event ImplementationRemoved(address indexed implementation);

    event AdapterAdded(
        address newAdapter,
        address indexed implementation,
        bytes32 indexed implTypeAndVersion,
        address indexed manager,
        bytes32 description
    );

    struct ImplementationDetail {
        address implementation;
        string implTypeAndVersion;
    }

    /// @notice Elevated access can register a new implementation
    function addImplementation(address implementation) external;

    /// @notice Elevated access can remove an existing implementation
    function removeImplementation(address implementation) external;

    /**
     * @notice Clone a registered implementation to create a new instance of an adapter
     * @dev Permisionless to clone an existing implementation
     * @param implementation The pre-registered implementation to clone
     * @param manager A designated manager (typically only this is allowed to inititialize
     *        after cloning), added to the immutable args of the clone.
     *        The manager is set as the `bundler` for access rights in the bundler framework.
     * @param description A small string (as bytes32) description for this clone.
     *        format is left to the caller to decide, but for consistency could (but not
     *        enforced) be structured like:
     *        "[ASSET1.symbol, ASSET2.symbol] / [DEBT1.symbol, DEBT2.symbol]"
     * @param immutableArgsData abi encoded representation of immutable args. Typically this
     *        is packed, and the implementation reads from the relevant runtime slot
     *        The immutable args are packed along with the `manager` (at slot 0x00) and
     *        `description` (slot 0x14). Meaning `immutableArgsData` starts from slot 0x34
     */
    function create(address implementation, address manager, bytes32 description, bytes calldata immutableArgsData)
        external
        returns (address);

    /// @notice Check if a given implemenation is registered
    function isRegistered(address implementation) external view returns (bool);

    /// @notice The number of registered implementations
    function numImplementations() external view returns (uint256);

    /**
     * @notice Paginated view of the implementations and their type/version string
     * @dev This can be called sequentially, increasing the `startIndex` each time by the number of items
     * returned in the previous call, until number of items returned is less than `maxItems`
     * Note if an implementation is removed then the order of the items may change.
     */
    function implementationDetailList(uint256 startIndex, uint256 maxItems)
        external
        view
        returns (ImplementationDetail[] memory items);
}
