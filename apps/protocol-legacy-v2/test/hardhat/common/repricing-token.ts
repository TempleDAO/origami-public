import { ethers } from "hardhat";
import { BigNumber, BigNumberish } from "ethers";
import { expect } from "chai";
import { 
    DummyRepricingToken, DummyRepricingToken__factory, 
    MintableToken, DummyMintableToken__factory
} from "../../../typechain";
import { 
    ZERO_ADDRESS, 
    blockTimestamp, 
    mineForwardSeconds, 
    recoverToken, 
    setExplicitAccess, 
    shouldRevertInvalidAccess,
    testErc20Permit
} from "../helpers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { OrigamiSignerWithAddress, getSigners } from "../signers";

describe("Repricing Token", async () => {
    let reserveToken: MintableToken;
    let repricingToken: DummyRepricingToken;
    let owner: OrigamiSignerWithAddress
    let operator: OrigamiSignerWithAddress;
    let alan: OrigamiSignerWithAddress;
    let bob: OrigamiSignerWithAddress;
    let spender: OrigamiSignerWithAddress;
    let gov: OrigamiSignerWithAddress;
    let govAddr: string;

    const reservesVestingDuration = 86400;

    before(async () => {
        [owner, operator, alan, bob, spender, gov] = await getSigners();
        govAddr = await gov.getAddress();
    });

    async function setup() {
        reserveToken = await new DummyMintableToken__factory(gov).deploy(govAddr, "reserveToken", "rToken", 18);
        await reserveToken.addMinter(gov.getAddress());
        repricingToken = await new DummyRepricingToken__factory(gov).deploy(govAddr, "ovTokenName", "ovToken", reserveToken.address, reservesVestingDuration);
        await setExplicitAccess(
            repricingToken,
            await operator.getAddress(),
            ["addPendingReserves"],
            true
        );

        return {
            reserveToken,
            repricingToken,
        };
    }

    beforeEach(async () => {
        ({
            reserveToken,
            repricingToken,
        } = await loadFixture(setup));
    });

    it("Init", async () => {
        expect(await repricingToken.symbol()).eq("ovToken");
        expect(await repricingToken.name()).eq("ovTokenName");
        expect(await repricingToken.decimals()).eq(await reserveToken.decimals());
        expect(await repricingToken.vestedReserves()).eq(0);
        expect(await repricingToken.pendingReserves()).eq(0);
        expect(await repricingToken.reservesVestingDuration()).eq(reservesVestingDuration);
        expect(await repricingToken.lastVestingCheckpoint()).eq(0);
        expect(await repricingToken.totalReserves()).eq(0);
        expect(await repricingToken.totalSupply()).eq(0);
        expect(await repricingToken.reservesPerShare()).eq(ethers.utils.parseEther("1"));
        const ur = await repricingToken.unvestedReserves();
        expect(ur.accrued).eq(0);
        expect(ur.outstanding).eq(0);
    });

    it("admin", async () => {
        await shouldRevertInvalidAccess(repricingToken, repricingToken.connect(owner).setReservesVestingDuration(0));
        await shouldRevertInvalidAccess(repricingToken, repricingToken.connect(alan).recoverToken(repricingToken.address, alan.getAddress(), 10));
        await shouldRevertInvalidAccess(repricingToken, repricingToken.connect(alan).addPendingReserves(0));

        // Happy paths
        await repricingToken.connect(gov).setReservesVestingDuration(0);
        await expect(repricingToken.connect(gov).recoverToken(repricingToken.address, alan.getAddress(), 10))
            .to.revertedWith("ERC20: transfer amount exceeds balance");
        await expect(repricingToken.connect(operator).addPendingReserves(0))
            .to.be.revertedWithCustomError(repricingToken, "ExpectedNonZero");
    });
    
    it("gov can recover tokens", async () => {
        // Add some reserves.
        {
            const amount = 50;
            await reserveToken.mint(operator.getAddress(), amount);
            await reserveToken.connect(operator).approve(repricingToken.address, amount);
            await repricingToken.connect(operator).addPendingReserves(amount);
        }

        // Can't recover <= the balance of reserve tokens
        {
            await expect(recoverToken(reserveToken, 1, repricingToken, owner))
                .to.be.revertedWithCustomError(repricingToken, "InvalidAmount")
                .withArgs(reserveToken.address, 1);

            await expect(recoverToken(reserveToken, 50, repricingToken, owner))
                .to.be.revertedWithCustomError(repricingToken, "InvalidAmount")
                .withArgs(reserveToken.address, 50);
        }
        
        // Any extra direct dontaions (no add reserves) can be recovered
        {
            const amount = 5;
            await reserveToken.mint(repricingToken.address, amount);

            await expect(recoverToken(reserveToken, amount+1, repricingToken, owner))
                .to.be.revertedWithCustomError(repricingToken, "InvalidAmount")
                .withArgs(reserveToken.address, amount+1);

            await recoverToken(reserveToken, amount, repricingToken, owner);
        }
        
        // Any other token can be recovered too
        {
            const amount = 50;
            const rando = await new DummyMintableToken__factory(gov).deploy(govAddr, "rando", "rando", 18);
            await rando.addMinter(gov.getAddress());
            await rando.mint(repricingToken.address, amount);
            await recoverToken(rando, amount, repricingToken, owner);
        }
    });

    it("Should setReservesVestingDuration()", async () => {
        await addReservesAndMint(500, 0);
        await mineForwardSeconds(10_000);
        const expectedAccrued = Math.floor(500 * 10_000 / reservesVestingDuration);

        await expect(repricingToken.setReservesVestingDuration(100))
            .to.emit(repricingToken, "ReservesVestingDurationSet")
            .withArgs(100)
            .to.emit(repricingToken, "ReservesCheckpoint")
            .withArgs(expectedAccrued, expectedAccrued, 500-expectedAccrued, 0);

        expect(await repricingToken.reservesVestingDuration()).to.eq(100);
    });

    async function addReservesAndMint(reservesAmount: BigNumberish, repricingAmount: BigNumberish) {
        if (!BigNumber.from(reservesAmount).isZero()) {
            await reserveToken.mint(operator.getAddress(), reservesAmount);
            await reserveToken.connect(operator).approve(repricingToken.address, reservesAmount);
            await repricingToken.connect(operator).addPendingReserves(reservesAmount);
        }

        if (!BigNumber.from(repricingAmount).isZero()) {
            await repricingToken.mint(operator.getAddress(), repricingAmount);
        }
    }

    it("should calculate sharesToReserves and reservesPerShare correctly", async () => {
        // 0 by default when no reserves/shares
        {
            expect(await repricingToken.sharesToReserves(0)).eq(0);
            expect(await repricingToken.sharesToReserves(100_000)).eq(100_000);
            expect(await repricingToken.reservesPerShare()).eq(ethers.utils.parseEther("1"));
        }

        // 1:1
        {
            const amount = ethers.utils.parseEther("100");
            await addReservesAndMint(amount, amount);
            await mineForwardSeconds(reservesVestingDuration/2-1); // Exactly half way through the vesting of 100
            expect(await repricingToken.sharesToReserves(0)).eq(0);
            expect(await repricingToken.sharesToReserves(100_000)).eq(50_000);
            expect(await repricingToken.reservesPerShare()).eq(ethers.utils.parseEther("0.5"));
        }

        // > 1:1
        {
            await mineForwardSeconds(reservesVestingDuration/2);
            await addReservesAndMint(ethers.utils.parseEther("50"), 0); // now 150:100
            await mineForwardSeconds(reservesVestingDuration/2); // Fully past the first 100, half way through the 50
            expect(await repricingToken.sharesToReserves(0)).eq(0);
            expect(await repricingToken.sharesToReserves(100_000)).eq(125_000);
            expect(await repricingToken.reservesPerShare()).eq(ethers.utils.parseEther("1.25"));
        }

        // < 1:1
        {
            await mineForwardSeconds(reservesVestingDuration/2); // Fully past the 150, half way through the 200
            await addReservesAndMint(0, ethers.utils.parseEther("200")); // now 150:300
            expect(await repricingToken.sharesToReserves(0)).eq(0);
            expect(await repricingToken.sharesToReserves(100_000)).eq(50_000);
            expect(await repricingToken.reservesPerShare()).eq(ethers.utils.parseEther("0.5"));
        }
    });

    it("should calculate reservesToShares correctly", async () => {
        // 1:1 by default when no reserves/shares
        {
            expect(await repricingToken.reservesToShares(0)).eq(0);
            expect(await repricingToken.reservesToShares(100_000)).eq(100_000);
        }

        // 1:1
        {
            const amount = ethers.utils.parseEther("100");
            await addReservesAndMint(amount, amount);
            await mineForwardSeconds(reservesVestingDuration/2-1); // Exactly half way through the vesting of 100
            expect(await repricingToken.reservesToShares(0)).eq(0);
            expect(await repricingToken.reservesToShares(100_000)).eq(200_000);
        }

        // > 1:1
        {
            await mineForwardSeconds(reservesVestingDuration/2); // Exactly half way through the vesting of 100
            const amount = ethers.utils.parseEther("100");
            await addReservesAndMint(amount, 0); // now 200:100
            await mineForwardSeconds(reservesVestingDuration/2); // 100 fully vested, 50 accrued
            expect(await repricingToken.reservesToShares(0)).eq(0);
            expect(await repricingToken.reservesToShares(100_000)).eq(66_666); // 100k / 150 reserves
        }

        // < 1:1
        {
            await mineForwardSeconds(reservesVestingDuration/2); // Exactly half way through the vesting of 100
            const amount = ethers.utils.parseEther("200");
            await addReservesAndMint(0, amount); // now 200:300
            await mineForwardSeconds(reservesVestingDuration); // Fully vested
            expect(await repricingToken.reservesToShares(0)).eq(0);
            expect(await repricingToken.reservesToShares(100_000)).eq(150_000);
        }
    });

    it("should _issueSharesFromReserves correctly", async () => {
        await reserveToken.mint(bob.getAddress(), 1_000);
        await reserveToken.connect(bob).approve(repricingToken.address, 1_000);

        // Error when reserves = 0
        await expect(repricingToken.connect(bob).issueSharesFromReserves(0, alan.getAddress(), 0))
            .to.revertedWithCustomError(repricingToken, "ExpectedNonZero");

        // Didn't get enough shares as expected
        await expect(repricingToken.connect(bob).issueSharesFromReserves(10, alan.getAddress(), 100))
            .to.revertedWithCustomError(repricingToken, "Slippage");

        // success
        await addReservesAndMint(ethers.utils.parseEther("100"), ethers.utils.parseEther("200"));
        await mineForwardSeconds(reservesVestingDuration/2-2); // 50 vested (50% of 100)

        await expect(repricingToken.connect(bob).issueSharesFromReserves(100, alan.getAddress(), 0))
            .to.emit(repricingToken, "Transfer")
            .withArgs(ZERO_ADDRESS, await alan.getAddress(), 400) // 100 * 200 supply / 50 reserves
            .to.emit(repricingToken, "VestedReservesAdded")
            .withArgs(100);
        expect(await repricingToken.balanceOf(bob.getAddress())).eq(0);
        expect(await repricingToken.balanceOf(alan.getAddress())).eq(400);
        expect(await reserveToken.balanceOf(bob.getAddress())).eq(900);
        expect(await reserveToken.balanceOf(alan.getAddress())).eq(0);
        expect(await reserveToken.balanceOf(repricingToken.address)).eq(ethers.utils.parseEther("100").add(100));

        // Burn some of the reserve tokens, so the invariant on balance check no longer holds
        await reserveToken.burn(repricingToken.address, ethers.utils.parseEther("10"));
        await reserveToken.mint(bob.getAddress(), 1_000);
        await reserveToken.connect(bob).approve(repricingToken.address, 1_000);
        await expect(repricingToken.connect(bob).issueSharesFromReserves(100, alan.getAddress(), 0))
            .to.revertedWithCustomError(repricingToken, "InsufficientBalance");
        
        // Works again if the repricing token has the tokens again
        await reserveToken.mint(repricingToken.address, ethers.utils.parseEther("10"));
        await repricingToken.connect(bob).issueSharesFromReserves(100, alan.getAddress(), 0);
    });

    it("should _redeemReservesFromShares correctly", async () => {
        // Error when reserves = 0
        await expect(repricingToken.connect(bob).redeemReservesFromShares(0, alan.getAddress(), 0))
            .to.revertedWithCustomError(repricingToken, "ExpectedNonZero");

        // No share balance
        await expect(repricingToken.connect(bob).redeemReservesFromShares(10, alan.getAddress(), 100))
            .to.revertedWithCustomError(repricingToken, "InsufficientBalance")
            .withArgs(repricingToken.address, 10, 0);

        // Issue alan with shares
        {
            await reserveToken.mint(alan.getAddress(), 1_000);
            await reserveToken.connect(alan).approve(repricingToken.address, 1_000);
            await repricingToken.connect(alan).issueSharesFromReserves(1_000, alan.getAddress(), 0);
            await addReservesAndMint(500, 0);
        }

        // Didn't get enough shares as expected
        await expect(repricingToken.connect(alan).redeemReservesFromShares(10, alan.getAddress(), 100))
            .to.revertedWithCustomError(repricingToken, "Slippage");

        // success
        await mineForwardSeconds(reservesVestingDuration/2-1); // 250 vested (50% of 500)
        await expect(repricingToken.connect(alan).redeemReservesFromShares(100, bob.getAddress(), 0))
            .to.emit(repricingToken, "Transfer")
            .withArgs(await alan.getAddress(), ZERO_ADDRESS, 100)
            .to.emit(repricingToken, "VestedReservesRemoved")
            .withArgs(125);
        expect(await repricingToken.balanceOf(bob.getAddress())).eq(0);
        expect(await repricingToken.balanceOf(alan.getAddress())).eq(900);
        expect(await reserveToken.balanceOf(bob.getAddress())).eq(125);
        expect(await reserveToken.balanceOf(alan.getAddress())).eq(0);
        expect(await reserveToken.balanceOf(repricingToken.address)).eq(1500-125);

        // Burn some of the reserve tokens, so the invariant on balance check no longer holds
        await reserveToken.burn(repricingToken.address, 500);
        await expect(repricingToken.connect(alan).redeemReservesFromShares(100, alan.getAddress(), 0))
            .to.revertedWithCustomError(repricingToken, "InsufficientBalance");
        
        // Works again if the repricing token has the tokens again
        await reserveToken.mint(repricingToken.address, 500);
        const balBefore = await reserveToken.balanceOf(repricingToken.address);
        await repricingToken.connect(alan).redeemReservesFromShares(100, repricingToken.address, 0);

        // Reserve tokens aren't sent anywhere this time.
        expect(await reserveToken.balanceOf(repricingToken.address)).eq(balBefore);
    });

    it("should calculate unvestedRewards", async () => {
        // Add to vested amount by issuing shares to Bob
        const vestedAmount = ethers.utils.parseEther("100");
        await reserveToken.mint(bob.getAddress(), vestedAmount);
        await reserveToken.connect(bob).approve(repricingToken.address, vestedAmount);
        await repricingToken.connect(bob).issueSharesFromReserves(vestedAmount, bob.getAddress(), 0);

        // Add a pending amount
        const pendingAmount = ethers.utils.parseEther("500");
        await addReservesAndMint(pendingAmount, 0);

        let elapsedSecs = 1;
        {
            await mineForwardSeconds(1);
            const uvr = await repricingToken.unvestedReserves();
            expect(uvr.accrued).eq(pendingAmount.mul(elapsedSecs).div(reservesVestingDuration));
            expect(uvr.outstanding).eq(pendingAmount.sub(uvr.accrued));
            expect(await repricingToken.totalReserves()).eq(vestedAmount.add(uvr.accrued));
        }

        elapsedSecs = 3333;
        {
            await mineForwardSeconds(elapsedSecs-1);
            const uvr = await repricingToken.unvestedReserves();
            expect(uvr.accrued).eq(pendingAmount.mul(elapsedSecs).div(reservesVestingDuration));
            expect(uvr.outstanding).eq(pendingAmount.sub(uvr.accrued));
            expect(await repricingToken.totalReserves()).eq(vestedAmount.add(uvr.accrued));
        }

        elapsedSecs = 86400;
        {
            await mineForwardSeconds(elapsedSecs-3333);
            const uvr = await repricingToken.unvestedReserves();
            expect(uvr.accrued).eq(pendingAmount.mul(elapsedSecs).div(reservesVestingDuration));
            expect(uvr.outstanding).eq(pendingAmount.sub(uvr.accrued));
            expect(await repricingToken.totalReserves()).eq(vestedAmount.add(uvr.accrued));
        }

        elapsedSecs = 86401;
        {
            await mineForwardSeconds(1);
            const uvr = await repricingToken.unvestedReserves();
            // Capped at the amount
            expect(uvr.accrued).eq(pendingAmount);
            expect(uvr.outstanding).eq(pendingAmount.sub(uvr.accrued));
            expect(await repricingToken.totalReserves()).eq(vestedAmount.add(uvr.accrued));
        }
    });

    it("should calculate unvestedRewards for instantaneous vesting", async () => {
        await repricingToken.setReservesVestingDuration(0);

        // Add to vested amount by issuing shares to Bob
        const vestedAmount = ethers.utils.parseEther("100");
        await reserveToken.mint(bob.getAddress(), vestedAmount);
        await reserveToken.connect(bob).approve(repricingToken.address, vestedAmount);
        await repricingToken.connect(bob).issueSharesFromReserves(vestedAmount, bob.getAddress(), 0);

        // Add a pending amount
        const pendingAmount = ethers.utils.parseEther("500");
        await addReservesAndMint(pendingAmount, 0);

        let elapsedSecs = 1;
        {
            await mineForwardSeconds(1);
            const uvr = await repricingToken.unvestedReserves();
            expect(uvr.accrued).eq(pendingAmount);
            expect(uvr.outstanding).eq(0);
            expect(await repricingToken.totalReserves()).eq(vestedAmount.add(pendingAmount));
        }

        elapsedSecs = 3333;
        {
            await mineForwardSeconds(elapsedSecs-1);
            const uvr = await repricingToken.unvestedReserves();
            expect(uvr.accrued).eq(pendingAmount);
            expect(uvr.outstanding).eq(0);
            expect(await repricingToken.totalReserves()).eq(vestedAmount.add(pendingAmount));
        }

        elapsedSecs = 86400;
        {
            await mineForwardSeconds(elapsedSecs-3333);
            const uvr = await repricingToken.unvestedReserves();
            expect(uvr.accrued).eq(pendingAmount);
            expect(uvr.outstanding).eq(0);
            expect(await repricingToken.totalReserves()).eq(vestedAmount.add(pendingAmount));
        }

        elapsedSecs = 86401;
        {
            await mineForwardSeconds(1);
            const uvr = await repricingToken.unvestedReserves();
            expect(uvr.accrued).eq(pendingAmount);
            expect(uvr.outstanding).eq(0);
            expect(await repricingToken.totalReserves()).eq(vestedAmount.add(pendingAmount));
        }
    });

    it("Should addPendingReserves()", async () => {
        await expect(repricingToken.connect(operator).addPendingReserves(0))
            .to.revertedWithCustomError(repricingToken, "ExpectedNonZero");

        const reservesAmount = ethers.utils.parseEther("100");
        await reserveToken.mint(operator.getAddress(), reservesAmount);
        await reserveToken.connect(operator).approve(repricingToken.address, reservesAmount);
        await expect(repricingToken.connect(operator).addPendingReserves(reservesAmount))
            .to.emit(repricingToken, "PendingReservesAdded")
            .withArgs(reservesAmount)
            .to.emit(repricingToken, "ReservesCheckpoint")
            .withArgs(0, 0, 0, reservesAmount);

        expect(await reserveToken.balanceOf(operator.getAddress())).eq(0);
        expect(await reserveToken.balanceOf(repricingToken.address)).eq(reservesAmount);

        // Burn some of the reserve tokens, so the invariant on balance check no longer holds
        await reserveToken.burn(repricingToken.address, ethers.utils.parseEther("10"));
        await reserveToken.mint(operator.getAddress(), reservesAmount);
        await reserveToken.connect(operator).approve(repricingToken.address, reservesAmount);
        await expect(repricingToken.connect(operator).addPendingReserves(reservesAmount))
            .to.revertedWithCustomError(repricingToken, "InsufficientBalance");

        // Works again if the repricing token has the tokens again
        await reserveToken.mint(repricingToken.address, ethers.utils.parseEther("10"));
        await repricingToken.connect(operator).addPendingReserves(reservesAmount);
    });

    it("should checkpoint reserves", async () => {
        await addReservesAndMint(500, 0);
        const checkpointAt = await blockTimestamp();
        await expect(repricingToken.checkpointReserves())
            .to.be.revertedWithCustomError(repricingToken, "CannotCheckpointReserves")
            .withArgs(1, reservesVestingDuration);

        await mineForwardSeconds(reservesVestingDuration-1); // Right on the vesting time

        expect(await repricingToken.vestedReserves()).eq(0);
        expect(await repricingToken.pendingReserves()).eq(500);
        expect(await repricingToken.lastVestingCheckpoint()).eq(checkpointAt);

        await expect(repricingToken.checkpointReserves())
            .to.emit(repricingToken, "ReservesCheckpoint")
            .withArgs(500, 500, 0, 0);

        expect(await repricingToken.vestedReserves()).eq(500);
        expect(await repricingToken.pendingReserves()).eq(0);
        expect(await repricingToken.lastVestingCheckpoint()).eq(await blockTimestamp());
    });

    it("permit works as expected", async () => {
        await testErc20Permit(repricingToken, alan, spender, 123);
    });
});
