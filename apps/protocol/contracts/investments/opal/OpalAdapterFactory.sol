pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { LibClone } from "solady/utils/LibClone.sol";
import { LibString } from "solady/utils/LibString.sol";
import { EnumerableSetLib } from "solady/utils/EnumerableSetLib.sol";

import { IOpalAdapterFactory } from "contracts/interfaces/investments/opal/IOpalAdapterFactory.sol";
import { IOpalAdapter } from "contracts/interfaces/investments/opal/adapters/IOpalAdapter.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

/// @title Origami Portfolio of Assets and Liabilities (OPAL) Adapter Factory
/// @notice A factory to clone whitelisted OPAL Adapter implementations
/// @dev Uses Solady's `Clones with immutable args`, which is a ERC1167 minimal proxy with the
/// immutable arguments appended to the back fo the runtime bytecode.
contract OpalAdapterFactory is IOpalAdapterFactory, OrigamiElevatedAccess {
    using EnumerableSetLib for EnumerableSetLib.AddressSet;

    /// @dev The set of whitelisted implementations which can be cloned
    EnumerableSetLib.AddressSet private _implementations;

    constructor(address _initialOwner) OrigamiElevatedAccess(_initialOwner) { }

    /// @inheritdoc IOpalAdapterFactory
    function addImplementation(address implementation) external override onlyElevatedAccess {
        if (!_implementations.add(implementation)) revert AlreadyRegistered();

        emit ImplementationAdded(
            implementation, LibString.toSmallString(IOpalAdapter(implementation).implTypeAndVersion())
        );
    }

    /// @inheritdoc IOpalAdapterFactory
    function removeImplementation(address implementation) external override onlyElevatedAccess {
        if (!_implementations.remove(implementation)) revert NotRegistered();
        emit ImplementationRemoved(implementation);
    }

    /// @inheritdoc IOpalAdapterFactory
    function create(address implementation, address manager, bytes32 description, bytes calldata immutableArgsData)
        external
        override
        returns (address adapter)
    {
        if (!_implementations.contains(implementation)) revert NotRegistered();

        // The implementation may enforce that only the `manager` can call
        // initialize() after clone (see OpalAdapterBase::initialize)
        bytes memory combinedImmutableArgs = abi.encodePacked(
            manager, // packed position 0x00
            description, // packed position 0x14
            immutableArgsData // packed from position 0x34
        );
        adapter = LibClone.clone(implementation, combinedImmutableArgs);

        emit AdapterAdded(
            adapter,
            implementation,
            LibString.toSmallString(IOpalAdapter(adapter).implTypeAndVersion()),
            manager,
            description
        );
    }

    /// @inheritdoc IOpalAdapterFactory
    function isRegistered(address implementation) external view override returns (bool) {
        return _implementations.contains(implementation);
    }

    /// @inheritdoc IOpalAdapterFactory
    function numImplementations() external view override returns (uint256) {
        return _implementations.length();
    }

    /// @inheritdoc IOpalAdapterFactory
    function implementationDetailList(uint256 startIndex, uint256 maxItems)
        external
        view
        override
        returns (ImplementationDetail[] memory items)
    {
        // No items if either maxItems is zero or there are no implementations registered.
        if (maxItems == 0) return new ImplementationDetail[](0);
        uint256 length = _implementations.length();
        if (length == 0) return new ImplementationDetail[](0);

        // No items if startIndex is greater than the max array index
        if (startIndex >= length) return new ImplementationDetail[](0);

        // end index is the max of the requested items or the length
        uint256 requestedEndIndex = startIndex + maxItems - 1;
        {
            uint256 maxPossibleEndIndex = length - 1;
            if (maxPossibleEndIndex < requestedEndIndex) requestedEndIndex = maxPossibleEndIndex;
        }

        uint256 numItems = requestedEndIndex - startIndex + 1;
        items = new ImplementationDetail[](numItems);
        address impl;
        for (uint256 i; i < numItems; ++i) {
            impl = _implementations.at(i + startIndex);
            items[i] = ImplementationDetail({
                implementation: impl, implTypeAndVersion: IOpalAdapter(impl).implTypeAndVersion()
            });
        }
    }
}
