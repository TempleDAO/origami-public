pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

/// @dev Because Foundry does not commit the state changes between invariant runs, we need to
/// save the latest state in a contract with persistent storage.
contract StateStore {
    address public latestHandler;
    bytes4 public latestSig;
    bool public finishedEarly;
    
    bool public cappedRebalanceDown;

    function set(address handler, bytes4 sig) external {
        latestHandler = handler;
        latestSig = sig;
        finishedEarly = false;
    }

    function pop() external returns (address handler_, bytes4 sig_, bool finishedEarly_) {
        handler_ = latestHandler;
        sig_ = latestSig;
        finishedEarly_ = finishedEarly;
        
        latestHandler = address(0);
        latestSig = bytes4(0);
        finishedEarly = false;
    }

    function setCappedRebalanceDown(bool value) external {
        cappedRebalanceDown = value;
    }
    
    function setFinishedEarly() external {
        finishedEarly = true;
    }
}
