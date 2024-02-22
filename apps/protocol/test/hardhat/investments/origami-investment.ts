import { Signer } from "ethers";
import { expect } from "chai";
import { 
    DummyOrigamiInvestment, DummyOrigamiInvestment__factory, 
    DummyMintableToken__factory,
    DummyMintableToken, 
} from "../../../typechain";
import { 
    expectBalancesChangeBy, 
} from "../helpers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { getSigners } from "../signers";

describe("Origami Investment Base Class", async () => {
    let alan: Signer;
    let oToken: DummyOrigamiInvestment;
    let gov: Signer;
    let govAddr: string;
    let underlyingInvestToken: DummyMintableToken;
    
    before( async () => {
        [alan, gov] = await getSigners();
        govAddr = await gov.getAddress();
    });

    async function setup() {
        underlyingInvestToken = await new DummyMintableToken__factory(gov).deploy(govAddr, "investToken", "investToken", 18);

        oToken = await new DummyOrigamiInvestment__factory(gov).deploy(
            govAddr,
            "oX", "oX", 
            underlyingInvestToken.address, 
            underlyingInvestToken.address
        );
        await oToken.addMinter(gov.getAddress());
        return {
            oToken,
            underlyingInvestToken,
        };
    }

    beforeEach(async () => {
        ({
            oToken,
            underlyingInvestToken,
        } = await loadFixture(setup));
    });

    it("constructor", async () => {
        expect(await oToken.apiVersion()).eq("0.2.0");
        expect(await oToken.baseToken()).eq(underlyingInvestToken.address);
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
