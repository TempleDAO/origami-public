import "@nomiclabs/hardhat-ethers";
import { OrigamiCowSwapper__factory } from "../../../../typechain";
import { deployAndMine, runAsyncMain } from "../../helpers";
import { getDeployContext } from "../deploy-context";

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiCowSwapper__factory(owner);
  await deployAndMine(
    "VAULTS.SUSDSpS.COW_SWAPPER_3",
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.COW_SWAP.VAULT_RELAYER,
    ADDRS.EXTERNAL.COW_SWAP.SETTLEMENT,
  );
}

runAsyncMain(main);
