
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
  byusd: number;
  bpt: number;
}
let TOKENS: string[];
let BALANCES: BigNumber[];
let TOKEN_INDEXES: TokenIndexes;
let POOL_ID: string;
let BPT_ADDRESS: string;
let HONEY_MINT_RATE_FROM_USDC: BigNumber; // Always 18dp
let HONEY_REDEEM_RATE_TO_BYUSD: BigNumber; // Always 18dp

const ZERO = BigNumber.from(0);
const ONE_BYUSD = ethers.utils.parseUnits("1", 6);
const ONE_USDC = ethers.utils.parseUnits("1", 6);
const ONE_HONEY = ethers.utils.parseUnits("1", 18);

// @todo confirm these details
// @todo and also if we want to do the entire size or just some of it
const MIN_REQUIRED_HONEY_MINT_RATE = ethers.utils.parseEther("1");
const MIN_REQUIRED_HONEY_REDEEM_RATE = ethers.utils.parseEther("0.9995");
const BALANCER_SLIPPAGE_BPS = 2;

// Contains the BYUSD available in the PSM if we want to redeem honey
const HONEY_MINTER_BYUSD_VAULT = '0x36A9975acd3B6F2e2CAd4E191967Ebf80F99d7ce';

/// @dev https://github.com/balancer/balancer-v2-monorepo/blob/36d282374b457dddea828be7884ee0d185db06ba/pkg/interfaces/contracts/pool-stable/StablePoolUserData.sol#L18
const EXACT_TOKENS_IN_FOR_BPT_OUT = 1;

/**
    Formula to calculate the inputs:
    
        honeyToSellForBYUSD + honeyToPair = totalHoneyAmount
    (1) honeyToPair = totalHoneyAmount - honeyToSellForBYUSD

    And:
        honeyToPair [HONEY] = byusdToPair [BYUSD] * tokenBalanceRatio [HONEY/BYUSD]
    (2) honeyToPair = honeyToSellForBYUSD [HONEY] * honeyToBYUSDRedeemRate [BYUSD/HONEY] * tokenBalanceRatio [HONEY/BYUSD]

    Substituting (1) into (2):
        totalHoneyAmount - honeyToSellForBYUSD = honeyToSellForBYUSD [HONEY] * honeyToBYUSDRedeemRate [BYUSD/HONEY] * tokenBalanceRatio [HONEY/BYUSD]
        totalHoneyAmount = honeyToSellForBYUSD + honeyToSellForBYUSD [HONEY] * honeyToBYUSDRedeemRate [BYUSD/HONEY] * tokenBalanceRatio [HONEY/BYUSD]
        totalHoneyAmount = honeyToSellForBYUSD [HONEY] * (1 + honeyToBYUSDRedeemRate [BYUSD/HONEY] * tokenBalanceRatio [HONEY/BYUSD])

        honeyToSellForBYUSD [HONEY] = totalHoneyAmount [HONEY] / (1 + honeyToBYUSDRedeemRate [BYUSD/HONEY] * tokenBalanceRatio [HONEY/BYUSD]))
*/
async function calcHoneySellAmount(totalHoneyAmount: BigNumber, honeyToByusdRedeemRate: BigNumber) {
  const honeyToByusdBalanceRatio = BALANCES[TOKEN_INDEXES.honey]
    .mul(ONE_BYUSD)
    .div(BALANCES[TOKEN_INDEXES.byusd]);
  const denominator = ONE_HONEY.add(
    honeyToByusdRedeemRate
      .mul(honeyToByusdBalanceRatio)
      .div(ONE_HONEY)
  );

  return totalHoneyAmount
    .mul(ONE_HONEY)
    .div(denominator);
}

async function initState() {
  POOL_ID = await INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_BYUSD.getPoolId();
  console.log("HONEY/BYUSD Pool ID:", POOL_ID);

  const ptokens = await INSTANCES.EXTERNAL.BEX.BALANCER_VAULT.getPoolTokens(POOL_ID);
  TOKENS = ptokens.tokens;
  BALANCES = ptokens.balances;
  BPT_ADDRESS = (await INSTANCES.EXTERNAL.BEX.BALANCER_VAULT.getPool(POOL_ID))[0];

  let honeyIndex: number = 0;
  let byusdIndex: number = 0;
  let bptIndex: number = 0;
  for (let i = 0; i < TOKENS.length; i++) {
    if (TOKENS[i].toLowerCase() === ADDRS.EXTERNAL.BERACHAIN.HONEY_TOKEN.toLowerCase()) {
      honeyIndex = i;
    } else if (TOKENS[i].toLowerCase() === ADDRS.EXTERNAL.PAYPAL.BYUSD_TOKEN.toLowerCase()) {
      byusdIndex = i;
    } else if (TOKENS[i].toLowerCase() === BPT_ADDRESS.toLowerCase()) {
      bptIndex = i;
    }
  }
  console.log("HONEY index in pool:", honeyIndex);
  console.log("BYUSD index in pool:", byusdIndex);
  console.log("BPT index in pool:", bptIndex);

  console.log("HONEY balance in pool:", ethers.utils.formatUnits(BALANCES[honeyIndex], 18));
  console.log("BYSD balance in pool:", ethers.utils.formatUnits(BALANCES[byusdIndex], 6));

  TOKEN_INDEXES = {
    honey: honeyIndex,
    byusd: byusdIndex,
    bpt: bptIndex,
  };

  HONEY_MINT_RATE_FROM_USDC = await getHoneyMintRate();
  HONEY_REDEEM_RATE_TO_BYUSD = await getHoneyRedeemRate();
}

interface Quote {
  tokenAmounts: BigNumber[],
  expectedLpTokenAmount: BigNumber,
  minLpTokenAmount: BigNumber,
  requestData: IBalancerVault.JoinPoolRequestStruct
}

async function proportionalAddLiquidityQuote(
  honeyAmount: BigNumber,
  byUsdcAmount: BigNumber,
  slippageBps: number
): Promise<Quote> {
  if (honeyAmount == ZERO) throw new Error("Invalid HONEY amount");
  if (byUsdcAmount == ZERO) throw new Error("Invalid BYUSD amount");

  const tokenAmounts = [ZERO, ZERO, ZERO];
  tokenAmounts[TOKEN_INDEXES.honey] = honeyAmount;
  tokenAmounts[TOKEN_INDEXES.byusd] = byUsdcAmount;

  const udAmountsIn = TOKEN_INDEXES.honey < TOKEN_INDEXES.byusd
    ? [tokenAmounts[TOKEN_INDEXES.honey], tokenAmounts[TOKEN_INDEXES.byusd]]
    : [tokenAmounts[TOKEN_INDEXES.byusd], tokenAmounts[TOKEN_INDEXES.honey]];
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

// Get the current BYUSD=>HONEY mint rate with sanity checks on the PSM
async function getHoneyRedeemRate() {
  const isBasketModeEnabled = await INSTANCES.EXTERNAL.BERACHAIN.HONEY_FACTORY.isBasketModeEnabled(false);
  console.log(`PSM isBasketModeEnabled = ${isBasketModeEnabled}`);
  if (isBasketModeEnabled) throw new Error("Cannot deploy proportional liquidity if BasketMode is enabled in HoneyFactory PSM");

  // Get the collateral assets from the HONEY PSM
  const numCollaterals = (await INSTANCES.EXTERNAL.BERACHAIN.HONEY_FACTORY.numRegisteredAssets()).toNumber();
  let byusdCollateralIndex = 0;
  for (let i=0; i < numCollaterals; ++i) {
    const collateralAddr = await INSTANCES.EXTERNAL.BERACHAIN.HONEY_FACTORY.registeredAssets(i);
    if (collateralAddr.toLowerCase() === ADDRS.EXTERNAL.PAYPAL.BYUSD_TOKEN.toLowerCase()) {
      byusdCollateralIndex = i;
      break;
    }
  }
  console.log(`BYUSD collateral index in HONEY PSM: ${byusdCollateralIndex}`);
  
  // Get the rate an expected redeem inputs
  const collateralOutputs = await INSTANCES.EXTERNAL.BERACHAIN.HONEY_FACTORY_READER.previewRedeemCollaterals(ADDRS.EXTERNAL.PAYPAL.BYUSD_TOKEN, ONE_HONEY);

  // Sanity check the output collaterals
  for (let i=0; i < collateralOutputs.length; ++i) {
    console.log(`\tcollateral[${i}] = ${collateralOutputs[i].toString()}`);
    if (i != byusdCollateralIndex) {
      if (!collateralOutputs[i].eq(ZERO)) throw new Error(`Honey Factory returned an unexpected collateral amount for index ${i}`);
    }
  }

  // Make it 18dp
  const honeyToByusdRedeemRate = collateralOutputs[byusdCollateralIndex]
    .mul(ONE_HONEY)
    .div(ONE_USDC);
  console.log(`HONEY => BYUSD redeem rate: ${ethers.utils.formatEther(honeyToByusdRedeemRate)}`);
  if (honeyToByusdRedeemRate.lt(MIN_REQUIRED_HONEY_REDEEM_RATE)) throw new Error("HONEY=>BYUSD redeem rate too low");

  return honeyToByusdRedeemRate;
}

async function getQuote(totalUsdcAmount: BigNumber, slippageBps: number) {
  // The entire USDC amount is converted to HONEY
  const usdcToHoneyMintRate = HONEY_MINT_RATE_FROM_USDC; // [HONEY/USDC] 18dp
  const totalHoneyAmount = totalUsdcAmount.mul(usdcToHoneyMintRate).div(ONE_USDC); // 18dp

  // Then some of that HONEY is converted to BYUSD to get proportional amounts
  const honeyToByUsdRedeemRate = HONEY_REDEEM_RATE_TO_BYUSD; // 18dp
  const honeyToSellToByusd = await calcHoneySellAmount(totalHoneyAmount, honeyToByUsdRedeemRate); // 18dp
  console.log(`honeyToSellToByusd: ${ethers.utils.formatUnits(honeyToSellToByusd, 18)}`);

  const byusdToPair = honeyToSellToByusd // 18dp
    .mul(honeyToByUsdRedeemRate)
    .div(ONE_HONEY)
    .mul(ONE_USDC)
    .div(ONE_HONEY);
  console.log(`byusdToPair: ${ethers.utils.formatUnits(byusdToPair, 6)}`);

  const honeyToPair = totalHoneyAmount.sub(honeyToSellToByusd);

  return {
    honeyToSellToByusd,
    quoteData: await proportionalAddLiquidityQuote(honeyToPair, byusdToPair, slippageBps),
  };
}

async function deployAsOwner(
  totalUsdcAmount: BigNumber,
  quote: {
    honeyToSellToByusd: BigNumber,
    quoteData: Quote,
  }
) {
  const provider = new ethers.providers.JsonRpcProvider("http://127.0.0.1:8545");
  await provider.send('anvil_impersonateAccount', [ADDRS.CORE.MULTISIG]);
  const signer  = provider.getSigner(ADDRS.CORE.MULTISIG);

  const signerAddr = await signer.getAddress();

  // 0. Recover USDC from the manager to the multisig
  await mine(
    INSTANCES.VAULTS.BOYCO_USDC_A.MANAGER.connect(signer).recoverToken(ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN, ADDRS.CORE.MULTISIG, totalUsdcAmount),
  );

  const balancesBefore = await Promise.all([
    await INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.balanceOf(signerAddr),
    await INSTANCES.EXTERNAL.BERACHAIN.HONEY_TOKEN.balanceOf(signerAddr),
    await INSTANCES.EXTERNAL.PAYPAL.BYUSD_TOKEN.balanceOf(signerAddr),
  ]);
  console.log("Balances Before:");
  console.log("\tUSDC:", ethers.utils.formatUnits(balancesBefore[0], 6));
  console.log("\tHONEY:", ethers.utils.formatUnits(balancesBefore[1], 18));
  console.log("\tBYUSD:", ethers.utils.formatUnits(balancesBefore[2], 6));

  // 1. Swap the entire USDC to HONEY via the PSM
  await mine(
    INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.connect(signer).approve(ADDRS.EXTERNAL.BERACHAIN.HONEY_FACTORY, totalUsdcAmount),
  );
  await mine(
    INSTANCES.EXTERNAL.BERACHAIN.HONEY_FACTORY.connect(signer).mint(ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN, totalUsdcAmount, ADDRS.CORE.MULTISIG, false)
  );

  // 2. Swap HONEY to BYUSD via the PSM
  await mine(
    INSTANCES.EXTERNAL.PAYPAL.BYUSD_TOKEN.connect(signer).approve(ADDRS.EXTERNAL.BERACHAIN.HONEY_FACTORY, quote.honeyToSellToByusd),
  );
  await mine(
    INSTANCES.EXTERNAL.BERACHAIN.HONEY_FACTORY.connect(signer).redeem(ADDRS.EXTERNAL.PAYPAL.BYUSD_TOKEN, quote.honeyToSellToByusd, ADDRS.CORE.MULTISIG, false)
  );

  const balancesAfter = await Promise.all([
    await INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.balanceOf(signerAddr),
    await INSTANCES.EXTERNAL.BERACHAIN.HONEY_TOKEN.balanceOf(signerAddr),
    await INSTANCES.EXTERNAL.PAYPAL.BYUSD_TOKEN.balanceOf(signerAddr),
  ]);

  console.log("Balances After:");
  console.log("\tUSDC:", ethers.utils.formatUnits(balancesAfter[0], 6));
  console.log("\tHONEY:", ethers.utils.formatUnits(balancesAfter[1], 18));
  console.log("\tBYUSD:", ethers.utils.formatUnits(balancesAfter[2], 6));

  const honeyReceived = balancesAfter[1].sub(balancesBefore[1]);
  if (honeyReceived.lt(quote.quoteData.tokenAmounts[TOKEN_INDEXES.honey])) throw new Error("Received less HONEY than expected");

  const byusdReceived = balancesAfter[2].sub(balancesBefore[2]);
  if (byusdReceived.lt(quote.quoteData.tokenAmounts[TOKEN_INDEXES.byusd])) throw new Error("Received less BYUSD than expected");

  // 3. Add the HONEY/BYUSD as liquidity into BEX and receive an LP receipt token
  await mine(
    INSTANCES.EXTERNAL.PAYPAL.BYUSD_TOKEN.connect(signer).approve(ADDRS.EXTERNAL.BEX.BALANCER_VAULT, quote.quoteData.tokenAmounts[TOKEN_INDEXES.byusd])
  );
  await mine(
    INSTANCES.EXTERNAL.BERACHAIN.HONEY_TOKEN.connect(signer).approve(ADDRS.EXTERNAL.BEX.BALANCER_VAULT, quote.quoteData.tokenAmounts[TOKEN_INDEXES.honey])
  );
  await mine(
    INSTANCES.EXTERNAL.BEX.BALANCER_VAULT.connect(signer).joinPool(
      POOL_ID,
      signerAddr,
      signerAddr,
      quote.quoteData.requestData,
    )
  );

  const balancesAtTheEnd = await Promise.all([
    await INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.balanceOf(signerAddr),
    await INSTANCES.EXTERNAL.BERACHAIN.HONEY_TOKEN.balanceOf(signerAddr),
    await INSTANCES.EXTERNAL.PAYPAL.BYUSD_TOKEN.balanceOf(signerAddr),
    await INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_BYUSD.balanceOf(signerAddr)
  ]);
  const lpBalance = balancesAtTheEnd[3];

  console.log("Balances After:");
  console.log("\tUSDC:", ethers.utils.formatUnits(balancesAtTheEnd[0], 6));
  console.log("\tHONEY:", ethers.utils.formatUnits(balancesAtTheEnd[1], 18));
  console.log("\tBYUSD:", ethers.utils.formatUnits(balancesAtTheEnd[2], 6));
  console.log("\tLP:", ethers.utils.formatUnits(lpBalance, 18));

  // @todo
  // // 3. Stake the BPT
  // await mine(
  //   INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_BYUSD.connect(signer).transfer(ADDRS.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_BYUSD, lpBalance)
  // );
  // await mine(
  //   INSTANCES.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_BYUSD.connect(signer).stake(INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_BYUSD.balanceOf(ADDRS.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_BYUSD))
  // );
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

function redeemHoney(
  contract: Contract,
  asset: string,
  honeyAmount: BigNumber,
  receiver: string,
  expectBasketMode: boolean
) {
  return createSafeTransaction(
    contract.address,
    "redeem",
    [
      {
        argType: "address",
        name: "asset",
        value: asset,
      },
      {
        argType: "uint256",
        name: "honeyAmount",
        value: honeyAmount.toString(),
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
    honeyToSellToByusd: BigNumber,
    quoteData: Quote,
  }
) {
  const batch = createSafeBatch(
    [
      // 1. Pull funds from manager back to multisig
      recoverToken(INSTANCES.VAULTS.BOYCO_USDC_A.MANAGER, ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN, ADDRS.CORE.MULTISIG, totalUsdcAmount),

      // 2. Swap the entire USDC to HONEY via the PSM
      approve(INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN, ADDRS.EXTERNAL.BERACHAIN.HONEY_FACTORY, totalUsdcAmount),
      mintHoney(INSTANCES.EXTERNAL.BERACHAIN.HONEY_FACTORY, ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN, totalUsdcAmount, ADDRS.CORE.MULTISIG, false),

      // 2. Swap HONEY to BYUSD via the PSM
      approve(INSTANCES.EXTERNAL.BERACHAIN.HONEY_TOKEN, ADDRS.EXTERNAL.BERACHAIN.HONEY_FACTORY, quote.honeyToSellToByusd),
      redeemHoney(INSTANCES.EXTERNAL.BERACHAIN.HONEY_FACTORY, ADDRS.EXTERNAL.PAYPAL.BYUSD_TOKEN, quote.honeyToSellToByusd, ADDRS.CORE.MULTISIG, false),

      // 3. Add the HONEY/BYUSD as liquidity into BEX and receive an LP receipt token
      approve(INSTANCES.EXTERNAL.PAYPAL.BYUSD_TOKEN, ADDRS.EXTERNAL.BEX.BALANCER_VAULT, quote.quoteData.tokenAmounts[TOKEN_INDEXES.byusd]),
      approve(INSTANCES.EXTERNAL.BERACHAIN.HONEY_TOKEN, ADDRS.EXTERNAL.BEX.BALANCER_VAULT, quote.quoteData.tokenAmounts[TOKEN_INDEXES.honey]),
      joinPool(INSTANCES.EXTERNAL.BEX.BALANCER_VAULT, POOL_ID, ADDRS.CORE.MULTISIG, ADDRS.CORE.MULTISIG, quote.quoteData.requestData),
    ],
  );

  const filename = path.join(__dirname, "./deploy-proportional-liquidity-byusd-honey-batch1.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

async function deployViaMsigStep2() {
  const lpBalance = await INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_BYUSD.balanceOf(ADDRS.CORE.MULTISIG);

  const batch = createSafeBatch(
    [
      // 4. Send the LP to the rewards vault proxy and stake.
      transferBpt(INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_BYUSD, ADDRS.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_BYUSD, lpBalance),
      stake(INSTANCES.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_BYUSD, lpBalance),
    ]
  );

  const filename = path.join(__dirname, "./deploy-proportional-liquidity-byusd-honey-batch2.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

async function main() {
  ({ owner, ADDRS, INSTANCES } = await getDeployContext(__dirname));

  // Set as the minimum amount to use
  let usdcDeployAmount = ethers.utils.parseUnits("100", 6);

  if (usdcDeployAmount.gt(ZERO)) {
    await initState();

    console.log("-------------");
    console.log(`Requested USDC to add: ${ethers.utils.formatUnits(usdcDeployAmount, 6)}`);

    // Cap to how much BYUSD is available in the PSM
    const byusdInPsm = await INSTANCES.EXTERNAL.PAYPAL.BYUSD_TOKEN.balanceOf(HONEY_MINTER_BYUSD_VAULT);
    console.log("BYUSD Balance in PSM:", ethers.utils.formatUnits(byusdInPsm, 6));
    const maxUsdcFromPsm = byusdInPsm
      .mul(ONE_HONEY)
      .div(HONEY_REDEEM_RATE_TO_BYUSD)
      .mul(ONE_HONEY)
      .div(HONEY_MINT_RATE_FROM_USDC);
    console.log("Max USDC which can be utilised :", ethers.utils.formatUnits(maxUsdcFromPsm, 6));
    usdcDeployAmount = usdcDeployAmount.gt(maxUsdcFromPsm) ? maxUsdcFromPsm : usdcDeployAmount;

    const availableInManager = await INSTANCES.VAULTS.BOYCO_USDC_A.MANAGER.unallocatedAssets();
    console.log("USDC available in manager:", ethers.utils.formatUnits(availableInManager, 6));
    usdcDeployAmount = usdcDeployAmount.gt(availableInManager) ? availableInManager : usdcDeployAmount;

    console.log("-------------");
    console.log(`USDC Deploy Amount: ${ethers.utils.formatUnits(usdcDeployAmount, 6)}`);
  }

  if (usdcDeployAmount.gt(ZERO)) {
    const quote = await getQuote(usdcDeployAmount, BALANCER_SLIPPAGE_BPS);
    console.log(`Quote BYUSD In: ${ethers.utils.formatUnits(quote.quoteData.tokenAmounts[TOKEN_INDEXES.byusd], 6)}`);
    console.log(`Quote HONEY In: ${ethers.utils.formatEther(quote.quoteData.tokenAmounts[TOKEN_INDEXES.honey])}`);
    console.log(`Quote BPT OUT (expected): ${ethers.utils.formatEther(quote.quoteData.expectedLpTokenAmount)}`);
    console.log(`Quote BPT OUT (min): ${ethers.utils.formatEther(quote.quoteData.minLpTokenAmount)}`);

    // This was a test run with my PK as the owner of the assets already
    await deployAsOwner(usdcDeployAmount, quote);

    // deployViaMsigStep1(totalUsdcAmount, quote);
  } else {
    await deployViaMsigStep2();
  }
}

runAsyncMain(main);
