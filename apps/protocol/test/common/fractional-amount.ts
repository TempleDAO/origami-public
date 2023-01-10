import { ethers } from "hardhat";
import { Signer } from "ethers";
import { expect } from "chai";
import { 
    DummyFractionalAmount__factory,
} from "../../typechain";

describe("Fractional Amount", async () => {
    let owner: Signer;

    it("sets correctly", async () => {
        [owner] = await ethers.getSigners();
        const dummyContract = await new DummyFractionalAmount__factory(owner).deploy();

        let rate = await dummyContract.fractionalRate();
        expect(rate.numerator).eq(0);
        expect(rate.denominator).eq(0);

        await expect(dummyContract.set(0, 0))
            .to.revertedWithCustomError(dummyContract, "InvalidParam");
        await expect(dummyContract.set(11, 10))
            .to.revertedWithCustomError(dummyContract, "InvalidParam");

        await dummyContract.set(333, 1000);
        rate = await dummyContract.fractionalRate();
        expect(rate.numerator).eq(333);
        expect(rate.denominator).eq(1000);
    });

    it("splits correctly", async () => {
        [owner] = await ethers.getSigners();
        const dummyContract = await new DummyFractionalAmount__factory(owner).deploy();

        const check = async (value: number, expectedNumerator: number, expectedDenominator: number) => {
            const result = await dummyContract.split(value);
            expect(result.numeratorAmount).eq(expectedNumerator);
            expect(result.denominatorAmount).eq(expectedDenominator);
        }

        await dummyContract.set(20, 100);
        await check(600, 120, 480);

        await dummyContract.set(333, 1000);
        await check(499, 166, 333);
        await check(500, 166, 334);
        await check(600, 199, 401);
    });
});