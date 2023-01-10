pragma solidity ^0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OrigamiGmxEarnAccount} from "../../../investments/gmx/OrigamiGmxEarnAccount.sol";

contract DummyOrigamiGmxEarnAccount is Initializable, OrigamiGmxEarnAccount {
    /// @dev The new address variable added for the OrigamiStaking contract upgrade test
    address public newAddr;

    function setNewAddr(address _newAddr) external {
        newAddr = _newAddr;
    }

    // A test so _authorizeUpgrade can be called
    function authorizeUpgrade() external {
        _authorizeUpgrade(address(this));
    }
}
