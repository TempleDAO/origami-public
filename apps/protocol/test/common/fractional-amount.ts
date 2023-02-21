import { Signer } from "ethers";
import { expect } from "chai";
import { 
    DummyFractionalAmount__factory,
} from "../../typechain";
import { PANIC_CODES } from "@nomicfoundation/hardhat-chai-matchers/panic";
import { getSigners } from "../signers";

describe("Fractional Amount", async () => {
    let owner: Signer;

    it("sets correctly", async () => {
        [owner] = await getSigners();
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
        [owner] = await getSigners();
        const dummyContract = await new DummyFractionalAmount__factory(owner).deploy();

        const check = async (value: number, expectedAmount1: number, expectedAmount2: number) => {
            const result = await dummyContract.split(value);
            expect(result.amount1).eq(expectedAmount1);
            expect(result.amount2).eq(expectedAmount2);
        }

        const checkCalldata = async (value: number, numerator: number, denominator: number, expectedAmount1: number, expectedAmount2: number) => {
            const result = await dummyContract.splitCalldata({numerator, denominator}, value);
            expect(result.amount1).eq(expectedAmount1);
            expect(result.amount2).eq(expectedAmount2);
        }

        const checkExplicit = async (value: number, numerator: number, denominator: number, expectedAmount1: number, expectedAmount2: number) => {
            const result = await dummyContract.splitExplicit(numerator, denominator, value);
            expect(result.amount1).eq(expectedAmount1);
            expect(result.amount2).eq(expectedAmount2);
        }

        await dummyContract.set(20, 100);
        await check(600, 120, 480);
        await checkCalldata(600, 2000, 10000, 120, 480);
        await checkExplicit(600, 2000, 10000, 120, 480);

        await dummyContract.set(333, 1000);
        await check(499, 166, 333);
        await check(500, 166, 334);
        await check(600, 199, 401);
        await checkCalldata(600, 3333, 10000, 199, 401);
        await checkExplicit(600, 3333, 10000, 199, 401);

        await checkExplicit(100, 0, 100, 0, 100);
        await expect(checkExplicit(100, 100, 0, 0, 100))
            .to.revertedWithPanic(PANIC_CODES.DIVISION_BY_ZERO);
    });
});