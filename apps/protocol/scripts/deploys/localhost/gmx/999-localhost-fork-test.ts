import { Signer } from 'ethers';
import { ethers } from 'hardhat';
import { impersonateSigner, mineForwardSeconds, ZERO_ADDRESS } from '../../../../test/helpers';
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
} from '../../../../typechain';
import {
    ensureExpectedEnvvars,
    fromAtto,
    mine,
} from '../../helpers';
import { GmxDeployedContracts, getDeployedContracts } from '../../arbitrum/gmx/contract-addresses';

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
}

function connectToContracts(DEPLOYED: GmxDeployedContracts, owner: Signer): ContractInstances {
    return {
        gmxEarnAccount: OrigamiGmxEarnAccount__factory.connect(DEPLOYED.ORIGAMI.GMX.GMX_EARN_ACCOUNT, owner),
        glpPrimaryEarnAccount: OrigamiGmxEarnAccount__factory.connect(DEPLOYED.ORIGAMI.GMX.GLP_PRIMARY_EARN_ACCOUNT, owner),
        glpSecondaryEarnAccount: OrigamiGmxEarnAccount__factory.connect(DEPLOYED.ORIGAMI.GMX.GLP_SECONDARY_EARN_ACCOUNT, owner),
        gmxManager: OrigamiGmxManager__factory.connect(DEPLOYED.ORIGAMI.GMX.GMX_MANAGER, owner),
        glpManager: OrigamiGmxManager__factory.connect(DEPLOYED.ORIGAMI.GMX.GLP_MANAGER, owner),
        gmxRewardsAggregator: OrigamiGmxRewardsAggregator__factory.connect(DEPLOYED.ORIGAMI.GMX.GMX_REWARDS_AGGREGATOR, owner),
        glpRewardsAggregator: OrigamiGmxRewardsAggregator__factory.connect(DEPLOYED.ORIGAMI.GMX.GLP_REWARDS_AGGREGATOR, owner),
        oGMX: OrigamiGmxInvestment__factory.connect(DEPLOYED.ORIGAMI.GMX.oGMX, owner),
        oGLP: OrigamiGlpInvestment__factory.connect(DEPLOYED.ORIGAMI.GMX.oGLP, owner),
        ovGMX: OrigamiInvestmentVault__factory.connect(DEPLOYED.ORIGAMI.GMX.ovGMX, owner),
        ovGLP: OrigamiInvestmentVault__factory.connect(DEPLOYED.ORIGAMI.GMX.ovGLP, owner),

        gmxToken: GMX_GMX__factory.connect(DEPLOYED.GMX.TOKENS.GMX_TOKEN, owner),
        gmxRewardRouter: GMX_RewardRouterV2__factory.connect(DEPLOYED.GMX.STAKING.GMX_REWARD_ROUTER, owner),
        glpRewardRouter: GMX_RewardRouterV2__factory.connect(DEPLOYED.GMX.STAKING.GLP_REWARD_ROUTER, owner),
        tokenPrices: TokenPrices__factory.connect(DEPLOYED.ORIGAMI.TOKEN_PRICES, owner),
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
      await gmxTokenTimelock.setGov(contracts.gmxToken.address, await owner.getAddress());
    }
}

// GMX.io has set 0 esGMX rewards on staked GLP -- for testing purposes we update to something meaningful.
async function setUpstreamRewardRates(contracts: ContractInstances, owner: Signer) {
    const rewardRouterMsig = await impersonateSigner(await contracts.glpRewardRouter.gov());

    const stakedGlpTracker = GMX_RewardTracker__factory.connect(await contracts.glpRewardRouter.stakedGlpTracker(), rewardRouterMsig);
    const glpEsGmxDistributor = GMX_RewardDistributor__factory.connect(await stakedGlpTracker.distributor(), rewardRouterMsig);
    await mine(glpEsGmxDistributor.setTokensPerInterval(ethers.utils.parseEther("0.1")));
}

async function dumpPrices(contracts: ContractInstances, weth: IERC20) {
    const prices = await contracts.tokenPrices.tokenPrices(
        [
          weth.address,
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

async function main() {
    ensureExpectedEnvvars();
    const [owner, fred, joe, bob] = await ethers.getSigners();

    const DEPLOYED: GmxDeployedContracts = getDeployedContracts();
    console.log("owner addr:", await owner.getAddress());
    console.log("origami msig:", DEPLOYED.ORIGAMI.MULTISIG);
    
    const origamiMultisig = await impersonateAndFund(owner, DEPLOYED.ORIGAMI.MULTISIG, 10);

    const contracts = connectToContracts(DEPLOYED, origamiMultisig);
    const weth = IERC20__factory.connect(await contracts.gmxRewardRouter.weth(), origamiMultisig);   

    await setUpstreamRewardRates(contracts, owner);

    // Check the token prices
    await dumpPrices(contracts, weth);

    // The GMX reward distributors don't have a huge supply of rewards in their balance
    // The impact being that it will simply cap out the rewards it distributes when anyone claims.
    // Normally GMX will top up the accounts as required by collecting fees and sending to the distributors.
    // So use Joe to deposit a tonne of ETH into wETH and transfer to the relevant GMX fee contracts
    {
        const wethWrapped = IWrappedToken__factory.connect(await contracts.gmxRewardRouter.weth(), origamiMultisig);
        await mine(wethWrapped.connect(joe).deposit({value: ethers.utils.parseEther("9999")}));
        const feeGlpTracker = GMX_RewardTracker__factory.connect(await contracts.glpRewardRouter.feeGlpTracker(), origamiMultisig);
        await mine(weth.connect(joe).transfer(feeGlpTracker.distributor(), ethers.utils.parseEther("4000")));
        const feeGmxTracker = GMX_RewardTracker__factory.connect(await contracts.gmxRewardRouter.feeGmxTracker(), origamiMultisig);
        await mine(weth.connect(joe).transfer(feeGmxTracker.distributor(), ethers.utils.parseEther("5500")));
        console.log("**Sent GMX distributors weth**");
    }
    
    await claimTokenOwnership(contracts, origamiMultisig);
    console.log("**Claimed GMX Ownership**");

    console.log("\n**Mint Fred some GMX and buy ovGMX**");
    {
      await mine(contracts.gmxToken.setMinter(origamiMultisig.getAddress(), true));
      const buyAmount = ethers.utils.parseEther("10000");
      await mine(contracts.gmxToken.mint(fred.getAddress(), buyAmount));

      const quote = await contracts.ovGMX.investQuote(buyAmount, contracts.gmxToken.address);
      await mine(contracts.gmxToken.connect(fred).approve(contracts.ovGMX.address, buyAmount));
      await mine(contracts.ovGMX.connect(fred).investWithToken(quote.quoteData, 0));

      console.log("Fred ovGMX Bal:", fromAtto(await contracts.ovGMX.balanceOf(fred.getAddress())));
      console.log("Fred oGMX Bal:", fromAtto(await contracts.oGMX.balanceOf(fred.getAddress())));
      console.log("ovGMX Total Supply:", fromAtto(await contracts.ovGMX.totalSupply()));
      console.log("ovGMX Total Reserves:", fromAtto(await contracts.ovGMX.totalReserves()));
      console.log("oGMX Total Supply:", fromAtto(await contracts.oGMX.totalSupply()));
    }

    console.log("\n**Bob buys some ovGLP with ETH**");
    {
      const buyAmount = ethers.utils.parseEther("5");
      const quote = await contracts.ovGLP.investQuote(buyAmount, ZERO_ADDRESS);
      console.log("quote:", quote);
      await mine(contracts.ovGLP.connect(bob).investWithNative(quote.quoteData, 0, {value: buyAmount}));

      console.log("Bob ovGLP Bal:", fromAtto(await contracts.ovGLP.balanceOf(bob.getAddress())));
      console.log("Bob oGLP Bal:", fromAtto(await contracts.oGLP.balanceOf(bob.getAddress())));
      console.log("ovGLP Total Supply:", fromAtto(await contracts.ovGLP.totalSupply()));
      console.log("ovGLP Total Reserves:", fromAtto(await contracts.ovGLP.totalReserves()));
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
    await dumpPrices(contracts, weth);

    console.log("\n**Harvest Rewards**");
    {
        await mineForwardSeconds(86400);

        console.log("GMX:");
        console.log("\tProjected Reward Rates", await contracts.gmxRewardsAggregator.projectedRewardRates());
        console.log("\tRewards Distributor", await contracts.gmxRewardsAggregator.rewardsDistributor(), await origamiMultisig.getAddress(), await owner.getAddress());
        console.log("\tMSIG oGMX before:", fromAtto(await contracts.oGMX.balanceOf(origamiMultisig.getAddress())));
        console.log("\tMSIG wETH before:", fromAtto(await weth.balanceOf(origamiMultisig.getAddress())));
        await contracts.gmxRewardsAggregator.connect(origamiMultisig).harvestRewards();
        console.log("\tMSIG oGMX after:", fromAtto(await contracts.oGMX.balanceOf(origamiMultisig.getAddress())));
        console.log("\tMSIG wETH after:", fromAtto(await weth.balanceOf(origamiMultisig.getAddress())));

        console.log("GLP:");
        console.log("\tProjected Reward Rates", await contracts.glpRewardsAggregator.projectedRewardRates());
        console.log("\tRewards Distributor", await contracts.glpRewardsAggregator.rewardsDistributor(), await origamiMultisig.getAddress(), await owner.getAddress());
        console.log("\tMSIG oGMX before:", fromAtto(await contracts.oGMX.balanceOf(origamiMultisig.getAddress())));
        console.log("\tMSIG wETH before:", fromAtto(await weth.balanceOf(origamiMultisig.getAddress())));
        await contracts.glpRewardsAggregator.connect(origamiMultisig).harvestRewards();
        console.log("\tMSIG oGMX after:", fromAtto(await contracts.oGMX.balanceOf(origamiMultisig.getAddress())));
        console.log("\tMSIG wETH after:", fromAtto(await weth.balanceOf(origamiMultisig.getAddress())));
    }

    console.log("\n**Bump Up Reserves**");
    {
        await contracts.oGMX.connect(origamiMultisig).addMinter(origamiMultisig.getAddress());
        await contracts.oGMX.connect(origamiMultisig).mint(origamiMultisig.getAddress(), ethers.utils.parseEther("1000"));
        await contracts.oGMX.connect(origamiMultisig).approve(contracts.ovGMX.address, ethers.utils.parseEther("1000"));
        await contracts.ovGMX.connect(origamiMultisig).addReserves(ethers.utils.parseEther("1000"));

        await contracts.oGLP.connect(origamiMultisig).addMinter(origamiMultisig.getAddress());
        await contracts.oGLP.connect(origamiMultisig).mint(origamiMultisig.getAddress(), ethers.utils.parseEther("2000"));
        await contracts.oGLP.connect(origamiMultisig).approve(contracts.ovGLP.address, ethers.utils.parseEther("2000"));
        await contracts.ovGLP.connect(origamiMultisig).addReserves(ethers.utils.parseEther("2000"));

        await dumpPrices(contracts, weth);
    }

    console.log("\n**Fred sells ovGMX to GMX**");
    {
      const sellAmount = ethers.utils.parseEther("100");

      console.log("Fred ovGMX Bal:", fromAtto(await contracts.ovGMX.balanceOf(fred.getAddress())));
      console.log("Fred oGMX Bal:", fromAtto(await contracts.oGMX.balanceOf(fred.getAddress())));
      console.log("Fred GMX Bal:", fromAtto(await contracts.gmxToken.balanceOf(fred.getAddress())));
      console.log("ovGMX Total Supply:", fromAtto(await contracts.ovGMX.totalSupply()));
      console.log("ovGMX Total Reserves:", fromAtto(await contracts.ovGMX.totalReserves()));
      console.log("oGMX Total Supply:", fromAtto(await contracts.oGMX.totalSupply()));
      console.log("MSIG(fees) oGMX Bal:", fromAtto(await contracts.oGMX.balanceOf(origamiMultisig.getAddress())));

      const quote = await contracts.ovGMX.exitQuote(sellAmount, contracts.gmxToken.address);
      await mine(contracts.ovGMX.connect(fred).exitToToken(quote.quoteData, 0, fred.getAddress()));

      console.log("Fred ovGMX Bal:", fromAtto(await contracts.ovGMX.balanceOf(fred.getAddress())));
      console.log("Fred oGMX Bal:", fromAtto(await contracts.oGMX.balanceOf(fred.getAddress())));
      console.log("Fred GMX Bal:", fromAtto(await contracts.gmxToken.balanceOf(fred.getAddress())));
      console.log("ovGMX Total Supply:", fromAtto(await contracts.ovGMX.totalSupply()));
      console.log("ovGMX Total Reserves:", fromAtto(await contracts.ovGMX.totalReserves()));
      console.log("oGMX Total Supply:", fromAtto(await contracts.oGMX.totalSupply()));
      console.log("MSIG(fees) oGMX Bal:", fromAtto(await contracts.oGMX.balanceOf(origamiMultisig.getAddress())));
    }

    console.log("\n**Check quotes when buying and selling GLP directly to DAI**");
    {
      const buyAmount = ethers.utils.parseEther("20");
      const buyQuote = await contracts.ovGLP.investQuote(buyAmount, ZERO_ADDRESS);
      console.log("Buy quote:", buyQuote);

      const feeGlpTracker = GMX_RewardTracker__factory.connect(await contracts.glpRewardRouter.feeGlpTracker(), origamiMultisig);
      const bobGlpBefore = await feeGlpTracker.depositBalances(bob.getAddress(), await contracts.gmxRewardRouter.glp());
      await contracts.glpRewardRouter.connect(bob).mintAndStakeGlpETH(0, 0, {value:buyAmount});
      const bobGlpAfter = await feeGlpTracker.depositBalances(bob.getAddress(), await contracts.gmxRewardRouter.glp());
      console.log("Bob Bought GLP:", fromAtto(bobGlpBefore), fromAtto(bobGlpAfter), fromAtto(bobGlpAfter.sub(bobGlpBefore)));

      await mineForwardSeconds(86400);

      const dai = "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1";
      const daiToken = IERC20__factory.connect(dai, origamiMultisig);
      const sellAmount = ethers.utils.parseEther("1000");
      const sellQuote = await contracts.ovGLP.exitQuote(sellAmount, daiToken.address);
      console.log("Sell quote:", sellQuote);
      const bobDaiBefore = await daiToken.balanceOf(bob.getAddress());
      await contracts.glpRewardRouter.connect(bob).unstakeAndRedeemGlp(dai, sellAmount, 0, bob.getAddress());
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
      console.log("oGLP Total Supply:", fromAtto(await contracts.oGLP.totalSupply()));
      console.log("MSIG(fees) oGLP Bal:", fromAtto(await contracts.oGLP.balanceOf(origamiMultisig.getAddress())));

      const quote = await contracts.ovGLP.exitQuote(sellAmount, dai);
      console.log(quote);
      await mine(contracts.ovGLP.connect(bob).exitToToken(quote.quoteData, 0, bob.getAddress()));

      console.log("Bob ovGLP Bal:", fromAtto(await contracts.ovGLP.balanceOf(bob.getAddress())));
      console.log("Bob oGLP Bal:", fromAtto(await contracts.oGLP.balanceOf(bob.getAddress())));
      console.log("Bob DAI Bal:", fromAtto(await daiToken.balanceOf(bob.getAddress())));
      console.log("ovGLP Total Supply:", fromAtto(await contracts.ovGLP.totalSupply()));
      console.log("ovGLP Total Reserves:", fromAtto(await contracts.ovGLP.totalReserves()));
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
