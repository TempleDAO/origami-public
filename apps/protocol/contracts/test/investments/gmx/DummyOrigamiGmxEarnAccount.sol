pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OrigamiGmxEarnAccount } from "contracts/investments/gmx/OrigamiGmxEarnAccount.sol";

contract DummyOrigamiGmxEarnAccount is Initializable, OrigamiGmxEarnAccount {
    /// @dev The new address variable added for the OrigamiStaking contract upgrade test
    address public newAddr;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _gmxRewardRouter) OrigamiGmxEarnAccount(_gmxRewardRouter) {}

    function setNewAddr(address _newAddr) external {
        newAddr = _newAddr;
    }

    // A test so _authorizeUpgrade can be called
    function authorizeUpgrade() external {
        _authorizeUpgrade(address(this));
    }
}
