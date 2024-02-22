import { BigNumber, BigNumberish, Contract, Signer } from 'ethers';
import { ethers } from 'hardhat';
import { applySlippage, impersonateSigner, mineForwardSeconds, ZERO_ADDRESS } from '../../../../test/hardhat/helpers';
import { 
    OrigamiGmxInvestment, OrigamiGmxInvestment__factory,
    OrigamiGlpInvestment, OrigamiGlpInvestment__factory,
    OrigamiGmxEarnAccount, OrigamiGmxEarnAccount__factory,
    OrigamiGmxRewardsAggregator, OrigamiGmxRewardsAggregator__factory,
    OrigamiGmxManager, OrigamiGmxManager__factory,
    GMX_GMX__factory, GMX_GMX, 
    GMX_GmxTimelock__factory, 
    GMX_TokenManager__factory, 
    GMX_RewardRouterV2__factory, 
    GMX_RewardRouterV2, 
    IWrappedToken__factory, 
    GMX_RewardTracker__factory,
    TokenPrices,
    TokenPrices__factory,
    GMX_RewardDistributor__factory,
    OrigamiInvestmentVault,
    OrigamiInvestmentVault__factory,
    IERC20__factory,
    IERC20,
    GMX_EsGMX__factory,
    GMX_Timelock__factory,
    IOrigamiElevatedAccess
} from '../../../../typechain';
import {
    ZeroExQuoteParams,
    encodeGlpHarvestParams,
    encodeGmxHarvestParams,
    ensureExpectedEnvvars,
    fromAtto,
    mine,
    zeroExQuote,
} from '../../helpers';
import { GmxDeployedContracts, getDeployedContracts as gmxDeployedContracts } from '../../arbitrum/gmx/contract-addresses';
import { getDeployedContracts as govDeployedContracts } from '../../arbitrum/governance/contract-addresses';

interface ContractInstances {
    gmxEarnAccount: OrigamiGmxEarnAccount,
    glpPrimaryEarnAccount: OrigamiGmxEarnAccount,
    glpSecondaryEarnAccount: OrigamiGmxEarnAccount,
    gmxManager: OrigamiGmxManager,
    glpManager: OrigamiGmxManager,
    gmxRewardsAggregator: OrigamiGmxRewardsAggregator,
    glpRewardsAggregator: OrigamiGmxRewardsAggregator,
    oGMX: OrigamiGmxInvestment,
    oGLP: OrigamiGlpInvestment,
    ovGMX: OrigamiInvestmentVault,
    ovGLP: OrigamiInvestmentVault,

    gmxToken: GMX_GMX,
    gmxRewardRouter: GMX_RewardRouterV2,
    glpRewardRouter: GMX_RewardRouterV2,
    tokenPrices: TokenPrices,
    weth: IERC20,
}

function connectToContracts(GMX_DEPLOYED: GmxDeployedContracts, owner: Signer): ContractInstances {
    return {
        gmxEarnAccount: OrigamiGmxEarnAccount__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.GMX_EARN_ACCOUNT, owner),
        glpPrimaryEarnAccount: OrigamiGmxEarnAccount__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.GLP_PRIMARY_EARN_ACCOUNT, owner),
        glpSecondaryEarnAccount: OrigamiGmxEarnAccount__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.GLP_SECONDARY_EARN_ACCOUNT, owner),
        gmxManager: OrigamiGmxManager__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.GMX_MANAGER, owner),
        glpManager: OrigamiGmxManager__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.GLP_MANAGER, owner),
        gmxRewardsAggregator: OrigamiGmxRewardsAggregator__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.GMX_REWARDS_AGGREGATOR, owner),
        glpRewardsAggregator: OrigamiGmxRewardsAggregator__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.GLP_REWARDS_AGGREGATOR, owner),
        oGMX: OrigamiGmxInvestment__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.oGMX, owner),
        oGLP: OrigamiGlpInvestment__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.oGLP, owner),
        ovGMX: OrigamiInvestmentVault__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.ovGMX, owner),
        ovGLP: OrigamiInvestmentVault__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.ovGLP, owner),

        gmxToken: GMX_GMX__factory.connect(GMX_DEPLOYED.GMX.TOKENS.GMX_TOKEN, owner),
        gmxRewardRouter: GMX_RewardRouterV2__factory.connect(GMX_DEPLOYED.GMX.STAKING.GMX_REWARD_ROUTER, owner),
        glpRewardRouter: GMX_RewardRouterV2__factory.connect(GMX_DEPLOYED.GMX.STAKING.GLP_REWARD_ROUTER, owner),
        tokenPrices: TokenPrices__factory.connect(GMX_DEPLOYED.ORIGAMI.TOKEN_PRICES, owner),

        weth: IERC20__factory.connect(GMX_DEPLOYED.GMX.LIQUIDITY_POOL.WETH_TOKEN, owner),
    }
}

async function impersonateAndFund(owner: Signer, address: string, amount: number): Promise<Signer> {
  const signer = await impersonateSigner(address);
  console.log("impersonateAndFund:", address, amount);
  if (amount > 0) {
    await mine(owner.sendTransaction({
        to: await signer.getAddress(),
        value: ethers.utils.parseEther(amount.toString()),
    }));
  }
  return signer;
}

async function claimTokenOwnership(contracts: ContractInstances, owner: Signer) {
    // Can set the gov of the reward router directly (no timelock)
    const rewardRouterMsig = await impersonateAndFund(owner, await contracts.gmxRewardRouter.gov(), 0.01);

    // GMX token has it's own timelock contract
    let gmxTokenTimelock = GMX_GmxTimelock__factory.connect(await contracts.gmxToken.gov(), owner);
    const gmxTokenTimelockMsig = await impersonateAndFund(owner, await gmxTokenTimelock.admin(), 0.02);
    gmxTokenTimelock = gmxTokenTimelock.connect(gmxTokenTimelockMsig);

    // The GMX Token is different - need to go through the TokenManager, and have 6 signers sign for it first.
    {
      const tokenManager = GMX_TokenManager__factory.connect(await gmxTokenTimelock.tokenManager(), owner);
      await mine(tokenManager.connect(rewardRouterMsig).signalSetGov(gmxTokenTimelock.address, contracts.gmxToken.address, owner.getAddress()));
      const tokenSigners = [
          "0x45e48668F090a3eD1C7961421c60Df4E66f693BD",
          "0xD7941C4Ca57a511F21853Bbc7FBF8149d5eCb398",
          "0x881690382102106b00a99E3dB86056D0fC71eee6",
          "0x2E5d207a4C0F7e7C52F6622DCC6EB44bC0fE1A13",
          "0x6091646D0354b03DD1e9697D33A7341d8C93a6F5",
          "0xd6D5a4070C7CFE0b42bE83934Cc21104AbeF1AD5",
      ]
      for (let idx=0; idx < tokenSigners.length; idx++) {
          const signer = await impersonateSigner(tokenSigners[idx]); //await impersonateAndFund(owner, tokenSigners[idx], 0.01);
          await mine(tokenManager.connect(signer).signSetGov(gmxTokenTimelock.address, contracts.gmxToken.address, owner.getAddress(), await tokenManager.actionsNonce()));
      }
      await mine(tokenManager.connect(rewardRouterMsig).setGov(gmxTokenTimelock.address, contracts.gmxToken.address, owner.getAddress(), await tokenManager.actionsNonce()));
    }

    // Gotta wait more time for the gmx timelock
    {
      const timelockWaitPeriod = await gmxTokenTimelock.longBuffer();
      await mineForwardSeconds(timelockWaitPeriod.add(1).toNumber());
      await mine(gmxTokenTimelock.setGov(contracts.gmxToken.address, await owner.getAddress()));
    }
}

// GMX.io has set 0 esGMX rewards on staked GLP -- for testing purposes we update to something meaningful.
async function setUpstreamRewardRates(contracts: ContractInstances, owner: Signer) {
    const rewardRouterMsig = await impersonateSigner(await contracts.glpRewardRouter.gov());
    const stakedGlpTracker = GMX_RewardTracker__factory.connect(await contracts.glpRewardRouter.stakedGlpTracker(), rewardRouterMsig);
    const glpEsGmxDistributor = GMX_RewardDistributor__factory.connect(await stakedGlpTracker.distributor(), rewardRouterMsig);
    await mine(glpEsGmxDistributor.setTokensPerInterval(ethers.utils.parseEther("0.1")));

    const esGmx = GMX_EsGMX__factory.connect(await glpEsGmxDistributor.rewardToken(), owner);

    // Get control of esGMX and add our owner as a valid minter
    {
        let timelock = GMX_Timelock__factory.connect(await esGmx.gov(), owner);
        const timelockMsig = await impersonateSigner(await timelock.admin());
        await mine(owner.sendTransaction({
            to: await timelockMsig.getAddress(),
            value: ethers.utils.parseEther("0.1")
        }));

        timelock = timelock.connect(timelockMsig);

        await mine(timelock.signalSetGov(esGmx.address, await owner.getAddress()));

        const timelockWaitPeriod = await timelock.buffer();
        await mineForwardSeconds(timelockWaitPeriod.add(1).toNumber());
        await mine(timelock.setGov(esGmx.address, await owner.getAddress()));
        await mine(esGmx.setMinter(await owner.getAddress(), true));
    }

    // Mint some esGMX to the distributor
    await mine(esGmx.connect(owner).mint(glpEsGmxDistributor.address, ethers.utils.parseEther("100000")));
}

type TokenPricesArg = string | boolean | BigNumberish;

const encodeFunction = (fn: string, ...args: TokenPricesArg[]): string => {
    const tokenPricesInterface = new ethers.utils.Interface(JSON.stringify(TokenPrices__factory.abi));
    return tokenPricesInterface.encodeFunctionData(fn, args);
}

const encodedOraclePrice = (oracle: string, stalenessThreshold: number): string => encodeFunction("oraclePrice", oracle, stalenessThreshold);

async function updateOracleThreshold(DEPLOYED: GmxDeployedContracts, contracts: ContractInstances) {
    const stalenessThreshold = 86400 * 365;
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        ZERO_ADDRESS, 
        encodedOraclePrice(DEPLOYED.PRICES.ETH_USD_ORACLE, stalenessThreshold),
    ));
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.LIQUIDITY_POOL.WBTC_TOKEN, 
        encodedOraclePrice(DEPLOYED.PRICES.BTC_USD_ORACLE, stalenessThreshold)));
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.LIQUIDITY_POOL.LINK_TOKEN, 
        encodedOraclePrice(DEPLOYED.PRICES.LINK_USD_ORACLE, stalenessThreshold)));
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.LIQUIDITY_POOL.UNI_TOKEN, 
        encodedOraclePrice(DEPLOYED.PRICES.UNI_USD_ORACLE, stalenessThreshold)));
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.LIQUIDITY_POOL.USDC_TOKEN, 
        encodedOraclePrice(DEPLOYED.PRICES.USDC_USD_ORACLE, stalenessThreshold)));
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.LIQUIDITY_POOL.USDC_E_TOKEN, 
        encodedOraclePrice(DEPLOYED.PRICES.USDC_USD_ORACLE, stalenessThreshold)));
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.LIQUIDITY_POOL.USDT_TOKEN, 
        encodedOraclePrice(DEPLOYED.PRICES.USDT_USD_ORACLE, stalenessThreshold)));
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.LIQUIDITY_POOL.DAI_TOKEN, 
        encodedOraclePrice(DEPLOYED.PRICES.DAI_USD_ORACLE, stalenessThreshold)));
    await mine(contracts.tokenPrices.setTokenPriceFunction(
        DEPLOYED.GMX.LIQUIDITY_POOL.FRAX_TOKEN, 
        encodedOraclePrice(DEPLOYED.PRICES.FRAX_USD_ORACLE, stalenessThreshold)));
}

async function dumpPrices(contracts: ContractInstances) {
    const prices = await contracts.tokenPrices.tokenPrices(
        [
          contracts.weth.address,
          contracts.gmxToken.address,
          contracts.oGMX.address,
          contracts.ovGMX.address,
          await contracts.glpManager.glpToken(),
          contracts.oGLP.address,
          contracts.ovGLP.address,
        ]
      );
      console.log("PRICES:");
      console.log("\tWETH:", ethers.utils.formatUnits(prices[0], 30));
      console.log("\tGMX:", ethers.utils.formatUnits(prices[1], 30));
      console.log("\toGMX:", ethers.utils.formatUnits(prices[2], 30));
      console.log("\tovGMX:", ethers.utils.formatUnits(prices[3], 30));
      console.log("\tGLP:", ethers.utils.formatUnits(prices[4], 30));
      console.log("\toGLP:", ethers.utils.formatUnits(prices[5], 30));
      console.log("\tovGLP:", ethers.utils.formatUnits(prices[6], 30));
      console.log();
}

async function getAggregatorRewardBalances(contracts: ContractInstances, aggregator: OrigamiGmxRewardsAggregator) {
    return {
        oGmx: await contracts.oGMX.balanceOf(aggregator.address),
        oGlp: await contracts.oGLP.balanceOf(aggregator.address),
    };
}

// Set to true to refresh the ZeroEx quotes. You'll probably have to update the fork block number
// in package.json: `"local-fork:arbitrum": ... --fork-block-number XXXX`
// Get the latest block number from https://arbiscan.io/blocks
const REFRESH_QUOTES = false;

const SLIPPAGE_BPS = 100; // 1%

const harvestGlp = async (contracts: ContractInstances, signer: Signer) => {
    const _harvestableRewards = await contracts.glpRewardsAggregator.harvestableRewards();
    const harvestableRewards = {weth: _harvestableRewards[0], oGmx: _harvestableRewards[1], oGlp: _harvestableRewards[2]};
    console.log(`\tGLP Harvestable Reward Amounts: [weth: ${harvestableRewards.weth}, oGmx: ${harvestableRewards.oGmx}, oGlp: ${harvestableRewards.oGlp}]`);

    // Get a quote to swap $oGMX rewards -> $GMX
    // NB: No slippage when exiting the oGMX position as it's redeemed in situ (not sold via a dex)
    const oGmxToGmxExitQuote = await contracts.oGMX.exitQuote(harvestableRewards.oGmx, contracts.gmxToken.address, 0, 0);
    console.log(`oGMX -> GMX Exit Quote: ${oGmxToGmxExitQuote}`);

    let gmxSellAmount = oGmxToGmxExitQuote.quoteData.minToTokenAmount;
    console.log(`\tGMX Sell Amount: ${gmxSellAmount.toString()}`);

    let guaranteedPrice: BigNumber;
    let zeroExQuoteData: string;
    if (REFRESH_QUOTES) {
        // Take a touch off the sell amount, as when it's run the next we may not have as many rewards to harvest (it's based on elapsed time).
        gmxSellAmount = applySlippage(gmxSellAmount, 100);

        const quoteParams: ZeroExQuoteParams = {
            sellToken: contracts.gmxToken.address,
            buyToken: contracts.weth.address,
            sellAmount: gmxSellAmount.toString(),
            priceImpactProtectionPercentage: 0.01, // 1%
            slippagePercentage: 0.02, // 2%
            enableSlippageProtection: true,
        }
        console.log(quoteParams);
        /**
zeroExQuote: 
curl "https://arbitrum.api.0x.org/swap/v1/quote?\
sellToken=0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a&\
buyToken=0x82aF49447D8a07e3bd95BD0d56f35241523fBab1&\
sellAmount=96818181206770331&\
priceImpactProtectionPercentage=0.01&\
slippagePercentage=0.01&\
enableSlippageProtection=true" | jq
*/
        const resp = await zeroExQuote("arbitrum", quoteParams);
        console.log(resp);
        console.log(resp.data);
        
        guaranteedPrice = ethers.utils.parseEther(resp.guaranteedPrice);
        zeroExQuoteData = resp.data;
    } else {
        // Copy the `guaranteedPrice` and `data` fields from the quote when refreshed.
        guaranteedPrice = ethers.utils.parseEther("0.04198649677896497");
        zeroExQuoteData = "0x415565b0000000000000000000000000fc5a1a6eb076a2c7ad06ed22c90d7e710e35ad0a00000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab10000000000000000000000000000000000000000000000000150f0551cd5681a000000000000000000000000000000000000000000000000000e2599e9e98ac900000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000050000000000000000000000000000000000000000000000000000000000000000130000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000046000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000fc5a1a6eb076a2c7ad06ed22c90d7e710e35ad0a00000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab100000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000420000000000000000000000000000000000000000000000000000000000000042000000000000000000000000000000000000000000000000000000000000003e00000000000000000000000000000000000000000000000000150f0551cd5681a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000420000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000001942616c616e63657256320000000000000000000000000000000000000000000000000000000000000150f0551cd5681a000000000000000000000000000000000000000000000000000e2599e9e98ac9000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000001c0000000000000000000000000ba12222222228d8ba445958a75a0704d566bf2c800000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200adeb25cb5920d4f7447af4a0428072edc2cee2200020000000000000000004a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000fc5a1a6eb076a2c7ad06ed22c90d7e710e35ad0a00000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab10000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000002000000000000000000000000fc5a1a6eb076a2c7ad06ed22c90d7e710e35ad0a000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd0000000000000000000000001000000000000000000000000000000000000011000000000000000000000000000000000000000000000065dcd75cd663e970ea";
    }

    console.log(`\tguaranteedPrice=[${guaranteedPrice}]`);

    const minWethExpected = gmxSellAmount.mul(guaranteedPrice).div(ethers.utils.parseEther("1"));
    console.log(`\tminWethExpected=${minWethExpected.toString()}`);

    // The total $WETH we have to sell = 
    //   1/ The expected amount of $WETH we will receive from selling the $GMX +
    //   2/ The harvested $WETH
    const wethToInvestInOGlp = minWethExpected.add(harvestableRewards.weth);
    console.log(`\twethToInvestInOGlp=[${wethToInvestInOGlp.toString()}]`);

    // Get a quote to swap $WETH -> $oGLP
    // There may be slippage on the expected output, as the underlying GLP purchase is executed via GMX.io
    const wethToOglpInvestQuote = await contracts.oGLP.investQuote(wethToInvestInOGlp, contracts.weth.address, SLIPPAGE_BPS, 0);
    console.log(`\tWETH -> oGLP Invest Quote: ${wethToOglpInvestQuote}`);

    // The total $oGLP expected in the aggregator = 
    //   1/ The min expected amount after the oGMX->GMX->wETH->oGLP swaps
    //   2/ The amount of oGlp already existing in the aggregator - given by the harvestableRewards()
    const totalOGlpAvailable = wethToOglpInvestQuote.quoteData.minInvestmentAmount.add(harvestableRewards.oGlp);
    console.log(`\ttotalOGlpAvailable=[${totalOGlpAvailable.toString()}]`);

    // To smooth the bump up out, we only add a percentage of the total available oGLP as reserves
    // each day.
    const addToReserveAmountPct = 1_000;
    console.log(`\taddToReserveAmountPct=[${addToReserveAmountPct}]`);

    const harvestParams: OrigamiGmxRewardsAggregator.HarvestGlpParamsStruct = {
        oGmxExitQuoteData: oGmxToGmxExitQuote.quoteData,
        gmxToNativeSwapData: zeroExQuoteData,
        oGlpInvestQuoteData: wethToOglpInvestQuote.quoteData,
        addToReserveAmountPct: addToReserveAmountPct,
    };
    console.log("\tHarvest Params:", harvestParams);

    console.log("\tovGLP Reserves Before:", await contracts.ovGLP.totalReserves());
    console.log("\tovGLP Vested & Pending Before:", (await contracts.ovGLP.vestedReserves()).add(await contracts.ovGLP.pendingReserves()));
    await mine(contracts.glpRewardsAggregator.connect(signer).harvestRewards(encodeGlpHarvestParams(harvestParams)));
    console.log("\tovGLP Reserves After:", await contracts.ovGLP.totalReserves());
    console.log("\tovGLP Vested & Pending After:", (await contracts.ovGLP.vestedReserves()).add(await contracts.ovGLP.pendingReserves()));
}

const harvestGmx = async (contracts: ContractInstances, signer: Signer) => {
    const _harvestableRewards = await contracts.gmxRewardsAggregator.harvestableRewards();
    const harvestableRewards = {weth: _harvestableRewards[0], oGmx: _harvestableRewards[1], oGlp: _harvestableRewards[2]};
    console.log(`\tGMX Harvestable Reward Amounts: [weth: ${harvestableRewards.weth}, oGmx: ${harvestableRewards.oGmx}, oGlp: ${harvestableRewards.oGlp}]`);
    const existingGmx = await contracts.gmxToken.balanceOf(contracts.gmxRewardsAggregator.address);
    console.log(`\tExisting GMX in aggregator: ${existingGmx.toString()}`);

    let wethSellAmount = harvestableRewards.weth;
    console.log(`\tWETH Sell Amount: ${wethSellAmount.toString()}`);

    let guaranteedPrice: BigNumber;
    let zeroExQuoteData: string;
    if (REFRESH_QUOTES) {
        // Take a touch off the sell amount, as when it's run the next we may not have as many rewards to harvest (it's based on elapsed time).
        wethSellAmount = applySlippage(wethSellAmount, 100);

        const quoteParams: ZeroExQuoteParams = {
            sellToken: contracts.weth.address,
            buyToken: contracts.gmxToken.address,
            sellAmount: wethSellAmount.toString(),
            priceImpactProtectionPercentage: 0.01, // 1%
            slippagePercentage: 0.02, // 2%
            enableSlippageProtection: true,
        }
        console.log(quoteParams);
        /**
eg:
zeroExQuote: 
curl "https://arbitrum.api.0x.org/swap/v1/quote?\
sellToken=0x82aF49447D8a07e3bd95BD0d56f35241523fBab1&\
buyToken=0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a&\
sellAmount=51636878185938045&\
priceImpactProtectionPercentage=0.01&\
slippagePercentage=0.01&\
enableSlippageProtection=true" | jq
*/
        const resp = await zeroExQuote("arbitrum", quoteParams);
        console.log(resp);
        console.log(resp.data);
        
        console.log(resp.guaranteedPrice);
        guaranteedPrice = ethers.utils.parseEther(resp.guaranteedPrice);
        zeroExQuoteData = resp.data;
    } else {
        // Copy the `guaranteedPrice` and `data` fields from the quote when refreshed.
        guaranteedPrice = ethers.utils.parseEther("22.863340548979358199");
        zeroExQuoteData = "0x415565b000000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab1000000000000000000000000fc5a1a6eb076a2c7ad06ed22c90d7e710e35ad0a00000000000000000000000000000000000000000000000000b5a0d6ac3b3b810000000000000000000000000000000000000000000000001038a10df89f0a8400000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000003e00000000000000000000000000000000000000000000000000000000000000013000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000003400000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab1000000000000000000000000fc5a1a6eb076a2c7ad06ed22c90d7e710e35ad0a00000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000002c000000000000000000000000000000000000000000000000000b5a0d6ac3b3b81000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000012556e697377617056330000000000000000000000000000000000000000000000000000000000000000b5a0d6ac3b3b810000000000000000000000000000000000000000000000001038a10df89f0a84000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000e592427a0aece92de3edee1f18e0157c058615640000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000002b82af49447d8a07e3bd95bd0d56f35241523fbab10001f4fc5a1a6eb076a2c7ad06ed22c90d7e710e35ad0a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000000200000000000000000000000082af49447d8a07e3bd95bd0d56f35241523fbab1000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000eae4cb5bd963e970e8";
    }

    console.log(`\tguaranteedPrice=[${guaranteedPrice}]`);
    const minGmxExpected = wethSellAmount.mul(guaranteedPrice).div(ethers.utils.parseEther("1"));
    console.log(`\tminGmxExpected=[${minGmxExpected.toString()}]`);

    // The total $GMX we have to invest = 
    //   1/ The expected amount of $GMX we will receive from selling the $WETH +
    //   2/ Any existing balance from previous swaps left over amounts
    const gmxToInvestInOGmx = minGmxExpected.add(existingGmx);
    console.log(`\tgmxToInvestInOGmx=[${gmxToInvestInOGmx.toString()}]`);

    // Get a quote to swap $GMX -> $oGMX
    // NB: No slippage when investing in the oGMX position as it's minted in situ (not bought via a dex)
    const gmxToOgmxInvestQuote = await contracts.oGMX.investQuote(gmxToInvestInOGmx, contracts.gmxToken.address, 0, 0);
    console.log(`\tGMX -> oGMX Invest Quote: ${gmxToOgmxInvestQuote}`);

    // The total $oGMX expected in the aggregator = 
    //   1/ The min expected amount after the wETH->GMX->oGMX swaps
    //   2/ The amount of oGMX already existing + harvested in the aggregator - given by the harvestableRewards()
    const totalOGmxAvailable = gmxToOgmxInvestQuote.quoteData.minInvestmentAmount.add(harvestableRewards.oGmx);
    console.log(`\ttotalOGmxAvailable=[${totalOGmxAvailable.toString()}]`);

    // To smooth the bump up out, we only add a percentage of the total available oGMX as reserves
    // each day.
    const addToReserveAmountPct = 1_000;
    console.log(`\taddToReserveAmountPct=[${addToReserveAmountPct}]`);

    const harvestParams: OrigamiGmxRewardsAggregator.HarvestGmxParamsStruct = {
        nativeToGmxSwapData: zeroExQuoteData,
        oGmxInvestQuoteData: gmxToOgmxInvestQuote.quoteData,
        addToReserveAmountPct: addToReserveAmountPct,
    };
    console.log("\tHarvest Params:", harvestParams);

    console.log("\tovGMX Reserves Before:", await contracts.ovGMX.totalReserves());
    console.log("\tovGMX Vested & Pending Before:", (await contracts.ovGMX.vestedReserves()).add(await contracts.ovGMX.pendingReserves()));
    await mine(contracts.gmxRewardsAggregator.connect(signer).harvestRewards(encodeGmxHarvestParams(harvestParams)));
    console.log("\tovGMX Reserves After:", await contracts.ovGMX.totalReserves());
    console.log("\tovGMX Vested & Pending After:", (await contracts.ovGMX.vestedReserves()).add(await contracts.ovGMX.pendingReserves()));
}

async function acceptOwner(contractToSet: IOrigamiElevatedAccess) {
    await mine(contractToSet.acceptOwner());
    console.log("Gov for:", contractToSet.address, "=", await contractToSet.owner());
}

// Have the timelock accept governance, and then give it back to owner
// as a test that the process works.
async function claimOwner(owner: Signer, contractToSet: IOrigamiElevatedAccess) {
    await acceptOwner(contractToSet);

    await mine(contractToSet.proposeNewOwner(await owner.getAddress()));
    await mine(contractToSet.connect(owner).acceptOwner());
    console.log("Gov for:", contractToSet.address, "=", await contractToSet.owner());
}

async function main() {
    ensureExpectedEnvvars();
    const [owner, fred, joe, bob, feeCollector] = await ethers.getSigners();

    const GMX_DEPLOYED = gmxDeployedContracts();
    const GOV_DEPLOYED = govDeployedContracts();
    console.log("owner addr:", await owner.getAddress());
    console.log("origami msig:", GOV_DEPLOYED.ORIGAMI.MULTISIG);
    
    const origamiMultisig = await impersonateAndFund(owner, GOV_DEPLOYED.ORIGAMI.MULTISIG, 10);
    const contracts = connectToContracts(GMX_DEPLOYED, origamiMultisig);

    await claimOwner(origamiMultisig, contracts.gmxRewardsAggregator as unknown as IOrigamiElevatedAccess);
    await claimOwner(origamiMultisig, contracts.glpRewardsAggregator as unknown as IOrigamiElevatedAccess);
    await claimOwner(origamiMultisig, contracts.oGMX as unknown as IOrigamiElevatedAccess);
    await claimOwner(origamiMultisig, contracts.oGLP as unknown as IOrigamiElevatedAccess);
    await claimOwner(origamiMultisig, contracts.ovGMX as unknown as IOrigamiElevatedAccess);
    await claimOwner(origamiMultisig, contracts.ovGLP as unknown as IOrigamiElevatedAccess);
    await claimOwner(origamiMultisig, contracts.gmxManager as unknown as IOrigamiElevatedAccess);
    
    await setUpstreamRewardRates(contracts, owner);
    await updateOracleThreshold(GMX_DEPLOYED, contracts);

    // Check the token prices
    await dumpPrices(contracts);

    // The GMX reward distributors don't have a huge supply of rewards in their balance
    // The impact being that it will simply cap out the rewards it distributes when anyone claims.
    // Normally GMX will top up the accounts as required by collecting fees and sending to the distributors.
    // So use Joe to deposit a tonne of ETH into wETH and transfer to the relevant GMX fee contracts
    {
        const wethWrapped = IWrappedToken__factory.connect(await contracts.gmxRewardRouter.weth(), origamiMultisig);
        await mine(wethWrapped.connect(joe).deposit({value: ethers.utils.parseEther("9999")}));
        const feeGlpTracker = GMX_RewardTracker__factory.connect(await contracts.glpRewardRouter.feeGlpTracker(), origamiMultisig);
        await mine(contracts.weth.connect(joe).transfer(feeGlpTracker.distributor(), ethers.utils.parseEther("4000")));
        const feeGmxTracker = GMX_RewardTracker__factory.connect(await contracts.gmxRewardRouter.feeGmxTracker(), origamiMultisig);
        await mine(contracts.weth.connect(joe).transfer(feeGmxTracker.distributor(), ethers.utils.parseEther("5500")));
        console.log("**Sent GMX distributors weth**");
    }
    
    await claimTokenOwnership(contracts, origamiMultisig);
    console.log("**Claimed GMX Ownership**");

    console.log("\n**Mint Fred some GMX and buy ovGMX**");
    {
      await mine(contracts.gmxToken.setMinter(origamiMultisig.getAddress(), true));
      const buyAmount = ethers.utils.parseEther("10000");
      await mine(contracts.gmxToken.mint(fred.getAddress(), buyAmount));

      const quote = await contracts.ovGMX.investQuote(buyAmount, contracts.gmxToken.address, 0, 0);
      await mine(contracts.gmxToken.connect(fred).approve(contracts.ovGMX.address, buyAmount));
      await mine(contracts.ovGMX.connect(fred).investWithToken(quote.quoteData));

      console.log("Fred ovGMX Bal:", fromAtto(await contracts.ovGMX.balanceOf(fred.getAddress())));
      console.log("Fred oGMX Bal:", fromAtto(await contracts.oGMX.balanceOf(fred.getAddress())));
      console.log("ovGMX Total Supply:", fromAtto(await contracts.ovGMX.totalSupply()));
      console.log("ovGMX Total Reserves:", fromAtto(await contracts.ovGMX.totalReserves()));
      console.log("ovGMX Vested Reserves:", fromAtto(await contracts.ovGMX.vestedReserves()));
      console.log("ovGMX Pending Reserves:", fromAtto(await contracts.ovGMX.pendingReserves()));
      console.log("oGMX Total Supply:", fromAtto(await contracts.oGMX.totalSupply()));
    }

    console.log("\n**Bob buys some ovGLP with ETH**");
    {
      const buyAmount = ethers.utils.parseEther("5");
      const quote = await contracts.ovGLP.investQuote(buyAmount, ZERO_ADDRESS, 0, 0);
      console.log("quote:", quote);
      await mine(contracts.ovGLP.connect(bob).investWithNative(quote.quoteData, {value: buyAmount}));

      console.log("Bob ovGLP Bal:", fromAtto(await contracts.ovGLP.balanceOf(bob.getAddress())));
      console.log("Bob oGLP Bal:", fromAtto(await contracts.oGLP.balanceOf(bob.getAddress())));
      console.log("ovGLP Total Supply:", fromAtto(await contracts.ovGLP.totalSupply()));
      console.log("ovGLP Total Reserves:", fromAtto(await contracts.ovGLP.totalReserves()));
      console.log("ovGLP Vested Reserves:", fromAtto(await contracts.ovGLP.vestedReserves()));
      console.log("ovGLP Pending Reserves:", fromAtto(await contracts.ovGLP.pendingReserves()));
      console.log("oGLP Total Supply:", fromAtto(await contracts.oGLP.totalSupply()));
    }

    console.log("\n**Transfer Staked GLP from Secondary Earn Account -> Primary Earn Account**");
    {
      const stakedGlpPosition = (await contracts.glpSecondaryEarnAccount.positions()).glpPositions.stakedGlp;
      console.log("Staked GLP Position in Secondary Earn Account:", ethers.utils.formatEther(stakedGlpPosition));

      // Mine forward the number of cooldown seconds
      await mineForwardSeconds(900);
       
      // Can now transfer - the staked GLP now ends up in the primary account
      await mine(contracts.glpSecondaryEarnAccount.transferStakedGlp(stakedGlpPosition, contracts.glpPrimaryEarnAccount.address));

      const stakedGlpPositionPrimary = (await contracts.glpPrimaryEarnAccount.positions()).glpPositions.stakedGlp;
      const stakedGlpPositionSecondary = (await contracts.glpSecondaryEarnAccount.positions()).glpPositions.stakedGlp;
      console.log("After xfer: Staked GLP Position in Primary, Secondary Earn Accounts:", ethers.utils.formatEther(stakedGlpPositionPrimary), ethers.utils.formatEther(stakedGlpPositionSecondary));
    }

    // Check the token prices again now that there are some reserves/shares
    await dumpPrices(contracts);

    console.log("\n**Harvest Rewards**");
    {
        // The deployment script vests 100% of the rewards, meaning all 100% of deposits are locked for a period of time
        // Set this to 10% so we can then pull up to 90% of the funds out still.
        await mine(contracts.gmxManager.setEsGmxVestingRate(1_000)); // Vest 10% of the esGMX rewards into GMX

        await mineForwardSeconds(86400);

        await mine(contracts.gmxRewardsAggregator.setPerformanceFeeCollector(feeCollector.getAddress()));
        console.log("GMX:");
        console.log("\tProjected Reward Rates (before perf fees)", await contracts.gmxRewardsAggregator.projectedRewardRates(false));
        console.log("\tProjected Reward Rates (after perf fees)", await contracts.gmxRewardsAggregator.projectedRewardRates(true));
        console.log("\tMSIG oGMX before:", fromAtto(await contracts.oGMX.balanceOf(origamiMultisig.getAddress())));
        console.log("\tMSIG wETH before:", fromAtto(await contracts.weth.balanceOf(origamiMultisig.getAddress())));
        await harvestGmx(contracts, origamiMultisig);
        console.log("\tMSIG oGMX after:", fromAtto(await contracts.oGMX.balanceOf(origamiMultisig.getAddress())));
        console.log("\tMSIG wETH after:", fromAtto(await contracts.weth.balanceOf(origamiMultisig.getAddress())));
        console.log("\tAPR:", await contracts.ovGMX.apr());
        console.log("\tFees Collected:", await contracts.oGMX.balanceOf(feeCollector.getAddress()));

        await mine(contracts.glpRewardsAggregator.setPerformanceFeeCollector(feeCollector.getAddress()));
        console.log("GLP:");
        console.log("\tProjected Reward Rates (before perf fees)", await contracts.glpRewardsAggregator.projectedRewardRates(false));
        console.log("\tProjected Reward Rates (after perf fees)", await contracts.gmxRewardsAggregator.projectedRewardRates(true));
        console.log("\tMSIG oGMX before:", fromAtto(await contracts.oGMX.balanceOf(origamiMultisig.getAddress())));
        console.log("\tMSIG wETH before:", fromAtto(await contracts.weth.balanceOf(origamiMultisig.getAddress())));
        await harvestGlp(contracts, origamiMultisig);
        console.log("\tMSIG oGMX after:", fromAtto(await contracts.oGMX.balanceOf(origamiMultisig.getAddress())));
        console.log("\tMSIG wETH after:", fromAtto(await contracts.weth.balanceOf(origamiMultisig.getAddress())));
        console.log("\tAPR:", await contracts.ovGLP.apr());
        console.log("\tFees Collected:", await contracts.oGLP.balanceOf(feeCollector.getAddress()));
    }

    console.log("\n**Bump Up Reserves**");
    {
        await mine(contracts.oGMX.connect(origamiMultisig).addMinter(origamiMultisig.getAddress()));
        await mine(contracts.oGMX.connect(origamiMultisig).mint(origamiMultisig.getAddress(), ethers.utils.parseEther("1000")));
        await mine(contracts.oGMX.connect(origamiMultisig).approve(contracts.ovGMX.address, ethers.utils.parseEther("1000")));
        await mine(contracts.ovGMX.connect(origamiMultisig).addPendingReserves(ethers.utils.parseEther("1000")));

        await mine(contracts.oGLP.connect(origamiMultisig).addMinter(origamiMultisig.getAddress()));
        await mine(contracts.oGLP.connect(origamiMultisig).mint(origamiMultisig.getAddress(), ethers.utils.parseEther("2000")));
        await mine(contracts.oGLP.connect(origamiMultisig).approve(contracts.ovGLP.address, ethers.utils.parseEther("2000")));
        await mine(contracts.ovGLP.connect(origamiMultisig).addPendingReserves(ethers.utils.parseEther("2000")));

        await dumpPrices(contracts);
    }

    console.log("\n**Fred sells ovGMX to GMX**");
    {
      const sellAmount = ethers.utils.parseEther("100");

      console.log("Fred ovGMX Bal:", fromAtto(await contracts.ovGMX.balanceOf(fred.getAddress())));
      console.log("Fred oGMX Bal:", fromAtto(await contracts.oGMX.balanceOf(fred.getAddress())));
      console.log("Fred GMX Bal:", fromAtto(await contracts.gmxToken.balanceOf(fred.getAddress())));
      console.log("ovGMX Total Supply:", fromAtto(await contracts.ovGMX.totalSupply()));
      console.log("ovGMX Total Reserves:", fromAtto(await contracts.ovGMX.totalReserves()));
      console.log("ovGMX Vested Reserves:", fromAtto(await contracts.ovGMX.vestedReserves()));
      console.log("ovGMX Pending Reserves:", fromAtto(await contracts.ovGMX.pendingReserves()));
      console.log("oGMX Total Supply:", fromAtto(await contracts.oGMX.totalSupply()));
      console.log("MSIG(fees) oGMX Bal:", fromAtto(await contracts.oGMX.balanceOf(origamiMultisig.getAddress())));

      const quote = await contracts.ovGMX.exitQuote(sellAmount, contracts.gmxToken.address, 0, 0);
      await mine(contracts.ovGMX.connect(fred).exitToToken(quote.quoteData, fred.getAddress()));

      console.log("Fred ovGMX Bal:", fromAtto(await contracts.ovGMX.balanceOf(fred.getAddress())));
      console.log("Fred oGMX Bal:", fromAtto(await contracts.oGMX.balanceOf(fred.getAddress())));
      console.log("Fred GMX Bal:", fromAtto(await contracts.gmxToken.balanceOf(fred.getAddress())));
      console.log("ovGMX Total Supply:", fromAtto(await contracts.ovGMX.totalSupply()));
      console.log("ovGMX Total Reserves:", fromAtto(await contracts.ovGMX.totalReserves()));
      console.log("ovGMX Vested Reserves:", fromAtto(await contracts.ovGMX.vestedReserves()));
      console.log("ovGMX Pending Reserves:", fromAtto(await contracts.ovGMX.pendingReserves()));
      console.log("oGMX Total Supply:", fromAtto(await contracts.oGMX.totalSupply()));
      console.log("MSIG(fees) oGMX Bal:", fromAtto(await contracts.oGMX.balanceOf(origamiMultisig.getAddress())));
    }

    console.log("\n**Check quotes when buying and selling GLP directly to DAI**");
    {
      const buyAmount = ethers.utils.parseEther("20");
      const buyQuote = await contracts.ovGLP.investQuote(buyAmount, ZERO_ADDRESS, 0, 0);
      console.log("Buy quote:", buyQuote);

      const feeGlpTracker = GMX_RewardTracker__factory.connect(await contracts.glpRewardRouter.feeGlpTracker(), origamiMultisig);
      const bobGlpBefore = await feeGlpTracker.depositBalances(bob.getAddress(), await contracts.gmxRewardRouter.glp());
      await mine(contracts.glpRewardRouter.connect(bob).mintAndStakeGlpETH(0, 0, {value:buyAmount}));
      const bobGlpAfter = await feeGlpTracker.depositBalances(bob.getAddress(), await contracts.gmxRewardRouter.glp());
      console.log("Bob Bought GLP:", fromAtto(bobGlpBefore), fromAtto(bobGlpAfter), fromAtto(bobGlpAfter.sub(bobGlpBefore)));

      await mineForwardSeconds(86400);

      const dai = "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1";
      const daiToken = IERC20__factory.connect(dai, origamiMultisig);
      const sellAmount = ethers.utils.parseEther("1000");
      const sellQuote = await contracts.ovGLP.exitQuote(sellAmount, daiToken.address, 0, 0);
      console.log("Sell quote:", sellQuote);
      const bobDaiBefore = await daiToken.balanceOf(bob.getAddress());
      await mine(contracts.glpRewardRouter.connect(bob).unstakeAndRedeemGlp(dai, sellAmount, 0, bob.getAddress()));
      const bobDaiAfter = await daiToken.balanceOf(bob.getAddress());
      console.log("Bob received DAI:", fromAtto(bobDaiBefore), fromAtto(bobDaiAfter), fromAtto(bobDaiAfter.sub(bobDaiBefore)));
    }

    console.log("\n**Bob sells ovGLP to DAI**");
    {
      const sellAmount = ethers.utils.parseEther("1000");

      const dai = "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1";
      const daiToken = IERC20__factory.connect(dai, origamiMultisig);

      console.log("Bob ovGLP Bal:", fromAtto(await contracts.ovGLP.balanceOf(bob.getAddress())));
      console.log("Bob oGLP Bal:", fromAtto(await contracts.oGLP.balanceOf(bob.getAddress())));
      console.log("Bob DAI Bal:", fromAtto(await daiToken.balanceOf(bob.getAddress())));
      console.log("ovGLP Total Supply:", fromAtto(await contracts.ovGLP.totalSupply()));
      console.log("ovGLP Total Reserves:", fromAtto(await contracts.ovGLP.totalReserves()));
      console.log("ovGLP Vested Reserves:", fromAtto(await contracts.ovGLP.vestedReserves()));
      console.log("ovGLP Pending Reserves:", fromAtto(await contracts.ovGLP.pendingReserves()));
      console.log("oGLP Total Supply:", fromAtto(await contracts.oGLP.totalSupply()));
      console.log("MSIG(fees) oGLP Bal:", fromAtto(await contracts.oGLP.balanceOf(origamiMultisig.getAddress())));

      const quote = await contracts.ovGLP.exitQuote(sellAmount, dai, 0, 0);
      console.log(quote);
      await mine(contracts.ovGLP.connect(bob).exitToToken(quote.quoteData, bob.getAddress()));

      console.log("Bob ovGLP Bal:", fromAtto(await contracts.ovGLP.balanceOf(bob.getAddress())));
      console.log("Bob oGLP Bal:", fromAtto(await contracts.oGLP.balanceOf(bob.getAddress())));
      console.log("Bob DAI Bal:", fromAtto(await daiToken.balanceOf(bob.getAddress())));
      console.log("ovGLP Total Supply:", fromAtto(await contracts.ovGLP.totalSupply()));
      console.log("ovGLP Total Reserves:", fromAtto(await contracts.ovGLP.totalReserves()));
      console.log("ovGLP Vested Reserves:", fromAtto(await contracts.ovGLP.vestedReserves()));
      console.log("ovGLP Pending Reserves:", fromAtto(await contracts.ovGLP.pendingReserves()));
      console.log("oGLP Total Supply:", fromAtto(await contracts.oGLP.totalSupply()));
      console.log("MSIG(fees) oGLP Bal:", fromAtto(await contracts.oGLP.balanceOf(origamiMultisig.getAddress())));
    }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
