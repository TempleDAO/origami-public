
import '@nomiclabs/hardhat-ethers';
import {
  mine,
  runAsyncMain,
} from '../../helpers';
import { getDeployContext } from '../deploy-context';
import { ethers } from 'ethers';
import { IERC20Metadata__factory } from '../../../../typechain';

async function main() {
  const { owner, ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const amount = ethers.utils.parseEther("2");
  await mine(INSTANCES.EXTERNAL.BERACHAIN.WBERA_TOKEN.deposit({value: amount}));

  const wberaAsErc20 = IERC20Metadata__factory.connect(ADDRS.EXTERNAL.BERACHAIN.WBERA_TOKEN, owner);
  await mine(wberaAsErc20.approve(ADDRS.EXTERNAL.BEX.BALANCER_VAULT, amount));

  await mine(INSTANCES.EXTERNAL.BEX.BALANCER_VAULT.swap(
    {
        // 80WBERA-20USDC-WEIGHTED
        // https://80000.testnet.routescan.io/token/0x4f9D20770732F10dF42921EFfA62eb843920a48A
        poolId: '0x4f9d20770732f10df42921effa62eb843920a48a00020000000000000000000a',
        kind: 0, // GIVEN_IN
        assetIn: ADDRS.EXTERNAL.BERACHAIN.WBERA_TOKEN,
        assetOut: ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
        amount: amount,
        userData: "0x"
    },
    {
        sender: await owner.getAddress(),
        fromInternalBalance: false,
        recipient: await owner.getAddress(),
        toInternalBalance: false,
    },
    1,
    parseInt((Date.now() / 1000).toFixed(0)) + 86_400
  ));

  const usdcBalance = await INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.balanceOf(await owner.getAddress());
  console.log("USDC Balance:", ethers.utils.formatUnits(usdcBalance, 6));
}

runAsyncMain(main);
