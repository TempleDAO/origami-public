pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

contract OrigamiTokenRecovery is OrigamiElevatedAccess {
    using SafeERC20 for IERC20;

    constructor(address initialOwner_) OrigamiElevatedAccess(initialOwner_) {}

    function recoverToken(address token, address from, address to, uint256 amount) external onlyElevatedAccess {
        IERC20(token).safeTransferFrom(from, to, amount);
    }
}
