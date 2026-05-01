
import "@nomiclabs/hardhat-ethers";
import { impersonateAndFund2, runAsyncMain } from "../../../helpers";
import { getDeployContext } from "../../deploy-context";
import { OpalAdapterBase__factory } from "../../../../../typechain";
import { removeAdapter, removeAdapterBatch } from "../../../opal-utils";
import { network } from "hardhat";
import path from "path";
import { BigNumber } from "ethers";

async function main() {
  const { owner, ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const opalVault = INSTANCES.VAULTS.OPAL_PT_SUSDE_PLASMA_A;
  const adapter = OpalAdapterBase__factory.connect(ADDRS.VAULTS.OPAL_PT_SUSDE_PLASMA_A.ADAPTER_INSTANCES["AAVE_V3.1: [PT-sUSDE-9APR2026]/[USDT0]"], owner);

  if (network.name == 'localhost') {
    const managerOwner = await impersonateAndFund2(await opalVault.MANAGER.owner());
    const adapterOwner = await impersonateAndFund2(await adapter.owner());
    await removeAdapter(
      opalVault.MANAGER.connect(managerOwner),
      adapter.connect(adapterOwner),
    );
  } else {
    const bs = await adapter.balanceSheet();
    const nonZeroAssets = bs.assets.filter((v: BigNumber) => !v.isZero());
    const nonZeroLiabilities = bs.liabilities.filter((v: BigNumber) => !v.isZero());
    if (nonZeroAssets.length > 0 || nonZeroLiabilities.length > 0) throw new Error("Adapter balances > 0");

    removeAdapterBatch(
      path.join(__dirname, "../02-remove-adapter.json"),
      opalVault.MANAGER,
      adapter,
    )
  }
}

runAsyncMain(main);
