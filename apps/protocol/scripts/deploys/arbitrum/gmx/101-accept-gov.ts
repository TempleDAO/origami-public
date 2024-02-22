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
import { getDeployedContracts as gmxDeployedContracts } from './contract-addresses';
import { getDeployedContracts as govDeployedContracts } from '../governance/contract-addresses';

async function main() {
    ensureExpectedEnvvars();
    const [owner] = await ethers.getSigners();
    const GMX_DEPLOYED = gmxDeployedContracts();
    const GOV_DEPLOYED = govDeployedContracts();

    const gmxEarnAccount = OrigamiGmxEarnAccount__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.GMX_EARN_ACCOUNT, owner);
    const glpPrimaryEarnAccount = OrigamiGmxEarnAccount__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.GLP_PRIMARY_EARN_ACCOUNT, owner);
    const glpSecondaryEarnAccount = OrigamiGmxEarnAccount__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.GLP_SECONDARY_EARN_ACCOUNT, owner);
    const gmxManager = OrigamiGmxManager__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.GMX_MANAGER, owner);
    const glpManager = OrigamiGmxManager__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.GLP_MANAGER, owner);
    const gmxRewardsAggr = OrigamiGmxRewardsAggregator__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.GMX_REWARDS_AGGREGATOR, owner);
    const glpRewardsAggr = OrigamiGmxRewardsAggregator__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.GLP_REWARDS_AGGREGATOR, owner);
    const oGMX = OrigamiGmxInvestment__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.oGMX, owner);
    const oGLP = OrigamiGmxInvestment__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.oGLP, owner);
    const ovGMX = OrigamiInvestmentVault__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.ovGMX, owner);
    const ovGLP = OrigamiInvestmentVault__factory.connect(GMX_DEPLOYED.ORIGAMI.GMX.ovGLP, owner);
    const tokenPrices = TokenPrices__factory.connect(GMX_DEPLOYED.ORIGAMI.TOKEN_PRICES, owner);

    // Propose governance change to the timelock
    await mine(oGMX.proposeNewOwner(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(oGLP.proposeNewOwner(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(ovGMX.proposeNewOwner(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(ovGLP.proposeNewOwner(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(gmxEarnAccount.proposeNewOwner(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(glpPrimaryEarnAccount.proposeNewOwner(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(glpSecondaryEarnAccount.proposeNewOwner(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(gmxManager.proposeNewOwner(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(glpManager.proposeNewOwner(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(gmxRewardsAggr.proposeNewOwner(GOV_DEPLOYED.ORIGAMI.MULTISIG));
    await mine(glpRewardsAggr.proposeNewOwner(GOV_DEPLOYED.ORIGAMI.MULTISIG));

    // Transfer ownership to the multisig
    await mine(tokenPrices.transferOwnership(GOV_DEPLOYED.ORIGAMI.MULTISIG));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
