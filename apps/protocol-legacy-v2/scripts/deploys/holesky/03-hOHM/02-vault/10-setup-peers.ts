import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiTokenTeleporter } from '../../../../../typechain';
import {
  mine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';
import { CONTRACTS as BEPOLIA_ADDRS } from '../../../bepolia/contract-addresses/bepolia';
import { Constants as BEPOLIA_CONSTANTS } from '../../../bepolia/constants';
import { EnforcedOptionParamStruct } from '../../../../../typechain/contracts/common/omnichain/OrigamiOFT';

let teleporter: OrigamiTokenTeleporter;

async function setBepoliaPeer() {
  await mine(teleporter.setPeer(BEPOLIA_CONSTANTS.LAYER_ZERO.EID, ethers.utils.zeroPad(BEPOLIA_ADDRS.VAULTS.hOHM.TOKEN, 32)));

  const options: EnforcedOptionParamStruct[] = [{
    eid: BEPOLIA_CONSTANTS.LAYER_ZERO.EID,
    msgType: 1, // SEND
    options: "0x00030100110100000000000000000000000000030d40",
  }];
  await mine(teleporter.setEnforcedOptions(options));
}

async function main() {
  const { INSTANCES } = await getDeployContext(__dirname);
  teleporter = INSTANCES.VAULTS.hOHM.TELEPORTER;

  await setBepoliaPeer();
}

runAsyncMain(main);
