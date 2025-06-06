import '@nomiclabs/hardhat-ethers';
import { OrigamiLovTokenMorphoManagerMarketAL__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiLovTokenMorphoManagerMarketAL__factory(owner);
  await deployAndMine(
    'LOV_ORIBGT_A.MANAGER',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.VAULTS.ORIBGT.TOKEN,
    ADDRS.EXTERNAL.BERACHAIN.WBERA_TOKEN,
    ADDRS.VAULTS.ORIBGT.TOKEN,
    ADDRS.LOV_ORIBGT_A.TOKEN,
    ADDRS.LOV_ORIBGT_A.EULER_V2_BORROW_LEND,

    // EULER: WBERA/oriBGT = iBGT/oriBGT * [1:1] WBERA
    // MARKET: WBERA/oriBGT = iBGT/oriBGT * WBERA/iBGT
    // EULER => MARKET: WBERA/iBGT
    // Note this also does a check to ensure WBERA/iBGT is not below 0.9
    ADDRS.ORACLES.IBGT_WBERA_WITH_PRICE_CHECK,
  );
}

runAsyncMain(main);
