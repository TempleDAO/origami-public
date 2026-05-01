pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/omnichain/OrigamiTeleportableToken.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { IOrigamiTeleportableToken } from "contracts/interfaces/common/omnichain/IOrigamiTeleportableToken.sol";

import { MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { SendParam, OFTReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/standards/oft-evm/interfaces/IOFT.sol";
import { IOFT } from "@layerzerolabs/lz-evm-oapp-v2/contracts/standards/oft-evm/interfaces/IOFT.sol";

/// @title Origami Teleportable Token
/// @notice An ERC20 token (supporting Permit) which does not require token approval to be spent
///     by the trusted teleporter. 
/// @dev There are intentionally no external mint/burn functions on this token, 
///     the teleporter is expected to be a 'locker', ie escrow the tokens.
contract OrigamiTeleportableToken is 
    ERC20Permit,
    OrigamiElevatedAccess,
    IOrigamiTeleportableToken
{
    using SafeERC20 for IERC20;
    /// @inheritdoc IOrigamiTeleportableToken
    IOFT public override teleporter;

    constructor(
        string memory name_,
        string memory symbol_,
        address initialOwner_
    )
        ERC20(name_, symbol_) 
        ERC20Permit(name_) 
        OrigamiElevatedAccess(initialOwner_)
    {}

    /// @inheritdoc IOrigamiTeleportableToken
    function setTeleporter(address newTeleporter) external override onlyElevatedAccess {
        if (newTeleporter == address(0)) revert CommonEventsAndErrors.InvalidAddress(newTeleporter);
        teleporter = IOFT(newTeleporter);
        emit TeleporterSet(newTeleporter);
    }

    /// @inheritdoc IERC20
    function allowance(address tokenOwner, address spender) public view virtual override(ERC20, IERC20) returns (uint256) {
        // If the spender is the trusted teleporter, then no approval is required.
        return spender == address(teleporter)
            ? type(uint256).max
            : super.allowance(tokenOwner, spender);
    }
    
    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public virtual override pure returns (bool) {
        return interfaceId == type(IOrigamiTeleportableToken).interfaceId 
            || interfaceId == type(IERC20Metadata).interfaceId
            || interfaceId == type(IERC20).interfaceId
            || interfaceId == type(IERC20Permit).interfaceId
            || interfaceId == type(EIP712).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       LAYER ZERO SEND                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IOrigamiTeleportableToken
    function send(
        SendParam calldata sendParam,
        MessagingFee calldata fee,
        address refundAddress
    ) external payable override returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) {
        // pull tokens to vault first. no allowance needed
        uint256 amount = sendParam.amountLD;
        _transfer(msg.sender, address(this), amount);

        // no approval, teleporter is trusted as spender
        (msgReceipt, oftReceipt) = teleporter.send{value: msg.value}(sendParam, fee, refundAddress);

        // There may be a dust refund as LZ truncates to 6 decimals by default.
        uint256 refundAmount = amount - oftReceipt.amountSentLD;
        if (refundAmount > 0) {
            _transfer(address(this), msg.sender, refundAmount);
        }
    }

    /// @inheritdoc IOrigamiTeleportableToken
    function quoteSend(
        SendParam calldata sendParam,
        bool payInLzToken
    ) external view override returns (MessagingFee memory fee) {
        fee = teleporter.quoteSend(sendParam, payInLzToken);
    }
}
