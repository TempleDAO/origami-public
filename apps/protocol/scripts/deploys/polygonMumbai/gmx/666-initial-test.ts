import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers } from 'hardhat';
import { 
    OrigamiGmxInvestment, OrigamiGmxInvestment__factory,
    OrigamiGlpInvestment, OrigamiGlpInvestment__factory,
    GMX_NamedToken, GMX_NamedToken__factory,
    GMX_StakedGlp, GMX_StakedGlp__factory, 
    GMX_GMX, GMX_GMX__factory, 
    OrigamiGmxEarnAccount, OrigamiGmxEarnAccount__factory, 
    OrigamiInvestmentVault, OrigamiInvestmentVault__factory, OrigamiGmxRewardsAggregator, OrigamiGmxRewardsAggregator__factory,
} from '../../../../typechain';
import {
    ensureExpectedEnvvars,
    mine,
} from '../../helpers';
import { GmxDeployedContracts, getDeployedContracts } from './contract-addresses';

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

    oGMX: OrigamiGmxInvestment,
    oGLP: OrigamiGlpInvestment,

    ovGMX: OrigamiInvestmentVault,
    ovGLP: OrigamiInvestmentVault,

    glpPrimaryEarnAccount: OrigamiGmxEarnAccount,
    glpSecondaryEarnAccount: OrigamiGmxEarnAccount,

    gmxRewardsAggregator: OrigamiGmxRewardsAggregator,
    glpRewardsAggregator: OrigamiGmxRewardsAggregator,
}

function connectToContracts(DEPLOYED: GmxDeployedContracts, owner: SignerWithAddress): ContractInstances {
    return {
        dai: GMX_NamedToken__factory.connect(DEPLOYED.GMX.LIQUIDITY_POOL.DAI_TOKEN, owner),
        bnb: GMX_NamedToken__factory.connect(DEPLOYED.GMX.LIQUIDITY_POOL.BNB_TOKEN, owner),
        weth: GMX_NamedToken__factory.connect(DEPLOYED.GMX.LIQUIDITY_POOL.WETH_TOKEN, owner),
        btc: GMX_NamedToken__factory.connect(DEPLOYED.GMX.LIQUIDITY_POOL.BTC_TOKEN, owner),
        stakedGlp: GMX_StakedGlp__factory.connect(DEPLOYED.GMX.STAKING.STAKED_GLP, owner),
        gmx: GMX_GMX__factory.connect(DEPLOYED.GMX.TOKENS.GMX_TOKEN, owner),

        oGMX: OrigamiGmxInvestment__factory.connect(DEPLOYED.ORIGAMI.GMX.oGMX, owner),
        oGLP: OrigamiGlpInvestment__factory.connect(DEPLOYED.ORIGAMI.GMX.oGLP, owner),
        ovGMX: OrigamiInvestmentVault__factory.connect(DEPLOYED.ORIGAMI.GMX.ovGMX, owner),
        ovGLP: OrigamiInvestmentVault__factory.connect(DEPLOYED.ORIGAMI.GMX.ovGLP, owner),

        glpPrimaryEarnAccount: OrigamiGmxEarnAccount__factory.connect(DEPLOYED.ORIGAMI.GMX.GLP_PRIMARY_EARN_ACCOUNT, owner),
        glpSecondaryEarnAccount: OrigamiGmxEarnAccount__factory.connect(DEPLOYED.ORIGAMI.GMX.GLP_SECONDARY_EARN_ACCOUNT, owner),

        gmxRewardsAggregator: OrigamiGmxRewardsAggregator__factory.connect(DEPLOYED.ORIGAMI.GMX.GMX_REWARDS_AGGREGATOR, owner),
        glpRewardsAggregator: OrigamiGmxRewardsAggregator__factory.connect(DEPLOYED.ORIGAMI.GMX.GLP_REWARDS_AGGREGATOR, owner),
    }
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
            const investAmount = ethers.utils.parseEther("100");
            const quote = await contracts.ovGMX.investQuote(investAmount, contracts.gmx.address);
            await mine(contracts.ovGMX.investWithToken(quote.quoteData, 100));
            console.log("Invested into ovGMX", ethers.utils.formatEther(quote.quoteData.expectedInvestmentAmount));
        }

        // Exit GMX
        {
            const exitAmount = ethers.utils.parseEther("75");
            const quote = await contracts.ovGMX.exitQuote(exitAmount, contracts.gmx.address);
            await mine(contracts.ovGMX.exitToToken(quote.quoteData, 100, owner.getAddress()));
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
            const quote = await contracts.ovGLP.investQuote(investAmount, toToken);
            await mine(contracts.ovGLP.investWithToken(quote.quoteData, 100));
            console.log("Invested into ovGLP", ethers.utils.formatEther(quote.quoteData.expectedInvestmentAmount));
        }

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
            const quote = await contracts.ovGLP.exitQuote(exitAmount, toToken);
            await mine(contracts.ovGLP.exitToToken(quote.quoteData, 100, owner.getAddress()));
            console.log("Exited from ovGLP", ethers.utils.formatEther(quote.quoteData.expectedToTokenAmount));
        }

        // Harvest
        {
            await mine(contracts.gmxRewardsAggregator.harvestRewards());
            await mine(contracts.glpRewardsAggregator.harvestRewards());
        }

        // Add/Remove Reserves
        {
            const addAmount = ethers.utils.parseEther("10");
            await mine(contracts.oGLP.mint(owner.getAddress(), addAmount));
            await mine(contracts.oGLP.approve(contracts.ovGLP.address, addAmount));
            console.log("ovGLP reservesPerShare before:", ethers.utils.formatEther(await contracts.ovGLP.reservesPerShare()));
            await mine(contracts.ovGLP.addReserves(addAmount));
            console.log("ovGLP reservesPerShare after:", ethers.utils.formatEther(await contracts.ovGLP.reservesPerShare()));

            await mine(contracts.oGMX.mint(owner.getAddress(), addAmount));
            await mine(contracts.oGMX.approve(contracts.ovGMX.address, addAmount));
            console.log("ovGMX reservesPerShare before:", ethers.utils.formatEther(await contracts.ovGMX.reservesPerShare()));
            await mine(contracts.ovGMX.addReserves(addAmount));
            console.log("ovGMX reservesPerShare after:", ethers.utils.formatEther(await contracts.ovGMX.reservesPerShare()));

            const removeAmount = ethers.utils.parseEther("5");
            console.log("ovGLP reservesPerShare before:", ethers.utils.formatEther(await contracts.ovGLP.reservesPerShare()));
            await mine(contracts.ovGLP.removeReserves(removeAmount));
            console.log("ovGLP reservesPerShare after:", ethers.utils.formatEther(await contracts.ovGLP.reservesPerShare()));

            console.log("ovGMX reservesPerShare before:", ethers.utils.formatEther(await contracts.ovGMX.reservesPerShare()));
            await mine(contracts.ovGMX.removeReserves(removeAmount));            console.log("ovGMX reservesPerShare before:", ethers.utils.formatEther(await contracts.ovGMX.reservesPerShare()));
            console.log("ovGMX reservesPerShare after:", ethers.utils.formatEther(await contracts.ovGMX.reservesPerShare()));
        }
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
