import * as fs from "fs";
import { TokenPrices } from "../../typechain/contracts/common/TokenPrices";
import { Contract } from "ethers";

interface SafeTransactionsBatch {
  chainId: string;
  meta: {},
  transactions: SafeTransaction[],
}

type DataType = 
  | "address"
  | "bytes"
  | "bytes4"
  | "bool"
  | "tuple[]"
  | "struct IOrigamiElevatedAccess.ExplicitAccess[]";

interface InputType {
  internalType: DataType;
  name: string;
  type: DataType;
  components?: InputType[];
}

export interface SafeTransaction {
  to: string;
  value: string;
  data: null;
  contractMethod: {
    inputs: InputType[];
    name: string;
    payable: boolean;
  }
  contractInputsValues: {[key:string]: string}
}

interface TransactionArgument {
  argType: DataType;
  name: string;
  value: string;
}

export function createSafeTransaction(
  contractAddr: string, 
  functionName: string,
  args: TransactionArgument[]
): SafeTransaction {
  const inputs: InputType[] = args.map(ta => {
    return {
      internalType: ta.argType,
      name: ta.name,
      type: ta.argType,
    };
  });
  const contractInputsValues = Object.fromEntries(
    args.map(ta => [ta.name, ta.value])
  );

  return {
    to: contractAddr,
    value: "0",
    data: null,
    contractMethod: {
      inputs,
      name: functionName,
      payable: false,
    },
    contractInputsValues
  }
}

export function createSafeBatch(
  chainId: number,
  transactions: SafeTransaction[],
): SafeTransactionsBatch {
  return {
    chainId: chainId.toString(),
    meta: {},
    transactions,
  };
}

export function writeSafeTransactionsBatch(
  batch: SafeTransactionsBatch,
  filePath: string,
) {
  const json = JSON.stringify(batch, null, 2);
  fs.writeFileSync(filePath, json);
}

function readSafeTransactionsBatch(
  filePath: string,
): SafeTransactionsBatch {
  const data = fs.readFileSync(filePath, {encoding: "utf8"});
  return JSON.parse(data);
}

export function appendTransactionsToBatch(
  filePath: string,
  transactions: SafeTransaction[],
) {
  const batch = readSafeTransactionsBatch(filePath);
  batch.transactions = [
    ...batch.transactions,
    ...transactions,
  ];
  writeSafeTransactionsBatch(batch, filePath);
  console.log(`Updated Safe tx's batch to: ${filePath}`);
}

export function setTokenPriceFunction(
  contract: TokenPrices,
  tokenAddress: string,
  fnCalldata: string,
) {
  return createSafeTransaction(
    contract.address,
    "setTokenPriceFunction",
    [
      {
        argType: "address",
        name: "tokenAddress",
        value: tokenAddress,
      },
      {
        argType: "bytes",
        name: "fnCalldata",
        value: fnCalldata,
      },
    ],
  )
}

export function acceptOwner(
  contract: Contract
) {
  return createSafeTransaction(
    contract.address,
    "acceptOwner",
    [],
  )
}

export function setTokenPrices(
  contract: Contract,
  tokenPricesAddress: string
) {
  return createSafeTransaction(
    contract.address,
    "setTokenPrices",
    [
      {
        argType: "address",
        name: "_tokenPrices",
        value: tokenPricesAddress,
      },
    ],
  )
}
