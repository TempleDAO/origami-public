import '@nomiclabs/hardhat-ethers';
import {
  mine,
  runAsyncMain,
  ZERO_ADDRESS,
} from '../../helpers';
import { getDeployContext } from '../deploy-context';
import { BigNumber, Contract, ethers } from 'ethers';
import { ContractInstances } from '../contract-addresses';
import { ContractAddresses } from '../contract-addresses/types';
import { IBalancerBptToken, IBalancerVault } from '../../../../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { approve, createSafeBatch, createSafeTransaction, SafeTransaction, writeSafeTransactionsBatch } from '../../safe-tx-builder';
import path from 'path';

let owner: SignerWithAddress;
let INSTANCES: ContractInstances;
let ADDRS: ContractAddresses;

interface PoolInfo {
  tokens: string[];
  balances: BigNumber[];
  poolId: string;
  bptInstance: IBalancerBptToken;
}

let HONEY_USDC_POOL_INFO: PoolInfo;
let HONEY_BYUSD_POOL_INFO: PoolInfo;

const ONE_USDC = ethers.utils.parseUnits("1", 6);
const SCALE_USDC_TO_HONEY = ethers.utils.parseUnits("1", 12);
const BALANCER_SLIPPAGE_BPS = 3;

async function initPool(
  bptInstance: IBalancerBptToken,
): Promise<PoolInfo> {
  const poolId = await bptInstance.getPoolId();
  console.log("Pool ID:", poolId);
  const ptokens = await INSTANCES.EXTERNAL.BEX.BALANCER_VAULT.getPoolTokens(poolId);

  return {
    tokens: ptokens.tokens,
    balances: ptokens.balances,
    poolId,
    bptInstance: bptInstance,
  }
}

async function initState() {
  console.log("HONEY_USDC_POOL_INFO:");
  HONEY_USDC_POOL_INFO = await initPool(INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_USDC);
  console.log("HONEY_BYUSD_POOL_INFO:");
  HONEY_BYUSD_POOL_INFO = await initPool(INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_BYUSD);

  // Check Honey minting
  {
    const isBasketModeEnabled = await INSTANCES.EXTERNAL.BERACHAIN.HONEY_FACTORY.isBasketModeEnabled(true);
    console.log(`PSM isBasketModeEnabled = ${isBasketModeEnabled}`);
    if (isBasketModeEnabled) throw new Error("Cannot deploy proportional liquidity if BasketMode is enabled in HoneyFactory PSM");

    const [, usdcToHoneyMintRate] = await INSTANCES.EXTERNAL.BERACHAIN.HONEY_FACTORY_READER.previewMintHoney(ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN, ONE_USDC);
    console.log(`USDC => HONEY mint rate: ${ethers.utils.formatEther(usdcToHoneyMintRate)}`);
    if (usdcToHoneyMintRate.lt(MIN_REQUIRED_HONEY_MINT_RATE)) throw new Error("USDC=>HONEY mint rate too low");
  }
 
}

const MIN_REQUIRED_HONEY_MINT_RATE = ethers.utils.parseEther("1");

interface JoinQuote {
  tokenAmounts: BigNumber[],
  expectedLpTokenAmount: BigNumber,
  minLpTokenAmount: BigNumber,
  requestData: IBalancerVault.JoinPoolRequestStruct
}

interface ExitQuote {
  bptAmount: BigNumber;
  expectedTokenAmounts: BigNumber[];
  requestData: IBalancerVault.ExitPoolRequestStruct;
}

/// @dev Join providing one token https://github.com/balancer/balancer-v2-monorepo/blob/36d282374b457dddea828be7884ee0d185db06ba/pkg/interfaces/contracts/pool-stable/StablePoolUserData.sol#L18
const EXACT_TOKENS_IN_FOR_BPT_OUT = 1;

/// @dev Exit to all tokens https://github.com/balancer/balancer-v2-monorepo/blob/36d282374b457dddea828be7884ee0d185db06ba/pkg/interfaces/contracts/pool-stable/StablePoolUserData.sol#L19
const EXACT_BPT_IN_FOR_ALL_TOKENS_OUT = 2;

const ZERO = BigNumber.from(0);

interface TokenIndexes {
  token1: number;
  token2: number;
  bpt: number;
}

function getTokenIndexes(poolInfo: PoolInfo, token1Address: string, token2Address: string): TokenIndexes {
  let token1Index: number = 0;
  let token2Index: number = 0;
  let bptIndex: number = 0;
  for (let i = 0; i < poolInfo.tokens.length; i++) {
    if (poolInfo.tokens[i].toLowerCase() === token1Address.toLowerCase()) {
      token1Index = i;
    } else if (poolInfo.tokens[i].toLowerCase() === token2Address.toLowerCase()) {
      token2Index = i;
    } else if (poolInfo.tokens[i].toLowerCase() === poolInfo.bptInstance.address.toLowerCase()) {
      bptIndex = i;
    }
  }

  return {
    token1: token1Index,
    token2: token2Index,
    bpt: bptIndex
  }
}

async function exactBptExitQuote(
  poolInfo: PoolInfo,
  bptAmount: BigNumber,
  slippageBps: number
): Promise<ExitQuote> {
  if (bptAmount == ZERO) throw new Error("Invalid BPT amount");

  const userData = ethers.utils.defaultAbiCoder.encode(
    ['uint8', 'uint256'],
    [EXACT_BPT_IN_FOR_ALL_TOKENS_OUT, bptAmount]
  );

  const response = await INSTANCES.EXTERNAL.BEX.BALANCER_QUERIES.callStatic.queryExit(
    poolInfo.poolId,
    ZERO_ADDRESS,
    ZERO_ADDRESS,
    {
      assets: poolInfo.tokens,
      minAmountsOut: [],
      userData,
      toInternalBalance: false
    }
  );
  const expectedTokenAmounts = response.amountsOut;

  // Apply slippage
  const minTokenAmounts: BigNumber[] = [];
  for (let i=0; i < expectedTokenAmounts.length; ++i) {
    minTokenAmounts.push(
      expectedTokenAmounts[i]
        .mul(10_000-slippageBps)
        .div(10_000)
    );
  }

  return {
    bptAmount,
    expectedTokenAmounts,
    requestData: {
      assets: poolInfo.tokens,
      minAmountsOut: minTokenAmounts,
      userData,
      toInternalBalance: false
    }
  }
}

async function exactTokensJoinQuote(
  poolInfo: PoolInfo,
  tokenIndexes: TokenIndexes,
  token1Amount: BigNumber, // honey
  token2Amount: BigNumber, // byusd | usdc
  slippageBps: number
): Promise<JoinQuote> {
  if (token1Amount == ZERO) throw new Error("Invalid TOKEN1 amount");
  if (token2Amount == ZERO) throw new Error("Invalid TOKEN2 amount");

  const tokenAmounts = [ZERO, ZERO, ZERO];
  tokenAmounts[tokenIndexes.token1] = token1Amount;
  tokenAmounts[tokenIndexes.token2] = token2Amount;

  const udAmountsIn = tokenIndexes.token1 < tokenIndexes.token2
    ? [tokenAmounts[tokenIndexes.token1], tokenAmounts[tokenIndexes.token2]]
    : [tokenAmounts[tokenIndexes.token2], tokenAmounts[tokenIndexes.token1]];
  const userData = ethers.utils.defaultAbiCoder.encode(
    ['uint8', 'uint256[]', 'uint256'],
    [EXACT_TOKENS_IN_FOR_BPT_OUT, udAmountsIn, 0]
  );

  const response = await INSTANCES.EXTERNAL.BEX.BALANCER_QUERIES.callStatic.queryJoin(
    poolInfo.poolId,
    ZERO_ADDRESS,
    ZERO_ADDRESS,
    {
      assets: poolInfo.tokens,
      maxAmountsIn: tokenAmounts,
      userData,
      fromInternalBalance: false
    }
  );
  const expectedLpTokenAmount = response.bptOut;

  // Apply slippage
  const minLpTokenAmount = expectedLpTokenAmount
    .mul(10_000 - slippageBps)
    .div(10_000);

  const requestData: IBalancerVault.JoinPoolRequestStruct = {
    assets: poolInfo.tokens,
    maxAmountsIn: tokenAmounts,
    userData: ethers.utils.defaultAbiCoder.encode(
      ['uint8', 'uint256[]', 'uint256'],
      [EXACT_TOKENS_IN_FOR_BPT_OUT, udAmountsIn, minLpTokenAmount]
    ),
    fromInternalBalance: false
  };

  return {
    tokenAmounts,
    expectedLpTokenAmount,
    minLpTokenAmount,
    requestData
  }
}

async function deployAsOwnerStep1(
  honeyUsdcBexQuote: ExitQuote,
) {
  const provider = new ethers.providers.JsonRpcProvider("http://127.0.0.1:8545");
  await provider.send('anvil_impersonateAccount', [ADDRS.CORE.MULTISIG]);
  const signer  = provider.getSigner(ADDRS.CORE.MULTISIG);
  const signerAddr = await signer.getAddress();

  const balancesBefore = await Promise.all([
    INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.balanceOf(ADDRS.VAULTS.BOYCO_USDC_A.MANAGER),
    INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.balanceOf(signerAddr),
    INSTANCES.EXTERNAL.BERACHAIN.HONEY_TOKEN.balanceOf(signerAddr),
    INSTANCES.EXTERNAL.PAYPAL.BYUSD_TOKEN.balanceOf(signerAddr),
    INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_USDC.balanceOf(signerAddr),
    INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_BYUSD.balanceOf(signerAddr),
    INSTANCES.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_USDC.stakedBalance(),
    INSTANCES.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_BYUSD.stakedBalance(),
  ]);
  console.log("Balances Before:");
  console.log("\tUSDC.e (manager):", ethers.utils.formatUnits(balancesBefore[0], 6));
  console.log("\tUSDC.e (msig):", ethers.utils.formatUnits(balancesBefore[1], 6));
  console.log("\tHONEY (msig):", ethers.utils.formatUnits(balancesBefore[2], 18));
  console.log("\tBYUSD (msig):", ethers.utils.formatUnits(balancesBefore[3], 6));
  console.log("\tHONEY|USDC BPT (msig):", ethers.utils.formatUnits(balancesBefore[4], 18));
  console.log("\tHONEY|BYUSD BPT (msig):", ethers.utils.formatUnits(balancesBefore[5], 18));
  console.log("\tHONEY|USDC BPT (infrared proxy):", ethers.utils.formatUnits(balancesBefore[6], 18));
  console.log("\tHONEY|BYUSD BPT (infrared proxy):", ethers.utils.formatUnits(balancesBefore[7], 18));

  // 1. Unstake
  await mine(
    INSTANCES.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_USDC.connect(signer).withdraw(honeyUsdcBexQuote.bptAmount, signerAddr)
  );

  // 2. Exit
  await mine(
    INSTANCES.EXTERNAL.BEX.BALANCER_VAULT.connect(signer).exitPool(
      HONEY_USDC_POOL_INFO.poolId,
      signerAddr,
      signerAddr,
      honeyUsdcBexQuote.requestData,
    )
  );

}


async function deployAsOwnerStep2(
  usdcToSwap: BigNumber,
  honeyForLp: BigNumber,
  honeyByusdBexQuote: JoinQuote
) {
  const provider = new ethers.providers.JsonRpcProvider("http://127.0.0.1:8545");
  await provider.send('anvil_impersonateAccount', [ADDRS.CORE.MULTISIG]);
  const signer  = provider.getSigner(ADDRS.CORE.MULTISIG);
  const signerAddr = await signer.getAddress();

  // 1. Convert USDC => HONEY
  await mine(
    INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.connect(signer).approve(ADDRS.EXTERNAL.BERACHAIN.HONEY_FACTORY, usdcToSwap)
  );
  await mine(
    INSTANCES.EXTERNAL.BERACHAIN.HONEY_FACTORY.connect(signer).mint(ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN, usdcToSwap, signerAddr, false)
  );

  // 2. Join HONEY/BYUSD 
  await mine(
    INSTANCES.EXTERNAL.BERACHAIN.HONEY_TOKEN.connect(signer).approve(ADDRS.EXTERNAL.BEX.BALANCER_VAULT, honeyForLp)
  );
  await mine(
    INSTANCES.EXTERNAL.BEX.BALANCER_VAULT.connect(signer).joinPool(
      HONEY_BYUSD_POOL_INFO.poolId,
      signerAddr,
      signerAddr,
      honeyByusdBexQuote.requestData,
    )
  );
}

async function deployAsOwnerStep3(
) {
  const provider = new ethers.providers.JsonRpcProvider("http://127.0.0.1:8545");
  await provider.send('anvil_impersonateAccount', [ADDRS.CORE.MULTISIG]);
  const signer  = provider.getSigner(ADDRS.CORE.MULTISIG);
  const signerAddr = await signer.getAddress();

  const bptBalance = await INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_BYUSD.balanceOf(signerAddr);

  // 1. Stake
  await mine(
    INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_BYUSD.connect(signer).transfer(ADDRS.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_BYUSD, bptBalance)
  );
  await mine(
    INSTANCES.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_BYUSD.connect(signer).stake(bptBalance)
  );

  const balancesAfter = await Promise.all([
    INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.balanceOf(ADDRS.VAULTS.BOYCO_USDC_A.MANAGER),
    INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.balanceOf(signerAddr),
    INSTANCES.EXTERNAL.BERACHAIN.HONEY_TOKEN.balanceOf(signerAddr),
    INSTANCES.EXTERNAL.PAYPAL.BYUSD_TOKEN.balanceOf(signerAddr),
    INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_USDC.balanceOf(signerAddr),
    INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_BYUSD.balanceOf(signerAddr),
    INSTANCES.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_USDC.stakedBalance(),
    INSTANCES.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_BYUSD.stakedBalance(),
  ]);
  console.log("Balances After:");
  console.log("\tUSDC.e (manager):", ethers.utils.formatUnits(balancesAfter[0], 6));
  console.log("\tUSDC.e (msig):", ethers.utils.formatUnits(balancesAfter[1], 6));
  console.log("\tHONEY (msig):", ethers.utils.formatUnits(balancesAfter[2], 18));
  console.log("\tBYUSD (msig):", ethers.utils.formatUnits(balancesAfter[3], 6));
  console.log("\tHONEY|USDC BPT (msig):", ethers.utils.formatUnits(balancesAfter[4], 18));
  console.log("\tHONEY|BYUSD BPT (msig):", ethers.utils.formatUnits(balancesAfter[5], 18));
  console.log("\tHONEY|USDC BPT (infrared proxy):", ethers.utils.formatUnits(balancesAfter[6], 18));
  console.log("\tHONEY|BYUSD BPT (infrared proxy):", ethers.utils.formatUnits(balancesAfter[7], 18));
}

function mintHoney(
  contract: Contract,
  asset: string,
  amount: BigNumber,
  receiver: string,
  expectBasketMode: boolean
) {
  return createSafeTransaction(
    contract.address,
    "mint",
    [
      {
        argType: "address",
        name: "asset",
        value: asset,
      },
      {
        argType: "uint256",
        name: "amount",
        value: amount.toString(),
      },
      {
        argType: "address",
        name: "receiver",
        value: receiver,
      },
      {
        argType: "bool",
        name: "expectBasketMode",
        value: expectBasketMode.toString(),
      },
    ],
  )
}

function joinPool(
  contract: Contract,
  poolId: string,
  sender: string,
  recipient: string,
  requestData: IBalancerVault.JoinPoolRequestStruct,
): SafeTransaction {
  return {
    to: contract.address,
    value: "0",
    data: null,
    contractMethod: {
      name: "joinPool",
      payable: true,
      inputs: [
        {
          internalType: "bytes32",
          name: "poolId",
          type: "bytes32"
        },
        {
          internalType: "address",
          name: "sender",
          type: "address"
        },
        {
          internalType: "address",
          name: "recipient",
          type: "address"
        },
        {
          components: [
            {
              internalType: "address[]",
              name: "assets",
              type: "address[]"
            },
            {
              internalType: "uint256[]",
              name: "maxAmountsIn",
              type: "uint256[]"
            },
            {
              internalType: "bytes",
              name: "userData",
              type: "bytes"
            },
            {
              internalType: "bool",
              name: "fromInternalBalance",
              type: "bool"
            },
          ],
          internalType: "struct IBalancerVault.JoinPoolRequest",
          name: "request",
          type: "tuple"
        }
      ],
    },
    contractInputsValues: {
      poolId,
      sender,
      recipient,
      request: JSON.stringify([
        requestData.assets,
        requestData.maxAmountsIn,
        requestData.userData,
        requestData.fromInternalBalance,
      ])
    }
  }
}

function exitPool(
  contract: Contract,
  poolId: string,
  sender: string,
  recipient: string,
  requestData: IBalancerVault.ExitPoolRequestStruct,
): SafeTransaction {
  return {
    to: contract.address,
    value: "0",
    data: null,
    contractMethod: {
      name: "exitPool",
      payable: true,
      inputs: [
        {
          internalType: "bytes32",
          name: "poolId",
          type: "bytes32"
        },
        {
          internalType: "address",
          name: "sender",
          type: "address"
        },
        {
          internalType: "address",
          name: "recipient",
          type: "address"
        },
        {
          components: [
            {
              internalType: "address[]",
              name: "assets",
              type: "address[]"
            },
            {
              internalType: "uint256[]",
              name: "minAmountsOut",
              type: "uint256[]"
            },
            {
              internalType: "bytes",
              name: "userData",
              type: "bytes"
            },
            {
              internalType: "bool",
              name: "toInternalBalance",
              type: "bool"
            },
          ],
          internalType: "struct IBalancerVault.ExitPoolRequest",
          name: "request",
          type: "tuple"
        }
      ],
    },
    contractInputsValues: {
      poolId,
      sender,
      recipient,
      request: JSON.stringify([
        requestData.assets,
        requestData.minAmountsOut,
        requestData.userData,
        requestData.toInternalBalance,
      ])
    }
  }
}

export function transferBpt(
  contract: Contract,
  recipient: string,
  amount: BigNumber
) {
  return createSafeTransaction(
    contract.address,
    "transfer",
    [
      {
        argType: "address",
        name: "recipient",
        value: recipient,
      },
      {
        argType: "uint256",
        name: "amount",
        value: amount.toString(),
      },
    ],
  )
}

function stake(
  contract: Contract,
  amount: BigNumber,
) {
  return createSafeTransaction(
    contract.address,
    "stake",
    [
      {
        argType: "uint256",
        name: "amount",
        value: amount.toString(),
      },
    ],
  )
}

function withdraw(
  contract: Contract,
  amount: BigNumber,
  recipient: string,
) {
  return createSafeTransaction(
    contract.address,
    "withdraw",
    [
      {
        argType: "uint256",
        name: "amount",
        value: amount.toString(),
      },
      {
        argType: "address",
        name: "recipient",
        value: recipient.toString(),
      },
    ],
  )
}

async function deployViaMsigStep1(
  honeyUsdcBexQuote: ExitQuote,
) {
  const batch = createSafeBatch(
    [
      // 1. Withdraw from infrared
      withdraw(INSTANCES.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_USDC, honeyUsdcBexQuote.bptAmount, ADDRS.CORE.MULTISIG),

      // 2. Exit from BEX
      exitPool(INSTANCES.EXTERNAL.BEX.BALANCER_VAULT, HONEY_USDC_POOL_INFO.poolId, ADDRS.CORE.MULTISIG, ADDRS.CORE.MULTISIG, honeyUsdcBexQuote.requestData),
    ],
  );

  const filename = path.join(__dirname, "./feb12-batch1.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

async function deployViaMsigStep2(
  usdcToSwap: BigNumber,
  honeyForLp: BigNumber,
  honeyByusdBexQuote: JoinQuote
) {
  const batch = createSafeBatch(
    [
      // 1. Convert USDC => HONEY
      approve(INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN, ADDRS.EXTERNAL.BERACHAIN.HONEY_FACTORY, usdcToSwap),
      mintHoney(INSTANCES.EXTERNAL.BERACHAIN.HONEY_FACTORY, ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN, usdcToSwap, ADDRS.CORE.MULTISIG, false),

      // 2. Join HONEY/BYUSD
      approve(INSTANCES.EXTERNAL.BERACHAIN.HONEY_TOKEN, ADDRS.EXTERNAL.BEX.BALANCER_VAULT, honeyForLp),
      joinPool(INSTANCES.EXTERNAL.BEX.BALANCER_VAULT, HONEY_BYUSD_POOL_INFO.poolId, ADDRS.CORE.MULTISIG, ADDRS.CORE.MULTISIG, honeyByusdBexQuote.requestData),
    ]
  );

  const filename = path.join(__dirname, "./feb12-batch2.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

async function deployViaMsigStep3(bptBalance: BigNumber) {
  const batch = createSafeBatch(
    [
      // 1. Stake HONEY/BYUSD BPT
      transferBpt(INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_BYUSD, ADDRS.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_BYUSD, bptBalance),
      stake(INSTANCES.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_BYUSD, bptBalance),
    ]
  );

  const filename = path.join(__dirname, "./feb12-batch3.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

async function getHoneyUsdcExitQuote(totalUsdValue: BigNumber): Promise<ExitQuote> {
  const honeyUsdcTokenIndexes = getTokenIndexes(
    HONEY_USDC_POOL_INFO,
    ADDRS.EXTERNAL.BERACHAIN.HONEY_TOKEN,
    ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN
  );
  const bptTotalSupply = await HONEY_USDC_POOL_INFO.bptInstance.getActualSupply(); // 1e18
  const honeyBalance = HONEY_USDC_POOL_INFO.balances[honeyUsdcTokenIndexes.token1]; // 1e18
  const usdcBalance = HONEY_USDC_POOL_INFO.balances[honeyUsdcTokenIndexes.token2].mul(SCALE_USDC_TO_HONEY); // 1e18
  const honeyToRemove = totalUsdValue
    .mul(honeyBalance)
    .div(honeyBalance.add(usdcBalance)); // 1e18
  const usdcToRemove = totalUsdValue.sub(honeyToRemove); // 1e18
  const bptToRemove = honeyToRemove.mul(bptTotalSupply).div(honeyBalance); // 1e18

  console.log("HONEY|USDC BPT Total Supply:", ethers.utils.formatUnits(bptTotalSupply, 18));
  console.log("HONEY|USDC HONEY Pool Balance:", ethers.utils.formatUnits(honeyBalance, 18));
  console.log("HONEY|USDC USDC Pool Balance:", ethers.utils.formatUnits(usdcBalance, 18));

  console.log("Total USD to Remove:", ethers.utils.formatUnits(totalUsdValue, 18));
  console.log("HONEY to Remove:", ethers.utils.formatUnits(honeyToRemove, 18));
  console.log("USDC to Remove:", ethers.utils.formatUnits(usdcToRemove, 18));
  console.log("BPT to Remove:", ethers.utils.formatUnits(bptToRemove, 18));

  const quote = await exactBptExitQuote(HONEY_USDC_POOL_INFO, bptToRemove, BALANCER_SLIPPAGE_BPS);
  console.log(quote);
  return quote;
}

enum OPERATION {
  Nothing,
  DeployLocalAnvil,
  MultisigStep1,
  MultisigStep2,
  MultisigStep3
}

const operation: OPERATION = OPERATION.MultisigStep3;
const totalUsdValue = ethers.utils.parseEther("7000000"); // 7mm

async function main() {
  ({ owner, ADDRS, INSTANCES } = await getDeployContext(__dirname));

  await initState();

  if (operation === OPERATION.Nothing) throw new Error("Need to define the OPERATION");

  if (operation === OPERATION.DeployLocalAnvil) {
    const quote = await getHoneyUsdcExitQuote(totalUsdValue);

    const balancesBefore = await Promise.all([
      INSTANCES.EXTERNAL.BERACHAIN.HONEY_TOKEN.balanceOf(ADDRS.CORE.MULTISIG),
      INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.balanceOf(ADDRS.CORE.MULTISIG),
    ])
    await deployAsOwnerStep1(quote);
    const balancesAfter = await Promise.all([
      INSTANCES.EXTERNAL.BERACHAIN.HONEY_TOKEN.balanceOf(ADDRS.CORE.MULTISIG),
      INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.balanceOf(ADDRS.CORE.MULTISIG),
    ])
    const usdcToSwap = balancesAfter[1]
      .sub(balancesBefore[1]);

    // Include the USDC which we'll swap to HONEY
    const honeyForLp = usdcToSwap.mul(SCALE_USDC_TO_HONEY)
      .add(balancesAfter[0])
      .sub(balancesBefore[0]);

    console.log("\nGetting quotes for HONEY/BYUSD");
    const honeyByusdTokenIndexes = getTokenIndexes(
      HONEY_BYUSD_POOL_INFO,
      ADDRS.EXTERNAL.BERACHAIN.HONEY_TOKEN,
      ADDRS.EXTERNAL.PAYPAL.BYUSD_TOKEN
    );
    const honeyByusdBexQuote = await exactTokensJoinQuote(
      HONEY_BYUSD_POOL_INFO, 
      honeyByusdTokenIndexes,
      honeyForLp,
      BigNumber.from(0),
      BALANCER_SLIPPAGE_BPS
    );
    console.log(`Quote HONEY In: ${ethers.utils.formatUnits(honeyByusdBexQuote.tokenAmounts[honeyByusdTokenIndexes.token1], 18)}`);
    console.log(`Quote BYUSD In: ${ethers.utils.formatUnits(honeyByusdBexQuote.tokenAmounts[honeyByusdTokenIndexes.token2], 6)}`);
    console.log(`Quote BPT OUT (expected): ${ethers.utils.formatEther(honeyByusdBexQuote.expectedLpTokenAmount)}`);
    console.log(`Quote BPT OUT (min): ${ethers.utils.formatEther(honeyByusdBexQuote.minLpTokenAmount)}`);
    await deployAsOwnerStep2(usdcToSwap, honeyForLp, honeyByusdBexQuote);

    await deployAsOwnerStep3();

  } else if (operation === OPERATION.MultisigStep1) {
    // Unstake and Exit HONEY/USDC BPT
    const quote = await getHoneyUsdcExitQuote(totalUsdValue);
    deployViaMsigStep1(quote);
  } else if (operation === OPERATION.MultisigStep2) {
    // Convert USDC => HONEY, join HONEY/BYUSD BPT
    const existingUsdc = ethers.utils.parseUnits("0", 6);
    const usdcToSwap = (await INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.balanceOf(ADDRS.CORE.MULTISIG))
      .sub(existingUsdc);

    const existingHoney = ethers.utils.parseUnits("1751.485227471980234933", 18);
    const honeyForLp = usdcToSwap.mul(SCALE_USDC_TO_HONEY)
      .add(await INSTANCES.EXTERNAL.BERACHAIN.HONEY_TOKEN.balanceOf(ADDRS.CORE.MULTISIG))
      .sub(existingHoney);
    
    console.log("\nGetting quotes for HONEY/BYUSD");
    const honeyByusdTokenIndexes = getTokenIndexes(
      HONEY_BYUSD_POOL_INFO,
      ADDRS.EXTERNAL.BERACHAIN.HONEY_TOKEN,
      ADDRS.EXTERNAL.PAYPAL.BYUSD_TOKEN
    );
    const honeyByusdBexQuote = await exactTokensJoinQuote(
      HONEY_BYUSD_POOL_INFO, 
      honeyByusdTokenIndexes,
      honeyForLp,
      BigNumber.from(0),
      BALANCER_SLIPPAGE_BPS
    );
    console.log(`Quote HONEY In: ${ethers.utils.formatUnits(honeyByusdBexQuote.tokenAmounts[honeyByusdTokenIndexes.token1], 18)}`);
    console.log(`Quote BYUSD In: ${ethers.utils.formatUnits(honeyByusdBexQuote.tokenAmounts[honeyByusdTokenIndexes.token2], 6)}`);
    console.log(`Quote BPT OUT (expected): ${ethers.utils.formatEther(honeyByusdBexQuote.expectedLpTokenAmount)}`);
    console.log(`Quote BPT OUT (min): ${ethers.utils.formatEther(honeyByusdBexQuote.minLpTokenAmount)}`);

    deployViaMsigStep2(usdcToSwap, honeyForLp, honeyByusdBexQuote);
  } else if (operation === OPERATION.MultisigStep3) {
    const bptBalance = await INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_BYUSD.balanceOf(ADDRS.CORE.MULTISIG);
    await deployViaMsigStep3(bptBalance);
  }
}

runAsyncMain(main);