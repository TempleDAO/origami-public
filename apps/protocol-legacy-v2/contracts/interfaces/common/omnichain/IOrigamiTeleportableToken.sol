pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/omnichain/IOrigamiTeleportableToken.sol)

import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SendParam, OFTReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/standards/oft-evm/interfaces/IOFT.sol";
import { MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { IOFT } from "@layerzerolabs/lz-evm-oapp-v2/contracts/standards/oft-evm/interfaces/IOFT.sol";

/// @title Origami Teleportable Token
/// @notice An ERC20 token (supporting Permit) which does not require token approval to be spent
///     by the trusted teleporter. 
/// @dev There are intentionally no external mint/burn functions on this token, 
///     the teleporter is expected to be a 'locker', ie escrow the tokens.
interface IOrigamiTeleportableToken is
    IERC20Metadata,
    IERC20Permit,
    IERC165
{
    event TeleporterSet(address indexed teleporter);

    /// @notice Set the trusted address permitted to to bridge this token to another chain.
    function setTeleporter(address newTeleporter) external;

    /// @notice The trusted address permitted to to bridge this token to another chain.
    function teleporter() external view returns (IOFT);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       LAYER ZERO SEND                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice This function is added for improved UX convenience and for users to interact directly 
     * with the vault. The vault relays the call to the trusted token teleporter contract. 
     * @dev Executes the send operation.
     * @param sendParam The parameters for the send operation.
     * @param fee The calculated fee for the send() operation.
     *      - nativeFee: The native fee.
     *      - lzTokenFee: The lzToken fee.
     * @param refundAddress The address to receive any excess funds.
     * @return msgReceipt The receipt for the send operation.
     * @return oftReceipt The OFT receipt information.
     *
     * @dev MessagingReceipt: LayerZero msg receipt
     *  - guid: The unique identifier for the sent message.
     *  - nonce: The nonce of the sent message.
     *  - fee: The LayerZero fee incurred for the message.
     */
    function send(
        SendParam memory sendParam,
        MessagingFee memory fee,
        address refundAddress
    ) external payable returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt);

    /**
     * @notice Provides a quote for the send() operation.
     *  This function is added for improved UX convenience and for users to interact directly with the vault
     *  The vault relays the call to the trusted token teleporter contract. 
     * @param sendParam The parameters for the send() operation.
     * @param payInLzToken Flag indicating whether the caller is paying in the LZ token.
     * @return msgFee The calculated LayerZero messaging fee from the send() operation.
     *
     * @dev MessagingFee: LayerZero msg fee
     *  - nativeFee: The native fee.
     *  - lzTokenFee: The lzToken fee.
     */
    function quoteSend(
        SendParam calldata sendParam,
        bool payInLzToken
    ) external view returns (MessagingFee memory msgFee);
}
