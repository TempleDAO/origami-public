pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (periphery/OrigamiLanternOffering.sol)

import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/**
 * @title Origami Lantern Offering
 * @notice Registered accounts can choose to participate in the offering
 * @dev It is a one time only option, all or nothing
 */
contract OrigamiLanternOffering is Pausable, OrigamiElevatedAccess {
    error NotRegistered();
    error AlreadyRegistered();
    error AlreadyParticipating();

    event Register(address indexed account, uint256 amount);
    event OfferingMade(address indexed account, uint256 amount);

    /// @notice Balance of registered amounts
    mapping(address account => uint256 amount) public balanceOf;

    /// @notice Accounts which are participating
    mapping(address account => bool participated) public participatedInOffering;

    /// @notice The total balance of registered amounts
    uint256 public totalSupply;

    /// @notice The total amount of offered amounts
    uint256 public totalOffered;
    
    constructor(address initialOwner) OrigamiElevatedAccess(initialOwner) {
        // Pause by default
        _pause();
    }

    /// @notice Eligable accounts for the lantern offering may call to nominate their participation.
    /// @dev It is a one time option to participate which will have a deadline (at which point it will be paused)
    /// Accounts can participate with their entire balance only
    function participateInOffering() external whenNotPaused {
        uint256 balance = balanceOf[msg.sender];
        if (balance == 0) revert NotRegistered();
        if (participatedInOffering[msg.sender]) revert AlreadyParticipating();

        emit OfferingMade(msg.sender, balance);
        participatedInOffering[msg.sender] = true;
        totalOffered += balance;
    }

    /// @notice Register multiple accounts who are eligable to participate in the offering
    /// @dev Encode (gas efficient) calldata via batchRegisterInputs()
    function batchRegister(bytes32[] calldata data) external onlyElevatedAccess {
        uint256 newSupply;
        address account;
        uint96 amount;
        for (uint256 i = 0; i < data.length; ++i) {
            // Shift to the right by 96 bytes and convert uint160 to address
            account = address(uint160(uint256(data[i]) >> 96));
            if (account == address(0)) revert CommonEventsAndErrors.InvalidAddress(account);
            if (balanceOf[account] != 0) revert AlreadyRegistered();

            // The right most 96 bites is converted to the uint96
            amount = uint96(uint256(data[i]));
            if (amount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
            emit Register(account, amount);

            balanceOf[account] = amount;
            newSupply += amount;
        }

        totalSupply += newSupply;
    }

    function togglePauseOffering() external onlyElevatedAccess {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
    }

    // Struct to help build up encoded registration data
    struct Registration {
        address account;
        uint96 amount;
    }

    /// @notice Encode registrations into required calldata for use in `batchRegister`
    /// @dev Validation on inputs is not done here -- deferred to the `batchRegister`
    function batchRegisterInputs(
        Registration[] calldata registrations
    ) external pure returns (bytes32[] memory data) {
        data = new bytes32[](registrations.length);

        Registration calldata registration;
        for (uint256 i; i < registrations.length; ++i) {
            registration = registrations[i];

            // Convert address to uint160, shift to the left by 96 bits
            // OR with uint96 amount (12 bytes)
            data[i] = bytes32(
                (uint256(uint160(registration.account)) << 96) |
                uint256(registration.amount)
            );
        }
    }
}
