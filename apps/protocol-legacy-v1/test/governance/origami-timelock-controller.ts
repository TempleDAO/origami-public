import { ethers } from "hardhat";
import { Signer } from "ethers";
import { expect } from "chai";
import { 
    DummyTimelockController, DummyTimelockController__factory,
    DummyMintableToken, DummyMintableToken__factory
} from "../../typechain";
import { 
    ZERO_ADDRESS, mineForwardSeconds, 
} from "../helpers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { getSigners } from "../signers";

describe("Origami Timelock Controller", async () => {
    let token: DummyMintableToken;
    let timelock: DummyTimelockController;

    let owner: Signer;
    let proposer: Signer;
    let executor: Signer;
    let bob: Signer;

    before(async () => {
        [owner, proposer, executor, bob] = await getSigners();
    });

    async function setup() {
        timelock = await new DummyTimelockController__factory(owner).deploy(60, [proposer.getAddress()], [executor.getAddress()], ZERO_ADDRESS);
        token = await new DummyMintableToken__factory(owner).deploy(timelock.address, "reserveToken", "rToken");
    
        return {
            token,
            timelock,
        };
    }

    beforeEach(async () => {
        ({
            token,
            timelock,
        } = await loadFixture(setup));
    });

    it("Add Minter", async () => {
        const encoded = token.interface.encodeFunctionData("addMinter", [await bob.getAddress()]);
        const now = Math.floor(Date.now() / 1000).toString();
        await timelock.connect(proposer).schedule(
            token.address,
            0,
            encoded,
            ethers.utils.formatBytes32String(""),
            ethers.utils.formatBytes32String(now),
            60
        );

        await mineForwardSeconds(58);

        await expect(
            timelock.connect(executor).execute(
                token.address,
                0,
                encoded,
                ethers.utils.formatBytes32String(""),
                ethers.utils.formatBytes32String(now)
            )
        )
            .to.revertedWith('TimelockController: operation is not ready');

        await mineForwardSeconds(1);
        await timelock.connect(executor).execute(
            token.address,
            0,
            encoded,
            ethers.utils.formatBytes32String(""),
            ethers.utils.formatBytes32String(now)
        );

        await token.connect(bob).mint(bob.getAddress(), 100);
        expect(await token.balanceOf(bob.getAddress())).eq(100);
    });

    it("Handle underlying revert string", async () => {
        const encoded = token.interface.encodeFunctionData("transferFrom", [await bob.getAddress(), timelock.address, 100000]);
        const now = Math.floor(Date.now() / 1000).toString();
        await timelock.connect(proposer).schedule(
            token.address,
            0,
            encoded,
            ethers.utils.formatBytes32String(""),
            ethers.utils.formatBytes32String(now),
            60
        );

        await mineForwardSeconds(60);

        await expect(
            timelock.connect(executor).execute(
                token.address,
                0,
                encoded,
                ethers.utils.formatBytes32String(""),
                ethers.utils.formatBytes32String(now)
            )
        )
            .to.be.revertedWith("ERC20: insufficient allowance");
    });

    it("Handle underlying no revert string", async () => {
        const encoded = token.interface.encodeFunctionData("revertNoMessage");
        const now = Math.floor(Date.now() / 1000).toString();
        await timelock.connect(proposer).schedule(
            token.address,
            0,
            encoded,
            ethers.utils.formatBytes32String(""),
            ethers.utils.formatBytes32String(now),
            60
        );

        await mineForwardSeconds(60);

        await expect(
            timelock.connect(executor).execute(
                token.address,
                0,
                encoded,
                ethers.utils.formatBytes32String(""),
                ethers.utils.formatBytes32String(now)
            )
        )
            .to.be.revertedWithCustomError(timelock, "UnknownExecuteError");
    });

});
