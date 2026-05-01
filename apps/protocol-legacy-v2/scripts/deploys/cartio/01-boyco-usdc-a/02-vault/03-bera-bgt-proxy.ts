import '@nomiclabs/hardhat-ethers';
import { OrigamiBeraBgtProxy__factory } from '../../../../../typechain';
import {
  deployProxyAndMine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiBeraBgtProxy__factory(owner);
  await deployProxyAndMine(
    ADDRS.VAULTS.BOYCO_USDC_A.BERA_BGT_PROXY,
    'VAULTS.BOYCO_USDC_A.BERA_BGT_PROXY',
    'uups',
    [ADDRS.EXTERNAL.BERACHAIN.BGT_TOKEN],
    factory,
    factory.deploy,
    await owner.getAddress(),
  );
}

runAsyncMain(main);
