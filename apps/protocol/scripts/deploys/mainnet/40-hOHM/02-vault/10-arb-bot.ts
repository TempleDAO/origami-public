import '@nomiclabs/hardhat-ethers';
import { OrigamiHOhmArbBot, OrigamiHOhmArbBot__factory } from '../../../../../typechain';
import {
  deployAndMine,
  mine,
  runAsyncMain,
  setExplicitAccess,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';
import { constants } from 'ethers';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiHOhmArbBot__factory(owner);
  const arbBot = await deployAndMine(
    'VAULTS.hOHM.ARB_BOT',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.VAULTS.hOHM.TOKEN,
    ADDRS.EXTERNAL.OLYMPUS.GOHM_STAKING,
    ADDRS.EXTERNAL.SKY.SUSDS_TOKEN,
    ADDRS.EXTERNAL.UNISWAP.ROUTER_V3,
    ADDRS.EXTERNAL.UNISWAP.QUOTER_V3,
    ADDRS.EXTERNAL.MORPHO.SINGLETON,
  ) as OrigamiHOhmArbBot;

  // Overlord
  await setExplicitAccess(
    arbBot,
    ADDRS.VAULTS.hOHM.ARB_BOT_OVERLORD_WALLET,
    ["approveToken", "executeRoute1", "executeRoute2"],
    true
  );
  
  // Route 1 approvals
  await mine(arbBot.approveToken(ADDRS.EXTERNAL.SKY.SUSDS_TOKEN, ADDRS.EXTERNAL.UNISWAP.ROUTER_V3, constants.MaxUint256));
  await mine(arbBot.approveToken(ADDRS.EXTERNAL.OLYMPUS.OHM_TOKEN, ADDRS.EXTERNAL.UNISWAP.ROUTER_V3, constants.MaxUint256));
  await mine(arbBot.approveToken(ADDRS.EXTERNAL.SKY.USDS_TOKEN, ADDRS.VAULTS.hOHM.TOKEN, constants.MaxUint256));
  await mine(arbBot.approveToken(ADDRS.EXTERNAL.SKY.USDS_TOKEN, ADDRS.EXTERNAL.SKY.SUSDS_TOKEN, constants.MaxUint256));
  await mine(arbBot.approveToken(ADDRS.EXTERNAL.SKY.SUSDS_TOKEN, ADDRS.EXTERNAL.MORPHO.SINGLETON, constants.MaxUint256));
  
  // Extra route 2 approvals
  await mine(arbBot.approveToken(ADDRS.EXTERNAL.OLYMPUS.OHM_TOKEN, ADDRS.EXTERNAL.OLYMPUS.GOHM_STAKING, constants.MaxUint256));
  await mine(arbBot.approveToken(ADDRS.EXTERNAL.OLYMPUS.GOHM_TOKEN, ADDRS.VAULTS.hOHM.TOKEN, constants.MaxUint256));
  await mine(arbBot.approveToken(ADDRS.VAULTS.hOHM.TOKEN, ADDRS.EXTERNAL.UNISWAP.ROUTER_V3, constants.MaxUint256));

  await mine(arbBot.proposeNewOwner(ADDRS.CORE.MULTISIG));
}

runAsyncMain(main);
