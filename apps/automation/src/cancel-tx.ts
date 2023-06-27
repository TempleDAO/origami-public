import * as ethers from 'ethers';

async function main() { 
  const privateKey = process.env.SIGNER_PRIVATE_KEY;
  if (privateKey == undefined ) {
    throw new Error("SIGNER_PRIVATE_KEY env not defined");
  }
  const alchemyKey = process.env.ALCHEMY_KEY;
  if (alchemyKey == undefined ) {
    throw new Error("ALCHEMY_KEY env not defined");
  }

  if (process.argv.length != 5) {
    throw new Error("Usage: node cancel-tx.js NETWORK NONCE GASPRICE");
  }

  const network = parseInt(process.argv[2]);
  const nonce = parseInt(process.argv[3]);
  const gasPrice = ethers.BigNumber.from(process.argv[4]);

  const provider = new ethers.providers.AlchemyProvider(network,alchemyKey);
  const wallet = new ethers.Wallet(privateKey, provider);
  console.log("Wallet address is " + wallet.address);

  const tx: ethers.providers.TransactionRequest = {
    nonce,
    to: ethers.constants.AddressZero,
    data: '0x',
    gasPrice,
  };

  const txResponse: ethers.providers.TransactionResponse = await wallet.sendTransaction(tx);
  console.log("Submitted tx " + txResponse.hash);
  const txReceipt = await txResponse.wait();
  console.log("Mined tx " + txReceipt.transactionHash);
}


main();
