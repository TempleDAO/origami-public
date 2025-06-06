pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { SendParam } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { MessagingFee } from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import { OrigamiTeleportableToken } from "contracts/common/omnichain/OrigamiTeleportableToken.sol";
import { OrigamiTokenTeleporter } from "contracts/common/omnichain/OrigamiTokenTeleporter.sol";
import { OFT, OrigamiOFT } from "contracts/common/omnichain/OrigamiOFT.sol";

import { TestHelperOz5, EndpointV2 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

contract OrigamiTokenTeleporterTestBase is TestHelperOz5 {

    OrigamiTokenTeleporter public teleporter_ttoken_a;
    OrigamiOFT public oftToken_b;
    OrigamiOFT public oftToken_c;
    OrigamiTeleportableToken public ttoken_a;

    uint32 aEid = 1;
    uint32 bEid = 2;
    uint32 cEid = 3;

    address public origamiMultisig = makeAddr("origamiMultisig");
    address public delegate = makeAddr("delegate");

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public unknownUser = makeAddr("unknownUsers");

    event MsgInspectorSet(address inspector);
    event PeerSet(uint32 eid, bytes32 peer);
    event DelegateSet(address sender, address delegate);

    function setUp() public virtual override {
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);

        super.setUp();
        setUpEndpoints(3, LibraryType.UltraLightNode);

        vm.startPrank(origamiMultisig);
        ttoken_a = new OrigamiTeleportableToken("TELE_TOKENA", "TTOKENA", origamiMultisig);
        vm.label(address(ttoken_a), "TELE_TOKEN_CHAIN_A");

        teleporter_ttoken_a = OrigamiTokenTeleporter(
            _deployOApp(
                type(OrigamiTokenTeleporter).creationCode,
                abi.encode(origamiMultisig, address(ttoken_a), address(endpoints[aEid]), origamiMultisig)
            )
        );
        ttoken_a.setTeleporter(address(teleporter_ttoken_a));

        oftToken_b = OrigamiOFT(
            _deployOApp(
                type(OrigamiOFT).creationCode,
                abi.encode(OFT.ConstructorArgs({
                    name: "OFT_TOKEN",
                    symbol: "OFT",
                    lzEndpoint: address(endpoints[bEid]),
                    delegate: origamiMultisig
                }))
            )
        );
        vm.label(address(oftToken_b), "OFT_CHAIN_B");
        oftToken_c = OrigamiOFT(
            _deployOApp(
                type(OrigamiOFT).creationCode,
                abi.encode(OFT.ConstructorArgs({
                    name: "OFT_TOKEN",
                    symbol: "OFT",
                    lzEndpoint: address(endpoints[cEid]),
                    delegate: origamiMultisig
                }))
            )
        );
        vm.label(address(oftToken_c), "OFT_CHAIN_C");

        deal(address(ttoken_a), alice, 1_000e18);

        // config and wire the ofts
        {
            // TTOKEN_A <=> OFT_B
            teleporter_ttoken_a.setPeer(bEid, addressToBytes32(address(oftToken_b)));
            oftToken_b.setPeer(aEid, addressToBytes32(address(teleporter_ttoken_a)));

            // OFT_B <=> OFT_C
            oftToken_b.setPeer(cEid, addressToBytes32(address(oftToken_c)));
            oftToken_c.setPeer(bEid, addressToBytes32(address(oftToken_b)));
        }
        vm.stopPrank();
    }
}

contract OrigamiTokenTeleporterTestAdmin is OrigamiTokenTeleporterTestBase {
    function test_init() public view {
        assertEq(teleporter_ttoken_a.owner(), origamiMultisig);
        assertEq(teleporter_ttoken_a.approvalRequired(), true);
        assertEq(teleporter_ttoken_a.token(), address(ttoken_a));
        assertEq(teleporter_ttoken_a.sharedDecimals(), 6);
        // unused function parameters
        assertEq(teleporter_ttoken_a.nextNonce(uint32(0), bytes32(0)), 0);
        assertEq(teleporter_ttoken_a.isPeer(bEid, addressToBytes32(address(oftToken_b))), true);
        assertEq(oftToken_b.isPeer(aEid, addressToBytes32(address(teleporter_ttoken_a))), true);
        assertEq(oftToken_b.isPeer(cEid, addressToBytes32(address(oftToken_c))), true);
        assertEq(oftToken_c.isPeer(bEid, addressToBytes32(address(oftToken_b))), true);

        assertEq(ttoken_a.balanceOf(alice), 1000 ether);
    }
}

contract OrigamiTokenTeleporterAccessTest is OrigamiTokenTeleporterTestBase {
    function test_access_setPeer_fail() public {
        vm.startPrank(unknownUser);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        teleporter_ttoken_a.setPeer(bEid, addressToBytes32(address(oftToken_b)));
        vm.stopPrank();
    }

    function test_access_setDelegate_fail() public {
        vm.startPrank(unknownUser);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        teleporter_ttoken_a.setDelegate(alice);
        vm.stopPrank();
    }

    function test_access_setMsgInspector_fail() public {
        vm.startPrank(unknownUser);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        teleporter_ttoken_a.setMsgInspector(alice);
        vm.stopPrank();
    }

    function test_access_setPeer_success() public {
        vm.startPrank(origamiMultisig);
        teleporter_ttoken_a.setPeer(bEid, addressToBytes32(address(oftToken_b)));
        vm.stopPrank();
    }

    function test_access_setDelegate_success() public {
        vm.startPrank(origamiMultisig);
        teleporter_ttoken_a.setDelegate(delegate);
        vm.stopPrank();
    }

    function test_access_setMsgInspector_success() public {
        vm.startPrank(origamiMultisig);
        teleporter_ttoken_a.setMsgInspector(alice);
        vm.stopPrank();
    }
}

contract OrigamiTokenTeleporterTest is OrigamiTokenTeleporterTestBase {
    using OptionsBuilder for bytes;

    function test_setPeer() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(teleporter_ttoken_a));
        emit PeerSet(bEid, addressToBytes32(address(oftToken_b)));
        teleporter_ttoken_a.setPeer(bEid, addressToBytes32(address(oftToken_b)));
        assertEq(teleporter_ttoken_a.isPeer(bEid, addressToBytes32(address(oftToken_b))), true);

        vm.expectEmit(address(teleporter_ttoken_a));
        emit PeerSet(bEid, addressToBytes32(address(delegate)));
        teleporter_ttoken_a.setPeer(bEid, addressToBytes32(address(delegate)));
        assertEq(teleporter_ttoken_a.isPeer(bEid, addressToBytes32(address(oftToken_b))), false);
        assertEq(teleporter_ttoken_a.isPeer(bEid, addressToBytes32(address(delegate))), true);
    }

    function test_setMsgInspector() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(teleporter_ttoken_a));
        emit MsgInspectorSet(alice);
        teleporter_ttoken_a.setMsgInspector(alice);
        assertEq(teleporter_ttoken_a.msgInspector(), alice);

        vm.expectEmit(address(teleporter_ttoken_a));
        emit MsgInspectorSet(bob);
        teleporter_ttoken_a.setMsgInspector(bob);
        assertEq(teleporter_ttoken_a.msgInspector(), bob);
    }

    function test_setDelegate() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(endpoints[aEid]));
        emit DelegateSet(address(teleporter_ttoken_a), delegate);
        teleporter_ttoken_a.setDelegate(delegate);
        assertEq(EndpointV2(endpoints[aEid]).delegates(address(teleporter_ttoken_a)), delegate);
    }

    function test_send_oft_dust() public {
        uint256 aliceBalance = 1_000e18;
        deal(address(oftToken_b), alice, 1_000e18);
        uint256 sendAmount = 123.456789876543212345e18;
        uint256 sendAmountLessDust = 123.456789e18;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            cEid,
            addressToBytes32(bob),
            sendAmount,
            sendAmountLessDust,
            options,
            "",
            ""
        );

        MessagingFee memory fee = oftToken_b.quoteSend(sendParam, false);
        assertEq(oftToken_b.balanceOf(alice), aliceBalance);
        assertEq(oftToken_b.balanceOf(bob), 0);
        assertEq(oftToken_c.balanceOf(alice), 0);
        assertEq(oftToken_c.balanceOf(bob), 0);

        vm.startPrank(alice);
        oftToken_b.send{value:fee.nativeFee}(sendParam, fee, payable(address(alice)));
        verifyPackets(cEid, addressToBytes32(address(oftToken_c)));

        assertEq(oftToken_b.balanceOf(alice), aliceBalance-sendAmountLessDust);
        assertEq(oftToken_b.balanceOf(bob), 0);
        assertEq(oftToken_c.balanceOf(alice), 0);
        assertEq(oftToken_c.balanceOf(bob), sendAmountLessDust);
    }

    function test_send_token_adapter_dust_aTob() public {
        uint256 aliceBalance = ttoken_a.balanceOf(alice);
        assertEq(aliceBalance, 1_000e18);
        uint256 sendAmount = 123.456789876543212345e18;
        uint256 sendAmountLessDust = 123.456789e18;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(bob),
            sendAmount,
            sendAmountLessDust,
            options,
            "",
            ""
        );

        MessagingFee memory fee = teleporter_ttoken_a.quoteSend(sendParam, false);
        assertEq(ttoken_a.balanceOf(alice), aliceBalance);
        assertEq(ttoken_a.balanceOf(bob), 0);
        assertEq(ttoken_a.balanceOf(address(teleporter_ttoken_a)), 0);
        assertEq(oftToken_b.balanceOf(alice), 0);
        assertEq(oftToken_b.balanceOf(bob), 0);

        // No explicit token approval is needed for the teleporter to spend on behalf of alice
        vm.startPrank(alice);
        teleporter_ttoken_a.send{value:fee.nativeFee}(sendParam, fee, payable(address(alice)));
        verifyPackets(bEid, addressToBytes32(address(oftToken_b)));

        assertEq(ttoken_a.balanceOf(alice), aliceBalance-sendAmountLessDust);
        assertEq(ttoken_a.balanceOf(bob), 0);
        assertEq(ttoken_a.balanceOf(address(teleporter_ttoken_a)), sendAmountLessDust);
        assertEq(oftToken_b.balanceOf(alice), 0);
        assertEq(oftToken_b.balanceOf(bob), sendAmountLessDust);
    }

    function test_send_token_adapter_dust_bToa() public {
        deal(address(ttoken_a), alice, 0);
        deal(address(oftToken_b), bob, 1_000e18);

        uint256 bobBalance = oftToken_b.balanceOf(bob);
        assertEq(bobBalance, 1_000e18);
        uint256 sendAmount = 123.456789876543212345e18;
        uint256 sendAmountLessDust = 123.456789e18;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            aEid,
            addressToBytes32(alice),
            sendAmount,
            sendAmountLessDust,
            options,
            "",
            ""
        );

        MessagingFee memory fee = oftToken_b.quoteSend(sendParam, false);
        assertEq(oftToken_b.balanceOf(alice), 0);
        assertEq(oftToken_b.balanceOf(bob), bobBalance);
        assertEq(ttoken_a.balanceOf(address(teleporter_ttoken_a)), 0);
        assertEq(ttoken_a.balanceOf(alice), 0);
        assertEq(ttoken_a.balanceOf(bob), 0);

        // teleporter needs some simulated 'locked' tokens
        deal(address(ttoken_a), address(teleporter_ttoken_a), sendAmountLessDust);
        vm.startPrank(bob);
        oftToken_b.send{value:fee.nativeFee}(sendParam, fee, payable(address(bob)));
        verifyPackets(aEid, addressToBytes32(address(teleporter_ttoken_a)));

        assertEq(oftToken_b.balanceOf(alice), 0);
        assertEq(oftToken_b.balanceOf(bob), bobBalance-sendAmountLessDust);
        assertEq(ttoken_a.balanceOf(address(teleporter_ttoken_a)), 0);
        assertEq(ttoken_a.balanceOf(alice), sendAmountLessDust);
        assertEq(ttoken_a.balanceOf(bob), 0);
    }

    function test_send_token_passthrough_dust_aTob() public {
        uint256 aliceBalance = ttoken_a.balanceOf(alice);
        assertEq(aliceBalance, 1_000e18);
        uint256 sendAmount = 123.456789876543212345e18;
        uint256 sendAmountLessDust = 123.456789e18;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(bob),
            sendAmount,
            sendAmountLessDust,
            options,
            "",
            ""
        );

        MessagingFee memory fee = ttoken_a.quoteSend(sendParam, false);
        assertEq(ttoken_a.balanceOf(alice), aliceBalance);
        assertEq(ttoken_a.balanceOf(bob), 0);
        assertEq(ttoken_a.balanceOf(address(teleporter_ttoken_a)), 0);
        assertEq(oftToken_b.balanceOf(alice), 0);
        assertEq(oftToken_b.balanceOf(bob), 0);

        // No explicit token approval is needed for the teleporter to spend on behalf of alice
        vm.startPrank(alice);
        ttoken_a.send{value:fee.nativeFee}(sendParam, fee, payable(address(alice)));
        verifyPackets(bEid, addressToBytes32(address(oftToken_b)));

        assertEq(ttoken_a.balanceOf(alice), aliceBalance-sendAmountLessDust);
        assertEq(ttoken_a.balanceOf(address(ttoken_a)), 0);
        assertEq(ttoken_a.balanceOf(bob), 0);
        assertEq(ttoken_a.balanceOf(address(teleporter_ttoken_a)), sendAmountLessDust);
        assertEq(oftToken_b.balanceOf(alice), 0);
        assertEq(oftToken_b.balanceOf(bob), sendAmountLessDust);
    }

    function test_send_token_adapter() public {
        uint256 aliceBalance = ttoken_a.balanceOf(alice);
        uint256 sendAmount = 123 ether;
        uint256 minSendAmount = sendAmount;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(bob),
            sendAmount,
            minSendAmount,
            options,
            "",
            ""
        );

        // get send quote
        MessagingFee memory fee = teleporter_ttoken_a.quoteSend(sendParam, false);
        assertEq(ttoken_a.balanceOf(alice), aliceBalance);
        assertEq(ttoken_a.balanceOf(address(teleporter_ttoken_a)), 0);
        assertEq(oftToken_b.balanceOf(bob), 0);

        // No explicit token approval is needed for the teleporter to spend on behalf of alice
        vm.startPrank(alice);
        teleporter_ttoken_a.send{value:fee.nativeFee}(sendParam, fee, payable(address(alice)));
        verifyPackets(bEid, addressToBytes32(address(oftToken_b)));

        assertEq(oftToken_b.balanceOf(bob), sendAmount);
        assertEq(ttoken_a.balanceOf(alice), aliceBalance - sendAmount);
        assertEq(ttoken_a.balanceOf(address(teleporter_ttoken_a)), sendAmount); // locked amount

        // checking lossless transfers
        uint256 sendAmount2 = 123456789876543212345;
        minSendAmount = _removeDust(sendAmount2);
        sendParam = SendParam(
            bEid,
            addressToBytes32(bob),
            sendAmount2,
            minSendAmount,
            options,
            "",
            ""
        );
        fee = teleporter_ttoken_a.quoteSend(sendParam, false);
        vm.startPrank(alice);
        teleporter_ttoken_a.send{value:fee.nativeFee}(sendParam, fee, payable(address(alice)));
        verifyPackets(bEid, addressToBytes32(address(oftToken_b)));
        assertEq(oftToken_b.balanceOf(bob), sendAmount+minSendAmount);
        assertEq(ttoken_a.balanceOf(alice), aliceBalance - sendAmount - minSendAmount);
        assertEq(ttoken_a.balanceOf(address(teleporter_ttoken_a)), sendAmount+minSendAmount);

        // bob sends to alice
        uint256 toSend = oftToken_b.balanceOf(bob);
        minSendAmount = _removeDust(toSend);
        uint256 dustAmount = toSend - minSendAmount;
        sendParam = SendParam(
            aEid,
            addressToBytes32(alice),
            toSend,
            minSendAmount,
            options,
            "",
            ""
        );
        fee = oftToken_b.quoteSend(sendParam, false);
        vm.startPrank(bob);
        oftToken_b.send{value:fee.nativeFee}(sendParam, fee, payable(address(bob)));
        verifyPackets(aEid, addressToBytes32(address(teleporter_ttoken_a)));
        assertEq(oftToken_b.balanceOf(bob), dustAmount);
        assertEq(ttoken_a.balanceOf(alice), aliceBalance - dustAmount);
        assertEq(ttoken_a.balanceOf(address(teleporter_ttoken_a)), 0);
    }

    function _setExplicitAccess(
        IOrigamiElevatedAccess theContract, 
        address allowedCaller, 
        bytes4 fnSelector, 
        bool value
    ) private {
        IOrigamiElevatedAccess.ExplicitAccess[] memory access = new IOrigamiElevatedAccess.ExplicitAccess[](1);
        access[0] = IOrigamiElevatedAccess.ExplicitAccess(fnSelector, value);
        theContract.setExplicitAccess(allowedCaller, access);
    }

    function _removeDust(uint256 _amountLD) private view returns (uint256 amountLD) {
        uint256 decimalConversionRate = 10 ** (ttoken_a.decimals() - teleporter_ttoken_a.sharedDecimals());
        return (_amountLD / decimalConversionRate) * decimalConversionRate;
    }
}