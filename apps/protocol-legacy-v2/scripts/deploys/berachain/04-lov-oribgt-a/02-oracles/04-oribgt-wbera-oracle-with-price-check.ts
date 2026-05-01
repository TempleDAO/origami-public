import '@nomiclabs/hardhat-ethers';
import { OrigamiOracleWithPriceCheck__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';
import { ethers } from 'ethers';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiOracleWithPriceCheck__factory(owner);
  await deployAndMine(
    'ORACLES.IBGT_WBERA_WITH_PRICE_CHECK',
    factory,
    factory.deploy,
    ADDRS.CORE.MULTISIG,
    ADDRS.ORACLES.IBGT_WBERA,
    {
      floor: ethers.utils.parseEther("0.9"),
      ceiling: ethers.utils.parseEther("2"),
    }
  );
}

runAsyncMain(main);