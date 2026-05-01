import * as fs from "fs";
import { TokenPrices } from "../../typechain/contracts/common/TokenPrices";
import { BigNumber, Contract } from "ethers";
import { IOrigamiElevatedAccess } from "../../typechain";
import { network } from "hardhat";

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
  | "tuple"
  | "tuple[]"
  | "struct IOrigamiElevatedAccess.ExplicitAccess[]"
  | "struct IOrigamiInvestment.InvestQuoteData"
  | "struct IBalancerVault.JoinPoolRequest"
  | "struct IBalancerVault.ExitPoolRequest"
  | "struct IOrigamiManagerPausable.Paused"
  | "address[]"
  | "uint256[]"
  | "bytes[]"
  | "bytes32"
  | "uint256"
  | "uint128"
  | "uint16"
  | "uint32"
  | "uint24"
  | "string"
  | "contract IInfraredVault"
  | "struct TokenPrices.PriceMapping[]";

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
      type: ta.argType.startsWith("contract ") ? "address" : ta.argType,
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
  transactions: SafeTransaction[],
): SafeTransactionsBatch {
  return {
    chainId: (network.config.chainId || "").toString(),
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

export function setTokenPriceFunctions(
  contract: Contract,
  mappings: TokenPrices.PriceMappingStruct[]
): SafeTransaction {
  const mappingDatas = mappings.map(m => `[\"${m.token}\",\"${m.fnCalldata}\"]`);
  
  return {
    to: contract.address,
    value: "0",
    data: null,
    contractMethod: {
      name: "setTokenPriceFunctions",
      payable: false,
      inputs: [
        {
          components: [
            { 
              internalType: "address",
              name: "token",
              type: "address"
            },
            {
              internalType: "bytes",
              name: "fnCalldata",
              type: "bytes"
            },
          ],
          internalType: "struct TokenPrices.PriceMapping[]",
          name: "mappings",
          type: "tuple[]",
        },
      ],
    },
    contractInputsValues: {
      mappings: `[${mappingDatas.join(`,`)}]`,
    },
  };
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

export function acceptOwnerAddr(
  address: string
) {
  return createSafeTransaction(
    address,
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

export function approve(
  contract: Contract,
  spender: string,
  amount: BigNumber
) {
  return createSafeTransaction(
    contract.address,
    "approve",
    [
      {
        argType: "address",
        name: "spender",
        value: spender,
      },
      {
        argType: "uint256",
        name: "amount",
        value: amount.toString(),
      },
    ],
  )
}

export function transfer(
  contract: Contract,
  to: string,
  amount: BigNumber
) {
  return createSafeTransaction(
    contract.address,
    "transfer",
    [
      {
        argType: "address",
        name: "to",
        value: to,
      },
      {
        argType: "uint256",
        name: "amount",
        value: amount.toString(),
      },
    ],
  )
}

export function setMaxTotalSupply(
  contract: Contract,
  maxSupply: BigNumber
) {
  return createSafeTransaction(
    contract.address,
    "setMaxTotalSupply",
    [
      {
        argType: "uint256",
        name: "_maxTotalSupply",
        value: maxSupply.toString(),
      },
    ],
  )
}

export function seedOrigami4626(
  contract: Contract,
  assetAmount: BigNumber,
  receiver: string,
  newMaxTotalSupply: BigNumber,
): SafeTransaction {
  return createSafeTransaction(
    contract.address,
    "seedDeposit",
    [
      {
        argType: "uint256",
        name: "assets",
        value: assetAmount.toString(),
      },
      {
        argType: "address",
        name: "receiver",
        value: receiver,
      },
      {
        argType: "uint256",
        name: "maxTotalSupply_",
        value: newMaxTotalSupply.toString(),
      },
    ],
  )
}

export function seedTokenizedBalanceSheet(
  contract: Contract,
  assetAmounts: BigNumber[],
  liabilityAmounts: BigNumber[],
  sharesToMint: BigNumber,
  receiver: string,
  newMaxTotalSupply: BigNumber,
  balanceSheetData: string,
): SafeTransaction {
  return createSafeTransaction(
    contract.address,
    "seed",
    [
      {
        argType: "uint256[]",
        name: "assetAmounts",
        value: `["${assetAmounts.join('","')}"]`,
      },
      {
        argType: "uint256[]",
        name: "liabilityAmounts",
        value: `["${liabilityAmounts.join('","')}"]`,
      },
      {
        argType: "uint256",
        name: "sharesToMint",
        value: sharesToMint.toString(),
      },
      {
        argType: "address",
        name: "receiver",
        value: receiver,
      },
      {
        argType: "uint256",
        name: "newMaxTotalSupply",
        value: newMaxTotalSupply.toString(),
      },
      {
        argType: "bytes",
        name: "balanceSheetData",
        value: balanceSheetData,
      },
    ],
  );
}

export function setSwapper(
  contract: Contract,
  swapper: string,
) {
  return createSafeTransaction(
    contract.address,
    "setSwapper",
    [
      {
        argType: "address",
        name: "_swapper",
        value: swapper,
      },
    ],
  )
}

export function recoverToken(
  contract: Contract,
  token: string,
  to: string,
  amount: BigNumber,
) {
  return createSafeTransaction(
    contract.address, 
    "recoverToken", 
    [
      {
        argType: "address",
        name: "_token",
        value: token,
      },
      {
        argType: "address",
        name: "_to",
        value: to,
      },
      {
        argType: "uint256",
        name: "_amount",
        value: amount.toString(),
      },
    ]
  );
}

export function setExplicitAccess(
  contract: Contract,
  allowedCaller: string,
  fnNames: string[],
  value: boolean
): SafeTransaction {
  const access: IOrigamiElevatedAccess.ExplicitAccessStruct[] = fnNames.map(
    (fn) => ({
      fnSelector: contract.interface.getSighash(
        contract.interface.getFunction(fn)
      ),
      allowed: value,
    })
  );

  return {
    to: contract.address,
    value: "0",
    data: null,
    contractMethod: {
      inputs: [
        {
          internalType: "address",
          name: "_allowedCaller",
          type: "address",
        },
        {
          internalType: "struct IOrigamiElevatedAccess.ExplicitAccess[]",
          name: "_access",
          type: "tuple[]",
          components: [
            {
              internalType: "bytes4",
              name: "fnSelector",
              type: "bytes4",
            },
            {
              internalType: "bool",
              name: "allowed",
              type: "bool",
            },
          ],
        },
      ],
      name: "setExplicitAccess",
      payable: false,
    },
    contractInputsValues: {
      _allowedCaller: allowedCaller,
      _access: JSON.stringify(access.map((a) => [a.fnSelector, a.allowed])),
    },
  };
}

export function whitelistRouter(
  swapperContract: Contract,
  routerAddress: `0x${string}`,
  allowed: boolean
): SafeTransaction {
  return createSafeTransaction(swapperContract.address, "whitelistRouter", [
    {
      argType: "address",
      name: "router",
      value: routerAddress,
    },
    {
      argType: "bool",
      name: "allowed",
      value: allowed.toString(),
    },
  ]);
}

export function addOpalAdapter(
  managerContract: Contract,
  implementationAddress: string,
  description: string,
  immutableArgsData: string,
  initData: string,
): SafeTransaction {
  return createSafeTransaction(managerContract.address, "addAdapter", [
    {
      argType: "address",
      name: "implementation",
      value: implementationAddress,
    },
    {
      argType: "bytes32",
      name: "description",
      value: description,
    },
    {
      argType: "bytes",
      name: "immutableArgsData",
      value: immutableArgsData,
    },
    {
      argType: "bytes",
      name: "initData",
      value: initData,
    },
  ]);
}

export function setFeeCollector(
  contract: Contract,
  newFeeCollector: string,
): SafeTransaction {
  return createSafeTransaction(contract.address, "setFeeCollector", [
    {
      argType: "address",
      name: "_feeCollector",
      value: newFeeCollector,
    },
  ]);
}

export function setOpalAdapterDeprecated(
  adapterContract: Contract,
  value: boolean
): SafeTransaction {
  return createSafeTransaction(adapterContract.address, "setDeprecated", [
    {
      argType: "bool",
      name: "value",
      value: value ? "true" : "false",
    },
  ]);
}

export function removeOpalAdapter(
  managerContract: Contract,
  adapterContract: Contract
): SafeTransaction {
  return createSafeTransaction(managerContract.address, "removeAdapter", [
    {
      argType: "address",
      name: "adapter",
      value: adapterContract.address,
    },
  ]);
}

export function setBundlerApproved(
  pluginContract: Contract,
  opalManager: Contract,
  value: boolean
): SafeTransaction {
  return createSafeTransaction(pluginContract.address, "setBundlerApproved", [
    {
      argType: "address",
      name: "account",
      value: opalManager.address,
    },
    {
      argType: "bool",
      name: "value",
      value: value ? "true" : "false",
    },
  ]);
}

export function setTbsPluginTrusted(
  tbsPlugin: Contract,
  opalToken: Contract,
): SafeTransaction {
  return createSafeTransaction(tbsPlugin.address, "trustVault", [
    {
      argType: "address",
      name: "vault",
      value: opalToken.address,
    },
  ]);
}

export function setPauserEnabled(
  managerContract: Contract,
  account: string,
  canPause: boolean,
): SafeTransaction {
  return createSafeTransaction(managerContract.address, "setPauser", [
    {
      argType: "address",
      name: "account",
      value: account,
    },
    {
      argType: "bool",
      name: "canPause",
      value: canPause.toString(),
    },
  ]);
}

export function setPaused(
  managerContract: Contract,
  investmentsPaused: boolean,
  exitsPaused: boolean,
): SafeTransaction {
  return {
    to: managerContract.address,
    value: "0",
    data: null,
    contractMethod: {
      name: "setPaused",
      payable: false,
      inputs: [
        {
          components: [
            {
              internalType: "bool",
              name: "investmentsPaused",
              type: "bool",
            },
            {
              internalType: "bool",
              name: "exitsPaused",
              type: "bool",
            },
          ],
          internalType: "struct IOrigamiManagerPausable.Paused",
          name: "updatedPaused",
          type: "tuple",
        },
      ],
    },
    contractInputsValues: {
      updatedPaused: JSON.stringify([investmentsPaused, exitsPaused]),
    },
  };
}

export function setOasPaused(
  oasContract: Contract,
  onStake: boolean,
  onWithdraw: boolean,
  onGetReward: boolean,
): SafeTransaction {
  return {
    to: oasContract.address,
    value: "0",
    data: null,
    contractMethod: {
      name: "setPaused",
      payable: false,
      inputs: [
        {
          name: "onStake_",
          type: "bool",
          internalType: "bool",
        },
        {
          name: "onWithdraw_",
          type: "bool",
          internalType: "bool",
        },
        {
          name: "onGetReward_",
          type: "bool",
          internalType: "bool",
        },
      ],
    },
    contractInputsValues: {
      onStake_: `${onStake}`,
      onWithdraw_: `${onWithdraw}`,
      onGetReward_: `${onGetReward}`,
    },
  };
}
