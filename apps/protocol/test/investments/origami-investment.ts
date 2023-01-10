import { ethers } from "hardhat";
import { Signer } from "ethers";
import { expect } from "chai";
import { 
    DummyOrigamiInvestment, DummyOrigamiInvestment__factory, 
    IOrigamiInvestment,
    MintableToken__factory, 
} from "../../typechain";
import { 
    EmptyBytes, ZERO_ADDRESS, 
    expectBalancesChangeBy, 
    shouldRevertNotOwner, shouldRevertPaused
} from "../helpers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

describe("Origami Investment Base Class", async () => {
    let owner: Signer;
    let alan: Signer;
    let oToken: DummyOrigamiInvestment;
    
    before( async () => {
        [owner, alan] = await ethers.getSigners();
    });

    async function setup() {
        const underlyingInvestToken = await new MintableToken__factory(owner).deploy("investToken", "investToken");

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

    it("admin", async () => {
        await shouldRevertNotOwner(oToken.connect(alan).pause());
        await shouldRevertNotOwner(oToken.connect(alan).unpause());

        await oToken.pause();
        await oToken.unpause();
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

    it("pause/unpause", async () => {
        // Pause the contract
        await oToken.pause();

        const investQuote: IOrigamiInvestment.InvestQuoteDataStruct = {
            fromToken: ZERO_ADDRESS,
            fromTokenAmount: 0,
            expectedInvestmentAmount: 0,
            underlyingInvestmentQuoteData: EmptyBytes,
        };

        await shouldRevertPaused(oToken.investWithToken(investQuote, 0));
        await shouldRevertPaused(oToken.investWithNative(investQuote, 0, {value: 0}));

        const exitQuote: IOrigamiInvestment.ExitQuoteDataStruct = {
            investmentTokenAmount: 0,
            toToken: ZERO_ADDRESS,
            expectedToTokenAmount: 0,
            underlyingInvestmentQuoteData: EmptyBytes,
        };
        await shouldRevertPaused(oToken.exitToToken(exitQuote, 0, alan.getAddress()));
        await shouldRevertPaused(oToken.exitToNative(exitQuote, 0, alan.getAddress()));

        await oToken.unpause();

        // Works again, but unsupported token
        await expect(oToken.investWithToken(investQuote, 0))
            .to.be.revertedWithCustomError(oToken, "InvalidToken");
    });
});
