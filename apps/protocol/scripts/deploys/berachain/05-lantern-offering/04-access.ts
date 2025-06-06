import '@nomiclabs/hardhat-ethers';
import { OrigamiLanternOffering__factory } from '../../../../typechain';
import { mine, runAsyncMain } from '../../helpers';
import { getDeployContext } from '../deploy-context';
import path from 'path';
import { network } from 'hardhat';
import { acceptOwner, createSafeBatch, writeSafeTransactionsBatch } from '../../safe-tx-builder';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const lanternFest = OrigamiLanternOffering__factory.connect(ADDRS.PERIPHERY.LANTERN_OFFERING, owner);
  await mine(lanternFest.proposeNewOwner(ADDRS.CORE.MULTISIG));

  if (network.name != "localhost") {
    const batch = createSafeBatch(
      [
        acceptOwner(lanternFest),
      ],
    );
    
    const filename = path.join(__dirname, "./accept-owner.json");
    writeSafeTransactionsBatch(batch, filename);
    console.log(`Wrote Safe tx's batch to: ${filename}`);
  }
}

runAsyncMain(main);
