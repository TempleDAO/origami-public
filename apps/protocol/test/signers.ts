import { ethers } from "ethers";
import { default as hre, network } from "hardhat";
import { time as timeHelpers } from "@nomicfoundation/hardhat-network-helpers";

// The same as "@nomiclabs/hardhat-ethers/signers.SignerWithAddress"
// Except force the block timestamp to increment by exactly one on each send transaction.
// Can't extend SignerWithAddress as the constructor is private.
// https://github.com/NomicFoundation/hardhat/issues/3635
export class OrigamiSignerWithAddress extends ethers.Signer {
  public static async create(signer: ethers.providers.JsonRpcSigner) {
    return new OrigamiSignerWithAddress(await signer.getAddress(), signer);
  }

  private constructor(
    public readonly address: string,
    private readonly _signer: ethers.providers.JsonRpcSigner
  ) {
    super();
    (this as any).provider = _signer.provider;
  }

  public async getAddress(): Promise<string> {
    return this.address;
  }

  public signMessage(message: string | ethers.utils.Bytes): Promise<string> {
    return this._signer.signMessage(message);
  }

  public signTransaction(
    transaction: ethers.utils.Deferrable<ethers.providers.TransactionRequest>
  ): Promise<string> {
    return this._signer.signTransaction(transaction);
  }

  public async sendTransaction(
    transaction: ethers.utils.Deferrable<ethers.providers.TransactionRequest>
  ): Promise<ethers.providers.TransactionResponse> {
    // Ensure we increment the block by exactly 1
    const currentTime = await timeHelpers.latest();
    await network.provider.send("evm_setNextBlockTimestamp", [currentTime+1]);
    return this._signer.sendTransaction(transaction);
  }

  public connect(provider: ethers.providers.Provider): OrigamiSignerWithAddress {
    return new OrigamiSignerWithAddress(this.address, this._signer.connect(provider));
  }

  public _signTypedData(
    ...params: Parameters<ethers.providers.JsonRpcSigner["_signTypedData"]>
  ): Promise<string> {
    return this._signer._signTypedData(...params);
  }

  public toJSON() {
    return `<OrigamiSignerWithAddress ${this.address}>`;
  }
}

export async function getSigners(
  ): Promise<OrigamiSignerWithAddress[]> {
    const accounts = await hre.ethers.provider.listAccounts();
    return await Promise.all(
      accounts.map((account) => getSigner(account))
    );
  }
  
export async function getSigner(
    address: string
  ): Promise<OrigamiSignerWithAddress> {
    const signer = hre.ethers.provider.getSigner(address);  
    return await OrigamiSignerWithAddress.create(signer);
  }