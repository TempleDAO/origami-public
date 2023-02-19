import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { 
    OrigamiGmxEarnAccount__factory,
    OrigamiGmxInvestment__factory,
    OrigamiGmxManager__factory,
    OrigamiGmxRewardsAggregator__factory,
    OrigamiInvestmentVault__factory,
    TokenPrices__factory,
 } from '../../../../typechain';
import {
    ensureExpectedEnvvars,
    mine,
} from '../../helpers';
import { getDeployedContracts } from './contract-addresses';

async function main() {
    ensureExpectedEnvvars();
    const [owner] = await ethers.getSigners();
    const DEPLOYED = getDeployedContracts();

    const gmxEarnAccount = OrigamiGmxEarnAccount__factory.connect(DEPLOYED.ORIGAMI.GMX.GMX_EARN_ACCOUNT, owner);
    const glpPrimaryEarnAccount = OrigamiGmxEarnAccount__factory.connect(DEPLOYED.ORIGAMI.GMX.GLP_PRIMARY_EARN_ACCOUNT, owner);
    const glpSecondaryEarnAccount = OrigamiGmxEarnAccount__factory.connect(DEPLOYED.ORIGAMI.GMX.GLP_SECONDARY_EARN_ACCOUNT, owner);
    const gmxManager = OrigamiGmxManager__factory.connect(DEPLOYED.ORIGAMI.GMX.GMX_MANAGER, owner);
    const glpManager = OrigamiGmxManager__factory.connect(DEPLOYED.ORIGAMI.GMX.GLP_MANAGER, owner);
    const gmxRewardsAggr = OrigamiGmxRewardsAggregator__factory.connect(DEPLOYED.ORIGAMI.GMX.GMX_REWARDS_AGGREGATOR, owner);
    const glpRewardsAggr = OrigamiGmxRewardsAggregator__factory.connect(DEPLOYED.ORIGAMI.GMX.GLP_REWARDS_AGGREGATOR, owner);
    const oGMX = OrigamiGmxInvestment__factory.connect(DEPLOYED.ORIGAMI.GMX.oGMX, owner);
    const oGLP = OrigamiGmxInvestment__factory.connect(DEPLOYED.ORIGAMI.GMX.oGLP, owner);
    const ovGMX = OrigamiInvestmentVault__factory.connect(DEPLOYED.ORIGAMI.GMX.ovGMX, owner);
    const ovGLP = OrigamiInvestmentVault__factory.connect(DEPLOYED.ORIGAMI.GMX.ovGLP, owner);
    const tokenPrices = TokenPrices__factory.connect(DEPLOYED.ORIGAMI.TOKEN_PRICES, owner);

    // Transfer ownership to the multisig
    await mine(oGMX.transferOwnership(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(oGLP.transferOwnership(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(ovGMX.transferOwnership(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(ovGLP.transferOwnership(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(gmxEarnAccount.transferOwnership(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(glpPrimaryEarnAccount.transferOwnership(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(glpSecondaryEarnAccount.transferOwnership(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(gmxManager.transferOwnership(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(glpManager.transferOwnership(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(gmxRewardsAggr.transferOwnership(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(glpRewardsAggr.transferOwnership(DEPLOYED.ORIGAMI.MULTISIG));
    await mine(tokenPrices.transferOwnership(DEPLOYED.ORIGAMI.MULTISIG));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
