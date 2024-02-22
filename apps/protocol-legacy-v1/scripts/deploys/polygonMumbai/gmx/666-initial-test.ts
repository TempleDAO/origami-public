import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers } from 'hardhat';
import { 
    OrigamiGmxInvestment, OrigamiGmxInvestment__factory,
    OrigamiGlpInvestment, OrigamiGlpInvestment__factory,
    GMX_NamedToken, GMX_NamedToken__factory,
    GMX_StakedGlp, GMX_StakedGlp__factory, 
    GMX_GMX, GMX_GMX__factory, 
    OrigamiGmxEarnAccount, OrigamiGmxEarnAccount__factory, 
    OrigamiInvestmentVault, OrigamiInvestmentVault__factory, 
    OrigamiGmxRewardsAggregator, OrigamiGmxRewardsAggregator__factory, 
    DummyDex, DummyDex__factory, 
    OrigamiGmxManager,
    OrigamiGmxManager__factory,
    GMX_GLP,
    GMX_GLP__factory,
    TokenPrices,
    TokenPrices__factory,
} from '../../../../typechain';
import {
    encodeGlpHarvestParams,
    encodeGmxHarvestParams,
    ensureExpectedEnvvars,
    mine,
} from '../../helpers';
import { GmxDeployedContracts, getDeployedContracts } from './contract-addresses';
import { BigNumber, Signer } from 'ethers';

/**
 * NOTE: This script is useful to run immediately after a fresh testnet deploy
 *       in order to verify the contracts are setup correctly, and to generate some initial events
 */ 

interface ContractInstances {
    dai: GMX_NamedToken,
    bnb: GMX_NamedToken,
    weth: GMX_NamedToken,
    btc: GMX_NamedToken,
    stakedGlp: GMX_StakedGlp,
    gmx: GMX_GMX,
    glp: GMX_GLP,

    oGMX: OrigamiGmxInvestment,
    oGLP: OrigamiGlpInvestment,

    ovGMX: OrigamiInvestmentVault,
    ovGLP: OrigamiInvestmentVault,

    glpPrimaryEarnAccount: OrigamiGmxEarnAccount,
    glpSecondaryEarnAccount: OrigamiGmxEarnAccount,

    gmxRewardsAggregator: OrigamiGmxRewardsAggregator,
    glpRewardsAggregator: OrigamiGmxRewardsAggregator,

    dex: DummyDex,
    gmxManager: OrigamiGmxManager,
    tokenPrices: TokenPrices,
}

function connectToContracts(DEPLOYED: GmxDeployedContracts, owner: SignerWithAddress): ContractInstances {
    return {
        dai: GMX_NamedToken__factory.connect(DEPLOYED.GMX.LIQUIDITY_POOL.DAI_TOKEN, owner),
        bnb: GMX_NamedToken__factory.connect(DEPLOYED.GMX.LIQUIDITY_POOL.BNB_TOKEN, owner),
        weth: GMX_NamedToken__factory.connect(DEPLOYED.GMX.LIQUIDITY_POOL.WETH_TOKEN, owner),
        btc: GMX_NamedToken__factory.connect(DEPLOYED.GMX.LIQUIDITY_POOL.BTC_TOKEN, owner),
        stakedGlp: GMX_StakedGlp__factory.connect(DEPLOYED.GMX.STAKING.STAKED_GLP, owner),
        gmx: GMX_GMX__factory.connect(DEPLOYED.GMX.TOKENS.GMX_TOKEN, owner),
        glp: GMX_GLP__factory.connect(DEPLOYED.GMX.TOKENS.GLP_TOKEN, owner),

        oGMX: OrigamiGmxInvestment__factory.connect(DEPLOYED.ORIGAMI.GMX.oGMX, owner),
        oGLP: OrigamiGlpInvestment__factory.connect(DEPLOYED.ORIGAMI.GMX.oGLP, owner),
        ovGMX: OrigamiInvestmentVault__factory.connect(DEPLOYED.ORIGAMI.GMX.ovGMX, owner),
        ovGLP: OrigamiInvestmentVault__factory.connect(DEPLOYED.ORIGAMI.GMX.ovGLP, owner),

        glpPrimaryEarnAccount: OrigamiGmxEarnAccount__factory.connect(DEPLOYED.ORIGAMI.GMX.GLP_PRIMARY_EARN_ACCOUNT, owner),
        glpSecondaryEarnAccount: OrigamiGmxEarnAccount__factory.connect(DEPLOYED.ORIGAMI.GMX.GLP_SECONDARY_EARN_ACCOUNT, owner),

        gmxRewardsAggregator: OrigamiGmxRewardsAggregator__factory.connect(DEPLOYED.ORIGAMI.GMX.GMX_REWARDS_AGGREGATOR, owner),
        glpRewardsAggregator: OrigamiGmxRewardsAggregator__factory.connect(DEPLOYED.ORIGAMI.GMX.GLP_REWARDS_AGGREGATOR, owner),

        dex: DummyDex__factory.connect(DEPLOYED.ZERO_EX_PROXY, owner),
        gmxManager: OrigamiGmxManager__factory.connect(DEPLOYED.ORIGAMI.GMX.GMX_MANAGER, owner),
        tokenPrices: TokenPrices__factory.connect(DEPLOYED.ORIGAMI.TOKEN_PRICES, owner),
    }
}

async function getAggregatorRewardBalances(contracts: ContractInstances, aggregator: OrigamiGmxRewardsAggregator) {
    return {
        oGmx: await contracts.oGMX.balanceOf(aggregator.address),
        oGlp: await contracts.oGLP.balanceOf(aggregator.address),
    };
}

const SLIPPAGE_BPS = 50; // 0.5%
const applySlippage = (bn: BigNumber) => bn.mul(10_000-SLIPPAGE_BPS).div(10_000);

const harvestGlp = async (contracts: ContractInstances, signer: Signer) => {
    console.log("HARVESTING GLP");
    const _harvestableRewards = await contracts.glpRewardsAggregator.harvestableRewards();
    const harvestableRewards = {weth: _harvestableRewards[0], oGmx: _harvestableRewards[1], oGlp: _harvestableRewards[2]};
    console.log(`\tGLP Harvestable Reward Amounts: [weth: ${harvestableRewards.weth}, oGmx: ${harvestableRewards.oGmx}, oGlp: ${harvestableRewards.oGlp}]`);

    // Get a quote to swap $oGMX rewards -> $GMX
    // NB: No slippage when exiting the oGMX position as it's redeemed in situ (not via a dex)
    const oGmxToGmxExitQuote = await contracts.oGMX.exitQuote(harvestableRewards.oGmx, contracts.gmx.address, 0, 0);
    console.log(`\toGMX -> GMX Exit Quote: ${oGmxToGmxExitQuote}`);

    const sellAmount = oGmxToGmxExitQuote.quoteData.expectedToTokenAmount;
    console.log(`\tSelling [${sellAmount.toString()}] GMX for wETH`);
    
    const buyWethAmount = sellAmount
        .mul(await contracts.dex.gmxPrice())
        .div(await contracts.dex.wrappedNativePrice());
    console.log(`\tExpected wETH Amount Bought: [${buyWethAmount.toString()}]`);

    const minWethExpected = applySlippage(buyWethAmount);
    console.log(`\tMin wETH Amount Bought: [${minWethExpected.toString()}]`);

    const gmxToWethQuoteData = contracts.dex.interface.encodeFunctionData("swapToWrappedNative", [sellAmount]);

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
        gmxToNativeSwapData: gmxToWethQuoteData,
        oGlpInvestQuoteData: wethToOglpInvestQuote.quoteData,
        addToReserveAmountPct: addToReserveAmountPct,
    };
    console.log("\tHarvest Params:", harvestParams);

    console.log("\tovGLP Reserves Before:", await contracts.ovGLP.totalReserves());
    console.log("\tovGLP Vested & Pending Before:", (await contracts.ovGLP.vestedReserves()).add(await contracts.ovGLP.pendingReserves()));
    await mine(contracts.glpRewardsAggregator.connect(signer).harvestRewards(encodeGlpHarvestParams(harvestParams)));
    console.log("\tovGLP Reserves After:", await contracts.ovGLP.totalReserves());
    console.log("\tovGLP Vested & Pending After:", (await contracts.ovGLP.vestedReserves()).add(await contracts.ovGLP.pendingReserves()), "\n");
}

const harvestGmx = async (contracts: ContractInstances, signer: Signer) => {
    console.log("HARVESTING GMX");

    const _harvestableRewards = await contracts.gmxRewardsAggregator.harvestableRewards();
    const harvestableRewards = {weth: _harvestableRewards[0], oGmx: _harvestableRewards[1], oGlp: _harvestableRewards[2]};
    console.log(`\tGMX Harvestable Reward Amounts: [weth: ${harvestableRewards.weth}, oGmx: ${harvestableRewards.oGmx}, oGlp: ${harvestableRewards.oGlp}]`);
    const existingGmx = await contracts.gmx.balanceOf(contracts.gmxRewardsAggregator.address);
    console.log(`\tExisting GMX in aggregator: ${existingGmx.toString()}`);

    const sellAmount = harvestableRewards.weth;
    console.log(`\tSelling [${sellAmount.toString()}] wETH for GMX`);
    const buyGmxAmount = sellAmount
        .mul(await contracts.dex.wrappedNativePrice())
        .div(await contracts.dex.gmxPrice());
    console.log(`\tExpected GMX Amount Bought: [${buyGmxAmount.toString()}]`);

    const minGmxExpected = applySlippage(buyGmxAmount);
    console.log(`\tMin GMX Amount Bought: [${minGmxExpected.toString()}]`);

    const wethToGmxQuoteData = contracts.dex.interface.encodeFunctionData("swapToGMX", [sellAmount]);

    // The total $GMX we have to invest = 
    //   1/ The expected amount of $GMX we will receive from selling the $WETH +
    //   2/ Any existing balance from previous swaps left over amounts
    const gmxToInvestInOGmx = minGmxExpected.add(existingGmx);
    console.log(`gmxToInvestInOGmx=[${gmxToInvestInOGmx.toString()}]`);

    // Get a quote to swap $GMX -> $oGMX
    // NB: No slippage when investing in the oGMX position as it's minted in situ (not bought via a dex)
    const gmxToOgmxInvestQuote = await contracts.oGMX.investQuote(gmxToInvestInOGmx, contracts.gmx.address, 0, 0);
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
        nativeToGmxSwapData: wethToGmxQuoteData,
        oGmxInvestQuoteData: gmxToOgmxInvestQuote.quoteData,
        addToReserveAmountPct: addToReserveAmountPct,
    };
    console.log("\tHarvest Params:", harvestParams);

    console.log("\tovGMX Reserves Before:", await contracts.ovGMX.totalReserves());
    console.log("\tovGMX Vested & Pending Before:", (await contracts.ovGMX.vestedReserves()).add(await contracts.ovGMX.pendingReserves()));
    await mine(contracts.gmxRewardsAggregator.connect(signer).harvestRewards(encodeGmxHarvestParams(harvestParams)));
    console.log("\tovGMX Reserves After:", await contracts.ovGMX.totalReserves());
    console.log("\tovGMX Vested & Pending Before:", (await contracts.ovGMX.vestedReserves()).add(await contracts.ovGMX.pendingReserves()), "\n");
}

async function dumpPrices(contracts: ContractInstances) {
    const prices = await contracts.tokenPrices.tokenPrices(
        [
          contracts.weth.address,
          contracts.gmx.address,
          contracts.oGMX.address,
          contracts.ovGMX.address,
          contracts.glp.address,
          contracts.oGLP.address,
          contracts.ovGLP.address,
        ]
      );
      console.log("PRICES:");
      console.log(
        {
            "weth": ethers.utils.formatUnits(prices[0], 30),
            "gmx": ethers.utils.formatUnits(prices[1], 30),
            "oGMX": ethers.utils.formatUnits(prices[2], 30),
            "ovGMX": ethers.utils.formatUnits(prices[3], 30),
            "glp": ethers.utils.formatUnits(prices[4], 30),
            "oGLP": ethers.utils.formatUnits(prices[5], 30),
            "ovGLP": ethers.utils.formatUnits(prices[6], 30),
        }
    );
}

function sleep(ms: number) {
    return new Promise( resolve => setTimeout(resolve, ms) );
}

async function main() {
    ensureExpectedEnvvars();
  
    const [owner] = await ethers.getSigners();
    const DEPLOYED = getDeployedContracts();
    const contracts = connectToContracts(DEPLOYED, owner);

    const amount = ethers.utils.parseEther("100000000");

    // GLP Invest Approvals
    await mine(contracts.dai.approve(contracts.ovGLP.address, amount));
    await mine(contracts.bnb.approve(contracts.ovGLP.address, amount));
    await mine(contracts.weth.approve(contracts.ovGLP.address, amount));
    await mine(contracts.btc.approve(contracts.ovGLP.address, amount));
    await mine(contracts.btc.approve(contracts.ovGLP.address, amount));
    await mine(contracts.stakedGlp.approve(contracts.ovGLP.address, amount));

    // GMX Invest Approvals
    await mine(contracts.gmx.mint(owner.getAddress(), amount));
    await mine(contracts.gmx.approve(contracts.ovGMX.address, amount));
    
    // $GMX
    {
        // Invest in $GMX
        {
            const investAmount = ethers.utils.parseEther("1100");
            const quote = await contracts.ovGMX.investQuote(investAmount, contracts.gmx.address, 100, 0);
            await mine(contracts.ovGMX.investWithToken(quote.quoteData));
            console.log("Invested into ovGMX", ethers.utils.formatEther(quote.quoteData.expectedInvestmentAmount));
        }

        // Exit GMX
        {
            const exitAmount = ethers.utils.parseEther("75");
            const quote = await contracts.ovGMX.exitQuote(exitAmount, contracts.gmx.address, 100, 0);
            await mine(contracts.ovGMX.exitToToken(quote.quoteData, owner.getAddress()));
            console.log("Exited from ovGMX", ethers.utils.formatEther(quote.quoteData.expectedToTokenAmount));
        }
    }

    // $GLP
    {
        const toToken = contracts.dai.address;

        // Invest in $GLP
        {
            const investAmount = ethers.utils.parseEther("1000");
            await mine(contracts.dai.mint(owner.getAddress(), investAmount));
            const quote = await contracts.ovGLP.investQuote(investAmount, toToken, 100, 0);
            await mine(contracts.ovGLP.investWithToken(quote.quoteData));
            console.log("Invested into ovGLP", ethers.utils.formatEther(quote.quoteData.expectedInvestmentAmount));
        }

        console.log("Waiting for the cooldown to end (15mins)...");
        await sleep(15*60*1000);

        // transfer from secondary earn account -> primary earn account
        {
            const secondaryPositions = await contracts.glpSecondaryEarnAccount.positions();
            console.log(`Transferring ${ethers.utils.formatEther(secondaryPositions.glpPositions.stakedGlp)} Staked GLP from Secondary => Primary`);

            await mine(contracts.glpSecondaryEarnAccount.addOperator(owner.getAddress()));
            await mine(contracts.glpSecondaryEarnAccount.transferStakedGlp(
                secondaryPositions.glpPositions.stakedGlp,
                contracts.glpPrimaryEarnAccount.address
            ));
            await mine(contracts.glpSecondaryEarnAccount.removeOperator(owner.getAddress()));

            const primaryPositions = await contracts.glpPrimaryEarnAccount.positions();
            console.log(`Primary Staked GLP: ${ethers.utils.formatEther(primaryPositions.glpPositions.stakedGlp)}`);
        }

        // Exit GLP
        {
            const exitAmount = ethers.utils.parseEther("75");
            const quote = await contracts.ovGLP.exitQuote(exitAmount, toToken, 100, 0);
            await mine(contracts.ovGLP.exitToToken(quote.quoteData, owner.getAddress()));
            console.log("Exited from ovGLP", ethers.utils.formatEther(quote.quoteData.expectedToTokenAmount));
        }
    }

    // Harvest
    {
        // Botstrap Origami with some GMX so it can harvest (need to convert oGMX -> GMX)
        {
            const seedAmount = ethers.utils.parseEther("5000");
            await mine(contracts.gmx.mint(contracts.gmxManager.address, seedAmount));
            await mine(contracts.gmxManager.addOperator(owner.getAddress()));
            await mine(contracts.gmxManager.applyGmx(seedAmount));
        }

        await harvestGmx(contracts, owner);
        await harvestGlp(contracts, owner);
    }

    await dumpPrices(contracts);

    // Add/Remove Reserves
    {
        const addAmount = ethers.utils.parseEther("10");
        await mine(contracts.oGLP.mint(owner.getAddress(), addAmount));
        await mine(contracts.oGLP.approve(contracts.ovGLP.address, addAmount));
        console.log("ovGLP reservesPerShare before:", ethers.utils.formatEther(await contracts.ovGLP.reservesPerShare()));
        await mine(contracts.ovGLP.addPendingReserves(addAmount));
        console.log("ovGLP reservesPerShare after:", ethers.utils.formatEther(await contracts.ovGLP.reservesPerShare()));

        await mine(contracts.oGMX.mint(owner.getAddress(), addAmount));
        await mine(contracts.oGMX.approve(contracts.ovGMX.address, addAmount));
        console.log("ovGMX reservesPerShare before:", ethers.utils.formatEther(await contracts.ovGMX.reservesPerShare()));
        await mine(contracts.ovGMX.addPendingReserves(addAmount));
        console.log("ovGMX reservesPerShare after:", ethers.utils.formatEther(await contracts.ovGMX.reservesPerShare()));
    }

    await dumpPrices(contracts);
  }
  
  // We recommend this pattern to be able to use async/await everywhere
  // and properly handle errors.
  main()
    .then(() => process.exit(0))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
