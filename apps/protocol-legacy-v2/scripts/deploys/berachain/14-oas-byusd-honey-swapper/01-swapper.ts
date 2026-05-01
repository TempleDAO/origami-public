import "@nomiclabs/hardhat-ethers";
import { OrigamiSwapperWithCallback__factory } from "../../../../typechain";
import { deployAndMine, runAsyncMain } from "../../helpers";
import { getDeployContext } from "../deploy-context";

async function main() {
  const { owner } = await getDeployContext(__dirname);

  const factory = new OrigamiSwapperWithCallback__factory(owner);
  await deployAndMine(
    "VAULTS.INFRARED_AUTO_STAKING_BYUSD_HONEY_A.SWAPPER",
    factory,
    factory.deploy,
    await owner.getAddress(),
  );
}

runAsyncMain(main);
