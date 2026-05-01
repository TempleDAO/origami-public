pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later


import { OrigamiTokenTeleporter } from "contracts/common/omnichain/OrigamiTokenTeleporter.sol";
import { OrigamiOFT } from "contracts/common/omnichain/OrigamiOFT.sol";
import { IOFT, OFT } from "@layerzerolabs/lz-evm-oapp-v2/contracts/standards/oft-evm/OFT.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { MessagingFee } from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";

import { OrigamiTeleportableToken } from "contracts/common/omnichain/OrigamiTeleportableToken.sol";
import { TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

contract MintableTeleportableToken is OrigamiTeleportableToken {
    constructor(
        address initialOwner_,
        string memory name_,
        string memory symbol_
    ) OrigamiTeleportableToken(name_, symbol_, initialOwner_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract OrigamiTeleportableTokenLayerZeroTestBase is TestHelperOz5, OrigamiTest {
    OrigamiTokenTeleporter internal teleporter;
    OrigamiOFT public origamiOft;

    uint32 aEid = 1;
    uint32 bEid = 2;

    MintableTeleportableToken internal vault;

    function setUp() public override {
        super.setUp();

        setUpEndpoints(2, LibraryType.UltraLightNode);
        vm.startPrank(origamiMultisig);
        deployContracts();
        wireOapps();
        vault.setTeleporter(address(teleporter));
        vm.stopPrank();
    }

    function deployContracts() internal {
        vault = new MintableTeleportableToken(origamiMultisig, "TELE_TOKEN", "TELE_TOKEN");

        teleporter = OrigamiTokenTeleporter(
            _deployOApp(
                type(OrigamiTokenTeleporter).creationCode,
                abi.encode(origamiMultisig, address(vault), address(endpoints[aEid]), origamiMultisig)
            )
        );

        origamiOft = OrigamiOFT(
            _deployOApp(
                type(OrigamiOFT).creationCode,
                abi.encode(
                    OFT.ConstructorArgs(
                        "ORIGAMI TOKEN B",
                        "ORGMB",
                        address(endpoints[bEid]),
                        origamiMultisig
                    )
                )
            )
        );
        
        vm.warp(100000000);
    }

    function wireOapps() internal {
        // config and wire the ofts
        address[] memory ofts = new address[](2);
        ofts[0] = address(teleporter);
        ofts[1] = address(origamiOft);
        teleporter.setPeer(bEid, addressToBytes32(address(origamiOft)));
        origamiOft.setPeer(aEid, addressToBytes32(address(teleporter)));
    }

    function mintShares(address user, uint256 tokenAmount) internal {
        vault.mint(user, tokenAmount);
    }

    function test_init() public view {
        {
            assertEq(origamiOft.name(), "ORIGAMI TOKEN B");
            assertEq(origamiOft.symbol(), "ORGMB");
            assertEq(origamiOft.owner(), origamiMultisig);
            assertEq(origamiOft.sharedDecimals(), 6);
        }
       
        {
            assertEq(teleporter.approvalRequired(), true);
            assertEq(teleporter.token(), address(vault));
            assertEq(teleporter.sharedDecimals(), 6);
            // unused function parameters
            assertEq(teleporter.nextNonce(uint32(0), bytes32(0)), 0);
            assertEq(teleporter.isPeer(bEid, addressToBytes32(address(origamiOft))), true);
            assertEq(origamiOft.isPeer(aEid, addressToBytes32(address(teleporter))), true);
        }

        {
            assertEq(address(vault.teleporter()), address(teleporter));
        }
    }
}

contract OrigamiTeleportableTokenLayerZeroTest is OrigamiTeleportableTokenLayerZeroTestBase {
    using OptionsBuilder for bytes;

    function test_quoteSend_teleportable_token() public view {
        uint256 sendAmount = 1 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(bob),
            sendAmount,
            sendAmount,
            options,
            "",
            ""
        );
        MessagingFee memory directFee = teleporter.quoteSend(sendParam, false);
        MessagingFee memory feeUsingVaultToken = vault.quoteSend(sendParam, false);
        assertEq(directFee.nativeFee, feeUsingVaultToken.nativeFee);

        sendAmount = 123 ether;
        sendParam = SendParam(
            bEid,
            addressToBytes32(bob),
            sendAmount,
            sendAmount,
            options,
            "",
            ""
        );
        directFee = teleporter.quoteSend(sendParam, false);
        feeUsingVaultToken = vault.quoteSend(sendParam, false);
        assertEq(directFee.nativeFee, feeUsingVaultToken.nativeFee);
    }

    function test_send_on_behalf_of() public {
        uint256 bobBalanceBefore = origamiOft.balanceOf(bob);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        
        // vault token sending on behalf of alice
        uint256 joinAmount = 1 ether;
        mintShares(alice, joinAmount);
        uint256 shares = vault.balanceOf(alice);

        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(bob),
            shares,
            shares,
            options,
            "",
            ""
        );
        MessagingFee memory fee = vault.quoteSend(sendParam, false);
        vm.deal(alice, fee.nativeFee);
        vm.startPrank(alice);
        vault.approve(address(vault), shares);
        vault.send{value:fee.nativeFee}(sendParam, fee, payable(address(alice)));
        verifyPackets(bEid, addressToBytes32(address(origamiOft)));
        assertEq(origamiOft.balanceOf(bob), bobBalanceBefore + shares);
        assertEq(vault.balanceOf(alice), 0);
    }
}