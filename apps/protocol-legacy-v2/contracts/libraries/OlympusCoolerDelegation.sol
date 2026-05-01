pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (libraries/OlympusCoolerDelegation.sol)

import { IDLGTEv1 } from "contracts/interfaces/external/olympus/IDLGTE.v1.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { IOrigamiHOhmManager } from "contracts/interfaces/investments/olympus/IOrigamiHOhmManager.sol";
import { SafeCast } from "contracts/libraries/SafeCast.sol";

/**
 * @notice Generate Olympus Cooler delegation requests on behalf of Origami users
 */
library OlympusCoolerDelegation {
    using SafeCast for uint256;

    struct Data {
        address delegateAddress;
        uint256 amount;
    }

    struct _Request {
        /// @dev The account to sync the delegation request for.
        /// If this request is not required to be applied (eg the delegated balance
        /// won't change), this will be address(0)
        address account;

        /// @dev The cooler delegation request
        IDLGTEv1.DelegationRequest request;
    }

    /**
     * @notice Update the gOHM delegation address and amount for a particular account, 
     * and update the `$delegation` state for that account.
     * @dev 
     *  - `account` cannot be address(0) - this will revert
     *  - `newDelegateAddress` may be address(0), meaning that gOHM collateral will become
     *    undelegated.
     *  - `newDelegateAddress` may remain the same as the existing one, meaning just the amount
     *    is updated
     *  - `newAmount` may be zero, meaning that any existing gOHM collateral is undelegated.
     *    however the `$delegation.delegateAddress` will remain as is unless `newDelegateAddress` 
     *    has also changed
     */
    function updateDelegateAndAmount(
        Data storage $delegation,
        address account,
        address newDelegateAddress,
        uint256 newAmount
    ) internal returns (IDLGTEv1.DelegationRequest[] memory) {
        _Request memory cdr1;
        _Request memory cdr2;
        address existingDelegateAddress = $delegation.delegateAddress;
        uint256 existingAmount = $delegation.amount;

        if (newDelegateAddress == existingDelegateAddress) {
            // The same delegate address - only need to sync the amount
            cdr1 = _syncAmount($delegation, account, existingDelegateAddress, existingAmount, newAmount);
        } else {
            // Update to a new delegate address along with a new amount
            // Set the old delegation amount to zero if it previously had a delegation address
            if (existingDelegateAddress != address(0)) {
                cdr1 = _syncDelegationRequest(account, existingDelegateAddress, existingAmount, 0);
            }

            // Set the delegation to the new address.
            // If the new delegation address is zero (request is to undelegate) then the amount just needs
            // to be sync'd to storage - no second cooler delegation request is needed.
            if (newDelegateAddress == address(0)) {
                newAmount = 0;
            } else {
                cdr2 = _syncDelegationRequest(account, newDelegateAddress, 0, newAmount);
            }

            // Persist state
            $delegation.delegateAddress = newDelegateAddress;
            if (existingAmount != newAmount) {
                $delegation.amount = newAmount;
            }
        }

        return _generateRequests(cdr1, cdr2);
    }

    /**
     * @dev Create a request (and sync state) to update the delegated amount for `account`
     */
    function syncAccountAmount(
        Data storage $delegation,
        address account,
        uint256 accountNewAmount
    ) internal returns (IDLGTEv1.DelegationRequest[] memory) {
        return _generateRequests(
            _syncAmount(
                $delegation,
                account,
                $delegation.delegateAddress,
                $delegation.amount,
                accountNewAmount
            )
        );
    }

    /**
     * @dev Create a request (and sync state) to update the delegated amount for `account1`
     * and `account2`
     */
    function syncAccountAmount(
        Data storage $delegation1,
        address account1,
        uint256 account1NewAmount,
        Data storage $delegation2,
        address account2,
        uint256 account2NewAmount
    ) internal returns (IDLGTEv1.DelegationRequest[] memory) {
        if (account1 == account2) revert CommonEventsAndErrors.InvalidAddress(account2);

        return _generateRequests(
            _syncAmount(
                $delegation1,
                account1,
                $delegation1.delegateAddress,
                $delegation1.amount,
                account1NewAmount
            ),
            _syncAmount(
                $delegation2,
                account2,
                $delegation2.delegateAddress,
                $delegation2.amount,
                account2NewAmount
            )
        );
    }

    /**
     * @dev Create a request (and sync state) to update the delegate address and
     * amount for `account`
     */
    function _syncAmount(
        Data storage $delegation,
        address account,
        address delegateAddress,
        uint256 existingAmount,
        uint256 newAmount
    ) private returns (
        _Request memory request
    ) {
        // If the delegate address is 0, then ensure the amount is also zero
        if (delegateAddress == address(0)) {
            newAmount = 0;
        }

        // Sync the amount if the new amount is different to the existing one.
        if (existingAmount != newAmount) {
            request = _syncDelegationRequest(account, delegateAddress, existingAmount, newAmount);

            // Persist state
            $delegation.amount = newAmount;
        }
    }

    /**
     * @dev Create the cooler delegation request for an account & delegate address for a new delegation amount.
     * The request will be for the amount delta (vs the existing delegated amount).
     * If no delegate address or no difference in the amount, then `request` will be left uninitialised
     */
    function _syncDelegationRequest(
        address account,
        address delegateAddress,
        uint256 existingDelegationAmount,
        uint256 newDelegationAmount
    ) private pure returns (_Request memory request) {
        // No delegate for this account - no request required.
        if (delegateAddress == address(0)) return request;

        // Only set the sync request item if the existing delegated amount is 
        // different to the target amount
        int256 delta = newDelegationAmount.encodeInt256() - existingDelegationAmount.encodeInt256();

        if (delta != 0) {
            request = _Request(
                account,
                IDLGTEv1.DelegationRequest({
                    delegate: delegateAddress,
                    amount: delta
                })
            );
        }
    }

    /// @dev Generate the Cooler DelegationRequest list for one (potentially uninitialized) request
    function _generateRequests(
        _Request memory cdr
    ) private returns (IDLGTEv1.DelegationRequest[] memory requests) {
        if (cdr.account != address(0)) {
            requests = new IDLGTEv1.DelegationRequest[](1);
            requests[0] = cdr.request;
            emit IOrigamiHOhmManager.DelegationApplied(cdr.account, cdr.request.delegate, cdr.request.amount);
        }

        // else requests is left uninitialized
    }

    /// @dev Generate the Cooler DelegationRequest list for two (potentially uninitialized) requests
    function _generateRequests(
        _Request memory cdr1,
        _Request memory cdr2
    ) private returns (IDLGTEv1.DelegationRequest[] memory requests) {
        if (cdr1.account != address(0) && cdr2.account != address(0)) {
            requests = new IDLGTEv1.DelegationRequest[](2);
            (requests[0], requests[1]) = (cdr1.request, cdr2.request);

            emit IOrigamiHOhmManager.DelegationApplied(cdr1.account, cdr1.request.delegate, cdr1.request.amount);
            emit IOrigamiHOhmManager.DelegationApplied(cdr2.account, cdr2.request.delegate, cdr2.request.amount);
        } else if (cdr1.account != address(0)) {
            return _generateRequests(cdr1);
        } else if (cdr2.account != address(0)) {
            return _generateRequests(cdr2);
        }

        // else requests is left uninitialized
    }
}
