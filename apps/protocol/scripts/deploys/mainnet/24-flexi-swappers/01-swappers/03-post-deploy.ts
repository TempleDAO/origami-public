import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  ensureExpectedEnvvars,
  impersonateAndFund,
  mine,
} from '../../../helpers';
import { ContractInstances, connectToContracts1, getDeployedContracts1 } from '../../contract-addresses';
import { ContractAddresses } from '../../contract-addresses/types';
import { createSafeBatch, createSafeTransaction, writeSafeTransactionsBatch } from '../../../safe-tx-builder';
import { OrigamiLovTokenFlashAndBorrowManager, OrigamiMorphoBorrowAndLend } from '../../../../../typechain';
import path from 'path';
import { JsonRpcSigner } from '@ethersproject/providers';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

const swapperMappings = () => [
  {
    contract: INSTANCES.LOV_SUSDE_A.MORPHO_BORROW_LEND,
    swapper: ADDRS.SWAPPERS.SUSDE_SWAPPER,
  },
  {
    contract: INSTANCES.LOV_SUSDE_B.MORPHO_BORROW_LEND,
    swapper: ADDRS.SWAPPERS.SUSDE_SWAPPER,
  },
  {
    contract: INSTANCES.LOV_USDE_A.MORPHO_BORROW_LEND,
    swapper: ADDRS.SWAPPERS.DIRECT_SWAPPER,
  },
  {
    contract: INSTANCES.LOV_USDE_B.MORPHO_BORROW_LEND,
    swapper: ADDRS.SWAPPERS.DIRECT_SWAPPER,
  },
  {
    contract: INSTANCES.LOV_WEETH_A.MORPHO_BORROW_LEND,
    swapper: ADDRS.SWAPPERS.DIRECT_SWAPPER,
  },
  {
    contract: INSTANCES.LOV_EZETH_A.MORPHO_BORROW_LEND,
    swapper: ADDRS.SWAPPERS.DIRECT_SWAPPER,
  },
  {
    contract: INSTANCES.LOV_WSTETH_A.MANAGER,
    swapper: ADDRS.SWAPPERS.DIRECT_SWAPPER,
  },
  {
    contract: INSTANCES.LOV_WSTETH_B.MANAGER,
    swapper: ADDRS.SWAPPERS.DIRECT_SWAPPER,
  },
  {
    contract: INSTANCES.LOV_WOETH_A.MORPHO_BORROW_LEND,
    swapper: ADDRS.SWAPPERS.DIRECT_SWAPPER,
  },
  {
    contract: INSTANCES.LOV_WETH_DAI_LONG_A.MANAGER,
    swapper: ADDRS.SWAPPERS.DIRECT_SWAPPER,
  },
  {
    contract: INSTANCES.LOV_WETH_SDAI_SHORT_A.MANAGER,
    swapper: ADDRS.SWAPPERS.DIRECT_SWAPPER,
  },
  {
    contract: INSTANCES.LOV_WBTC_DAI_LONG_A.MANAGER,
    swapper: ADDRS.SWAPPERS.DIRECT_SWAPPER,
  },
  {
    contract: INSTANCES.LOV_WBTC_SDAI_SHORT_A.MANAGER,
    swapper: ADDRS.SWAPPERS.DIRECT_SWAPPER,
  },
  {
    contract: INSTANCES.LOV_WETH_WBTC_LONG_A.MANAGER,
    swapper: ADDRS.SWAPPERS.DIRECT_SWAPPER,
  },
  {
    contract: INSTANCES.LOV_WETH_WBTC_SHORT_A.MANAGER,
    swapper: ADDRS.SWAPPERS.DIRECT_SWAPPER,
  },
  {
    contract: INSTANCES.LOV_PT_SUSDE_OCT24_A.MORPHO_BORROW_LEND,
    swapper: ADDRS.SWAPPERS.DIRECT_SWAPPER,
  },
  // {
  //   contract: INSTANCES.LOV_MKR_DAI_LONG_A.MANAGER,
  //   swapper: ADDRS.SWAPPERS.DIRECT_SWAPPER,
  // },
  {
    contract: INSTANCES.LOV_AAVE_USDC_LONG_A.MANAGER,
    swapper: ADDRS.SWAPPERS.DIRECT_SWAPPER,
  },
  {
    contract: INSTANCES.LOV_SDAI_A.MORPHO_BORROW_LEND,
    swapper: ADDRS.SWAPPERS.DIRECT_SWAPPER,
  },
  {
    contract: INSTANCES.LOV_USD0pp_A.MORPHO_BORROW_LEND,
    swapper: ADDRS.SWAPPERS.DIRECT_SWAPPER,
  },
];

async function updateSwappers(signer: JsonRpcSigner) {
  for (const mapping of swapperMappings()) {
    await mine(mapping.contract.connect(signer).setSwapper(mapping.swapper));
  }
}

export function setSwapperFunction(
  contract: OrigamiMorphoBorrowAndLend | OrigamiLovTokenFlashAndBorrowManager,
  swapper: string,
) {
  return createSafeTransaction(
    contract.address,
    "setSwapper",
    [
      {
        argType: "address",
        name: "_swapper",
        value: swapper,
      },
    ],
  )
}

async function updateSwappersSafeBatch() {
  const batch = createSafeBatch(
    1,
    swapperMappings().map(mapping => setSwapperFunction(mapping.contract, mapping.swapper)),
  );

  const filename = path.join(__dirname, "../transactions-batch.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  ADDRS = await getDeployedContracts1(__dirname);
  INSTANCES = connectToContracts1(owner, ADDRS);

  await mine(INSTANCES.SWAPPERS.DIRECT_SWAPPER.whitelistRouter(ADDRS.EXTERNAL.ONE_INCH.ROUTER_V6, true));
  await mine(INSTANCES.SWAPPERS.DIRECT_SWAPPER.whitelistRouter(ADDRS.EXTERNAL.PENDLE.ROUTER, true));
  await mine(INSTANCES.SWAPPERS.SUSDE_SWAPPER.whitelistRouter(ADDRS.EXTERNAL.ONE_INCH.ROUTER_V6, true));

  if (network.name === "localhost") {
    const signer = await impersonateAndFund(owner, ADDRS.CORE.MULTISIG);
    await updateSwappers(signer);
  } else {
    await updateSwappersSafeBatch();
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
