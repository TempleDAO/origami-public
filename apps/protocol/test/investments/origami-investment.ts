import { ethers } from "hardhat";
import { Signer } from "ethers";
import { expect } from "chai";
import { 
    DummyOrigamiInvestment, DummyOrigamiInvestment__factory, 
    DummyMintableToken__factory, 
} from "../../typechain";
import { 
    expectBalancesChangeBy, 
} from "../helpers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { getSigners } from "../signers";

describe("Origami Investment Base Class", async () => {
    let owner: Signer;
    let alan: Signer;
    let oToken: DummyOrigamiInvestment;
    
    before( async () => {
        [owner, alan] = await getSigners();
    });

    async function setup() {
        const underlyingInvestToken = await new DummyMintableToken__factory(owner).deploy("investToken", "investToken");

        oToken = await new DummyOrigamiInvestment__factory(owner).deploy(
            "oX", "oX", 
            underlyingInvestToken.address, 
            underlyingInvestToken.address
        );
        await oToken.addMinter(owner.getAddress());
        return {
            oToken,
        };
    }

    beforeEach(async () => {
        ({
            oToken,
        } = await loadFixture(setup));
    });

    it("constructor", async () => {
        expect(await oToken.apiVersion()).eq("0.1.0");
    });

    it("can mint receipt token", async () => {
        await expectBalancesChangeBy(async () => { 
            await oToken.mint(alan.getAddress(), 100);
        },
            [oToken, alan, 100],
            [oToken, oToken, 0],
        );

        expect(await oToken.totalSupply()).eq(100);
    });
});
