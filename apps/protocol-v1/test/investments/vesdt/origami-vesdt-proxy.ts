import { ethers } from "hardhat";
import { BigNumber, Signer } from "ethers";
import { expect } from "chai";
import { 
    OrigamiVeSDTProxy, OrigamiVeSDTProxy__factory, 
    IStakeDao_WalletWhitelist__factory,
    MintableToken, MintableToken__factory,
    IStakeDao_ClaimRewards,
    IStakeDao_VeSDT, IStakeDao_VeSDT__factory,
    IStakeDao_VeSDTRewardsDistributor, IStakeDao_VeSDTRewardsDistributor__factory,
    IERC20, IERC20__factory, IStakeDao_LiquidityGaugeV4__factory, 
    IStakeDao_GaugeController__factory, 
    ISnapshotDelegator__factory, 
    IStakeDao_VeBoost,
    IStakeDao_VeBoost__factory, 
} from "../../../typechain";
import { 
    shouldRevertNotGov,
    forkMainnet,
    deployUupsProxy,
    impersonateSigner,
    blockTimestamp,
    shouldRevertNotOperator,
    mineForwardSeconds,
    expectApproxEqRel,
    ZERO_ADDRESS,
    upgradeUupsProxy,
} from "../../helpers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";

const mainnetAddresses = {
    vesdt: '0x0C30476f66034E11782938DF8e4384970B6c9e8a',
    sdt: '0x73968b9a57c6E53d41345FD57a6E6ae27d6CDB2F',
    veSDTRewardsDistributor: '0x29f3dd38dB24d3935CF1bf841e6b2B461A3E5D92',
    sdFRAX3CRV_f: '0x5af15DA84A4a6EDf2d9FA6720De921E1026E37b7', // The reward token from staking veSDT
    gaugeRewardsClaimer: '0x633120100e108F03aCe79d6C78Aac9a56db1be0F',
    sdtLockerGaugeController: '0x75f8f7fa4b6DA6De9F4fE972c811b778cefce882', 
    sdtStrategyGaugeController: '0x3F3F0776D411eb97Cfa4E3eb25F33c01ca4e7Ca8',
    snapshotDelegateRegistry: '0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446',
    veBoost: '0x47B3262C96BB55A8D2E4F8E3Fed29D2eAB6dB6e9',
    whitelist: '0x37E8386602d9EBEa2c56dd11d8E142290595f1b5',

    // https://lockers.stakedao.org/lockers/crv
    sdCRV_gauge: '0x7f50786A0b15723D741727882ee99a0BF34e3466',

    // https://lockers.stakedao.org/lockers/angle
    sdANGLE_gauge: '0xE55843a90672f7d8218285e51EE8fF8E233F35d5',

    // https://lockers.stakedao.org/strategies/factory-v2-109
    sdsdCRVCRV_f_gauge: '0x531167aBE95375Ec212f2b5417EF05a9953410C1',

    // https://lockers.stakedao.org/strategies/factory-v2-101
    sdsdAGAG_f_gauge: '0x1E3923A498de30ff8C5Ac8bfAb1De9AFa58fDE5d',
};

const TWO_YEARS = 86400 * 365 * 2;
const FOUR_YEARS = 86400 * 365 * 4;

describe("Origami VeSDT Proxy", async () => {
    let owner: Signer;
    let operator: Signer;
    let alice: Signer;
    let gov: Signer;

    let proxy: OrigamiVeSDTProxy;
    let veSDT: IStakeDao_VeSDT;
    let sdt: MintableToken;
    let veSDTRewardsDistributor: IStakeDao_VeSDTRewardsDistributor;
    let sdFRAX3CRVf: IERC20;
    let veBoost: IStakeDao_VeBoost;
    
    before( async () => {
        [owner, operator, alice, gov] = await ethers.getSigners();
    });

    async function setup() {
        forkMainnet(16474660, process.env.MAINNET_RPC_URL);

        proxy = await deployUupsProxy(
            new OrigamiVeSDTProxy__factory(gov),
            [
                mainnetAddresses.vesdt,
                mainnetAddresses.sdt,
            ],
            await gov.getAddress(),
            mainnetAddresses.veSDTRewardsDistributor,
            mainnetAddresses.gaugeRewardsClaimer,
            mainnetAddresses.sdtLockerGaugeController,
            mainnetAddresses.sdtStrategyGaugeController,
            mainnetAddresses.snapshotDelegateRegistry,
            mainnetAddresses.veBoost
        );
        await proxy.addOperator(operator.getAddress());

        const whitelist = IStakeDao_WalletWhitelist__factory.connect(mainnetAddresses.whitelist, owner);
        const whitelistAdmin = await impersonateSigner(await whitelist.admin());
        await whitelist.connect(whitelistAdmin).approveWallet(proxy.address);

        veSDT = IStakeDao_VeSDT__factory.connect(mainnetAddresses.vesdt, owner);
        sdt = MintableToken__factory.connect(mainnetAddresses.sdt, owner);
        veSDTRewardsDistributor = IStakeDao_VeSDTRewardsDistributor__factory.connect(mainnetAddresses.veSDTRewardsDistributor, owner);
        sdFRAX3CRVf = IERC20__factory.connect(mainnetAddresses.sdFRAX3CRV_f, owner);
        veBoost = IStakeDao_VeBoost__factory.connect(mainnetAddresses.veBoost, owner);

        return {
            proxy,
            veSDT,
            sdt,
            veSDTRewardsDistributor,
            sdFRAX3CRVf,
            veBoost,
        }
    }

    beforeEach(async () => {
        ({
            proxy,
            veSDT,
            sdt,
            veSDTRewardsDistributor,
            sdFRAX3CRVf,
            veBoost,
        } = await loadFixture(setup));
    });

    const roundLockEndToWeek = (unlockTime: number) => {
        const week = BigNumber.from(86400*7);
        return BigNumber.from(unlockTime).div(week).mul(week);
    }

    const pullSDT = async (to: string, amount: BigNumber) => {
        const sdtWhale = await impersonateSigner("0xC5d3D004a223299C4F95Bb702534C14A32e8778c");
        await sdt.connect(sdtWhale).transfer(to, amount);
    }

    const lockVeSdt = async (amount: BigNumber, lockDurationSecs: number) => {
        await pullSDT(proxy.address, amount);

        const now = await blockTimestamp();
        const unlockTime = now + lockDurationSecs;

        await expect(proxy.connect(operator).veSDTCreateLock(amount, unlockTime))
            .to.emit(veSDT, "Deposit")
            .withArgs(proxy.address, amount, roundLockEndToWeek(unlockTime), 1, anyValue);
    }

    describe("Owner Only", async () => {
        it("initialize", async () => {
            expect(await proxy.veSDT()).eq(mainnetAddresses.vesdt);
            expect(await proxy.sdtToken()).eq(mainnetAddresses.sdt);
            expect(await proxy.veSDTRewardsDistributor()).eq(mainnetAddresses.veSDTRewardsDistributor);
            expect(await proxy.gaugeRewardsClaimer()).eq(mainnetAddresses.gaugeRewardsClaimer);
            expect(await proxy.sdtLockerGaugeController()).eq(mainnetAddresses.sdtLockerGaugeController);
            expect(await proxy.sdtStrategiesGaugeController()).eq(mainnetAddresses.sdtStrategyGaugeController);
            expect(await proxy.snapshotDelegateRegistry()).eq(mainnetAddresses.snapshotDelegateRegistry);
        });

        it("admin", async () => {
            await shouldRevertNotGov(proxy, proxy.connect(alice).addOperator(alice.getAddress()));
            await shouldRevertNotGov(proxy, proxy.connect(alice).removeOperator(alice.getAddress()));
            await shouldRevertNotGov(proxy, proxy.connect(alice).setSDTLockerGaugeController(alice.getAddress()));
            await shouldRevertNotGov(proxy, proxy.connect(alice).setSDTStrategiesGaugeController(alice.getAddress()));
            await shouldRevertNotGov(proxy, proxy.connect(alice).setVeSDTRewardsDistributor(alice.getAddress()));
            await shouldRevertNotGov(proxy, proxy.connect(alice).setSnapshotDelegateRegistry(alice.getAddress()));
            await shouldRevertNotGov(proxy, proxy.connect(alice).setVeBoost(alice.getAddress()));
            await shouldRevertNotGov(proxy, proxy.connect(alice).setGaugeRewardsClaimer(alice.getAddress()));

            // Happy paths
            await proxy.addOperator(operator.getAddress());
            await proxy.setSDTLockerGaugeController(alice.getAddress());
            await proxy.setSDTStrategiesGaugeController(alice.getAddress());
            await proxy.setVeSDTRewardsDistributor(alice.getAddress());
            await proxy.setSnapshotDelegateRegistry(alice.getAddress());
            await proxy.setVeBoost(alice.getAddress());
            await proxy.setGaugeRewardsClaimer(alice.getAddress());
            await proxy.removeOperator(operator.getAddress());
        });

        it("should set SDT Locker Gauge Controller", async () => {
            await expect(proxy.setSDTLockerGaugeController(ZERO_ADDRESS))
                .to.be.revertedWithCustomError(proxy, "InvalidAddress");
            await expect(proxy.setSDTLockerGaugeController(alice.getAddress()))
                .to.emit(proxy, "SDTLockerGaugeControllerSet")
                .withArgs(await alice.getAddress());
            expect(await proxy.sdtLockerGaugeController()).eq(await alice.getAddress());
        });

        it("should set SDT Strategies Gauge Controller", async () => {
            await expect(proxy.setSDTStrategiesGaugeController(ZERO_ADDRESS))
                .to.be.revertedWithCustomError(proxy, "InvalidAddress");
            await expect(proxy.setSDTStrategiesGaugeController(alice.getAddress()))
                .to.emit(proxy, "SDTStrategiesGaugeControllerSet")
                .withArgs(await alice.getAddress());
            expect(await proxy.sdtStrategiesGaugeController()).eq(await alice.getAddress());
        });

        it("should set veSDT Rewards Distributor", async () => {
            await expect(proxy.setVeSDTRewardsDistributor(ZERO_ADDRESS))
                .to.be.revertedWithCustomError(proxy, "InvalidAddress");
            await expect(proxy.setVeSDTRewardsDistributor(alice.getAddress()))
                .to.emit(proxy, "VeSDTRewardsDistributorSet")
                .withArgs(await alice.getAddress());
            expect(await proxy.veSDTRewardsDistributor()).eq(await alice.getAddress());
        });

        it("should set Delegate Registry", async () => {
            await expect(proxy.setSnapshotDelegateRegistry(ZERO_ADDRESS))
                .to.be.revertedWithCustomError(proxy, "InvalidAddress");
            await expect(proxy.setSnapshotDelegateRegistry(alice.getAddress()))
                .to.emit(proxy, "SnapshotDelegateRegistrySet")
                .withArgs(await alice.getAddress());
            expect(await proxy.snapshotDelegateRegistry()).eq(await alice.getAddress());
        });

        it("should set VeBoost", async () => {
            await expect(proxy.setVeBoost(ZERO_ADDRESS))
                .to.be.revertedWithCustomError(proxy, "InvalidAddress");
            await expect(proxy.setVeBoost(alice.getAddress()))
                .to.emit(proxy, "VeBoostSet")
                .withArgs(await alice.getAddress());
            expect(await proxy.veBoost()).eq(await alice.getAddress());
        });

        it("should set Gauge Rewards Claimer", async () => {
            await expect(proxy.setGaugeRewardsClaimer(ZERO_ADDRESS))
                .to.be.revertedWithCustomError(proxy, "InvalidAddress");
            await expect(proxy.setGaugeRewardsClaimer(alice.getAddress()))
                .to.emit(proxy, "GaugeRewardsClaimerSet")
                .withArgs(await alice.getAddress());
            expect(await proxy.gaugeRewardsClaimer()).eq(await alice.getAddress());
        });

        it("should upgrade()", async () => {
            await expect(
                upgradeUupsProxy(
                    proxy.address, 
                    [
                        mainnetAddresses.vesdt,
                        mainnetAddresses.sdt,
                    ],
                    new OrigamiVeSDTProxy__factory(owner)
                )
            ).to.revertedWithCustomError(proxy, "NotGovernor");

            // Upgrade the contract
            await upgradeUupsProxy(
                proxy.address, [
                    mainnetAddresses.vesdt,
                    mainnetAddresses.sdt,
                ],
                new OrigamiVeSDTProxy__factory(gov)
            );

            // Check the new contract storage after upgrading it.
            expect(await proxy.gaugeRewardsClaimer()).eq(mainnetAddresses.gaugeRewardsClaimer);
        });

    });

    describe("veSDT", async () => {
        it("admin", async () => {
            await shouldRevertNotOperator(proxy.connect(alice).veSDTCreateLock(100, 86400), proxy, alice);
            await shouldRevertNotOperator(proxy.connect(alice).veSDTIncreaseAmount(100), proxy, alice);
            await shouldRevertNotOperator(proxy.connect(alice).veSDTIncreaseUnlockTime(86400), proxy, alice);
            await shouldRevertNotOperator(proxy.connect(alice).veSDTWithdraw(alice.getAddress()), proxy, alice);
            await shouldRevertNotOperator(proxy.connect(alice).veSDTClaimRewards(alice.getAddress()), proxy, alice);
    
            // Happy access paths
            await expect(proxy.connect(operator).veSDTCreateLock(100, 86400))
                .to.be.revertedWith('Can only lock until time in the future');
            await expect(proxy.connect(operator).veSDTIncreaseUnlockTime(86400))
                .to.be.revertedWith('Lock expired');
            await proxy.connect(operator).veSDTWithdraw(alice.getAddress());
            await proxy.connect(operator).veSDTClaimRewards(alice.getAddress());
        });

        it("should create lock", async () => {
            const amount = ethers.utils.parseEther("100");
            const lockDuration = TWO_YEARS;
            await lockVeSdt(amount, lockDuration);
            const expectedExpiry = roundLockEndToWeek(await blockTimestamp() + lockDuration);

            const lockedBal = await proxy.veSDTLocked();
            const directLockedBal = await veSDT.locked(proxy.address);
            expect(lockedBal).deep.eq(directLockedBal);
            expect(lockedBal.amount).eq(amount);
            expect(lockedBal.end).eq(expectedExpiry);
        });

        it("should increase amount", async () => {
            const amount = ethers.utils.parseEther("100");
            const lockDuration = TWO_YEARS;
            await lockVeSdt(amount, lockDuration);
            const lockedBal = await proxy.veSDTLocked();

            const increase = amount.div(2);
            await pullSDT(proxy.address, increase);

            await expect(proxy.connect(operator).veSDTIncreaseAmount(increase))
                .to.emit(veSDT, "Deposit")
                .withArgs(proxy.address, increase, lockedBal.end, 2, anyValue);

            const finalLockedBal = await proxy.veSDTLocked();
            expect(finalLockedBal.amount.sub(lockedBal.amount)).eq(increase);
            expect(finalLockedBal.end).eq(lockedBal.end);
        });

        it("should increase unlock time", async () => {
            const amount = ethers.utils.parseEther("100");
            const lockDuration = TWO_YEARS;
            await lockVeSdt(amount, lockDuration);
            const lockedBal = await proxy.veSDTLocked();

            const newUnlockTime = await blockTimestamp() + FOUR_YEARS;

            await expect(proxy.connect(operator).veSDTIncreaseUnlockTime(newUnlockTime))
                .to.emit(veSDT, "Deposit")
                .withArgs(proxy.address, 0, roundLockEndToWeek(newUnlockTime), 3, anyValue);

            const finalLockedBal = await proxy.veSDTLocked();
            expect(finalLockedBal.amount).eq(lockedBal.amount);
            expect(finalLockedBal.end).eq(roundLockEndToWeek(newUnlockTime));
        });

        it("should withdraw to alice", async () => {
            const amount = ethers.utils.parseEther("100");
            const lockDuration = TWO_YEARS;
            await lockVeSdt(amount, lockDuration);

            // Can't withdraw an unexpired lock
            await expect(proxy.connect(operator).veSDTWithdraw(alice.getAddress()))
                .to.revertedWith("The lock didn't expire");

            await mineForwardSeconds(lockDuration+1);
            await expect(proxy.connect(operator).veSDTWithdraw(alice.getAddress()))
                .to.emit(proxy, "VeSDTWithdrawn")
                .withArgs(await alice.getAddress(), amount);

            // Alice gets the SDT, proxy has no locks left.
            expect(await sdt.balanceOf(alice.getAddress())).eq(amount);
            const lockedBal = await proxy.veSDTLocked();
            expect(lockedBal.amount).eq(0);
            expect(lockedBal.end).eq(0);
        });

        it("should withdraw to proxy", async () => {
            const amount = ethers.utils.parseEther("100");
            const lockDuration = TWO_YEARS;
            await lockVeSdt(amount, lockDuration);

            await mineForwardSeconds(lockDuration+1);
            await expect(proxy.connect(operator).veSDTWithdraw(proxy.address))
                .to.emit(proxy, "VeSDTWithdrawn")
                .withArgs(proxy.address, amount);

            // Proxy gets the SDT, proxy has no locks left.
            expect(await sdt.balanceOf(proxy.address)).eq(amount);
            const lockedBal = await proxy.veSDTLocked();
            expect(lockedBal.amount).eq(0);
            expect(lockedBal.end).eq(0);
        });

        it("should get balance of as voting power", async () => {
            const amount = ethers.utils.parseEther("100");
            const lockDuration = TWO_YEARS;
            await lockVeSdt(amount, lockDuration);

            // The actual voting power is value * (unlock time / max lock time)
            // Slightly less than where it started because an extra second has passed.
            const expectedVotingPower = amount.mul(lockDuration).div(FOUR_YEARS);
            const actualVotingPower = await proxy.veSDTVotingBalance();

            const tolerance = ethers.utils.parseEther("0.0005"); // 0.05%
            expectApproxEqRel(actualVotingPower, expectedVotingPower, tolerance);
        });

        it("should get total supply of voting power", async () => {
            const bal = await proxy.totalVeSDTSupply();
            const directBal = await veSDT["totalSupply()"]();
            expect(bal).eq(directBal);
        });

        it("should get veSDT locked summary", async () => {
            const amount = ethers.utils.parseEther("100");
            const lockDuration = TWO_YEARS;
            await lockVeSdt(amount, lockDuration);

            const lockedBal = await proxy.veSDTLocked();
            const directLockedBal = await veSDT.locked(proxy.address);
            expect(lockedBal).deep.eq(directLockedBal);
            expect(lockedBal.amount).eq(amount);
            expect(lockedBal.end).eq(roundLockEndToWeek(await blockTimestamp() + lockDuration));
        });

        const claimRewards = async (expectClaim: boolean, account: string) => {
            const rewardsBefore = await sdFRAX3CRVf.balanceOf(account);
            if (expectClaim) {
                await expect(proxy.connect(operator).veSDTClaimRewards(account))
                    .to.emit(proxy, "VeSDTRewardsClaimed")
                    .withArgs(account, anyValue, sdFRAX3CRVf.address);
            } else {
                await expect(proxy.connect(operator).veSDTClaimRewards(account))
                    .to.not.emit(proxy, "VeSDTRewardsClaimed");
            }
            const rewardsAfter = await sdFRAX3CRVf.balanceOf(account);
            return rewardsAfter.sub(rewardsBefore);
        }

        const checkClaim = async (account: string) => {
            const amount = ethers.utils.parseEther("100");
            const lockDuration = TWO_YEARS;
            await lockVeSdt(amount, lockDuration);

            // Nothing to claim immediately.
            const amountClaimed = await claimRewards(false, account);
            expect(amountClaimed).eq(0);

            await mineForwardSeconds(86400*14);

            // Fund the rewards distributor with some extra tokens to pay out.
            const sdFRAX3CRVfWhale = await impersonateSigner("0xc5d3d004a223299c4f95bb702534c14a32e8778c");
            await sdFRAX3CRVf.connect(sdFRAX3CRVfWhale).transfer(veSDTRewardsDistributor.address, sdFRAX3CRVf.balanceOf(sdFRAX3CRVfWhale.getAddress()));

            const amountClaimed2 = await claimRewards(true, account);
            const tolerance = ethers.utils.parseEther("0.01"); // 1%
            expectApproxEqRel(amountClaimed2, ethers.utils.parseEther("0.0423"), tolerance);
        }

        it("should claim to alice", async () => {
            await checkClaim(await alice.getAddress());
        });

        it("should claim to proxy", async () => {
            await checkClaim(proxy.address);
        });
    });

    describe("sdToken Liquid Lockers", async () => {
        it("admin", async () => {
            await shouldRevertNotOperator(proxy.connect(alice).claimGaugeRewards([mainnetAddresses.sdCRV_gauge], alice.getAddress()), proxy, alice);
            const lockStatus: IStakeDao_ClaimRewards.LockStatusStruct = {
                locked: [true, true, true],
                staked: [true, true, true],
                lockSDT: false,
            }
            await shouldRevertNotOperator(proxy.connect(alice).claimAndLockGaugeRewards([mainnetAddresses.sdCRV_gauge], lockStatus, alice.getAddress()), proxy, alice);
            await shouldRevertNotOperator(proxy.connect(alice).voteForSDTLockers(
                [mainnetAddresses.sdCRV_gauge, mainnetAddresses.sdANGLE_gauge], 
                [5000, 5000]
            ), proxy, alice);
            await shouldRevertNotOperator(proxy.connect(alice).voteForSDTStrategies(
                [mainnetAddresses.sdsdCRVCRV_f_gauge, mainnetAddresses.sdsdAGAG_f_gauge], 
                [5000, 5000]
            ), proxy, alice);
            
            // Happy access paths
            await proxy.connect(operator).claimGaugeRewards([mainnetAddresses.sdCRV_gauge], alice.getAddress());
            await proxy.connect(operator).claimAndLockGaugeRewards([mainnetAddresses.sdCRV_gauge], lockStatus, alice.getAddress());
            await expect(proxy.connect(operator).voteForSDTLockers(
                [mainnetAddresses.sdCRV_gauge, mainnetAddresses.sdANGLE_gauge], 
                [5000, 5000]
            )).to.be.revertedWith('Your token lock expires too soon');
            await expect(proxy.connect(operator).voteForSDTStrategies(
                [mainnetAddresses.sdsdCRVCRV_f_gauge, mainnetAddresses.sdsdAGAG_f_gauge], 
                [5000, 5000]
            )).to.be.revertedWith('Your token lock expires too soon');
        });

        async function getGaugeTokens() {
            const allRewardTokens = [];
            const sdCRV_gauge = IStakeDao_LiquidityGaugeV4__factory.connect(mainnetAddresses.sdCRV_gauge, owner);
            {
                const sdCRVWhale = await impersonateSigner('0xb0e83C2D71A991017e0116d58c5765Abc57384af');
                const amount = ethers.utils.parseEther("100");
                await IERC20__factory.connect(mainnetAddresses.sdCRV_gauge, owner)
                    .connect(sdCRVWhale)
                    .transfer(proxy.address, amount);

                const rewardTokenCount = (await sdCRV_gauge.reward_count()).toNumber();
                for (let i=0; i < rewardTokenCount; ++i) {
                    allRewardTokens.push(await sdCRV_gauge.reward_tokens(i));
                }        
            }

            const sdsdCRVCRV_f_gauge = IStakeDao_LiquidityGaugeV4__factory.connect(mainnetAddresses.sdsdCRVCRV_f_gauge, owner);
            {
                const whale = await impersonateSigner('0x7a16fF8270133F063aAb6C9977183D9e72835428');
                const amount = ethers.utils.parseEther("100");
                await IERC20__factory.connect(mainnetAddresses.sdsdCRVCRV_f_gauge, owner)
                    .connect(whale)
                    .transfer(proxy.address, amount);

                const rewardTokenCount = (await sdsdCRVCRV_f_gauge.reward_count()).toNumber();
                for (let i=0; i < rewardTokenCount; ++i) {
                    allRewardTokens.push(await sdsdCRVCRV_f_gauge.reward_tokens(i));
                }        
            }
            
            return {
                gauges: [sdCRV_gauge.address, sdsdCRVCRV_f_gauge.address],
                allRewardTokens,
            }
        }
        
        it("should claim gauge rewards to alice", async () => {
            const {gauges, allRewardTokens} = await getGaugeTokens();
            await mineForwardSeconds(86400*14);

            await expect(proxy.connect(operator).claimGaugeRewards(gauges, alice.getAddress()))
                .to.emit(proxy, "GaugeRewardsClaimed")
                .withArgs(gauges, await alice.getAddress());

            // Ensure there's a positive reward balance for each reward token.
            for (let rewardToken of allRewardTokens) {
                const bal = await IERC20__factory.connect(rewardToken, owner).balanceOf(alice.getAddress());
                expect(bal).gt(0);
            }
        });

        it("should claim gauge rewards to proxy", async () => {
            const {gauges, allRewardTokens} = await getGaugeTokens();
            await mineForwardSeconds(86400*14);

            await expect(proxy.connect(operator).claimGaugeRewards(gauges, proxy.address))
                .to.emit(proxy, "GaugeRewardsClaimed")
                .withArgs(gauges, proxy.address);

            // Ensure there's a positive reward balance for each reward token.
            for (let rewardToken of allRewardTokens) {
                const bal = await IERC20__factory.connect(rewardToken, owner).balanceOf(proxy.address);
                expect(bal).gt(0);
            }
        });

        const checkClaimAndLock = async (account: string) => {
            // Create a veSDT lock so the compounding is applied.
            const amount = ethers.utils.parseEther("100");
            const lockDuration = TWO_YEARS;
            await lockVeSdt(amount, lockDuration);
            const veSDTBefore = (await proxy.veSDTLocked()).amount;

            const sdCRV_gauge = IERC20__factory.connect(mainnetAddresses.sdCRV_gauge, owner);
            const sdCRVGaugeBefore = await sdCRV_gauge.balanceOf(proxy.address);

            const {gauges, allRewardTokens} = await getGaugeTokens();
            await mineForwardSeconds(86400*14);

            const lockedStatus: IStakeDao_ClaimRewards.LockStatusStruct = {
                locked: [true, true, true],
                staked: [true, true, true],
                lockSDT: true,
            };
            await expect(proxy.connect(operator).claimAndLockGaugeRewards(gauges, lockedStatus, account))
                .to.emit(proxy, "GaugeRewardsClaimedAndLocked")
                .withArgs(gauges, account);

            // 3CRV doesn't get compounded, the others do
            const CRV3 = '0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490';
            for (let rewardToken of allRewardTokens) {
                const bal = await IERC20__factory.connect(rewardToken, owner).balanceOf(account);
                if (rewardToken === CRV3) {
                    expect(bal).gt(0);
                } else {
                    expect(bal).eq(0);
                }
            }

            // More veSDT locked
            const veSDTAfter = (await proxy.veSDTLocked()).amount;
            expect(veSDTAfter).gt(veSDTBefore);

            // More sdCRV-gauge locked and staked
            const sdCRVGaugeAfter = await sdCRV_gauge.balanceOf(proxy.address);
            expect(sdCRVGaugeAfter).gt(sdCRVGaugeBefore);
        }

        it("should claim and lock gauge rewards to alice", async () => {
            await checkClaimAndLock(await alice.getAddress());
        });

        it("should claim and lock gauge rewards to proxy", async () => {
            await checkClaimAndLock(proxy.address);
        });

        it("should vote for lockers", async () => {
            const gauges = [mainnetAddresses.sdCRV_gauge, mainnetAddresses.sdANGLE_gauge];
            await expect(proxy.connect(operator).voteForSDTLockers(gauges, [5000]))
                .to.be.revertedWithCustomError(proxy, "InvalidParam");

            const weights = [5000, 2500];
            await expect(proxy.connect(operator).voteForSDTLockers(gauges, weights))
                .to.be.revertedWith("Your token lock expires too soon");
            
            const amount = ethers.utils.parseEther("100");
            const lockDuration = TWO_YEARS;
            await lockVeSdt(amount, lockDuration);

            const controller = IStakeDao_GaugeController__factory.connect(mainnetAddresses.sdtLockerGaugeController, owner);
            await expect(proxy.connect(operator).voteForSDTLockers(gauges, weights))
                .to.emit(controller, "VoteForGauge");
            expect(await controller.vote_user_power(proxy.address)).eq(7500);
        });

        it("should vote for strategies", async () => {
            const gauges = [mainnetAddresses.sdsdCRVCRV_f_gauge, mainnetAddresses.sdsdAGAG_f_gauge];

            await expect(proxy.connect(operator).voteForSDTStrategies(gauges, [5000]))
                .to.be.revertedWithCustomError(proxy, "InvalidParam");

            const weights = [5000, 2500];
            await expect(proxy.connect(operator).voteForSDTStrategies(gauges, weights))
                .to.be.revertedWith("Your token lock expires too soon");
            
            const amount = ethers.utils.parseEther("100");
            const lockDuration = TWO_YEARS;
            await lockVeSdt(amount, lockDuration);

            const controller = IStakeDao_GaugeController__factory.connect(mainnetAddresses.sdtStrategyGaugeController, owner);
            await expect(proxy.connect(operator).voteForSDTStrategies(gauges, [5000, 2500]))
                .to.emit(controller, "VoteForGauge");
            expect(await controller.vote_user_power(proxy.address)).eq(7500);
        });
    });

    describe("Metagovernance Delegate", async () => {

        it("admin", async () => {
            const id = ethers.utils.formatBytes32String("lido-snapshot.eth");
            await shouldRevertNotOperator(proxy.connect(alice).setMetagoverananceDelegate(id, alice.getAddress()), proxy, alice);
            await shouldRevertNotOperator(proxy.connect(alice).clearMetagoverananceDelegate(id), proxy, alice);
            
            // Happy access paths
            await proxy.connect(operator).setMetagoverananceDelegate(id, alice.getAddress());
            await proxy.connect(operator).clearMetagoverananceDelegate(id);
        });

        it("should set delegate", async () => {
            const id = ethers.utils.formatBytes32String("lido-snapshot.eth");
            await expect(proxy.connect(operator).setMetagoverananceDelegate(id, alice.getAddress()))
                .to.emit(proxy, "MetagovernanceSetDelegate")
                .withArgs(id, await alice.getAddress());

            const register = ISnapshotDelegator__factory.connect(mainnetAddresses.snapshotDelegateRegistry, owner);
            expect(await register.delegation(proxy.address, id)).eq(await alice.getAddress());
        });

        it("should clear delegate", async () => {
            const id = ethers.utils.formatBytes32String("lido-snapshot.eth");
            await proxy.connect(operator).setMetagoverananceDelegate(id, alice.getAddress());

            const register = ISnapshotDelegator__factory.connect(mainnetAddresses.snapshotDelegateRegistry, owner);

            await expect(proxy.connect(operator).clearMetagoverananceDelegate(id))
                .to.emit(proxy, "MetagovernanceClearDelegate")
                .withArgs(id);

            expect(await register.delegation(proxy.address, id)).eq(ZERO_ADDRESS);  
        });
    });

    describe("VeBoost", async () => {

        it("admin", async () => {
            const delegateAmount = ethers.utils.parseEther("10");
            const endtime = roundLockEndToWeek((await blockTimestamp()) + 14*86400);
            await lockVeSdt(ethers.utils.parseEther("100"), TWO_YEARS);
            await shouldRevertNotOperator(proxy.connect(alice).delegateVeBoost(alice.getAddress(), delegateAmount, endtime), proxy, alice);
            
            // Happy access paths
            await proxy.connect(operator).delegateVeBoost(alice.getAddress(), delegateAmount, endtime, {gasLimit:5000000});
        });

        it("should delegate veBoost", async () => {
            const amount = ethers.utils.parseEther("100");
            const lockDuration = TWO_YEARS;
            await lockVeSdt(amount, lockDuration);
            const votingBal = await proxy.veSDTVotingBalance();

            // When no delegations, the veBoost balance == the veSDT voting balance.
            const bal = await proxy.veBoostBalance();
            expect(await veBoost.balanceOf(proxy.address)).eq(bal).eq(votingBal);

            const delegateAmount = ethers.utils.parseEther("10");
            const endtime = roundLockEndToWeek((await blockTimestamp()) + 14*86400);
            await expect(proxy.connect(operator).delegateVeBoost(alice.getAddress(), delegateAmount, endtime))
                .to.emit(veBoost, "Boost");

            // The new veBoost balance is the total veSDT balance minus what's been delegated
            const bal2 = await proxy.veBoostBalance();
            const votingBal2 = await proxy.veSDTVotingBalance();
            const tolerance = ethers.utils.parseEther("0.0005"); // 0.05%
            expectApproxEqRel(bal2, votingBal2.sub(delegateAmount), tolerance);
        });
    });

    describe("Recovery", async () => {
        it("admin", async () => {
            await shouldRevertNotOperator(proxy.connect(alice).transferToken(mainnetAddresses.sdt, alice.getAddress(), 100), proxy, alice);
            await shouldRevertNotOperator(proxy.connect(alice).increaseTokenAllowance(mainnetAddresses.sdt, alice.getAddress(), 100), proxy, alice);

            // Happy access paths
            await expect(proxy.connect(operator).transferToken(mainnetAddresses.sdt, alice.getAddress(), 100))
                .to.be.revertedWith('ERC20: transfer amount exceeds balance');
            await proxy.connect(operator).increaseTokenAllowance(mainnetAddresses.sdt, alice.getAddress(), 100);
        });

        it("should perform transfer", async () => {
            const amount = ethers.utils.parseEther("100");
            const sdFRAX3CRVfWhale = await impersonateSigner("0xc5d3d004a223299c4f95bb702534c14a32e8778c");
            await sdFRAX3CRVf.connect(sdFRAX3CRVfWhale).transfer(proxy.address, amount);
            
            await expect(proxy.connect(operator).transferToken(
                sdFRAX3CRVf.address, 
                alice.getAddress(),
                amount
            )).to.emit(proxy, "TokenTransferred").withArgs(
                sdFRAX3CRVf.address, 
                await alice.getAddress(),
                amount);

            expect(await sdFRAX3CRVf.balanceOf(alice.getAddress())).eq(amount);
        });

        it("should increase token allowance", async () => {
            const amount = ethers.utils.parseEther("100");
            await expect(proxy.connect(operator).increaseTokenAllowance(
                sdFRAX3CRVf.address, 
                alice.getAddress(),
                amount
            )).to.emit(sdFRAX3CRVf, "Approval").withArgs(
                proxy.address,
                await alice.getAddress(),
                amount);

            expect(await sdFRAX3CRVf.allowance(proxy.address, alice.getAddress())).eq(amount);
        });
    });

});
