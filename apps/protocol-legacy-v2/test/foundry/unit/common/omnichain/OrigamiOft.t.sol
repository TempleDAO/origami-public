pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { SendParam } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { MessagingFee } from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { IOFT, OFT } from "@layerzerolabs/lz-evm-oapp-v2/contracts/standards/oft-evm/OFT.sol";

import { OrigamiTeleportableToken } from "contracts/common/omnichain/OrigamiTeleportableToken.sol";
import { OrigamiTokenTeleporter } from "contracts/common/omnichain/OrigamiTokenTeleporter.sol";
import { OrigamiOFT } from "contracts/common/omnichain/OrigamiOFT.sol";

import { TestHelperOz5, EndpointV2 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { EnforcedOptionParam } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract OrigamiOftTestBase is TestHelperOz5, OrigamiTest {
    using OptionsBuilder for bytes;

    OrigamiOFT public origamiOft_b;
    OrigamiOFT public origamiOft_c;
    OrigamiTokenTeleporter public teleporter_ttoken_a;
    OrigamiTeleportableToken public ttoken_a;

    uint32 aEid = 1;
    uint32 bEid = 2;
    uint32 cEid = 3;

    address public delegate = makeAddr("delegate");

    event MsgInspectorSet(address inspector);
    event PeerSet(uint32 eid, bytes32 peer);
    event DelegateSet(address sender, address delegate);

    function setUp() public virtual override {
        super.setUp();
        setUpEndpoints(3, LibraryType.UltraLightNode);

        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);

        vm.startPrank(origamiMultisig);
        ttoken_a = new OrigamiTeleportableToken("TOKEN_A", "TKNA", origamiMultisig);
        deal(address(ttoken_a), alice, 1000 ether, true);

        {
            _deploy();
            _wireOfts();
        }

        ttoken_a.setTeleporter(address(teleporter_ttoken_a));

        vm.stopPrank();
    }

    function _deploy() internal {
        teleporter_ttoken_a = OrigamiTokenTeleporter(
            _deployOApp(
                type(OrigamiTokenTeleporter).creationCode,
                abi.encode(origamiMultisig, address(ttoken_a), address(endpoints[aEid]), origamiMultisig)
            )
        );

        origamiOft_b = OrigamiOFT(
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

        origamiOft_c = OrigamiOFT(
            _deployOApp(
                type(OrigamiOFT).creationCode,
                abi.encode(
                    OFT.ConstructorArgs(
                        "ORIGAMI TOKEN C",
                        "ORGMC",
                        address(endpoints[cEid]),
                        origamiMultisig
                    )
                )
            )
        );
    }

    function _sendInitialTokens(address _recipient, uint256 _amount) internal {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam = SendParam(
            bEid, // send to other origami oft
            addressToBytes32(_recipient),
            _amount,
            _amount,
            options,
            "",
            ""
        );
        // get send quote
        MessagingFee memory fee = teleporter_ttoken_a.quoteSend(sendParam, false);
        // approve
        vm.startPrank(_recipient);
        ttoken_a.approve(address(teleporter_ttoken_a), _amount);
        teleporter_ttoken_a.send{value:fee.nativeFee}(sendParam, fee, payable(address(_recipient)));
        verifyPackets(bEid, addressToBytes32(address(origamiOft_b)));
    }

    function _wireOfts() private {
        // config and wire the ofts
        address[] memory ofts = new address[](3);
        ofts[0] = address(teleporter_ttoken_a);
        ofts[1] = address(origamiOft_b);
        ofts[2] = address(origamiOft_c);
        vm.startPrank(origamiMultisig);
        teleporter_ttoken_a.setPeer(bEid, addressToBytes32(address(origamiOft_b)));
        origamiOft_b.setPeer(aEid, addressToBytes32(address(teleporter_ttoken_a)));
        teleporter_ttoken_a.setPeer(cEid, addressToBytes32(address(origamiOft_c)));
        origamiOft_c.setPeer(aEid, addressToBytes32(address(teleporter_ttoken_a)));
        origamiOft_c.setPeer(bEid, addressToBytes32(address(origamiOft_b)));
        origamiOft_b.setPeer(cEid, addressToBytes32(address(origamiOft_c)));
    }

    function _removeDust(uint256 _amountLD, uint256 _vaultDecimals) internal view returns (uint256 amountLD) {
        uint256 decimalConversionRate = 10 ** (_vaultDecimals - teleporter_ttoken_a.sharedDecimals());
        return (_amountLD / decimalConversionRate) * decimalConversionRate;
    }

    function _getOptions() internal pure returns (bytes memory options) {
        options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
    }
}

contract OrigamiOftTestAdmin is OrigamiOftTestBase {

    function test_init() public view {
        {
            assertEq(origamiOft_b.name(), "ORIGAMI TOKEN B");
            assertEq(origamiOft_b.symbol(), "ORGMB");
            assertEq(origamiOft_b.owner(), origamiMultisig);
            assertEq(origamiOft_c.owner(), origamiMultisig);
            assertEq(origamiOft_c.balanceOf(bob), 0);
            assertEq(origamiOft_b.sharedDecimals(), 6);
            assertEq(origamiOft_c.sharedDecimals(), 6);
        }
       
        {
            assertEq(teleporter_ttoken_a.approvalRequired(), true);
            assertEq(teleporter_ttoken_a.token(), address(ttoken_a));
            assertEq(teleporter_ttoken_a.sharedDecimals(), 6);
            // unused function parameters
            assertEq(teleporter_ttoken_a.nextNonce(uint32(0), bytes32(0)), 0);
            assertEq(teleporter_ttoken_a.isPeer(bEid, addressToBytes32(address(origamiOft_b))), true);
            assertEq(origamiOft_b.isPeer(cEid, addressToBytes32(address(origamiOft_c))), true);
        }
    }

    function test_supportsInterface() public view {
        assertEq(origamiOft_b.supportsInterface(type(IOFT).interfaceId), true);
        assertEq(origamiOft_b.supportsInterface(type(IERC20Metadata).interfaceId), true);
        assertEq(origamiOft_b.supportsInterface(type(IERC20).interfaceId), true);
        assertEq(origamiOft_b.supportsInterface(type(IERC20Permit).interfaceId), true);
        assertEq(origamiOft_b.supportsInterface(type(EIP712).interfaceId), true);
        assertEq(origamiOft_b.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(origamiOft_b.supportsInterface(type(IOrigamiInvestment).interfaceId), false);
    }
}

contract OrigamiOftTestAccess is OrigamiOftTestBase {
    function test_access_setPeer() public {
        expectElevatedAccess();
        origamiOft_b.setPeer(cEid, addressToBytes32(address(origamiOft_c)));

        vm.startPrank(origamiMultisig);
        origamiOft_b.setPeer(cEid, addressToBytes32(address(origamiOft_c)));
    }

     function test_access_setDelegate() public {
        expectElevatedAccess();
        origamiOft_b.setDelegate(alice);

        vm.startPrank(origamiMultisig);
        origamiOft_b.setDelegate(alice);
    }

    function test_access_setMsgInspector() public {
        expectElevatedAccess();
        origamiOft_b.setMsgInspector(alice);

        vm.startPrank(origamiMultisig);
        origamiOft_b.setMsgInspector(alice);
    }

    function test_access_setEnforcedOptions() public {
        expectElevatedAccess();
        EnforcedOptionParam[] memory options;
        origamiOft_b.setEnforcedOptions(options);

        vm.startPrank(origamiMultisig);
        origamiOft_b.setEnforcedOptions(options);
    }

    function test_access_setPreCrime() public {
        expectElevatedAccess();
        origamiOft_b.setPreCrime(alice);

        vm.startPrank(origamiMultisig);
        origamiOft_b.setPreCrime(alice);
    }
}

contract OrigamiOftTestPermit is OrigamiOftTestBase {
    function test_permit() public {
        check_permit(origamiOft_b);
    }
}

contract OrigamiOftTestSend is OrigamiOftTestBase {

    function test_setPeer() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(origamiOft_b));
        emit PeerSet(cEid, addressToBytes32(address(origamiOft_c)));
        origamiOft_b.setPeer(cEid, addressToBytes32(address(origamiOft_c)));
        assertEq(origamiOft_b.isPeer(cEid, addressToBytes32(address(origamiOft_c))), true);

        vm.expectEmit(address(origamiOft_b));
        emit PeerSet(cEid, addressToBytes32(address(delegate)));
        origamiOft_b.setPeer(cEid, addressToBytes32(address(delegate)));
        assertEq(origamiOft_b.isPeer(cEid, addressToBytes32(address(origamiOft_c))), false);
        assertEq(origamiOft_b.isPeer(cEid, addressToBytes32(address(delegate))), true);
    }

    function test_setMsgInspector() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(origamiOft_b));
        emit MsgInspectorSet(alice);
        origamiOft_b.setMsgInspector(alice);
        assertEq(origamiOft_b.msgInspector(), alice);

        vm.expectEmit(address(origamiOft_b));
        emit MsgInspectorSet(bob);
        origamiOft_b.setMsgInspector(bob);
        assertEq(origamiOft_b.msgInspector(), bob);
    }

    function test_setDelegate() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(endpoints[bEid]));
        emit DelegateSet(address(origamiOft_b), delegate);
        origamiOft_b.setDelegate(delegate);
        assertEq(EndpointV2(endpoints[bEid]).delegates(address(origamiOft_b)), delegate);
    }

    function test_send_origami_oft_token() public {
        uint256 sendAmount = 11 ether;
        _sendInitialTokens(alice, sendAmount);
        uint256 aliceBalance = origamiOft_b.balanceOf(alice);
        uint256 minSendAmount = sendAmount;
        bytes memory options = _getOptions();
        SendParam memory sendParam = SendParam(
            cEid, // send to other origami oft
            addressToBytes32(bob),
            sendAmount,
            minSendAmount,
            options,
            "",
            ""
        );
        // get send quote
        MessagingFee memory fee = origamiOft_b.quoteSend(sendParam, false);
        assertEq(origamiOft_b.balanceOf(alice), aliceBalance);
        assertEq(origamiOft_c.balanceOf(alice), 0);
        assertEq(origamiOft_b.balanceOf(bob), 0);

        vm.startPrank(alice);
        origamiOft_b.send{value:fee.nativeFee}(sendParam, fee, payable(address(alice)));
        verifyPackets(cEid, addressToBytes32(address(origamiOft_c)));

        assertEq(origamiOft_c.balanceOf(bob), sendAmount);
        assertEq(origamiOft_b.balanceOf(alice), aliceBalance - sendAmount);

        // bob sends to alice
        sendAmount = 1 ether;
        sendParam = SendParam(
            bEid, // send to other origami oft
            addressToBytes32(alice),
            sendAmount,
            sendAmount,
            options,
            "",
            ""
        );
        fee = origamiOft_c.quoteSend(sendParam, false);
        aliceBalance = origamiOft_b.balanceOf(alice);
        uint256 bobBalance = origamiOft_c.balanceOf(bob);
        vm.startPrank(bob);
        origamiOft_c.send{value:fee.nativeFee}(sendParam, fee, payable(address(bob)));
        verifyPackets(bEid, addressToBytes32(address(origamiOft_b)));
        assertEq(origamiOft_b.balanceOf(alice), aliceBalance+sendAmount);
        assertEq(origamiOft_c.balanceOf(bob), bobBalance-sendAmount);
    }

    function test_send_origami_oft_token_multi() public {
        uint256 aliceBalance = ttoken_a.balanceOf(alice);
        uint256 bobBalance = ttoken_a.balanceOf(bob);
        // approve and teleport
        vm.startPrank(alice);
        ttoken_a.approve(address(teleporter_ttoken_a), aliceBalance);
        bytes memory options = _getOptions();
        uint256 sendAmount = 123 ether;
        uint256 minAmount = _removeDust(sendAmount, ttoken_a.decimals());
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(alice), // send to self
            sendAmount,
            minAmount,
            options,
            "",
            ""
        );
        MessagingFee memory fee = teleporter_ttoken_a.quoteSend(sendParam, false);
        aliceBalance = ttoken_a.balanceOf(alice);
        // from initial send in setup
        assertEq(ttoken_a.balanceOf(address(teleporter_ttoken_a)), 0);

        teleporter_ttoken_a.send{value:fee.nativeFee}(sendParam, fee, payable(address(alice)));
        verifyPackets(bEid, addressToBytes32(address(origamiOft_b)));

        assertEq(ttoken_a.balanceOf(address(teleporter_ttoken_a)), minAmount);
        assertEq(origamiOft_b.balanceOf(alice), minAmount);
        assertEq(ttoken_a.balanceOf(alice), aliceBalance-sendAmount);

        // bob sends to alice
        vm.startPrank(bob);
        ttoken_a.approve(address(teleporter_ttoken_a), bobBalance);
        sendAmount = bobBalance;
        minAmount = _removeDust(sendAmount, ttoken_a.decimals());
        sendParam = SendParam(
            bEid,
            addressToBytes32(alice), // send to alice
            sendAmount,
            minAmount,
            options,
            "",
            ""
        );
        fee = teleporter_ttoken_a.quoteSend(sendParam, false);
        uint256 teleporterBalance = ttoken_a.balanceOf(address(teleporter_ttoken_a));
        uint256 oft_b_aliceBalance = origamiOft_b.balanceOf(alice);
        teleporter_ttoken_a.send{value:fee.nativeFee}(sendParam, fee, payable(address(bob)));
        verifyPackets(bEid, addressToBytes32(address(origamiOft_b)));
        assertEq(ttoken_a.balanceOf(address(teleporter_ttoken_a)), teleporterBalance+minAmount);
        assertEq(origamiOft_b.balanceOf(alice), oft_b_aliceBalance+minAmount);
        assertEq(ttoken_a.balanceOf(bob), 0);

         // send all back to bob
        oft_b_aliceBalance = origamiOft_b.balanceOf(alice);
        teleporterBalance = ttoken_a.balanceOf(address(teleporter_ttoken_a));
        minAmount = _removeDust(oft_b_aliceBalance, origamiOft_b.decimals());
        vm.startPrank(alice);
        sendParam = SendParam(
            aEid,
            addressToBytes32(bob), // send to bob
            oft_b_aliceBalance,
            minAmount,
            options,
            "",
            ""
        );
        fee = origamiOft_b.quoteSend(sendParam, false);
        origamiOft_b.send{value:fee.nativeFee}(sendParam, fee, payable(address(alice)));
        verifyPackets(aEid, addressToBytes32(address(teleporter_ttoken_a)));
        assertEq(ttoken_a.balanceOf(address(teleporter_ttoken_a)), teleporterBalance-minAmount);
        assertEq(origamiOft_b.balanceOf(alice), 0);
        assertEq(ttoken_a.balanceOf(bob), minAmount);
    }

    function test_send_oft_between_x_chains() public {
        uint256 amount = 10 ether;
        _sendInitialTokens(alice, amount);
        uint256 aliceBalance = origamiOft_b.balanceOf(alice);
        uint256 teleporterBalance = ttoken_a.balanceOf(address(teleporter_ttoken_a));
        // alice sends to bob from chain b to chain c
        uint256 minAmount = _removeDust(amount, ttoken_a.decimals());
        SendParam memory sendParam = SendParam(
            cEid,
            addressToBytes32(bob), // send to bob
            amount,
            minAmount,
            _getOptions(),
            "",
            ""
        );
        MessagingFee memory fee = teleporter_ttoken_a.quoteSend(sendParam, false);
        origamiOft_b.send{value:fee.nativeFee}(sendParam, fee, payable(address(alice)));
        verifyPackets(cEid, addressToBytes32(address(origamiOft_c)));

        assertEq(origamiOft_b.balanceOf(address(alice)), aliceBalance-amount);
        assertEq(origamiOft_b.balanceOf(bob), 0);
        assertEq(origamiOft_c.balanceOf(bob), minAmount);
        // didn't change with locker
        assertEq(teleporterBalance, ttoken_a.balanceOf(address(teleporter_ttoken_a)));
        assertEq(origamiOft_b.balanceOf(address(teleporter_ttoken_a)), 0);
        assertEq(origamiOft_c.balanceOf(address(teleporter_ttoken_a)), 0);
    }
}