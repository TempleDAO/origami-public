// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract TokenDrainer is Script {
    function run(address tokenAddress, address existingOwnerAddress, address newOwnerAddress) external {
        IERC20Metadata token = IERC20Metadata(tokenAddress);
        uint256 amount = token.balanceOf(existingOwnerAddress);

        console.log("Pulling %s %s", amount, token.symbol());
        console.log("from %s to %s", existingOwnerAddress, newOwnerAddress);
        console.log("~-~-~-~-~-~-~-~-~-");
        console.log("BEFORE");
        console.log("Existing owner balance: %d", amount);
        console.log("New owner balance: %d", token.balanceOf(newOwnerAddress));
        console.log("~-~-~-~-~-~-~-~-~-");

        // Runs a single command to transfer the token amount from old to new address
        vm.broadcast(existingOwnerAddress);
        token.transfer(newOwnerAddress, amount);

        console.log("~-~-~-~-~-~-~-~-~-");
        console.log("AFTER");
        console.log("Existing owner balance: %d", token.balanceOf(existingOwnerAddress));
        console.log("New owner balance: %d", token.balanceOf(newOwnerAddress));
        console.log("~-~-~-~-~-~-~-~-~-");
    }

    function run() external pure {
        console.log("NOT IMPLEMENTED");
        revert("NOT IMPLEMENTED");
    }
}
