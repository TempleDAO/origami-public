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
import { approve, createSafeBatch, createSafeTransaction, recoverToken, SafeTransaction, writeSafeTransactionsBatch } from '../../safe-tx-builder';
import path from 'path';

let owner: SignerWithAddress;
let INSTANCES: ContractInstances;
let ADDRS: ContractAddresses;

interface PoolInfo {
  tokens: string[];
  balances: BigNumber[];
  poolId: string;
  bptAddress: string;
}

let HONEY_USDC_POOL_INFO: PoolInfo;
let HONEY_BYUSD_POOL_INFO: PoolInfo;

const ONE_USDC = ethers.utils.parseUnits("1", 6);
const BALANCER_SLIPPAGE_BPS = 1;

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
    bptAddress: bptInstance.address,
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

/*

Pre-launch:
1/ Pull remaining 60mm USDC into multisig
2/ Approve 21+18=39mm USDC to HONEY PSM
3/ mint 39mm HONEY from PSM
4/ approve 39mm HONEY to bex
5/ approve 21mm USDC.e to bex
6/ approve 9mm BYUSD to bex
7/ join 21mm HONEY + 21mm USDC.e to bex
8/ join 18mm HONEY + 9mm BYUSD to bex

Post-launch:
9/ stake HONEY|USD.e bpt to origami's infrared proxy: 0x2eC7777838A49E2C83152d455B3CA753c6d08b79
10/ stake HONEY|BYUSD bpt to origami's infrared proxy: 0xFE76a8323334288815B40f2424893beC3DAE3504
*/

// 42mm total
const HONEY_USDC_LP = {
  HONEY: ethers.utils.parseUnits("21000000", 18),
  USDC: ethers.utils.parseUnits("21000000", 6),
};

// 27mm total
const HONEY_BYUSD_LP = {
  HONEY: ethers.utils.parseUnits("18000010", 18),
  BYUSD: ethers.utils.parseUnits("9000000", 6),
};

const MIN_REQUIRED_HONEY_MINT_RATE = ethers.utils.parseEther("1");

interface Quote {
  tokenAmounts: BigNumber[],
  expectedLpTokenAmount: BigNumber,
  minLpTokenAmount: BigNumber,
  requestData: IBalancerVault.JoinPoolRequestStruct
}

const EXACT_TOKENS_IN_FOR_BPT_OUT = 1;
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
    } else if (poolInfo.tokens[i].toLowerCase() === poolInfo.bptAddress.toLowerCase()) {
      bptIndex = i;
    }
  }

  return {
    token1: token1Index,
    token2: token2Index,
    bpt: bptIndex
  }
}

async function exactTokensJoinQuote(
  poolInfo: PoolInfo,
  tokenIndexes: TokenIndexes,
  token1Amount: BigNumber, // honey
  token2Amount: BigNumber, // byusd | usdc
  slippageBps: number
): Promise<Quote> {
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

async function deployAsOwner(
  usdcToRecover: BigNumber,
  usdcToConvertToHoney: BigNumber,
  honeyUsdcBexQuote: Quote,
  honeyByusdBexQuote: Quote
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

  // 1. Recover USDC from the manager to the multisig
  await mine(
    INSTANCES.VAULTS.BOYCO_USDC_A.MANAGER.connect(signer).recoverToken(ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN, ADDRS.CORE.MULTISIG, usdcToRecover),
  );
  
  // 2. Swap USDC to HONEY via the PSM
  await mine(
    INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.connect(signer).approve(ADDRS.EXTERNAL.BERACHAIN.HONEY_FACTORY, usdcToConvertToHoney)
  );
  await mine(
    INSTANCES.EXTERNAL.BERACHAIN.HONEY_FACTORY.connect(signer).mint(ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN, usdcToConvertToHoney, signerAddr, false)
  );
  
  // 3. Approvals to BEX
  await mine(
    INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.connect(signer).approve(ADDRS.EXTERNAL.BEX.BALANCER_VAULT, HONEY_USDC_LP.USDC)
  );
  await mine(
    INSTANCES.EXTERNAL.PAYPAL.BYUSD_TOKEN.connect(signer).approve(ADDRS.EXTERNAL.BEX.BALANCER_VAULT, HONEY_BYUSD_LP.BYUSD)
  );
  await mine(
    INSTANCES.EXTERNAL.BERACHAIN.HONEY_TOKEN.connect(signer).approve(ADDRS.EXTERNAL.BEX.BALANCER_VAULT, HONEY_USDC_LP.HONEY.add(HONEY_BYUSD_LP.HONEY))
  );
  
  // 4. Join into BEX
  await mine(
    INSTANCES.EXTERNAL.BEX.BALANCER_VAULT.connect(signer).joinPool(
      HONEY_USDC_POOL_INFO.poolId,
      signerAddr,
      signerAddr,
      honeyUsdcBexQuote.requestData,
    )
  );
  await mine(
    INSTANCES.EXTERNAL.BEX.BALANCER_VAULT.connect(signer).joinPool(
      HONEY_BYUSD_POOL_INFO.poolId,
      signerAddr,
      signerAddr,
      honeyByusdBexQuote.requestData,
    )
  );

  // 5. Transfer and stake into Infrared vault
  const balances = await Promise.all([
    INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_USDC.balanceOf(signerAddr),
    INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_BYUSD.balanceOf(signerAddr)
  ]);
  await mine(
    INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_USDC.connect(signer).transfer(ADDRS.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_USDC, balances[0])
  );
  await mine(
    INSTANCES.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_USDC.connect(signer).stake(balances[0])
  );
  await mine(
    INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_BYUSD.connect(signer).transfer(ADDRS.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_BYUSD, balances[1])
  );
  await mine(
    INSTANCES.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_BYUSD.connect(signer).stake(balances[1])
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

async function deployViaMsigStep1(
  usdcToRecover: BigNumber,
  usdcToConvertToHoney: BigNumber,
  honeyUsdcBexQuote: Quote,
  honeyByusdBexQuote: Quote
) {
  const batch = createSafeBatch(
    [
      // 1. Recover USDC from the manager to the multisig
      recoverToken(INSTANCES.VAULTS.BOYCO_USDC_A.MANAGER, ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN, ADDRS.CORE.MULTISIG, usdcToRecover),

      // 2. Swap USDC to HONEY via the PSM
      approve(INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN, ADDRS.EXTERNAL.BERACHAIN.HONEY_FACTORY, usdcToConvertToHoney),
      mintHoney(INSTANCES.EXTERNAL.BERACHAIN.HONEY_FACTORY, ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN, usdcToConvertToHoney, ADDRS.CORE.MULTISIG, false),

      // 3. Approvals to BEX
      approve(INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN, ADDRS.EXTERNAL.BEX.BALANCER_VAULT, HONEY_USDC_LP.USDC),
      approve(INSTANCES.EXTERNAL.PAYPAL.BYUSD_TOKEN, ADDRS.EXTERNAL.BEX.BALANCER_VAULT, HONEY_BYUSD_LP.BYUSD),
      approve(INSTANCES.EXTERNAL.BERACHAIN.HONEY_TOKEN, ADDRS.EXTERNAL.BEX.BALANCER_VAULT, HONEY_USDC_LP.HONEY.add(HONEY_BYUSD_LP.HONEY)),

      // 4. Join into BEX
      joinPool(INSTANCES.EXTERNAL.BEX.BALANCER_VAULT, HONEY_USDC_POOL_INFO.poolId, ADDRS.CORE.MULTISIG, ADDRS.CORE.MULTISIG, honeyUsdcBexQuote.requestData),
      joinPool(INSTANCES.EXTERNAL.BEX.BALANCER_VAULT, HONEY_BYUSD_POOL_INFO.poolId, ADDRS.CORE.MULTISIG, ADDRS.CORE.MULTISIG, honeyByusdBexQuote.requestData),
    ],
  );

  const filename = path.join(__dirname, "./deploy-proportional-liquidity-batch1.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

async function deployViaMsigStep2() {
  const balances = await Promise.all([
    INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_USDC.balanceOf(ADDRS.CORE.MULTISIG),
    INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_BYUSD.balanceOf(ADDRS.CORE.MULTISIG)
  ]);

  const batch = createSafeBatch(
    [
      // 5. Send the LP to the rewards vault proxy and stake.
      transferBpt(INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_USDC, ADDRS.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_USDC, balances[0]),
      stake(INSTANCES.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_USDC, balances[0]),
      transferBpt(INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_BYUSD, ADDRS.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_BYUSD, balances[1]),
      stake(INSTANCES.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_BYUSD, balances[1]),
    ]
  );

  const filename = path.join(__dirname, "./deploy-proportional-liquidity-batch2.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

enum OPERATION {
  Nothing,
  DeployLocalAnvil,
  MultisigAddLiquidity,
  MultisigStake
}

const operation: OPERATION = OPERATION.Nothing;


async function main() {
  ({ owner, ADDRS, INSTANCES } = await getDeployContext(__dirname));

  await initState();

  if (operation === OPERATION.Nothing) throw new Error("Need to define the OPERATION");

  if (operation === OPERATION.DeployLocalAnvil || operation === OPERATION.MultisigAddLiquidity) {
    const usdcAvailable = await INSTANCES.VAULTS.BOYCO_USDC_A.MANAGER.unallocatedAssets();
    const totalUsdcRequiredWad = HONEY_USDC_LP.USDC.mul(ethers.utils.parseUnits("1", 12))
      .add(HONEY_USDC_LP.HONEY)
      .add(HONEY_BYUSD_LP.HONEY);
    console.log("USDC Available:", ethers.utils.formatUnits(usdcAvailable, 6));
    console.log("Total USDC Required:", ethers.utils.formatUnits(totalUsdcRequiredWad, 18));

    if (totalUsdcRequiredWad.gt(usdcAvailable.mul(ethers.utils.parseUnits("1", 12)))) throw new Error("Not enough USDC");

    console.log("\nGetting quotes for HONEY/USDC");
    const honeyUsdcTokenIndexes = getTokenIndexes(
      HONEY_USDC_POOL_INFO,
      ADDRS.EXTERNAL.BERACHAIN.HONEY_TOKEN,
      ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN
    );
    const honeyUsdcBexQuote = await exactTokensJoinQuote(
      HONEY_USDC_POOL_INFO,
      honeyUsdcTokenIndexes,
      HONEY_USDC_LP.HONEY, HONEY_USDC_LP.USDC,
      BALANCER_SLIPPAGE_BPS
    );
    console.log(`Quote HONEY In: ${ethers.utils.formatUnits(honeyUsdcBexQuote.tokenAmounts[honeyUsdcTokenIndexes.token1], 18)}`);
    console.log(`Quote USDC In: ${ethers.utils.formatUnits(honeyUsdcBexQuote.tokenAmounts[honeyUsdcTokenIndexes.token2], 6)}`);
    console.log(`Quote BPT OUT (expected): ${ethers.utils.formatEther(honeyUsdcBexQuote.expectedLpTokenAmount)}`);
    console.log(`Quote BPT OUT (min): ${ethers.utils.formatEther(honeyUsdcBexQuote.minLpTokenAmount)}`);

    console.log("\nGetting quotes for HONEY/BYUSD");
    const honeyByusdTokenIndexes = getTokenIndexes(
      HONEY_BYUSD_POOL_INFO,
      ADDRS.EXTERNAL.BERACHAIN.HONEY_TOKEN,
      ADDRS.EXTERNAL.PAYPAL.BYUSD_TOKEN
    );
    const honeyByusdBexQuote = await exactTokensJoinQuote(
      HONEY_BYUSD_POOL_INFO, 
      honeyByusdTokenIndexes,
      HONEY_BYUSD_LP.HONEY,
      HONEY_BYUSD_LP.BYUSD,
      BALANCER_SLIPPAGE_BPS
    );
    console.log(`Quote HONEY In: ${ethers.utils.formatUnits(honeyByusdBexQuote.tokenAmounts[honeyByusdTokenIndexes.token1], 18)}`);
    console.log(`Quote BYUSD In: ${ethers.utils.formatUnits(honeyByusdBexQuote.tokenAmounts[honeyByusdTokenIndexes.token2], 6)}`);
    console.log(`Quote BPT OUT (expected): ${ethers.utils.formatEther(honeyByusdBexQuote.expectedLpTokenAmount)}`);
    console.log(`Quote BPT OUT (min): ${ethers.utils.formatEther(honeyByusdBexQuote.minLpTokenAmount)}`);

    if (operation === OPERATION.DeployLocalAnvil) {
      await deployAsOwner(
        usdcAvailable,
        HONEY_USDC_LP.HONEY.add(HONEY_BYUSD_LP.HONEY).div(ethers.utils.parseUnits("1", 12)),
        honeyUsdcBexQuote,
        honeyByusdBexQuote
      );
    } else if (operation === OPERATION.MultisigAddLiquidity) {
      await deployViaMsigStep1(
        usdcAvailable,
        HONEY_USDC_LP.HONEY.add(HONEY_BYUSD_LP.HONEY).div(ethers.utils.parseUnits("1", 12)),
        honeyUsdcBexQuote,
        honeyByusdBexQuote
      );
    }
  } else if (operation === OPERATION.MultisigStake) {
    await deployViaMsigStep2();
  }
}

runAsyncMain(main);