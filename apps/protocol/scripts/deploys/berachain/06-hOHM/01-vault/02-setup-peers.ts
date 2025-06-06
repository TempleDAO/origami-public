import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiOFT } from '../../../../../typechain';
import {
  mine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';
import { EnforcedOptionParamStruct } from '../../../../../typechain/contracts/common/omnichain/OrigamiOFT';
import { DEFAULT_SETTINGS as MAINNET_DEFAULT_SETTINGS } from '../../../mainnet/default-settings';
import { CONTRACTS as MAINNET_ADDRS } from '../../../mainnet/contract-addresses/mainnet';

async function setPeer(oft: OrigamiOFT) {
  await mine(oft.setPeer(
    MAINNET_DEFAULT_SETTINGS.EXTERNAL.LAYER_ZERO.ENDPOINT_ID,
    ethers.utils.zeroPad(MAINNET_ADDRS.VAULTS.hOHM.TELEPORTER, 32)
  ));
  
  const options: EnforcedOptionParamStruct[] = [{
    eid: MAINNET_DEFAULT_SETTINGS.EXTERNAL.LAYER_ZERO.ENDPOINT_ID,
    msgType: 1, // SEND
    // minimum 200k gas for transfers
    options: "0x00030100110100000000000000000000000000030d40",
  }];
  await mine(oft.setEnforcedOptions(options));
}

async function main() {
  const { INSTANCES } = await getDeployContext(__dirname);
  await setPeer(INSTANCES.VAULTS.hOHM.TOKEN);
}

runAsyncMain(main);
