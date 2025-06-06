import '@nomiclabs/hardhat-ethers';
import {
  runAsyncMain,
} from '../../helpers';
import { getDeployContext } from '../deploy-context';
import { IOrigamiLovToken, IOrigamiLovToken__factory, IOrigamiLovTokenManager__factory, IOrigamiManagerPausable } from '../../../../typechain';
import { createSafeBatch, createSafeTransaction, SafeTransaction, writeSafeTransactionsBatch } from '../../safe-tx-builder';
import path from 'path';

const TO_DELEVER = [
  'LOV_SUSDE_A',
  'LOV_SUSDE_B',
  'LOV_USDE_A',
  'LOV_USDE_B',

  'LOV_WEETH_A',
  'LOV_WETH_DAI_LONG_A',
  'LOV_WETH_SDAI_SHORT_A',
  'LOV_AAVE_USDC_LONG_A',
  'LOV_SDAI_A',
  'LOV_RSWETH_A',
  'LOV_WETH_CBBTC_LONG_A',
];

function collectPerformanceFees(
  contract: IOrigamiLovToken,
): SafeTransaction {
  return createSafeTransaction(
    contract.address,
    "collectPerformanceFees",
    [],
  )
}

function setPaused(
  contract: IOrigamiManagerPausable,
  investmentsPaused: boolean,
  exitsPaused: boolean,
): SafeTransaction {
  return {
    to: contract.address,
    value: "0",
    data: null,
    contractMethod: {
      name: "setPaused",
      payable: false,
      inputs: [
        {
          components: [
            {
              internalType: "bool",
              name: "investmentsPaused",
              type: "bool"
            },
            {
              internalType: "bool",
              name: "exitsPaused",
              type: "bool"
            },
          ],
          internalType: "struct IOrigamiManagerPausable.Paused",
          name: "updatedPaused",
          type: "tuple"
        }
      ],
    },
    contractInputsValues: {
      updatedPaused: JSON.stringify([
        investmentsPaused,
        exitsPaused,
      ])
    }
  }
}

async function main() {
  const {owner, ADDRS} = await getDeployContext(__dirname);

  const safeBatchItems = [];
  for (const [name, vault] of Object.entries(ADDRS)) {
    if (!TO_DELEVER.includes(name)) continue;

    const vaultInstance = IOrigamiLovToken__factory.connect(vault.TOKEN, owner);
    const manager = IOrigamiLovTokenManager__factory.connect(vault.MANAGER, owner);
    safeBatchItems.push(collectPerformanceFees(vaultInstance));
    safeBatchItems.push(setPaused(manager, true, false));
  }

  const batch = createSafeBatch(safeBatchItems);
  const filename = path.join(__dirname, "./03-post-process.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

runAsyncMain(main);
