import { ethers } from "hardhat";
import { BigNumber, BigNumberish, Signer } from "ethers";
import { expect } from "chai";
import { 
    DummyRepricingToken, DummyRepricingToken__factory, 
    MintableToken, MintableToken__factory
} from "../../typechain";
import { 
    ZERO_ADDRESS, 
    recoverToken, 
    shouldRevertNotOwner,
    testErc20Permit
} from "../helpers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

describe("Repricing Token", async () => {
    let reserveToken: MintableToken;
    let repricingToken: DummyRepricingToken;
    let owner: SignerWithAddress
    let operator: SignerWithAddress;
    let alan: SignerWithAddress;
    let bob: SignerWithAddress;
    let spender: SignerWithAddress;

    before(async () => {
        [owner, operator, alan, bob, spender] = await ethers.getSigners();
    });

    async function setup() {
        reserveToken = await new MintableToken__factory(owner).deploy("reserveToken", "rToken");
        await reserveToken.addMinter(owner.getAddress());
        repricingToken = await new DummyRepricingToken__factory(owner).deploy("ovTokenName", "ovToken", reserveToken.address);
        await repricingToken.addOperator(operator.getAddress());

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
        expect(await repricingToken.totalReserves()).eq(0);
        expect(await repricingToken.totalSupply()).eq(0);       
    });

    it("admin", async () => {
        await shouldRevertNotOwner(repricingToken.connect(alan).recoverToken(repricingToken.address, alan.getAddress(), 10));
        await shouldRevertNotOwner(repricingToken.connect(alan).addOperator(ZERO_ADDRESS));
        await shouldRevertNotOwner(repricingToken.connect(alan).removeOperator(ZERO_ADDRESS));
        await expect(repricingToken.connect(alan).addReserves(0))
            .to.revertedWithCustomError(repricingToken, "OnlyOperators")
            .withArgs(await alan.getAddress());
        await expect(repricingToken.connect(alan).removeReserves(0))
            .to.revertedWithCustomError(repricingToken, "OnlyOperators")
            .withArgs(await alan.getAddress());

        // Happy paths
        await expect(repricingToken.recoverToken(repricingToken.address, alan.getAddress(), 10))
            .to.revertedWith("ERC20: transfer amount exceeds balance");
        await repricingToken.addOperator(alan.getAddress());
        await repricingToken.connect(alan).addReserves(0);
        await repricingToken.connect(alan).removeReserves(0);
        await repricingToken.removeOperator(alan.getAddress());
    });

    it("should add operator", async() => {
        // addOperator() test covered by operators.ts
    });

    it("should remove operator", async() => {
        // removeOperator() test covered by operators.ts
    });
    
    it("owner can recover tokens", async () => {           
        const amount = 50;
        await reserveToken.mint(repricingToken.address, amount);
        await recoverToken(reserveToken, amount, repricingToken, owner);
    });

    async function addReservesAndMint(reservesAmount: BigNumberish, repricingAmount: BigNumberish) {
        if (!BigNumber.from(reservesAmount).isZero()) {
            await reserveToken.mint(operator.getAddress(), reservesAmount);
            await reserveToken.connect(operator).approve(repricingToken.address, reservesAmount);
            await repricingToken.connect(operator).addReserves(reservesAmount);
        }

        if (!BigNumber.from(repricingAmount).isZero()) {
            await repricingToken.mint(operator.getAddress(), repricingAmount);
        }
    }

    it("should calculate sharesToReserves and reservesPerShare correctly", async () => {
        // 0 by default when no reserves/shares
        {
            expect(await repricingToken.sharesToReserves(0)).eq(0);
            expect(await repricingToken.sharesToReserves(100_000)).eq(0);
            expect(await repricingToken.reservesPerShare()).eq(0);
        }

        // 1:1
        {
            await addReservesAndMint(100, 100);
            expect(await repricingToken.sharesToReserves(0)).eq(0);
            expect(await repricingToken.sharesToReserves(100_000)).eq(100_000);
            expect(await repricingToken.reservesPerShare()).eq(ethers.utils.parseEther("1"));
        }

        // > 1:1
        {
            await addReservesAndMint(50, 0); // now 150:100
            expect(await repricingToken.sharesToReserves(0)).eq(0);
            expect(await repricingToken.sharesToReserves(100_000)).eq(150_000);
            expect(await repricingToken.reservesPerShare()).eq(ethers.utils.parseEther("1.5"));
        }

        // < 1:1
        {
            await addReservesAndMint(0, 200); // now 150:300
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
            await addReservesAndMint(100, 100);
            expect(await repricingToken.reservesToShares(0)).eq(0);
            expect(await repricingToken.reservesToShares(100_000)).eq(100_000);
        }

        // > 1:1
        {
            await addReservesAndMint(100, 0); // now 200:100
            expect(await repricingToken.reservesToShares(0)).eq(0);
            expect(await repricingToken.reservesToShares(100_000)).eq(50_000);
        }

        // < 1:1
        {
            await addReservesAndMint(0, 200); // now 200:300
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
        await addReservesAndMint(100, 200);
        await expect(repricingToken.connect(bob).issueSharesFromReserves(100, alan.getAddress(), 0))
            .to.emit(repricingToken, "Transfer")
            .withArgs(ZERO_ADDRESS, await alan.getAddress(), 200)
            .to.emit(repricingToken, "ReservesAdded")
            .withArgs(100);
        expect(await repricingToken.balanceOf(bob.getAddress())).eq(0);
        expect(await repricingToken.balanceOf(alan.getAddress())).eq(200);
        expect(await reserveToken.balanceOf(bob.getAddress())).eq(900);
        expect(await reserveToken.balanceOf(alan.getAddress())).eq(0);
        expect(await reserveToken.balanceOf(repricingToken.address)).eq(200);
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
        await expect(repricingToken.connect(alan).redeemReservesFromShares(100, bob.getAddress(), 0))
            .to.emit(repricingToken, "Transfer")
            .withArgs(await alan.getAddress(), ZERO_ADDRESS, 100)
            .to.emit(repricingToken, "ReservesRemoved")
            .withArgs(150);
        expect(await repricingToken.balanceOf(bob.getAddress())).eq(0);
        expect(await repricingToken.balanceOf(alan.getAddress())).eq(900);
        expect(await reserveToken.balanceOf(bob.getAddress())).eq(150);
        expect(await reserveToken.balanceOf(alan.getAddress())).eq(0);
        expect(await reserveToken.balanceOf(repricingToken.address)).eq(1500-150);
    });

    it("should addReserves and removeReserves correctly", async () => {
        await reserveToken.mint(operator.getAddress(), 1_000);
        await reserveToken.connect(operator).approve(repricingToken.address, 1_000);

        await expect(repricingToken.connect(operator).addReserves(100))
            .to.emit(repricingToken, "ReservesAdded")
            .withArgs(100);
        expect(await repricingToken.totalReserves()).eq(100);
        expect(await reserveToken.balanceOf(repricingToken.address)).eq(100);
        expect(await reserveToken.balanceOf(operator.getAddress())).eq(1_000-100);

        await expect(repricingToken.connect(operator).removeReserves(100))
            .to.emit(repricingToken, "ReservesRemoved")
            .withArgs(100);
        expect(await repricingToken.totalReserves()).eq(0);
        expect(await reserveToken.balanceOf(repricingToken.address)).eq(0);
        expect(await reserveToken.balanceOf(operator.getAddress())).eq(1_000);
    });

    it("permit works as expected", async () => {
        await testErc20Permit(repricingToken, alan, spender, 123);
    });
});
