import { network, ethers, upgrades } from "hardhat";
import { BaseContract, BigNumber, BigNumberish, Contract, ContractFactory, ContractTransaction, Signer, TypedDataDomain, TypedDataField } from "ethers";
import { assert, expect } from "chai";
import { CommonEventsAndErrors__factory, ERC20Permit, IOrigamiInvestment } from "../typechain";
import { impersonateAccount, time as timeHelpers } from "@nomicfoundation/hardhat-network-helpers";
import { isAddress, splitSignature } from "ethers/lib/utils";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

export const EmptyBytes = "0x";

export async function shouldRevertNotOwner(p: Promise<any>) {
  await expect(p).to.be.revertedWith("Ownable: caller is not the owner");
}

export async function shouldRevertPaused(p: Promise<any>) {
  await expect(p).to.be.revertedWith("Pausable: paused");
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

export async function deployUupsProxy<T extends Initializable>(
  factory: ContractFactory,
  ...args: Parameters<T['initialize']>): Promise<T> {

  const contract = await upgrades.deployProxy(factory, args, {kind: 'uups'}) as T;
  await contract.deployed();
  return contract;
};

export async function upgradeUupsProxy<T extends Initializable>(
  existingProxyAddress: string,
  factory: ContractFactory): Promise<T> {

  if (!existingProxyAddress || !isAddress(existingProxyAddress)) {
    throw new Error("Invalid existingProxyAddress");
  }

  const contract = await upgrades.upgradeProxy(existingProxyAddress, factory, {kind: 'uups'}) as T;
  await contract.deployed();
  return contract;
};

export async function upgradeUupsProxyAndCall<T extends Initializable>(
  existingProxyAddress: string,
  factory: ContractFactory,
  call: string | { fn: string; args?: unknown[] }): Promise<T> {

  if (!existingProxyAddress || !isAddress(existingProxyAddress)) {
    throw new Error("Invalid existingProxyAddress");
  }

  const contract = await upgrades.upgradeProxy(existingProxyAddress, factory, {call, kind: 'uups'}) as T;
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

export const slightlyGte = (lhs: BigNumber, rhs: BigNumber, epsilon: BigNumberish) => {
  if (typeof epsilon === 'number') {
    epsilon = toAtto(epsilon);
  }

  // console.log("slightlyGte", lhs, rhs, epsilon, lhs.gte(rhs) && lhs.lte(rhs.add(epsilon)));
  return lhs.gte(rhs) && lhs.lte(rhs.add(epsilon));
} 

export const slightlyLte = (lhs: BigNumber, rhs: BigNumber, epsilon: BigNumberish) => {
    if (typeof epsilon === 'number') {
      epsilon = toAtto(epsilon);
    }
  
    // console.log("slightlyLte", lhs, rhs, epsilon, lhs.lte(rhs) && lhs.gte(rhs.sub(epsilon)));
    return lhs.lte(rhs) && lhs.gte(rhs.sub(epsilon));
}

// Hardhat matcher predicate, where the value matches an expected value 
// to within a certain precision.
export const slightlyGtePred = (rhs: BigNumber, epsilon: number) => {
  return (lhs: BigNumber) => slightlyGte(lhs, rhs, epsilon);
}

const investQuoteTypes = 'tuple(address fromToken, uint256 fromTokenAmount, uint256 expectedInvestmentAmount, bytes underlyingInvestmentQuoteData)';
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

export const signedPermit = async(
    signer: SignerWithAddress,
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
    signer: SignerWithAddress, 
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