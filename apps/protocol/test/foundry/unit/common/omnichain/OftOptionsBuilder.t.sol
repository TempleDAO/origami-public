pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { Test } from "forge-std/Test.sol";

contract OrigamiOftTestBase is Test {
    using OptionsBuilder for bytes;

    function test_options() public pure {
        bytes memory theBytes = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0); // gas limit, msg.value
        bytes memory expected = hex"00030100110100000000000000000000000000030d40";
        vm.assertEq(theBytes, expected);
    }
}
