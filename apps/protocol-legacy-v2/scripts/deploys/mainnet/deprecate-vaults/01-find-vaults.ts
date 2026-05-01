import '@nomiclabs/hardhat-ethers';
import {
  runAsyncMain,
} from '../../helpers';
import { getDeployContext } from '../deploy-context';
import { IERC20Metadata__factory, IOrigamiLovToken__factory, IOrigamiLovTokenManager__factory, IOrigamiManagerPausable } from '../../../../typechain';
import { BigNumber, ethers } from 'ethers';

async function main() {
  const {owner, ADDRS} = await getDeployContext(__dirname);

  const TO_KEEP = [
    'LOV_WSTETH_A',
    'LOV_WSTETH_B',
    'LOV_USD0pp_A',
    'LOV_PT_SUSDE_MAY_2025_A',

    'SUSDSpS', // not a lov token
    'BOYCO_USDC_A', // in berachain
    'ORIBGT', // in berachain
    'hOHM', // not yet released
  ];

  const ALREADY_DEPRECATED = [
    'LOV_WOETH_A',
    'LOV_PT_SUSDE_OCT24_A',
    'LOV_PT_USD0pp_MAR_2025_A',
  ];

  const alreadyDeprecated = [];
  const toDeprecate = [];
  for (const [name, vault] of Object.entries(ADDRS)) {
    if (!name.startsWith("LOV_")) continue;
    if (vault.MANAGER === "0x") continue;
    if (TO_KEEP.includes(name)) continue;

    const vaultInstance = IOrigamiLovToken__factory.connect(vault.TOKEN, owner);
    const manager = IOrigamiLovTokenManager__factory.connect(vault.MANAGER, owner);
    const assetsAndLiabilities = await manager.assetsAndLiabilities(0);
    const reserveToken = IERC20Metadata__factory.connect(await vaultInstance.reserveToken(), owner);
    const reserveTokenDecimals = await reserveToken.decimals();
    const userALRange = await manager.userALRange();
    const rebalanceALRange = await manager.rebalanceALRange();

    const result = {
      name,
      assets: parseFloat(ethers.utils.formatUnits(assetsAndLiabilities.assets, reserveTokenDecimals)),
      liabilities: parseFloat(ethers.utils.formatUnits(assetsAndLiabilities.liabilities, reserveTokenDecimals)),
      AL: parseFloat(ethers.utils.formatUnits(assetsAndLiabilities.ratio, 18)),
      userALFloor: userALRange.floor.toString(),
      userALCeiling: userALRange.ceiling.toString(),
      rebalanceALFloor: rebalanceALRange.floor.toString(),
      rebalanceALCeiling: rebalanceALRange.ceiling.toString(),
    }

    if (
      assetsAndLiabilities.ratio.gte(ethers.utils.parseEther("100")) ||
      assetsAndLiabilities.assets == BigNumber.from(0) ||
      assetsAndLiabilities.liabilities == BigNumber.from(0) ||
      ALREADY_DEPRECATED.includes(name)
    ) {
      alreadyDeprecated.push(result);
    } else {
      toDeprecate.push(result);
    }
  }

  console.log("TO DEPRECATE:");
  console.log(JSON.stringify(toDeprecate, undefined, 2));
  console.log("");
  console.log("LIKELY ALREADY DEPRECATED:");
  console.log(JSON.stringify(alreadyDeprecated, undefined, 2));
}

runAsyncMain(main);
