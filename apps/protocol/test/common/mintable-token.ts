import { expect } from "chai";
import { DummyMintableToken, DummyMintableToken__factory } from "../../typechain";
import { recoverToken, shouldRevertNotOwner, testErc20Permit } from "../helpers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { OrigamiSignerWithAddress, getSigners } from "../signers";

describe("Mintable Token", async () => {
    let token: DummyMintableToken;
    let owner: OrigamiSignerWithAddress
    let minter: OrigamiSignerWithAddress
    let alan: OrigamiSignerWithAddress
    let spender: OrigamiSignerWithAddress

    before(async () => {
        [owner, minter, alan, spender] = await getSigners();
    });

    async function setup() {
        token = await new DummyMintableToken__factory(owner).deploy("My Mintable Token", "oLP");

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
        expect(await token.isMinter(minterAddress)).eq(false);
        await shouldRevertNotOwner(token.connect(alan).addMinter(alanAddress));
        await expect(token.addMinter(minterAddress))
            .to.emit(token, "AddedMinter")
            .withArgs(minterAddress);
        expect(await token.isMinter(minterAddress)).eq(true);
    
        // Only minter can, well mint
        await token.connect(minter).mint(alanAddress, 10);
        expect(await token.balanceOf(alanAddress)).equals(10);
        await expect(token.mint(alanAddress, 10))
            .to.revertedWithCustomError(token, "CannotMintOrBurn")
            .withArgs(await owner.getAddress());
    
        // Only admin can remove a minter
        await shouldRevertNotOwner(token.connect(alan).removeMinter(minterAddress));
        await expect(token.removeMinter(minterAddress))
            .to.emit(token, "RemovedMinter")
            .withArgs(minterAddress);
        expect(await token.isMinter(minterAddress)).eq(false);

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
