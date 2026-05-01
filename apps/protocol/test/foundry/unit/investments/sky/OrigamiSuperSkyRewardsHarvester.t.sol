pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiSuperSkyRewardsHarvester } from "contracts/investments/sky/OrigamiSuperSkyRewardsHarvester.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IOrigamiSuperSkyManager } from "contracts/interfaces/investments/sky/IOrigamiSuperSkyManager.sol";
import { OrigamiCowSwapper } from "contracts/common/swappers/OrigamiCowSwapper.sol";
import { IOrigamiSuperSkyManager } from "contracts/interfaces/investments/sky/IOrigamiSuperSkyManager.sol";

contract OrigamiSuperSkyRewardsHarvesterTest is OrigamiTest {
    OrigamiSuperSkyRewardsHarvester internal harvester;

    IOrigamiSuperSkyManager internal constant MANAGER =
        IOrigamiSuperSkyManager(0xc522335fBfe21d7A7d1135eb0E016a89DA49dC9e);
    OrigamiCowSwapper internal constant COW_SWAPPER_3 = OrigamiCowSwapper(0x25dD72CC1dE50e963948e464c09AeBA0d9312349);
    IERC20 internal constant SKY_TOKEN = IERC20(0x56072C95FAA701256059aa122697B133aDEd9279);
    IERC20 internal constant USDS_TOKEN = IERC20(0xdC035D45d973E3EC169d2276DDab16f1e407384F);
    IERC20 internal constant SPK_TOKEN = IERC20(0xc20059e0317DE91738d13af027DfC4a50781b066);

    address internal constant MSIG = 0x781B4c57100738095222bd92D37B07ed034AB696;

    function setUp() public virtual {
        fork("mainnet", 23_728_142);
        harvester = new OrigamiSuperSkyRewardsHarvester(address(MANAGER));

        vm.prank(MSIG);
        setExplicitAccess(COW_SWAPPER_3, address(harvester), OrigamiCowSwapper.recoverToken.selector, true);
    }

    function addSkyHarvest() internal {
        vm.startPrank(MSIG);
        MANAGER.addFarm(0xB44C2Fb4181D7Cb06bdFf34A46FdFe4a259B40Fc, 0);
        MANAGER.switchFarms(3);
        skip(1 days);
    }

    function test_claimFarmRewards_nothing() public {
        assertEq(MANAGER.unallocatedAssets(), 0);
        assertEq(MANAGER.stakedBalance(), 51_317_429.803524435504005898e18);
        assertEq(USDS_TOKEN.balanceOf(address(COW_SWAPPER_3)), 859.991389573336908244e18);
        assertEq(SPK_TOKEN.balanceOf(address(COW_SWAPPER_3)), 12_077.12240151096704631e18);
        assertEq(SKY_TOKEN.balanceOf(address(COW_SWAPPER_3)), 0);

        uint32[] memory farms = new uint32[](3);
        farms[0] = 1;
        farms[1] = 2;
        farms[2] = 3;
        harvester.claimFarmRewards(farms, alice);

        assertEq(MANAGER.unallocatedAssets(), 0);
        assertEq(MANAGER.stakedBalance(), 51_317_429.803524435504005898e18);
        assertEq(USDS_TOKEN.balanceOf(address(COW_SWAPPER_3)), 1396.088108315613841539e18);
        assertEq(SPK_TOKEN.balanceOf(address(COW_SWAPPER_3)), 12_077.12240151096704631e18);
        assertEq(SKY_TOKEN.balanceOf(address(COW_SWAPPER_3)), 0);
    }

    function test_claimFarmRewards_withSky() public {
        uint256 existingStakedBalance = MANAGER.stakedBalance();
        assertEq(MANAGER.unallocatedAssets(), 0);
        assertEq(existingStakedBalance, 51_317_429.803524435504005898e18);
        assertEq(USDS_TOKEN.balanceOf(address(COW_SWAPPER_3)), 859.991389573336908244e18);
        assertEq(SPK_TOKEN.balanceOf(address(COW_SWAPPER_3)), 12_077.12240151096704631e18);
        assertEq(SKY_TOKEN.balanceOf(address(COW_SWAPPER_3)), 0);

        addSkyHarvest();

        uint32[] memory farms = new uint32[](3);
        farms[0] = 1;
        farms[1] = 2;
        farms[2] = 3;

        uint256 expectedNewSky = 24_239.788591122404667337e18;
        vm.expectEmit(address(MANAGER));
        emit IOrigamiSuperSkyManager.Reinvest(expectedNewSky);
        harvester.claimFarmRewards(farms, alice);

        assertEq(MANAGER.unallocatedAssets(), 0);
        assertEq(MANAGER.stakedBalance(), existingStakedBalance + expectedNewSky);
        assertEq(USDS_TOKEN.balanceOf(address(COW_SWAPPER_3)), 1396.088108315613841539e18);
        assertEq(SPK_TOKEN.balanceOf(address(COW_SWAPPER_3)), 12_077.12240151096704631e18);
        assertEq(SKY_TOKEN.balanceOf(address(COW_SWAPPER_3)), 0);
    }
}
