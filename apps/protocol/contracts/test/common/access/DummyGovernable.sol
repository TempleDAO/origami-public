pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Governable} from "../../../common/access/Governable.sol";

contract DummyGovernable is Initializable, Governable {
    constructor(address initialGovernor) Governable(initialGovernor) {}

    function testOnlyGov() external view onlyGov returns (uint256) {
        return 1;
    }

}
