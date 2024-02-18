import { Signer } from "ethers";
import { expect } from "chai";
import { 
    DummyGovernable,
    DummyGovernable__factory,
    DummyGovernableUpgradeable,
    DummyGovernableUpgradeable__factory,
} from "../../../typechain";
import { getSigners } from "../../signers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { deployUupsProxy, shouldRevertNotGov, upgradeUupsProxy, upgradeUupsProxyAndCall, ZERO_ADDRESS } from "../../helpers";

describe("Governable", async () => {
    let owner: Signer;
    let alan: Signer;
    let timelock: Signer;
    let timelock2: Signer;
    let governable: DummyGovernable;
    let governableUpgradeable: DummyGovernableUpgradeable;

    before( async () => {
        [owner, alan, timelock, timelock2] = await getSigners();
    });

    async function setup() {
        // Invalid governor
        await expect(new DummyGovernable__factory(owner).deploy(ZERO_ADDRESS))
            .to.be.reverted;
        
        governable = await new DummyGovernable__factory(owner).deploy(await timelock.getAddress());

        await expect(deployUupsProxy(
            new DummyGovernableUpgradeable__factory(owner), 
            undefined,
            ZERO_ADDRESS,
        )).to.be.reverted;

        governableUpgradeable = await deployUupsProxy(
            new DummyGovernableUpgradeable__factory(owner), 
            undefined,
            await timelock.getAddress(),
        );

        return {
            governable,
        };
    }

    beforeEach(async () => {
        ({
            governable,
        } = await loadFixture(setup));
    });

    describe("non-upgradeable", async () => {
        it("construction and init", async () => {
            expect(await governable.gov()).eq(await timelock.getAddress());

            // Already initialized
            await expect(governable.do_init(owner.getAddress()))
                .to.be.revertedWithCustomError(governable, "NotGovernor");
        });

        it("Check modifiers", async () => {
            await expect(governable.connect(owner).checkOnlyGov())
                .to.revertedWithCustomError(governable, "NotGovernor");

            await expect(governable.connect(owner).proposeNewGov(alan.getAddress()))
                .to.revertedWithCustomError(governable, "NotGovernor");
        });

        it("Check ownership/gov transfer", async () => {
            await expect(governable.connect(timelock).proposeNewGov(ZERO_ADDRESS))
                .to.revertedWithCustomError(governable, "InvalidAddress")
                .withArgs(ZERO_ADDRESS);

            await expect(governable.connect(timelock).proposeNewGov(timelock2.getAddress()))
                .to.emit(governable, "NewGovernorProposed")
                .withArgs(await timelock.getAddress(), ZERO_ADDRESS, await timelock2.getAddress());

            // Still the old timelock
            expect(await governable.gov()).eq(await timelock.getAddress());

            // No one else can accept
            await expect(governable.connect(owner).acceptGov())
                .to.revertedWithCustomError(governable, "InvalidAddress");

            await expect(governable.connect(timelock2).acceptGov())
                .to.emit(governable, "NewGovernorAccepted")
                .withArgs(await timelock.getAddress(), await timelock2.getAddress());

            // Now updated
            expect(await governable.gov()).eq(await timelock2.getAddress());
            expect(await governable.connect(timelock2).checkOnlyGov()).eq(1);
        });
    });

    describe("upgradeable", async () => {
        it("construction and init", async () => {
            expect(await governableUpgradeable.gov()).eq(await timelock.getAddress());

            // Already initialized
            await expect(governableUpgradeable.do_init(owner.getAddress()))
                .to.be.revertedWithCustomError(governableUpgradeable, "NotGovernor");
        });

        it("Check modifiers", async () => {
            await expect(governableUpgradeable.connect(owner).checkOnlyGov())
                .to.revertedWithCustomError(governableUpgradeable, "NotGovernor");

            await expect(governableUpgradeable.connect(alan).proposeNewGov(alan.getAddress()))
                .to.revertedWithCustomError(governableUpgradeable, "NotGovernor");
        });

        it("Check ownership/gov transfer", async () => {
            await expect(governableUpgradeable.connect(timelock).proposeNewGov(ZERO_ADDRESS))
            .to.revertedWithCustomError(governableUpgradeable, "InvalidAddress")
            .withArgs(ZERO_ADDRESS);

            await expect(governableUpgradeable.connect(timelock).proposeNewGov(timelock2.getAddress()))
                .to.emit(governableUpgradeable, "NewGovernorProposed")
                .withArgs(await timelock.getAddress(), ZERO_ADDRESS, await timelock2.getAddress());

            // Still the old timelock
            expect(await governableUpgradeable.gov()).eq(await timelock.getAddress());

            // No one else can accept
            await expect(governableUpgradeable.connect(owner).acceptGov())
                .to.revertedWithCustomError(governableUpgradeable, "InvalidAddress");

            await expect(governableUpgradeable.connect(timelock2).acceptGov())
                .to.emit(governableUpgradeable, "NewGovernorAccepted")
                .withArgs(await timelock.getAddress(), await timelock2.getAddress());

            // Now updated
            expect(await governableUpgradeable.gov()).eq(await timelock2.getAddress());
            expect(await governableUpgradeable.connect(timelock2).checkOnlyGov()).eq(1);
        });

        it("should upgrade() - an existing var is the same", async () => {
            // Check a var before upgrade
            expect(await governableUpgradeable.gov()).eq(await timelock.getAddress());

            // Upgrade the contract
            await upgradeUupsProxy(governableUpgradeable.address, undefined, new DummyGovernableUpgradeable__factory(timelock));

            // Check the new contract storage after upgrading it.
            expect(await governableUpgradeable.gov()).eq(await timelock.getAddress());
        });

        it("should upgrade() with the call - the new storage var is set as expected", async () => {
            // Check a var before upgrade
            expect(await governableUpgradeable.gov()).eq(await timelock.getAddress());

            // Upgrade the contract and call the function
            await upgradeUupsProxyAndCall(governableUpgradeable.address, new DummyGovernableUpgradeable__factory(timelock), undefined, {
                fn: "proposeNewGov",
                args: [await timelock2.getAddress()]
            });

            // Get the new contract
            const newAcct = DummyGovernableUpgradeable__factory.connect(governableUpgradeable.address, owner);

            // The new contract addr is the same as the previous contract
            expect(newAcct.address).eq(governableUpgradeable.address);

            // Check the new contract storage after upgrading it.
            expect(await newAcct.gov()).eq(await timelock.getAddress());
            await governableUpgradeable.connect(timelock2).acceptGov();

            // Check the ownership of authorizeUpgrade
            await shouldRevertNotGov(governableUpgradeable, newAcct.connect(alan).authorizeUpgrade());
            await newAcct.connect(timelock2).authorizeUpgrade();

            await expect(newAcct.connect(timelock2).initialize(await timelock.getAddress()))
                .to.revertedWith("Initializable: contract is already initialized");
                
            await expect(governableUpgradeable.Governable_init(await timelock.getAddress()))
                .to.revertedWith("Initializable: contract is not initializing");
            await expect(governableUpgradeable.Governable_init_unchained(await timelock.getAddress()))
                .to.revertedWith("Initializable: contract is not initializing");

        });
    });
});