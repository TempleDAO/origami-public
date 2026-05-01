import { ethers } from "ethers";
import { mine, runAsyncMain } from "../../../helpers";
import { getDeployContext } from "../../deploy-context";
import { DummyDexRouter__factory } from "../../../../../typechain";

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  // const sUsdsAmount = ethers.utils.parseEther("3333");
  // const hOhmAmount = ethers.utils.parseEther("303000");

  const sUsdsAmount = await INSTANCES.EXTERNAL.SKY.SUSDS_TOKEN.balanceOf(ADDRS.VAULTS.hOHM.MANAGER);
  console.log("sUsdsBalance:", ethers.utils.formatEther(sUsdsAmount));
  const hOhmAmount = sUsdsAmount.mul(ethers.utils.parseEther("1")).div(ethers.utils.parseEther("0.011"));
  console.log("hOhmAmount", ethers.utils.formatEther(hOhmAmount));

  const routerIface = new ethers.utils.Interface(JSON.stringify(DummyDexRouter__factory.abi));
  const routerData = routerIface.encodeFunctionData("doExactSwap", ([
    ADDRS.EXTERNAL.SKY.SUSDS_TOKEN,
    sUsdsAmount.toString(),
    ADDRS.VAULTS.hOHM.TOKEN,
    hOhmAmount.toString()
  ]));

  const swapperData = ethers.utils.defaultAbiCoder.encode(
    ['tuple(address router, uint256 minBuyAmount, address receiver, bytes data)'],
    [{
      router: ADDRS.VAULTS.hOHM.DUMMY_DEX_ROUTER,
      minBuyAmount: hOhmAmount.toString(), 
      receiver: ADDRS.VAULTS.hOHM.MANAGER, 
      data: routerData
    }]
  )

  await mine(
    INSTANCES.VAULTS.hOHM.MANAGER.sweep(sUsdsAmount, swapperData)
  );
}

runAsyncMain(main);
