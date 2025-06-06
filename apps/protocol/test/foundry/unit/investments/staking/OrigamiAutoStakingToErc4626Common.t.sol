pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

import { IInfraredVault } from "contracts/interfaces/external/infrared/IInfraredVault.sol";
import { IMultiRewards } from "contracts/interfaces/external/staking/IMultiRewards.sol";
import { IOrigamiAutoStaking } from "contracts/interfaces/investments/staking/IOrigamiAutoStaking.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiAutoStakingToErc4626 } from "contracts/investments/staking/OrigamiAutoStakingToErc4626.sol";
import { OrigamiAutoStakingFactory } from "contracts/factories/staking/OrigamiAutoStakingFactory.sol";
import { OrigamiAutoStakingToErc4626Deployer } from "contracts/factories/staking/OrigamiAutoStakingToErc4626Deployer.sol";
import { OrigamiSwapperWithCallbackDeployer } from "contracts/factories/swappers/OrigamiSwapperWithCallbackDeployer.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { OrigamiSwapperWithCallback } from "contracts/common/swappers/OrigamiSwapperWithCallback.sol";
import { DummyDexRouter } from "contracts/test/common/swappers/DummyDexRouter.sol";

contract OrigamiAutoStakingToErc4626Common is OrigamiTest {
    OrigamiAutoStakingToErc4626 internal ohmHoneyAutoStaking;
    OrigamiAutoStakingToErc4626 internal wberaHoneyAutoStaking;
    OrigamiAutoStakingFactory internal vaultFactory;
    OrigamiAutoStakingToErc4626Deployer internal vaultDeployer;
    OrigamiSwapperWithCallbackDeployer internal swapperDeployer;

    DummyDexRouter internal router;
    OrigamiSwapperWithCallback internal swapper;

    IERC20Metadata internal constant WBERA = IERC20Metadata(0x6969696969696969696969696969696969696969);
    IERC20Metadata internal constant OHM_HONEY = IERC20Metadata(0x98bDEEde9A45C28d229285d9d6e9139e9F505391);
    IERC20Metadata internal constant WBERA_HONEY = IERC20Metadata(0x2c4a603A2aA5596287A06886862dc29d56DbC354);
    IERC20Metadata internal constant IBGT = IERC20Metadata(0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b);
    IERC20Metadata internal constant HONEY = IERC20Metadata(0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce);
    IERC20Metadata internal constant USDC = IERC20Metadata(0x549943e04f40284185054145c6E4e9568C1D3241);
    IInfraredVault internal constant IR_OHM_HONEY = IInfraredVault(0xa57Cb177Beebc35A1A26A286951a306d9B752524);
    IInfraredVault internal constant IR_WBERA_HONEY = IInfraredVault(0xe2d8941dfb85435419D90397b09D18024ebeef2C);
    IERC4626 internal constant ORI_BGT = IERC4626(0x69f1E971257419B1E9C405A553f252c64A29A30a);

    IERC20Metadata internal constant BYUSD_HONEY = IERC20Metadata(0xdE04c469Ad658163e2a5E860a03A86B52f6FA8C8);
    IInfraredVault internal constant IR_BYUSD_HONEY = IInfraredVault(0xbbB228B0D7D83F86e23a5eF3B1007D0100581613);

    DummyMintableToken internal OTHER_REWARD_TOKEN;

    uint96 internal constant REWARDS_DURATION = 10 minutes;

    uint256 internal constant BERACHAIN_FORK_BLOCK_NUMBER = 3088840;

    uint16 internal constant DEFAULT_FEE_BPS = 100; // 1%

    function setUpContracts() internal {
        vm.label(address(WBERA), "WBERA");
        vm.label(address(OHM_HONEY), "OHM_HONEY");
        vm.label(address(WBERA_HONEY), "WBERA_HONEY");
        vm.label(address(ORI_BGT), "oriBGT");
        vm.label(address(IBGT), "iBGT");
        vm.label(address(HONEY), "HONEY");
        vm.label(address(USDC), "USDC");
        vm.label(address(IR_OHM_HONEY), "IR_OHM_HONEY");
        vm.label(address(IR_WBERA_HONEY), "IR_WBERA_HONEY");

        OTHER_REWARD_TOKEN = new DummyMintableToken(origamiMultisig, "REWARD", "REWARD", 18);
        vm.label(address(OTHER_REWARD_TOKEN), "OTHER_REWARD_TOKEN");

        // deploy auto staker contracts
        vaultDeployer = new OrigamiAutoStakingToErc4626Deployer(address(IBGT), address(ORI_BGT));
        vaultFactory = new OrigamiAutoStakingFactory(
            origamiMultisig,
            address(vaultDeployer),
            feeCollector,
            REWARDS_DURATION,
            address(swapperDeployer)
        );

        vm.startPrank(origamiMultisig);
        IOrigamiAutoStaking vault = vaultFactory.registerVault(
            address(WBERA_HONEY),
            address(IR_WBERA_HONEY),
            DEFAULT_FEE_BPS,
            address(0),
            new address[](0)
        );
        OrigamiAutoStakingToErc4626(address(vault)).acceptOwner();

        wberaHoneyAutoStaking = OrigamiAutoStakingToErc4626(address(vault));
        vault = vaultFactory.registerVault(
            address(OHM_HONEY),
            address(IR_OHM_HONEY),
            DEFAULT_FEE_BPS,
            address(0),
            new address[](0)
        );
        OrigamiAutoStakingToErc4626(address(vault)).acceptOwner();
        ohmHoneyAutoStaking = OrigamiAutoStakingToErc4626(address(vault));

        router = new DummyDexRouter();
        swapper = new OrigamiSwapperWithCallback(origamiMultisig);
        swapper.whitelistRouter(address(router), true);
        doMint(IBGT, address(router), 1_000_000e18);

        OTHER_REWARD_TOKEN.addMinter(origamiMultisig);
        vm.stopPrank();
    }

    function addReward(
        address stakingToken,
        address rewardToken,
        uint256 rewardsDuration,
        uint256 feeBps
    ) internal {
        (address vault,) = vaultFactory.currentVaultForAsset(stakingToken);
        vm.expectEmit(vault);
        emit IMultiRewards.RewardStored(rewardToken, rewardsDuration);
        IOrigamiAutoStaking(vault).addReward(rewardToken, rewardsDuration, feeBps);
    }

    function removeReward(
        address stakingToken,
        address rewardToken
    ) internal {
        (address vault,) = vaultFactory.currentVaultForAsset(stakingToken);
        vm.expectEmit(vault);
        emit IMultiRewards.RewardRemoved(rewardToken);
        IOrigamiAutoStaking(vault).removeReward(rewardToken);
    }
}
