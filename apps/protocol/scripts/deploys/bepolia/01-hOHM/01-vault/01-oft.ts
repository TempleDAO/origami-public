import '@nomiclabs/hardhat-ethers';
import { OrigamiOFT__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';
import { DEFAULT_SETTINGS } from '../../../holesky/default-settings';

async function main() {
    const { owner, ADDRS } = await getDeployContext(__dirname);

    const factory = new OrigamiOFT__factory(owner);
    await deployAndMine(
        'VAULTS.hOHM.TOKEN',
        factory,
        factory.deploy,
        {
            name: DEFAULT_SETTINGS.VAULTS.hOHM.TOKEN_NAME,
            symbol: DEFAULT_SETTINGS.VAULTS.hOHM.TOKEN_SYMBOL,
            lzEndpoint: ADDRS.EXTERNAL.LAYER_ZERO.ENDPOINT,
            delegate: await owner.getAddress(),
        }
    );
}

runAsyncMain(main);