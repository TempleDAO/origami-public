import "@nomiclabs/hardhat-ethers";
import { runAsyncMain } from "../../../helpers";
import path from "path";
import {
  createSafeBatch,
  setExplicitAccess,
  writeSafeTransactionsBatch,
} from "../../../safe-tx-builder";
import { getDeployContext } from "../../deploy-context";
import { OrigamiMorphoBorrowAndLend__factory } from "../../../../../typechain";
import { ethers } from "hardhat";

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const MORPHO_FUNCTIONS = [
    "recoverToken(address,address,uint256)",
    "supply(uint256)"
  ];

  const [owner] = await ethers.getSigners();

  const batch = createSafeBatch([
    setExplicitAccess(
      INSTANCES.LOV_SUSDE_A.MORPHO_BORROW_LEND,
      ADDRS.LOV_SUSDE_A.OVERLORD_WALLET,
      MORPHO_FUNCTIONS,
      true
    ),
    setExplicitAccess(
      INSTANCES.LOV_SUSDE_B.MORPHO_BORROW_LEND,
      ADDRS.LOV_SUSDE_B.OVERLORD_WALLET, 
      MORPHO_FUNCTIONS,
      true
    ),
    setExplicitAccess(
      INSTANCES.LOV_USDE_B.MORPHO_BORROW_LEND,
      ADDRS.LOV_USDE_B.OVERLORD_WALLET,
      MORPHO_FUNCTIONS,
      true
    ),
    setExplicitAccess(
      INSTANCES.LOV_WEETH_A.MORPHO_BORROW_LEND,
      ADDRS.LOV_WEETH_A.OVERLORD_WALLET,
      MORPHO_FUNCTIONS,
      true
    ),
    setExplicitAccess(
      INSTANCES.LOV_WOETH_A.MORPHO_BORROW_LEND,
      ADDRS.LOV_WOETH_A.OVERLORD_WALLET,
      MORPHO_FUNCTIONS,
      true
    ),
    setExplicitAccess(
      INSTANCES.LOV_PT_SUSDE_MAR_2025_A.MORPHO_BORROW_LEND,
      ADDRS.LOV_PT_SUSDE_MAR_2025_A.OVERLORD_WALLET,
      MORPHO_FUNCTIONS,
      true
    ),
    setExplicitAccess(
      INSTANCES.LOV_SDAI_A.MORPHO_BORROW_LEND,
      ADDRS.LOV_SDAI_A.OVERLORD_WALLET,
      MORPHO_FUNCTIONS,
      true
    ),
    setExplicitAccess(
      INSTANCES.LOV_USD0pp_A.MORPHO_BORROW_LEND,
      ADDRS.LOV_USD0pp_A.OVERLORD_WALLET,
      MORPHO_FUNCTIONS,
      true
    ),
    setExplicitAccess(
      INSTANCES.LOV_RSWETH_A.MORPHO_BORROW_LEND,
      ADDRS.LOV_RSWETH_A.OVERLORD_WALLET,
      MORPHO_FUNCTIONS,
      true
    ),
    setExplicitAccess(
      INSTANCES.LOV_PT_USD0pp_MAR_2025_A.MORPHO_BORROW_LEND,
      ADDRS.LOV_PT_USD0pp_MAR_2025_A.OVERLORD_WALLET,
      MORPHO_FUNCTIONS,
      true
    ),
    setExplicitAccess(
      INSTANCES.LOV_PT_LBTC_MAR_2025_A.MORPHO_BORROW_LEND,
      ADDRS.LOV_PT_LBTC_MAR_2025_A.OVERLORD_WALLET,
      MORPHO_FUNCTIONS,
      true
    ),
    // LOV_SDAI_A has a legacy morpho market that had points
    setExplicitAccess(
      OrigamiMorphoBorrowAndLend__factory.connect('0xDF3D394669Fe433713D170c6DE85f02E260c1c34', owner),
      ADDRS.LOV_SDAI_A.OVERLORD_WALLET,
      MORPHO_FUNCTIONS,
      true
    )
  ]);

  const filename = path.join(__dirname, "../transactions-batch.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

runAsyncMain(main);
