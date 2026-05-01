import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiTokenTeleporter } from '../../../../../typechain';
import {
  mine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';
import { EnforcedOptionParamStruct } from '../../../../../typechain/contracts/common/omnichain/OrigamiOFT';
import { CONTRACTS as BERACHAIN_ADDRS } from '../../../berachain/contract-addresses/berachain';
import { DEFAULT_SETTINGS as BERACHAIN_DEFAULT_SETTINGS } from '../../../berachain/default-settings';

async function setPeer(teleporter: OrigamiTokenTeleporter) {
  await mine(teleporter.setPeer(
    BERACHAIN_DEFAULT_SETTINGS.EXTERNAL.LAYER_ZERO.ENDPOINT_ID,
    ethers.utils.zeroPad(BERACHAIN_ADDRS.VAULTS.hOHM.TOKEN, 32)
  ));

  const options: EnforcedOptionParamStruct[] = [{
    eid: BERACHAIN_DEFAULT_SETTINGS.EXTERNAL.LAYER_ZERO.ENDPOINT_ID,
    msgType: 1, // SEND
    // minimum 200k gas for transfers
    options: "0x00030100110100000000000000000000000000030d40",
  }];
  await mine(teleporter.setEnforcedOptions(options));
}

async function main() {
  const { INSTANCES } = await getDeployContext(__dirname);
  await setPeer(INSTANCES.VAULTS.hOHM.TELEPORTER);
}

runAsyncMain(main);
