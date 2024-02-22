import { network, ethers, upgrades } from "hardhat";
import { BaseContract, BigNumber, BigNumberish, Contract, ContractFactory, ContractTransaction, Signer, TypedDataDomain, TypedDataField } from "ethers";
import { assert, expect } from "chai";
import { CommonEventsAndErrors__factory, ERC20Permit, IOrigamiElevatedAccess, IOrigamiInvestment } from "../../typechain";
import { impersonateAccount, time as timeHelpers } from "@nomicfoundation/hardhat-network-helpers";
import { isAddress, splitSignature } from "ethers/lib/utils";
import { AssertionError } from "assert";
import { OrigamiSignerWithAddress } from "./signers";
import { StandaloneOptions } from "@openzeppelin/hardhat-upgrades/src/utils/options";

export const EmptyBytes = "0x";
export const ONE_ETH = ethers.utils.parseEther("1");
export const ZERO_SLIPPAGE = 0;
export const ZERO_DEADLINE = 0;
export const BN_ZERO = BigNumber.from(0);

export async function shouldRevertNotOwner(p: Promise<any>) {
    await expect(p).to.be.revertedWith("Ownable: caller is not the owner");
}

export async function shouldRevertInvalidAccess(
    contract: { interface: any },
    p: Promise<any>,
) {
    await expect(p).to.be.revertedWithCustomError(contract, "InvalidAccess");
}

export async function shouldRevertErc20Balance(p: Promise<any>) {
    await expect(p).to.be.revertedWith("ERC20: transfer amount exceeds balance");
}

export async function forkMainnet(
  blockNumber: number = 14702622, 
  rpcUrl: string | undefined = process.env.MAINNET_RPC_URL
) {
  console.log("Forking Mainnet:", blockNumber);
  await network.provider.request({
    method: "hardhat_reset",
    params: [
        {
        forking: {
            jsonRpcUrl: rpcUrl,
            blockNumber,
        },
    },
    ],
  });
}

// Impersonate an address and run fn(signer), then stop impersonating.
export async function impersonateSigner(address: string): Promise<Signer> {
  await impersonateAccount(address);
  return await ethers.getSigner(address);
}

export async function recoverToken(token: Contract, amount: BigNumberish, from: Contract, signer: Signer) {
  const balBefore = await token.balanceOf(await signer.getAddress());
  const lib = CommonEventsAndErrors__factory.connect(from.address, signer);
  await expect(from.recoverToken(token.address, await signer.getAddress(), amount))
      .to.emit(lib, "TokenRecovered")
      .withArgs(await signer.getAddress(), token.address, amount);
  const balAfter = await token.balanceOf(await signer.getAddress());
  expect(balAfter.sub(balBefore)).eq(amount);
}

export interface StakingLight {
  balanceOf: (account: string) => Promise<BigNumber>
  address: string
}

type ERC20Light = StakingLight | StakingLight & {name: () => Promise<string>};

export type ChangedBy = BigNumber | Number | 'gt' | 'gte' | 'lt' | 'lte';

export async function expectBalancesChangeBy(
  tx: () => Promise<any>, 
  ...changes: [ERC20Light, Signer|BaseContract, ChangedBy][]
): Promise<void> {
  const oldBalances: BigNumber[] = await getBalances(changes);
  await tx();
  const newBalances: BigNumber[] = await getBalances(changes);

  for (let i = 0; i < changes.length; i++) {
    const [token, account, delta] = changes[i];
    const address = await getAddressOf(account);
    const tokenName = ('name' in token) ? await token.name() : token.address;

    if (delta === "gt") {
      assert(
        newBalances[i].gt(oldBalances[i]),
        `Expected the new balance ${fromAtto(newBalances[i])} for "${address}" on token '${tokenName}' to be greater-than the old balance ${fromAtto(oldBalances[i])} (check #${i})`
      );
    }
    else if (delta === "gte") {
      assert(
        newBalances[i].gte(oldBalances[i]),
        `Expected the new balance ${fromAtto(newBalances[i])} for "${address}" on token '${tokenName}' to be greater-than-or-equal to the old balance ${fromAtto(oldBalances[i])} (check #${i})`
      );
    }
    else if (delta === "lt") {
      assert(
        newBalances[i].lt(oldBalances[i]),
        `Expected the new balance ${fromAtto(newBalances[i])} for "${address}" on token '${tokenName}' to be less-than the old balance ${fromAtto(oldBalances[i])} (check #${i})`
      );
    }
    else if (delta === "lte") {
      assert(
        newBalances[i].lte(oldBalances[i]),
        `Expected the new balance ${fromAtto(newBalances[i])} for "${address}" on token '${tokenName}' to be less-than-or-equal to the old balance ${fromAtto(oldBalances[i])} (check #${i})`
      );
    } else {
      const expectedChange = BigNumber.from(delta);
      const actualChange = newBalances[i].sub(oldBalances[i]);
      assert(
        expectedChange.eq(actualChange),
        `Expected "${address}" on token '${tokenName}' to change balance by ${fromAtto(expectedChange)}, ` +
        `but it has changed by ${fromAtto(actualChange)} (check #${i})`
      );
    }
  }
}

async function getBalances(changes: [ERC20Light, Signer|BaseContract, ChangedBy][]) {
  const balances: BigNumber[] = [];

  for (const [token, account, _] of changes) {
    balances.push(await token.balanceOf(await getAddressOf(account)))
  }

  return balances;
}

export async function getEthBalance(contractOrEoa: Signer | Contract) {
    if ('getBalance' in contractOrEoa) {
        return await contractOrEoa.getBalance();
    } else {
        return await contractOrEoa.provider.getBalance(contractOrEoa.address);
    }
};

async function getAddressOf(account: Signer|BaseContract) {
  if (account instanceof Signer) {
    return await account.getAddress();
  } else {
    return account.address;
  }
}

/**
 * Current block timestamp
 */
export const blockTimestamp = async (): Promise<number> => {
  return await timeHelpers.latest();
}

/**
 * Mine forward the given number of seconds
 */
export const mineForwardSeconds = async (seconds: number) => {
  await timeHelpers.increase(seconds);
}

interface Initializable extends Contract {
  initialize(...args: any[]): Promise<ContractTransaction>;
}

function uupsOpts(constructorArgs?: unknown[]): StandaloneOptions {
  return {kind: 'uups', constructorArgs};
}

export async function deployUupsProxy<T extends Initializable>(
  factory: ContractFactory,
  constructorArgs?: unknown[],
  ...args: Parameters<T['initialize']>): Promise<T> {

  const opts = uupsOpts(constructorArgs);
  const contract = await upgrades.deployProxy(factory, args, opts) as T;
  await contract.deployed();
  return contract;
};

export async function upgradeUupsProxy<T extends Initializable>(
  existingProxyAddress: string,
  constructorArgs: unknown[] | undefined,
  factory: ContractFactory): Promise<T> {

  if (!existingProxyAddress || !isAddress(existingProxyAddress)) {
    throw new Error("Invalid existingProxyAddress");
  }

  const opts = uupsOpts(constructorArgs);
  const contract = await upgrades.upgradeProxy(existingProxyAddress, factory, opts) as T;
  await contract.deployed();
  return contract;
};

export async function upgradeUupsProxyAndCall<T extends Initializable>(
  existingProxyAddress: string,
  factory: ContractFactory,
  constructorArgs: unknown[] | undefined,
  call: string | { fn: string; args?: unknown[] }): Promise<T> {

  if (!existingProxyAddress || !isAddress(existingProxyAddress)) {
    throw new Error("Invalid existingProxyAddress");
  }

  const opts = {
    call,
    ...uupsOpts(constructorArgs)
  };
  const contract = await upgrades.upgradeProxy(existingProxyAddress, factory, opts) as T;
  await contract.deployed();
  return contract;
};

export function toAtto(n: number): BigNumber {
  return ethers.utils.parseEther(n.toString());
}

export function fromAtto(n: BigNumber): number {
  return Number.parseFloat(ethers.utils.formatUnits(n, 18));
}

export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

export const delta = (a: BigNumberish, b: BigNumberish): BigNumber => {
    return BigNumber.from(a).gt(b) ? BigNumber.from(a).sub(b) : BigNumber.from(b).sub(a);
}

export const percentDelta = (a: BigNumberish, b: BigNumberish): BigNumber => {
    return delta(a, b).mul(ONE_ETH).div(b);
}

// deltaPct of 1.0 == 100%
export const tolerance = (deltaPct: number): BigNumber => {
    const pctStr = (deltaPct / 100).toString();
    return ethers.utils.parseEther(pctStr);
}

export const expectApproxEqAbs = (actual: BigNumberish, expected: BigNumberish, maxDelta: BigNumberish) => {
    const d = delta(actual, expected);

    if (d.gt(maxDelta)) {
        console.error("Error: a ~= b not satisfied");
        console.log("  Expected:", expected);
        console.log("    Actual:", actual);
        console.log(" Max Delta:", maxDelta);
        console.log("     Delta:", d);
    // } else {
    //     //     // Uncomment to also show when it is satisfied - useful to know how close things are to the limit.
    //     console.log("Error: a ~= b IS satisfied");
    //     console.log("  Expected:", expected);
    //     console.log("    Actual:", actual);
    //     console.log(" Max Delta:", maxDelta);
    //     console.log("     Delta:", d);
    }
    expect(d).lte(maxDelta);
}

// maxPercentDelta should be in 1e18 terms.
// eg ethers.utils.parseEther("0.0005"); == 0.05%
export const expectApproxEqRel = (actual: BigNumberish, expected: BigNumberish, maxPercentDelta: BigNumberish) => {
    const actualBn = BigNumber.from(actual);
    const expectedBn = BigNumber.from(expected);
    const maxPercentDeltaBn = BigNumber.from(maxPercentDelta);
    if (expectedBn.isZero()) return expect(actualBn).eq(expectedBn);
    const pctDeltaBn = percentDelta(actualBn, expectedBn);

    if (pctDeltaBn.gt(maxPercentDeltaBn)) {
        console.error("Error: a ~= b not satisfied");
        console.log("    Expected:", expectedBn.toString());
        console.log("      Actual:", actualBn.toString());
        console.log("   Abs Delta:", delta(actualBn, expectedBn).toString());
        console.log(" Max % Delta:", maxPercentDeltaBn.toString());
        console.log("     % Delta:", pctDeltaBn.toString());
    // } else {
    //     // Uncomment to also show when it is satisfied - useful to know how close things are to the limit.
    //     console.log("Error: a ~= b IS satisfied");
    //     console.log("    Expected:", expectedBn.toString());
    //     console.log("      Actual:", actualBn.toString());
    //     console.log("   Abs Delta:", delta(actualBn, expectedBn).toString());
    //     console.log(" Max % Delta:", maxPercentDeltaBn.toString());
    //     console.log("     % Delta:", pctDeltaBn.toString());
    }
    expect(pctDeltaBn).lte(maxPercentDeltaBn);
}

export const expectApproxEqRelPred = (expected: BigNumber, maxPercentDelta: BigNumberish) => {
    return (actual: BigNumber) => {
        // This will throw if false
        try {
            expectApproxEqRel(actual, expected, maxPercentDelta);
            return true;
        } catch (e: unknown) {
            if (e instanceof AssertionError) {
                console.error(e.message);
            } else {
                throw e;
            }
            return false;
        }
    };
}

const investQuoteTypes = 'tuple(address fromToken, uint256 fromTokenAmount, uint256 maxSlippageBps, uint256 deadline, uint256 expectedInvestmentAmount, uint256 minInvestmentAmount, bytes underlyingInvestmentQuoteData)';
export const encodeInvestQuoteData = (quoteData: IOrigamiInvestment.InvestQuoteDataStruct): string => {
    return ethers.utils.defaultAbiCoder.encode(
        [investQuoteTypes], 
        [quoteData]
    );
}

export const decodeInvestQuoteData = (encodedQuoteData: string): IOrigamiInvestment.InvestQuoteDataStruct => {
    return ethers.utils.defaultAbiCoder.decode(
        [investQuoteTypes], 
        encodedQuoteData
    )[0];
}

const exitQuoteTypes = 'tuple(uint256 investmentTokenAmount, address toToken, uint256 maxSlippageBps, uint256 deadline, uint256 expectedToTokenAmount, uint256 minToTokenAmount, bytes underlyingInvestmentQuoteData)';
export const encodeExitQuoteData = (quoteData: IOrigamiInvestment.ExitQuoteDataStruct): string => {
    return ethers.utils.defaultAbiCoder.encode(
        [exitQuoteTypes], 
        [quoteData]
    );
}

export const decodeExitQuoteData = (encodedQuoteData: string): IOrigamiInvestment.ExitQuoteDataStruct => {
    return ethers.utils.defaultAbiCoder.decode(
        [exitQuoteTypes], 
        encodedQuoteData
    )[0];
}

export const signedPermit = async(
    signer: OrigamiSignerWithAddress,
    token: ERC20Permit,
    spender: string,
    amount: BigNumberish,
    deadline: number,
) => {
    const chainId = await signer.getChainId();
    const signerAddr = await signer.getAddress();
    const nonce = await token.nonces(signerAddr);
    
    const domain: TypedDataDomain = {
        name: await token.name(),
        version: '1',
        chainId,
        verifyingContract: token.address
    };

    const permit: Record<string, TypedDataField[]> = {
        Permit: [
            { name: 'owner', type: 'address' },
            { name: 'spender', type: 'address' },
            { name: 'value', type: 'uint256' },
            { name: 'nonce', type: 'uint256' },
            { name: 'deadline', type: 'uint256' },
        ],
    };

    const value = {
        owner: signerAddr,
        spender,
        value: amount,
        nonce,
        deadline,
    };

    const signature = await signer._signTypedData(domain, permit, value);
    return splitSignature(signature);
}

export const testErc20Permit = async (
    token: ERC20Permit, 
    signer: OrigamiSignerWithAddress, 
    spender: Signer, 
    amount: BigNumberish
) => {
    const now = await blockTimestamp();   
    const allowanceBefore = await token.allowance(signer.getAddress(), spender.getAddress());

    // Check for expired deadlines
    {
        const deadline = now - 1;
        const { v, r, s } = await signedPermit(signer, token, await spender.getAddress(), amount, deadline);
        await expect(token.permit(
            signer.getAddress(),
            spender.getAddress(),
            amount,
            deadline,
            v,
            r,
            s
        )).to.revertedWith("ERC20Permit: expired deadline");
    }

    // Permit successfully increments the allowance
    const deadline = now + 3600;
    const { v, r, s } = await signedPermit(signer, token, await spender.getAddress(), amount, deadline);
    {
        await token.permit(
            signer.getAddress(),
            spender.getAddress(),
            amount,
            deadline,
            v,
            r,
            s,
        );
        
        expect(await token.allowance(signer.getAddress(), spender.getAddress())).to.eq(allowanceBefore.add(amount));   
    }
            
    // Can't re-use the same signature for another permit (the nonce was incremented)
    {
        await expect(token.permit(
            signer.getAddress(),
            spender.getAddress(),
            amount,
            deadline,
            v,
            r,
            s,
        )).to.revertedWith("ERC20Permit: invalid signature");
    }
}

export const applySlippage = (
    expectedAmount: BigNumberish, 
    slippageBps: number
) => BigNumber.from(expectedAmount).mul(10_000 - slippageBps).div(10_000);

export async function setExplicitAccess(contract: Contract, allowedCaller: string, fnNames: string[], value: boolean) {
  const access: IOrigamiElevatedAccess.ExplicitAccessStruct[] = fnNames.map(fn => {
      return {
          fnSelector: contract.interface.getSighash(contract.interface.getFunction(fn)),
          allowed: value
      }
  });
  await contract.setExplicitAccess(allowedCaller, access);
}
