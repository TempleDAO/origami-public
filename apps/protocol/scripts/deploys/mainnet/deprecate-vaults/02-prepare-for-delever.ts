import '@nomiclabs/hardhat-ethers';
import {
  runAsyncMain,
} from '../../helpers';
import { getDeployContext } from '../deploy-context';
import { IERC20Metadata__factory, IOrigamiLovToken__factory, IOrigamiLovTokenManager, IOrigamiLovTokenManager__factory, IOrigamiManagerPausable } from '../../../../typechain';
import { BigNumber, ethers } from 'ethers';
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

function setPauser(
  contract: IOrigamiManagerPausable,
  account: string,
  canPause: boolean,
): SafeTransaction {
  return createSafeTransaction(
    contract.address,
    "setPauser",
    [
      {
        argType: "address",
        name: "account",
        value: account,
      },
      {
        argType: "bool",
        name: "canPause",
        value: canPause.toString(),
      },
    ],
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

function setUserALRange(
  contract: IOrigamiLovTokenManager,
  floor: BigNumber,
  ceiling: BigNumber,
): SafeTransaction {
  return createSafeTransaction(
    contract.address,
    "setUserALRange",
    [
      {
        argType: "uint128",
        name: "floor",
        value: floor.toString(),
      },
      {
        argType: "uint128",
        name: "ceiling",
        value: ceiling.toString(),
      },
    ],
  )
}

function setRebalanceALRange(
  contract: IOrigamiLovTokenManager,
  floor: BigNumber,
  ceiling: BigNumber,
): SafeTransaction {
  return createSafeTransaction(
    contract.address,
    "setRebalanceALRange",
    [
      {
        argType: "uint128",
        name: "floor",
        value: floor.toString(),
      },
      {
        argType: "uint128",
        name: "ceiling",
        value: ceiling.toString(),
      },
    ],
  )
}

function setFeeConfig(
  contract: IOrigamiLovTokenManager,
  minDepositFeeBps: BigNumber,
  minExitFeeBps: BigNumber,
  feeLeverageFactor: BigNumber,
): SafeTransaction {
  return createSafeTransaction(
    contract.address,
    "setFeeConfig",
    [
      {
        argType: "uint16",
        name: "_minDepositFeeBps",
        value: minDepositFeeBps.toString(),
      },
      {
        argType: "uint16",
        name: "_minExitFeeBps",
        value: minExitFeeBps.toString(),
      },
      {
        argType: "uint24",
        name: "_feeLeverageFactor",
        value: feeLeverageFactor.toString(),
      },
    ],
  )
}

async function main() {
  const {owner, ADDRS} = await getDeployContext(__dirname);

  const alreadyDeprecated = [];
  const toDeprecate = [];
  for (const [name, vault] of Object.entries(ADDRS)) {
    if (!TO_DELEVER.includes(name)) continue;

    const vaultInstance = IOrigamiLovToken__factory.connect(vault.TOKEN, owner);
    const manager = IOrigamiLovTokenManager__factory.connect(vault.MANAGER, owner);
    const assetsAndLiabilities = await manager.assetsAndLiabilities(0);
    const reserveToken = IERC20Metadata__factory.connect(await vaultInstance.reserveToken(), owner);
    const reserveTokenDecimals = await reserveToken.decimals();
    const userALRange = await manager.userALRange();
    const rebalanceALRange = await manager.rebalanceALRange();

    const result = {
      name,
      vaultInstance,
      manager,
      assets: parseFloat(ethers.utils.formatUnits(assetsAndLiabilities.assets, reserveTokenDecimals)),
      liabilities: parseFloat(ethers.utils.formatUnits(assetsAndLiabilities.liabilities, reserveTokenDecimals)),
      AL: parseFloat(ethers.utils.formatUnits(assetsAndLiabilities.ratio, 18)),
      userALFloor: userALRange.floor,
      userALCeiling: userALRange.ceiling,
      rebalanceALFloor: rebalanceALRange.floor,
      rebalanceALCeiling: rebalanceALRange.ceiling,
    }

    if (
      assetsAndLiabilities.ratio.gte(ethers.utils.parseEther("10000")) ||
      assetsAndLiabilities.assets == BigNumber.from(0) ||
      assetsAndLiabilities.liabilities == BigNumber.from(0)
    ) {
      alreadyDeprecated.push(result);
    } else {
      toDeprecate.push(result);
    }
  }

  const maxAL = BigNumber.from("340282366920938463463374607431768211455");
  const safeBatchItems = toDeprecate
    .map(v => (
      [
        setPauser(v.manager, ADDRS.CORE.MULTISIG, true),
        setPaused(v.manager, true, true),
        setUserALRange(v.manager, v.userALFloor, maxAL),
        setRebalanceALRange(v.manager, v.rebalanceALFloor, maxAL),
        setFeeConfig(v.manager, BigNumber.from(0), BigNumber.from(0), BigNumber.from(0)),
      ]
    ))
    .flat();
  
  const batch = createSafeBatch(safeBatchItems);
  const filename = path.join(__dirname, "./02-prepare-for-delever.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

runAsyncMain(main);
