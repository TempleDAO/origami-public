import { Signer } from "ethers";
import { expect } from "chai";
import { 
    DummyOperators__factory,
} from "../../../typechain";
import { getSigners } from "../../signers";

describe("Operators", async () => {
    let owner: Signer;
    let alan: Signer;

    before( async () => {
        [owner, alan] = await getSigners();
    });

    it("Can add/remove/etc", async () => {
        const operators = await new DummyOperators__factory(owner).deploy();

        const alanAddr = await alan.getAddress();
        expect(await operators.operators(alanAddr)).eq(false);

        // Can't call isOperator protected function
        await expect(operators.connect(alan).setFoo(111))
            .to.revertedWithCustomError(operators, "OnlyOperators")
            .withArgs(await alan.getAddress());
        expect(await operators.foo()).eq(0);

        // Now add operator
        await expect(operators.addOperator(alanAddr))
            .to.emit(operators, "AddedOperator")
            .withArgs(alanAddr);
        expect(await operators.operators(alanAddr)).eq(true);

        // Can call isOperator protected function
        await operators.connect(alan).setFoo(111);
        expect(await operators.foo()).eq(111);
        
        await expect(operators.removeOperator(alanAddr))
            .to.emit(operators, "RemovedOperator")
            .withArgs(alanAddr);
        expect(await operators.operators(alanAddr)).eq(false);

        // Can't call isOperator protected function
        await expect(operators.connect(alan).setFoo(222))
            .to.revertedWithCustomError(operators, "OnlyOperators")
            .withArgs(await alan.getAddress());
        expect(await operators.foo()).eq(111);
    });
});