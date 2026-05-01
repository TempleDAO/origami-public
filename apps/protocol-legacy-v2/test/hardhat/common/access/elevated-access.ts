import { Signer } from "ethers";
import { expect } from "chai";
import { 
    DummyElevatedAccessUpgradeablev1,
    DummyElevatedAccessUpgradeablev1__factory,
    DummyElevatedAccessUpgradeablev2__factory
} from "../../../../typechain";
import { getSigners } from "../../signers";
import { deployUupsProxy, upgradeUupsProxy, upgradeUupsProxyAndCall, ZERO_ADDRESS } from "../../helpers";
import { upgrades } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

describe("Elevated Access Upgradeablity", async () => {
    let owner: Signer;
    let ownerAddr: string;
    let alan: Signer;
    let elevatedAccessUpgradeable: DummyElevatedAccessUpgradeablev1;

    before( async () => {
        [owner, alan] = await getSigners();
        ownerAddr = await owner.getAddress();
    });

    async function setup() {
        await expect(deployUupsProxy(
            new DummyElevatedAccessUpgradeablev1__factory(owner), 
            undefined,
            ZERO_ADDRESS,
        )).to.be.reverted;

        elevatedAccessUpgradeable = await deployUupsProxy(
            new DummyElevatedAccessUpgradeablev1__factory(owner), 
            undefined,
            ownerAddr,
        );

        return {
            elevatedAccessUpgradeable,
        };
    }

    beforeEach(async () => {
        ({
            elevatedAccessUpgradeable,
        } = await loadFixture(setup));
    });

    describe("upgradeable", async () => {
        it("construction and init", async () => {
            expect(await elevatedAccessUpgradeable.owner()).eq(ownerAddr);

            // Already initialized
            await expect(elevatedAccessUpgradeable.do_init(ownerAddr))
                .to.be.revertedWithCustomError(elevatedAccessUpgradeable, "InvalidAccess");
        });

        it("should upgrade", async () => {
            // No errors thrown
            await upgrades.validateUpgrade(elevatedAccessUpgradeable.address, new DummyElevatedAccessUpgradeablev2__factory(owner), {kind:'uups'});

            // Upgrade the contract
            await expect(upgradeUupsProxy(elevatedAccessUpgradeable.address, undefined, new DummyElevatedAccessUpgradeablev2__factory(alan)))
                .to.be.revertedWithCustomError(
                    elevatedAccessUpgradeable, "InvalidAccess"
                );

            // Upgrade the contract and set the new xxx var
            await upgradeUupsProxyAndCall(elevatedAccessUpgradeable.address, new DummyElevatedAccessUpgradeablev2__factory(owner), undefined, {
                fn: "setXXX",
                args: [123]
            });

            // const v2 = elevatedAccessUpgradeable as DummyElevatedAccessUpgradeablev2;
            const v2 = DummyElevatedAccessUpgradeablev2__factory.connect(elevatedAccessUpgradeable.address, owner);

            // Check the new contract storage after upgrading it.
            expect(await v2.owner()).eq(ownerAddr);
            expect(await v2.xxx()).eq(123);

            // Check the ownership of authorizeUpgrade
            await expect(v2.connect(alan).authorizeUpgrade())
                .to.be.revertedWithCustomError(
                    elevatedAccessUpgradeable, "InvalidAccess"
                );

            await v2.connect(owner).authorizeUpgrade();

            await expect(v2.connect(alan).initialize(ownerAddr))
                .to.revertedWith("Initializable: contract is already initialized");
                
            await expect(elevatedAccessUpgradeable.OrigamiElevatedAccess_init(ownerAddr))
                .to.revertedWith("Initializable: contract is not initializing");
            await expect(elevatedAccessUpgradeable.OrigamiElevatedAccess_init_unchained(ownerAddr))
                .to.revertedWith("Initializable: contract is not initializing");
        });
    });
});
