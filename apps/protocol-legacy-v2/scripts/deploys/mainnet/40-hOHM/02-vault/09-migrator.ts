import '@nomiclabs/hardhat-ethers';
import { OrigamiCoolerMigrator__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiCoolerMigrator__factory(owner);
  await deployAndMine(
    'VAULTS.hOHM.MIGRATOR',
    factory,
    factory.deploy,
    ADDRS.CORE.MULTISIG,
    ADDRS.VAULTS.hOHM.TOKEN,
    ADDRS.EXTERNAL.OLYMPUS.GOHM_TOKEN,
    ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN,
    ADDRS.EXTERNAL.SKY.USDS_TOKEN,
    ADDRS.EXTERNAL.MAKER_DAO.DAI_USDS_CONVERTER,
    ADDRS.EXTERNAL.OLYMPUS.MONO_COOLER,
    ADDRS.EXTERNAL.MAKER_DAO.DAI_FLASHLOAN_LENDER,
    [
      ADDRS.EXTERNAL.OLYMPUS.COOLER_V1.CLEARINGHOUSE_V1_1,
      ADDRS.EXTERNAL.OLYMPUS.COOLER_V1.CLEARINGHOUSE_V1_2,
      ADDRS.EXTERNAL.OLYMPUS.COOLER_V1.CLEARINGHOUSE_V1_3,
    ],
  );
}

runAsyncMain(main);
