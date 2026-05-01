import '@nomiclabs/hardhat-ethers';
import { deployAndMine, mine, runAsyncMain, setExplicitAccess } from '../../helpers';
import { getDeployContext } from '../deploy-context';
import { IERC20Metadata__factory, OrigamiSwapperWithLiquidityManagement, OrigamiSwapperWithLiquidityManagement__factory } from '../../../../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ContractAddresses, InfraredAutoCompounderVault } from '../contract-addresses/types';
import { acceptOwner, createSafeBatch, createSafeTransaction, writeSafeTransactionsBatch } from '../../safe-tx-builder';
import path from 'path';

let OWNER: SignerWithAddress;
let ADDRS: ContractAddresses;

const OLD_SWAPPERS = {
  INFRARED_AUTO_COMPOUNDER_OHM_HONEY_A: {
    SWAPPER: '0x88A3D5D74B0F666B384445aF5D5e67bfE2E18A9d'
  },
  INFRARED_AUTO_COMPOUNDER_BYUSD_HONEY_A: {
    SWAPPER: '0x23c5E239D689FcA690b5062fBA7677ab367cD7F9'
  },
  INFRARED_AUTO_COMPOUNDER_RUSD_HONEY_A: {
    SWAPPER: '0x3BEcD87c3fa5BC22786ae0795F93a47aeFC00810'
  },
  INFRARED_AUTO_COMPOUNDER_WBERA_IBERA_A: {
    SWAPPER: '0x4322a7FD41A8AdF5cf681aF3791e762a5753B498'
  },
  INFRARED_AUTO_COMPOUNDER_WBERA_HONEY_A: {
    SWAPPER: '0x364b4fAe190AD428364E179590b4d0384bEd0a03'
  },
  INFRARED_AUTO_COMPOUNDER_WBERA_IBGT_A: {
    SWAPPER: '0x312F1CE9e3Ebc1a4069490c8A9A62A04b562EE71'
  },
}

async function deploySwapper(key: string, vaultAddrs: InfraredAutoCompounderVault, lpRouterAddr: string) {
  const factory = new OrigamiSwapperWithLiquidityManagement__factory(OWNER);
  const oldSwapper = OrigamiSwapperWithLiquidityManagement__factory.connect(vaultAddrs.SWAPPER, OWNER);
  const newSwapper = await deployAndMine(
    key, 
    factory, 
    factory.deploy,
    await OWNER.getAddress(),
    await oldSwapper.lpToken()
  ) as OrigamiSwapperWithLiquidityManagement;

  await setExplicitAccess(newSwapper, vaultAddrs.OVERLORD_WALLET, ['execute', 'addLiquidity'], true);
  await mine(newSwapper.whitelistRouter(ADDRS.EXTERNAL.OOGABOOGA.ROUTER, true));
  await mine(newSwapper.whitelistRouter(lpRouterAddr, true));
  await mine(newSwapper.proposeNewOwner(ADDRS.CORE.MULTISIG));
}

async function recoverToken(
  oldSwapperAddr: string,
  token: string,
  newSwapper: string,
) {
  const oldSwapper = OrigamiSwapperWithLiquidityManagement__factory.connect(oldSwapperAddr, OWNER);
  const tkn = IERC20Metadata__factory.connect(token, OWNER);
  const balance = await tkn.balanceOf(oldSwapper.address);
  console.log(`recovering ${balance.toString()} of ${token} from ${oldSwapperAddr} to ${newSwapper}`);
  return createSafeTransaction(
    oldSwapper.address, 
    "recoverToken", 
    [
      {
        argType: "address",
        name: "token",
        value: token,
      },
      {
        argType: "address",
        name: "to",
        value: newSwapper,
      },
      {
        argType: "uint256",
        name: "amount",
        value: balance.toString(),
      },
    ]
  );
}

function setSwapper(vaultAddrs: InfraredAutoCompounderVault) {
  return createSafeTransaction(
    vaultAddrs.MANAGER, 
    "setSwapper", 
    [
      {
        argType: "address",
        name: "_swapper",
        value: vaultAddrs.SWAPPER,
      },
    ]
  );
}

async function phase1() {
  await deploySwapper("VAULTS.INFRARED_AUTO_COMPOUNDER_OHM_HONEY_A.SWAPPER", ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_OHM_HONEY_A, ADDRS.EXTERNAL.KODIAK.ISLAND_ROUTER);
  await deploySwapper("VAULTS.INFRARED_AUTO_COMPOUNDER_BYUSD_HONEY_A.SWAPPER", ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_BYUSD_HONEY_A, ADDRS.EXTERNAL.BEX.BALANCER_VAULT);
  await deploySwapper("VAULTS.INFRARED_AUTO_COMPOUNDER_RUSD_HONEY_A.SWAPPER", ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_RUSD_HONEY_A, ADDRS.EXTERNAL.KODIAK.ISLAND_ROUTER);
  await deploySwapper("VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_IBERA_A.SWAPPER", ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_IBERA_A, ADDRS.EXTERNAL.KODIAK.ISLAND_ROUTER);
  await deploySwapper("VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_HONEY_A.SWAPPER", ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_HONEY_A, ADDRS.EXTERNAL.KODIAK.ISLAND_ROUTER);
  await deploySwapper("VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_IBGT_A.SWAPPER", ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_IBGT_A, ADDRS.EXTERNAL.KODIAK.ISLAND_ROUTER);
}

async function phase2() {
  const recoverCommands = [
    await recoverToken(OLD_SWAPPERS.INFRARED_AUTO_COMPOUNDER_OHM_HONEY_A.SWAPPER, ADDRS.EXTERNAL.INFRARED.IBGT_TOKEN, ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_OHM_HONEY_A.SWAPPER),
    await recoverToken(OLD_SWAPPERS.INFRARED_AUTO_COMPOUNDER_OHM_HONEY_A.SWAPPER, ADDRS.EXTERNAL.OLYMPUS.OHM_TOKEN, ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_OHM_HONEY_A.SWAPPER),
    await recoverToken(OLD_SWAPPERS.INFRARED_AUTO_COMPOUNDER_OHM_HONEY_A.SWAPPER, ADDRS.EXTERNAL.BERACHAIN.HONEY_TOKEN, ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_OHM_HONEY_A.SWAPPER),

    await recoverToken(OLD_SWAPPERS.INFRARED_AUTO_COMPOUNDER_RUSD_HONEY_A.SWAPPER, ADDRS.EXTERNAL.BERACHAIN.HONEY_TOKEN, ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_RUSD_HONEY_A.SWAPPER),

    await recoverToken(OLD_SWAPPERS.INFRARED_AUTO_COMPOUNDER_WBERA_IBERA_A.SWAPPER, ADDRS.EXTERNAL.BERACHAIN.WBERA_TOKEN, ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_IBERA_A.SWAPPER),

    await recoverToken(OLD_SWAPPERS.INFRARED_AUTO_COMPOUNDER_WBERA_HONEY_A.SWAPPER, ADDRS.EXTERNAL.BERACHAIN.HONEY_TOKEN, ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_HONEY_A.SWAPPER),
    await recoverToken(OLD_SWAPPERS.INFRARED_AUTO_COMPOUNDER_WBERA_HONEY_A.SWAPPER, ADDRS.EXTERNAL.BERACHAIN.WBERA_TOKEN, ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_HONEY_A.SWAPPER),

    await recoverToken(OLD_SWAPPERS.INFRARED_AUTO_COMPOUNDER_WBERA_IBGT_A.SWAPPER, ADDRS.EXTERNAL.BERACHAIN.WBERA_TOKEN, ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_IBGT_A.SWAPPER),
    await recoverToken(OLD_SWAPPERS.INFRARED_AUTO_COMPOUNDER_WBERA_IBGT_A.SWAPPER, ADDRS.EXTERNAL.INFRARED.IBGT_TOKEN, ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_IBGT_A.SWAPPER),
  ];

  const setSwapperCommands = [
    setSwapper(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_OHM_HONEY_A),
    setSwapper(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_BYUSD_HONEY_A),
    setSwapper(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_RUSD_HONEY_A),
    setSwapper(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_IBERA_A),
    setSwapper(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_HONEY_A),
    setSwapper(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_IBGT_A),
  ]

  const claimOwnershipCommands = [
    acceptOwner(OrigamiSwapperWithLiquidityManagement__factory.connect(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_OHM_HONEY_A.SWAPPER, OWNER)),
    acceptOwner(OrigamiSwapperWithLiquidityManagement__factory.connect(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_BYUSD_HONEY_A.SWAPPER, OWNER)),
    acceptOwner(OrigamiSwapperWithLiquidityManagement__factory.connect(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_RUSD_HONEY_A.SWAPPER, OWNER)),
    acceptOwner(OrigamiSwapperWithLiquidityManagement__factory.connect(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_IBERA_A.SWAPPER, OWNER)),
    acceptOwner(OrigamiSwapperWithLiquidityManagement__factory.connect(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_HONEY_A.SWAPPER, OWNER)),
    acceptOwner(OrigamiSwapperWithLiquidityManagement__factory.connect(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_IBGT_A.SWAPPER, OWNER)),
  ];

    const batch = createSafeBatch(
      [
        ...recoverCommands,
        ...setSwapperCommands,
        ...claimOwnershipCommands,
      ],
    );
    
    const filename = path.join(__dirname, "./upgrade-swapper-batch.json");
    writeSafeTransactionsBatch(batch, filename);
    console.log(`Wrote Safe tx's batch to: ${filename}`);
}

async function main() {
  ({ owner: OWNER, ADDRS } = await getDeployContext(__dirname));

  // Run phase 1 first, then phase 2 after contracts have been updated and verified
  // await phase1();
  await phase2();
}

runAsyncMain(main);
