pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/omnichain/OrigamiOFT.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

import { IOFT, OFT } from "@layerzerolabs/lz-evm-oapp-v2/contracts/standards/oft-evm/OFT.sol";
import { OrigamiOftElevatedAccess } from "contracts/common/access/OrigamiOftElevatedAccess.sol";

/**
 * @title Origami OFT
 * @dev A vanilla LayerZero OFT, but with OrigamiElevatedAccess access controls and Permit capability
 */
contract OrigamiOFT is 
    IERC165,
    OFT,
    ERC20Permit,
    OrigamiOftElevatedAccess
{    
    constructor(
        OFT.ConstructorArgs memory args_
    ) 
        OFT(args_)
        ERC20Permit(args_.name)
        OrigamiOftElevatedAccess(args_.delegate)
    {
    }
    
    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public virtual override pure returns (bool) {
        return interfaceId == type(IOFT).interfaceId
            || interfaceId == type(IERC20Metadata).interfaceId
            || interfaceId == type(IERC20).interfaceId
            || interfaceId == type(IERC20Permit).interfaceId
            || interfaceId == type(EIP712).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }
}
