
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
import { IBalancerVault } from '../../../../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { approve, createSafeBatch, createSafeTransaction, recoverToken, SafeTransaction, writeSafeTransactionsBatch } from '../../safe-tx-builder';
import path from 'path';

let owner: SignerWithAddress;
let INSTANCES: ContractInstances;
let ADDRS: ContractAddresses;

interface TokenIndexes {
  honey: number;
  usdc: number;
  bpt: number;
}
let TOKENS: string[];
let BALANCES: BigNumber[];
let TOKEN_INDEXES: TokenIndexes;
let POOL_ID: string;
let BPT_ADDRESS: string;

const ZERO = BigNumber.from(0);
const ONE_USDC = ethers.utils.parseUnits("1", 6);
const ONE_HONEY = ethers.utils.parseUnits("1", 18);

const MIN_REQUIRED_HONEY_MINT_RATE = ethers.utils.parseEther("0.995");
const BALANCER_SLIPPAGE_BPS = 2;

// https://staging.safe.berachain.com/settings/setup?safe=cArtio:0x6C173dD7c662ce719CF14F108146A48D43444A21
const MULTISIG = '0x6C173dD7c662ce719CF14F108146A48D43444A21';
    
/// @dev https://github.com/balancer/balancer-v2-monorepo/blob/36d282374b457dddea828be7884ee0d185db06ba/pkg/interfaces/contracts/pool-stable/StablePoolUserData.sol#L18
const EXACT_TOKENS_IN_FOR_BPT_OUT = 1;

/**
    Formula to calculate the inputs:
    
        usdcToSellForHoney + usdcToPair = totalUsdcAmount
    (1) usdcToPair = totalUsdcAmount - usdcToSellForHoney

    And:
        usdcToPair [USDC] = honeyToPair [HONEY] / tokenBalanceRatio [HONEY/USDC]
    (2) usdcToPair = usdcToSellForHoney [USDC] * usdcToHoneyMintRate [HONEY/USDC] / tokenBalanceRatio [HONEY/USDC]

    Substituting (1) into (2):
        totalUsdcAmount - usdcToSellForHoney = usdcToSellForHoney [USDC] * usdcToHoneyMintRate [HONEY/USDC] / tokenBalanceRatio [HONEY/USDC]
        totalUsdcAmount = usdcToSellForHoney + usdcToSellForHoney [USDC] * usdcToHoneyMintRate [HONEY/USDC] / tokenBalanceRatio [HONEY/USDC]
        totalUsdcAmount = usdcToSellForHoney [USDC] * (1 [6dp] + usdcToHoneyMintRate [HONEY/USDC] / tokenBalanceRatio [HONEY/USDC])

        usdcToSellForHoney = totalUsdcAmount [USDC] / (1 [6dp] + usdcToHoneyMintRate [HONEY/USDC] / tokenBalanceRatio [HONEY/USDC])
*/
async function calcUsdcSellAmount(totalUsdcAmount: BigNumber, usdcToHoneyMintRate: BigNumber) {
  const honeyToUsdcBalanceRatio = BALANCES[TOKEN_INDEXES.honey]
    .mul(ONE_USDC)
    .div(BALANCES[TOKEN_INDEXES.usdc]);
  const denominator = ONE_HONEY.add(
    usdcToHoneyMintRate
      .mul(ONE_HONEY)
      .div(honeyToUsdcBalanceRatio)
  );

  return totalUsdcAmount
    .mul(ONE_HONEY)
    .div(denominator);
}

async function initState() {
  POOL_ID = await INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_USDC.getPoolId();
  console.log("HONEY/USDC Pool ID:", POOL_ID);

  const ptokens = await INSTANCES.EXTERNAL.BEX.BALANCER_VAULT.getPoolTokens(POOL_ID);
  TOKENS = ptokens.tokens;
  BALANCES = ptokens.balances;
  BPT_ADDRESS = (await INSTANCES.EXTERNAL.BEX.BALANCER_VAULT.getPool(POOL_ID))[0];

  let honeyIndex: number = 0;
  let usdcIndex: number = 0;
  let bptIndex: number = 0;
  for (let i = 0; i < TOKENS.length; i++) {
    if (TOKENS[i].toLowerCase() === ADDRS.EXTERNAL.BERACHAIN.HONEY_TOKEN.toLowerCase()) {
      honeyIndex = i;
    } else if (TOKENS[i].toLowerCase() === ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN.toLowerCase()) {
      usdcIndex = i;
    } else if (TOKENS[i].toLowerCase() === BPT_ADDRESS.toLowerCase()) {
      bptIndex = i;
    }
  }
  console.log("HONEY index in pool:", honeyIndex);
  console.log("USDC index in pool:", usdcIndex);
  console.log("BPT index in pool:", bptIndex);
  TOKEN_INDEXES = {
    honey: honeyIndex,
    usdc: usdcIndex,
    bpt: bptIndex,
  };
}

interface Quote {
  tokenAmounts: BigNumber[],
  expectedLpTokenAmount: BigNumber,
  minLpTokenAmount: BigNumber,
  requestData: IBalancerVault.JoinPoolRequestStruct
}

async function proportionalAddLiquidityQuote(honeyAmount: BigNumber, slippageBps: number): Promise<Quote> {
  if (honeyAmount == ZERO) throw new Error("Invalid HONEY amount");

  const tokenAmounts = [ZERO, ZERO, ZERO];
  tokenAmounts[TOKEN_INDEXES.honey] = honeyAmount;

  const honeyBalance = BALANCES[TOKEN_INDEXES.honey];
  if (honeyBalance == ZERO) throw new Error("Invalid HONEY balance");
  tokenAmounts[TOKEN_INDEXES.usdc] = BALANCES[TOKEN_INDEXES.usdc]
    .mul(honeyAmount)
    .div(honeyBalance);

  const udAmountsIn = TOKEN_INDEXES.honey < TOKEN_INDEXES.usdc
    ? [tokenAmounts[TOKEN_INDEXES.honey], tokenAmounts[TOKEN_INDEXES.usdc]]
    : [tokenAmounts[TOKEN_INDEXES.usdc], tokenAmounts[TOKEN_INDEXES.honey]];
  const userData = ethers.utils.defaultAbiCoder.encode(
    ['uint8', 'uint256[]', 'uint256'],
    [EXACT_TOKENS_IN_FOR_BPT_OUT, udAmountsIn, 0]
  );

  const response = await INSTANCES.EXTERNAL.BEX.BALANCER_QUERIES.callStatic.queryJoin(
    POOL_ID,
    ZERO_ADDRESS,
    ZERO_ADDRESS,
    {
      assets: TOKENS,
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
    assets: TOKENS,
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

// Get the current USDC=>HONEY mint rate with sanity checks on the PSM
async function getHoneyMintRate() {
  // return ethers.utils.parseEther("0.995");

  const isBasketModeEnabled = await INSTANCES.EXTERNAL.BERACHAIN.HONEY_FACTORY.isBasketModeEnabled(true);
  console.log(`PSM isBasketModeEnabled = ${isBasketModeEnabled}`);
  if (isBasketModeEnabled) throw new Error("Cannot deploy proportional liquidity if BasketMode is enabled in HoneyFactory PSM");

  // Get the collateral assets from the HONEY PSM
  const numCollaterals = (await INSTANCES.EXTERNAL.BERACHAIN.HONEY_FACTORY.numRegisteredAssets()).toNumber();
  let usdcCollateralIndex = 0;
  for (let i=0; i < numCollaterals; ++i) {
    const collateralAddr = await INSTANCES.EXTERNAL.BERACHAIN.HONEY_FACTORY.registeredAssets(i);
    if (collateralAddr.toLowerCase() === ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN.toLowerCase()) {
      usdcCollateralIndex = i;
      break;
    }
  }
  console.log(`USDC collateral index in HONEY PSM: ${usdcCollateralIndex}`);
  
  // Get the rate an expected mint inputs
  const [collateralInputs, usdcToHoneyMintRate] = await INSTANCES.EXTERNAL.BERACHAIN.HONEY_FACTORY_READER.previewMintHoney(ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN, ONE_USDC);
  console.log(`USDC => HONEY mint rate: ${ethers.utils.formatEther(usdcToHoneyMintRate)}`);

  if (usdcToHoneyMintRate.lt(MIN_REQUIRED_HONEY_MINT_RATE)) throw new Error("USDC=>HONEY mint rate too low");

  // Sanity check the required input collaterals
  for (let i=0; i < collateralInputs.length; ++i) {
    console.log(`\tcollateral[${i}] = ${collateralInputs[i].toString()}`);
    if (i == usdcCollateralIndex) {
      if (!collateralInputs[i].eq(ONE_USDC)) throw new Error("Honey Factory returned an unexpected collateral amount for USDC");
    } else {
      if (!collateralInputs[i].eq(ZERO)) throw new Error(`Honey Factory returned an unexpected collateral amount for index ${i}`);
    }
  }

  return usdcToHoneyMintRate;
}

async function getQuote(totalUsdcAmount: BigNumber, slippageBps: number) {
  const usdcToHoneyMintRate = await getHoneyMintRate(); // 18dp
  const usdcToSellForHoney = await calcUsdcSellAmount(totalUsdcAmount, usdcToHoneyMintRate); // 6dp
  console.log(`usdcToSellForHoney: ${ethers.utils.formatUnits(usdcToSellForHoney, 6)}`);

  const honeyToPair = usdcToSellForHoney // 18dp
    .mul(usdcToHoneyMintRate)
    .div(ONE_USDC);
  console.log(`honeyToPair: ${ethers.utils.formatEther(honeyToPair)}`);

  return {
    usdcToSellForHoney,
    quoteData: await proportionalAddLiquidityQuote(honeyToPair, slippageBps),
  };
}

async function deployAsOwner(quote: {
  usdcToSellForHoney: BigNumber,
  quoteData: Quote,
}) {
  const ownerAddr = await owner.getAddress();

  // 1. Swap USDC to HONEY via the PSM
  await mine(
    INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.approve(ADDRS.EXTERNAL.BERACHAIN.HONEY_FACTORY, quote.usdcToSellForHoney)
  );
  const honeyBalanceBefore = await INSTANCES.EXTERNAL.BERACHAIN.HONEY_TOKEN.balanceOf(ownerAddr);
  await mine(
    INSTANCES.EXTERNAL.BERACHAIN.HONEY_FACTORY.mint(ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN, quote.usdcToSellForHoney, ownerAddr, false)
  );
  const honeyBalanceAfter = await INSTANCES.EXTERNAL.BERACHAIN.HONEY_TOKEN.balanceOf(ownerAddr);
  const honeyReceived = honeyBalanceAfter.sub(honeyBalanceBefore);
  console.log(`HONEY received: ${ethers.utils.formatEther(honeyReceived)}`);
  if (honeyReceived.lt(quote.quoteData.tokenAmounts[TOKEN_INDEXES.honey])) throw new Error(`Received less HONEY than expected`);

  // 2. Add the HONEY/USDC as liquidity into BEX and receive an LP receipt token
  await mine(
    INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.approve(ADDRS.EXTERNAL.BEX.BALANCER_VAULT, quote.quoteData.tokenAmounts[TOKEN_INDEXES.usdc])
  );
  await mine(
    INSTANCES.EXTERNAL.BERACHAIN.HONEY_TOKEN.approve(ADDRS.EXTERNAL.BEX.BALANCER_VAULT, quote.quoteData.tokenAmounts[TOKEN_INDEXES.honey])
  );
  await mine(
    INSTANCES.EXTERNAL.BEX.BALANCER_VAULT.joinPool(
      POOL_ID,
      ownerAddr,
      ownerAddr,
      quote.quoteData.requestData,
    )
  );

  const lpBalance = INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_USDC.balanceOf(ownerAddr);

  // 3. Stake the BPT
  await mine(
    INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_USDC.transfer(ADDRS.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_USDC, lpBalance)
  );
  await mine(
    INSTANCES.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_USDC.stake(INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_USDC.balanceOf(ADDRS.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_USDC))
  );
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

function deployViaMsigStep1(
  totalUsdcAmount: BigNumber,
  quote: {
    usdcToSellForHoney: BigNumber,
    quoteData: Quote,
  }
) {
  const batch = createSafeBatch(
    [
      // 1. Pull funds from manager back to multisig
      recoverToken(INSTANCES.VAULTS.BOYCO_USDC_A.MANAGER, ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN, MULTISIG, totalUsdcAmount),

      // 2. Swap USDC to HONEY via the PSM
      approve(INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN, ADDRS.EXTERNAL.BERACHAIN.HONEY_FACTORY, quote.usdcToSellForHoney),
      mintHoney(INSTANCES.EXTERNAL.BERACHAIN.HONEY_FACTORY, ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN, quote.usdcToSellForHoney, MULTISIG, false),

      // 3. Add the HONEY/USDC as liquidity into BEX and receive an LP receipt token
      approve(INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN, ADDRS.EXTERNAL.BEX.BALANCER_VAULT, quote.quoteData.tokenAmounts[TOKEN_INDEXES.usdc]),
      approve(INSTANCES.EXTERNAL.BERACHAIN.HONEY_TOKEN, ADDRS.EXTERNAL.BEX.BALANCER_VAULT, quote.quoteData.tokenAmounts[TOKEN_INDEXES.honey]),
      joinPool(INSTANCES.EXTERNAL.BEX.BALANCER_VAULT, POOL_ID, MULTISIG, MULTISIG, quote.quoteData.requestData),
    ],
  );

  const filename = path.join(__dirname, "./deploy-proportional-liquidity-batch1.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

async function deployViaMsigStep2() {
  const lpBalance = await INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_USDC.balanceOf(MULTISIG);

  const batch = createSafeBatch(
    [
      // 4. Send the LP to the rewards vault proxy and stake.
      transferBpt(INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_USDC, ADDRS.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_USDC, lpBalance),
      stake(INSTANCES.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_USDC, lpBalance),
    ]
  );

  const filename = path.join(__dirname, "./deploy-proportional-liquidity-batch2.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

async function main() {
  ({ owner, ADDRS, INSTANCES } = await getDeployContext(__dirname));

  // @todo override this to use a smaller amount than the max
  const totalUsdcAmount = await INSTANCES.VAULTS.BOYCO_USDC_A.MANAGER.unallocatedAssets();
  // const totalUsdcAmount = ethers.utils.parseUnits("1000", 6);

  if (totalUsdcAmount.gt(ZERO)) {
    console.log(`Total USDC Amount to add: ${totalUsdcAmount}`);

    await initState();

    const quote = await getQuote(totalUsdcAmount, BALANCER_SLIPPAGE_BPS);
    console.log(`Quote USDC In: ${ethers.utils.formatUnits(quote.quoteData.tokenAmounts[TOKEN_INDEXES.usdc], 6)}`);
    console.log(`Quote HONEY In: ${ethers.utils.formatEther(quote.quoteData.tokenAmounts[TOKEN_INDEXES.honey])}`);
    console.log(`Quote BPT OUT (expected): ${ethers.utils.formatEther(quote.quoteData.expectedLpTokenAmount)}`);
    console.log(`Quote BPT OUT (min): ${ethers.utils.formatEther(quote.quoteData.minLpTokenAmount)}`);

    // This was a test run with my PK as the owner of the assets already
    // await deployAsOwner(quote);

    deployViaMsigStep1(totalUsdcAmount, quote);
  } else {
    await deployViaMsigStep2();
  }
}

runAsyncMain(main);
