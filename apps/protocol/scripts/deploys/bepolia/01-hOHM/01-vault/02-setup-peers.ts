import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiOFT } from '../../../../../typechain';
import {
  mine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';
import { CONTRACTS as HOLESKY_CONTRACTS } from '../../../holesky/contract-addresses/holesky';
import { Constants as HOLESKY_CONSTANTS } from '../../../holesky/constants';
import { EnforcedOptionParamStruct } from '../../../../../typechain/contracts/common/omnichain/OrigamiOFT';


async function setHoleskyPeer(oft: OrigamiOFT) {
  await mine(oft.setPeer(HOLESKY_CONSTANTS.LAYER_ZERO.EID, ethers.utils.zeroPad(HOLESKY_CONTRACTS.VAULTS.hOHM.TELEPORTER, 32)));
  
  const options: EnforcedOptionParamStruct[] = [{
    eid: HOLESKY_CONSTANTS.LAYER_ZERO.EID,
    msgType: 1, // SEND
    options: "0x00030100110100000000000000000000000000030d40",
  }];
  await mine(oft.setEnforcedOptions(options));
}

async function main() {
    const { INSTANCES } = await getDeployContext(__dirname);

    await setHoleskyPeer(INSTANCES.VAULTS.hOHM.TOKEN);
}

runAsyncMain(main);
