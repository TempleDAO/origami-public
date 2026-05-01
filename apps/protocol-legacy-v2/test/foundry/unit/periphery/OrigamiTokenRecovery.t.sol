pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiTokenRecovery } from "contracts/periphery/OrigamiTokenRecovery.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IOrigamiHOhmArbBot } from "contracts/interfaces/external/olympus/IOrigamiHOhmArbBot.sol";

contract OrigamiTokenRecoveryTest is OrigamiTest {
    OrigamiTokenRecovery internal tokenRecovery;

    address internal constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address internal constant sUSDS = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    IOrigamiHOhmArbBot internal constant ARB_BOT_V1 = IOrigamiHOhmArbBot(0xE682946182E5780843D5f6d2C023B8B89765D0fd);
    address internal constant ORIGAMI_MULTISIG = 0x781B4c57100738095222bd92D37B07ed034AB696;

    function setUp() public {
        fork("mainnet", 22667738);
        tokenRecovery = new OrigamiTokenRecovery(ORIGAMI_MULTISIG);
    }

    function test_recoverToken_access() public {
        expectElevatedAccess();
        tokenRecovery.recoverToken(USDS, address(ARB_BOT_V1), ORIGAMI_MULTISIG, 1e18);
    }

    function test_recoverToken() public {
        vm.startPrank(ORIGAMI_MULTISIG);
        address arbBotAddr = address(ARB_BOT_V1);
        uint256 usdsBal = IERC20(USDS).balanceOf(arbBotAddr);
        assertGt(usdsBal, 0);
        uint256 susdsBal = IERC20(sUSDS).balanceOf(arbBotAddr);
        assertGt(susdsBal, 0);

        ARB_BOT_V1.approveToken(IERC20(USDS), address(tokenRecovery), type(uint256).max);
        ARB_BOT_V1.approveToken(IERC20(sUSDS), address(tokenRecovery), type(uint256).max);
        
        tokenRecovery.recoverToken(USDS, arbBotAddr, ORIGAMI_MULTISIG, usdsBal);
        tokenRecovery.recoverToken(sUSDS, arbBotAddr, ORIGAMI_MULTISIG, susdsBal);

        assertEq(IERC20(USDS).balanceOf(arbBotAddr), 0);
        assertEq(IERC20(USDS).balanceOf(ORIGAMI_MULTISIG), usdsBal);

        assertEq(IERC20(sUSDS).balanceOf(arbBotAddr), 0);
        assertEq(IERC20(sUSDS).balanceOf(ORIGAMI_MULTISIG), susdsBal);
    }
}
