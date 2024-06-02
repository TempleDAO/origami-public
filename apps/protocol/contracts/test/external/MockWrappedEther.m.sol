pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { MintableToken } from "contracts/common/MintableToken.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

contract MockWrappedEther is MintableToken {
    using Address for address payable;

    event Deposit(address indexed dst, uint wad);
    event Withdrawal(address indexed src, uint wad);

    constructor(
        address _initialOwner
    ) MintableToken("Wrapped Ether", "WETH", _initialOwner) {
    }

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) public {
        _burn(msg.sender, amount);
        emit Withdrawal(msg.sender, amount);
        payable(msg.sender).sendValue(amount);
    }
}
