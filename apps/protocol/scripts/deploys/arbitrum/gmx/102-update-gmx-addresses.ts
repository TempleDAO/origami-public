import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiGmxEarnAccount, OrigamiGmxEarnAccount__factory, OrigamiGmxManager, OrigamiGmxManager__factory, TimelockController, TimelockController__factory } from '../../../../typechain';
import {
  ensureExpectedEnvvars,
} from '../../helpers';
import { getDeployedContracts } from './contract-addresses';
import { getDeployedContracts as govDeployedContracts } from '../governance/contract-addresses';
import { BigNumber, PopulatedTransaction } from 'ethers';

/*
anvil --hardfork cancun --fork-url https://arb-mainnet.g.alchemy.com/v2/gE49sK2udf5hmLGW1TTjUT3Iu4CVkJLX --fork-block-number 202455199 --timestamp 1713484828
*/

const GMX_DEPLOYED_CONTRACTS = getDeployedContracts();
const GOV_DEPLOYED_CONTRACTS = govDeployedContracts();
const SALT = "gmxUpgrade-19-04-23";

async function logScheduleBatch(
  pptxs: Promise<PopulatedTransaction>[], 
  timelock: TimelockController, 
  minDelay: BigNumber
) {
  const ptxs = await Promise.all(pptxs);
  const items = ptxs.map(v => {
    if (!v.data || !v.to) throw Error("unknown tx data or to");

    return {
      to: v.to,
      data: v.data,
    };
  });

  console.log("Items to Schedule:");
  console.log(items);

  const schedulePtx = await timelock.populateTransaction.scheduleBatch(
    items.map(v => v.to),
    items.map(v => 0),
    items.map(v => v.data),
    ethers.utils.formatBytes32String(""),
    ethers.utils.formatBytes32String(SALT),
    minDelay,
  )

  console.log("TX DATA");
  console.log(schedulePtx.data);
}

async function logExecuteBatch(
  pptxs: Promise<PopulatedTransaction>[], 
  timelock: TimelockController
) {
  const ptxs = await Promise.all(pptxs);
  const items = ptxs.map(v => {
    if (!v.data || !v.to) throw Error("unknown tx data or to");

    return {
      to: v.to,
      data: v.data,
    };
  });

  console.log("Items to Execute:");
  console.log(items);

  const schedulePtx = await timelock.populateTransaction.executeBatch(
    items.map(v => v.to),
    items.map(v => 0),
    items.map(v => v.data),
    ethers.utils.formatBytes32String(""),
    ethers.utils.formatBytes32String(SALT)
  );

  console.log(schedulePtx.data);
}

async function updateEarnAccount(ea: OrigamiGmxEarnAccount): Promise<PopulatedTransaction> {
  const esGmxVester = await ea.esGmxVester();
  const stakedGlp = await ea.stakedGlp();
  return ea.populateTransaction.initGmxContracts(
    GMX_DEPLOYED_CONTRACTS.GMX.STAKING.GMX_REWARD_ROUTER,
    GMX_DEPLOYED_CONTRACTS.GMX.STAKING.GLP_REWARD_ROUTER,
    esGmxVester,
    stakedGlp
  );
}

async function updateManager(manager: OrigamiGmxManager): Promise<PopulatedTransaction> {
  return manager.populateTransaction.initGmxContracts(
    GMX_DEPLOYED_CONTRACTS.GMX.STAKING.GMX_REWARD_ROUTER,
    GMX_DEPLOYED_CONTRACTS.GMX.STAKING.GLP_REWARD_ROUTER
  );
}

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();

  const timelock = TimelockController__factory.connect(GOV_DEPLOYED_CONTRACTS.ORIGAMI.GOV_TIMELOCK, owner);
  const minDelay = await timelock.getMinDelay();

  const GMX_EARN_ACCOUNT = OrigamiGmxEarnAccount__factory.connect(
    GMX_DEPLOYED_CONTRACTS.ORIGAMI.GMX.GMX_EARN_ACCOUNT, owner
  );
  const GLP_PRIMARY_EARN_ACCOUNT = OrigamiGmxEarnAccount__factory.connect(
    GMX_DEPLOYED_CONTRACTS.ORIGAMI.GMX.GLP_PRIMARY_EARN_ACCOUNT, owner
  );
  const GLP_SECONDARY_EARN_ACCOUNT = OrigamiGmxEarnAccount__factory.connect(
    GMX_DEPLOYED_CONTRACTS.ORIGAMI.GMX.GLP_SECONDARY_EARN_ACCOUNT, owner
  );
  const GMX_MANAGER = OrigamiGmxManager__factory.connect(
    GMX_DEPLOYED_CONTRACTS.ORIGAMI.GMX.GMX_MANAGER, owner
  );
  const GLP_MANAGER = OrigamiGmxManager__factory.connect(
    GMX_DEPLOYED_CONTRACTS.ORIGAMI.GMX.GLP_MANAGER, owner
  );

  const ptxs = [
    updateEarnAccount(GMX_EARN_ACCOUNT),
    updateEarnAccount(GLP_PRIMARY_EARN_ACCOUNT),
    updateEarnAccount(GLP_SECONDARY_EARN_ACCOUNT),
    updateManager(GMX_MANAGER),
    updateManager(GLP_MANAGER),
  ]

  await logScheduleBatch(ptxs, timelock, minDelay);
  await logExecuteBatch(ptxs, timelock);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });