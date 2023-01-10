import { ethers } from "hardhat";
import { expect } from "chai";
import { MintableToken, MintableToken__factory } from "../../typechain";
import { recoverToken, shouldRevertNotOwner, testErc20Permit } from "../helpers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

describe("Mintable Token", async () => {
    let token: MintableToken;
    let owner: SignerWithAddress
    let minter: SignerWithAddress
    let alan: SignerWithAddress
    let spender: SignerWithAddress

    before(async () => {
        [owner, minter, alan, spender] = await ethers.getSigners();
    });

    async function setup() {
        token = await new MintableToken__factory(owner).deploy("My Mintable Token", "oLP");

        return {
            token,
        };
    }

    beforeEach(async () => {
        ({
            token,
        } = await loadFixture(setup));
    });

    it("Init", async () => {
        expect(await token.symbol()).eq("oLP");
        expect(await token.name()).eq("My Mintable Token");
        expect(await token.totalSupply()).eq(0);
    });

    it("admin", async () => {
        await shouldRevertNotOwner(token.connect(alan).recoverToken(token.address, alan.getAddress(), 10));

        // Happy paths
        await expect(token.recoverToken(token.address, alan.getAddress(), 10))
            .to.revertedWith("ERC20: transfer amount exceeds balance");
    });

    it("owner can recover tokens", async () => {           
        const amount = 50;
        await token.addMinter(owner.getAddress());
        await token.mint(token.address, amount);
        await recoverToken(token, amount, token, owner);
    });

    it("Only specified roles can mint", async () => {
        const alanAddress: string = await alan.getAddress();
        const minterAddress: string = await minter.getAddress();
    
        // mint should fail when no minter set.
        await expect(token.mint(alanAddress, 10))
            .to.revertedWithCustomError(token, "CannotMintOrBurn")
            .withArgs(await owner.getAddress());

        // Only admin can add a minter
        await shouldRevertNotOwner(token.connect(alan).addMinter(alanAddress));
        await token.addMinter(minterAddress);
    
        // Only minter can, well mint
        await token.connect(minter).mint(alanAddress, 10);
        expect(await token.balanceOf(alanAddress)).equals(10);
        await expect(token.mint(alanAddress, 10))
            .to.revertedWithCustomError(token, "CannotMintOrBurn")
            .withArgs(await owner.getAddress());
    
        // Only admin can remove a minter
        await shouldRevertNotOwner(token.connect(alan).removeMinter(minterAddress));
        await token.removeMinter(minterAddress);

        expect(await token.totalSupply()).eq(10);
    });

    it("only specified roles can burn", async () => {
        const alanAddress: string = await alan.getAddress();
        const minterAddress: string = await minter.getAddress();
    
        // mint should fail when no minter set.
        await expect(token.burn(alanAddress, 10))
            .to.revertedWithCustomError(token, "CannotMintOrBurn")
            .withArgs(await owner.getAddress());
    
        await token.addMinter(minterAddress);
    
        // Only minter can burn
        await token.connect(minter).mint(alanAddress, 100);
        await token.connect(minter).burn(alanAddress, 10);
        expect(await token.balanceOf(alanAddress)).equals(90);
        await expect(token.burn(alanAddress, 10))
            .to.revertedWithCustomError(token, "CannotMintOrBurn")
            .withArgs(await owner.getAddress());
            
        expect(await token.totalSupply()).eq(90);
    });

    it("permit works as expected", async () => {
        await testErc20Permit(token, alan, spender, 123);
    });
});
