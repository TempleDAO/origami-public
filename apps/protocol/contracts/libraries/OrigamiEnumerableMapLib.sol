pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (libraries/OrigamiEnumerableMapLib.sol)

import { EnumerableSetLib as SoladyEnumerableSetLib } from "solady/utils/EnumerableSetLib.sol";
import { AdapterDetails } from "contracts/investments/opal/OpalManager.sol";

library OrigamiEnumerableMapLib {
    using SoladyEnumerableSetLib for SoladyEnumerableSetLib.AddressSet;
    using SoladyEnumerableSetLib for SoladyEnumerableSetLib.Bytes32Set;

    error EnumerableMapKeyNotFound();

    /// @dev An enumerable map of `address` to `AdapterDetails`.
    struct AddressToAdapterDetailsMap {
        SoladyEnumerableSetLib.AddressSet _keys;
        mapping(address => AdapterDetails) _values;
    }

    struct Bytes32ToAddressSetMap {
        SoladyEnumerableSetLib.Bytes32Set _keys;
        mapping(bytes32 => SoladyEnumerableSetLib.AddressSet) _values;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     GETTERS / SETTERS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Adds a new default key to the map (or returns the existing reference) and returns the storage reference to
    /// that value. Returns true if `key` was added to the map, that is if it was not already present.
    /// Reverts if the map grows bigger than the custom on-the-fly capacity `cap`.
    function add(AddressToAdapterDetailsMap storage map, address key, uint256 cap)
        internal
        returns (bool wasAdded, AdapterDetails storage value)
    {
        value = map._values[key];
        wasAdded = map._keys.add(key, cap);
    }

    /// @dev Removes a key-value pair from the map.
    /// Returns true if `key` was removed from the map, that is if it was present.
    function remove(AddressToAdapterDetailsMap storage map, address key) internal returns (bool) {
        delete map._values[key];
        return map._keys.remove(key);
    }

    /// @dev Returns true if the key is in the map.
    function contains(AddressToAdapterDetailsMap storage map, address key) internal view returns (bool) {
        return map._keys.contains(key);
    }

    /// @dev Returns the number of key-value pairs in the map.
    function length(AddressToAdapterDetailsMap storage map) internal view returns (uint256) {
        return map._keys.length();
    }

    /// @dev Returns the key-value pair at index `i`. Reverts if `i` is out-of-bounds.
    function keyValueAt(AddressToAdapterDetailsMap storage map, uint256 i)
        internal
        view
        returns (address key, AdapterDetails storage value)
    {
        value = map._values[key = map._keys.at(i)];
    }

    /// @dev Tries to return the value associated with the key.
    function tryGet(AddressToAdapterDetailsMap storage map, address key)
        internal
        view
        returns (bool exists, AdapterDetails storage value)
    {
        exists = contains(map, key);
        value = map._values[key];
    }

    /// @dev Returns the value for the key. Reverts if the key is not found.
    function get(AddressToAdapterDetailsMap storage map, address key)
        internal
        view
        returns (AdapterDetails storage value)
    {
        if (contains(map, key)) return map._values[key];
        _revertNotFound();
    }

    /// @dev Returns the keys. May run out-of-gas if the map is too big.
    function keys(AddressToAdapterDetailsMap storage map) internal view returns (address[] memory) {
        return map._keys.values();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     GETTERS / SETTERS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Adds `item` into the set of values for `key`
    /// @return keyAdded true if `key` is new to the map
    /// @return itemAdded true if `item` is new to the value set for `key`
    function addItem(Bytes32ToAddressSetMap storage map, bytes32 key, address item)
        internal
        returns (bool keyAdded, bool itemAdded)
    {
        if (itemAdded = map._values[key].add(item)) {
            keyAdded = map._keys.add(key);
        }
    }

    /// @dev Returns the index of `value` in the map keys.
    /// Returns `NOT_FOUND` if the value does not exist.
    function indexOfE(Bytes32ToAddressSetMap storage map, bytes32 key) internal view returns (uint256 result) {
        result = map._keys.indexOf(key);
        if (result == SoladyEnumerableSetLib.NOT_FOUND) revert EnumerableMapKeyNotFound();
    }

    /// @dev Removes an item from the value set for a given key.
    /// If the value set becomes empty as a result then the entire key is removed.
    /// @return itemRemoved true if `item` was removed from the set of values, that is if it was present.
    /// @return keyRemoved true if `key` was removed from the map, that is if it was present and the set
    ///         of values for the key was empty after removing the item
    function removeFromValueSet(Bytes32ToAddressSetMap storage map, bytes32 key, address item)
        internal
        returns (bool itemRemoved, bool keyRemoved)
    {
        SoladyEnumerableSetLib.AddressSet storage items = map._values[key];

        // This may change the order of items
        itemRemoved = items.remove(item);

        if (items.length() == 0) {
            delete map._values[key];

            // This may change the order of keys
            keyRemoved = map._keys.remove(key);
        }
    }

    /// @dev Returns the number of key-value pairs in the map.
    function length(Bytes32ToAddressSetMap storage map) internal view returns (uint256) {
        return map._keys.length();
    }

    /// @dev Returns the key-value pair at index `i`. Reverts if `i` is out-of-bounds.
    function keyAt(Bytes32ToAddressSetMap storage map, uint256 i) internal view returns (bytes32 key) {
        key = map._keys.at(i);
    }

    /// @dev Reverts with `EnumerableMapKeyNotFound()`.
    /// See solady/utils/EnumerableMapLib.sol
    function _revertNotFound() private pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, 0x88682bf3) // `EnumerableMapKeyNotFound()`.
            revert(0x1c, 0x04)
        }
    }
}
