export interface Chain {
  id: number;
  name: string,
  transactionUrl(txhash: string): string,
}

export const MUMBAI : Chain = {
  id: 80001,
  name: "Polygon Mumbai",
  transactionUrl(txhash: string) {
    return `https://mumbai.polygonscan.com/tx/${txhash}`;
  }
};

export const ARBITRUM : Chain = {
  id: 42161,
  name: "Arbitrum",
  transactionUrl(txhash: string) {
    return `https://arbiscan.io/tx/${txhash}`;
  }
};

