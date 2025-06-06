import { BigNumber, ethers } from "ethers";
import { runAsyncMain } from "../../helpers";
import * as fs from 'fs';
import path from "path";
import { getDeployContext } from "../deploy-context";

// Festival Offering
const abi = [
  "event OfferingMade(address indexed account, uint256 amount)",
];

// Define block range
const earliestBlock: number = 4633170; // 4323139;
const latestBlock: number = 4955881;
const BKAMI_TO_USDC = ethers.utils.parseEther("0.012");
const ONE_ETHER = ethers.utils.parseEther("1");
const blockPerQuery = 10_000;

async function main() {
  const { ADDRS } = await getDeployContext(__dirname);

  const iface = new ethers.utils.Interface(abi);
  const provider = new ethers.providers.JsonRpcBatchProvider(process.env.BERACHAIN_RPC_URL);

  let fromBlock = earliestBlock;
  let toBlock = fromBlock + blockPerQuery;
  let totalFullPrecision: BigNumber = BigNumber.from(0);
  let totalUsdc: BigNumber = BigNumber.from(0);

  // Formatting for the Gnosis Safe 'csv airdrop' app
  const lines: string[] = ["token_type,token_address,receiver,amount,id"];
  while (true) {
    const tBlock = toBlock > latestBlock ? latestBlock : toBlock;
    console.log(`Checking blocks ${fromBlock} => ${tBlock}`);
    const filter: ethers.providers.Filter = {
      address: ADDRS.PERIPHERY.LANTERN_OFFERING,
      fromBlock,
      toBlock: tBlock,
      topics: [iface.getEventTopic("OfferingMade")],
    };

    try {
      const logs: ethers.providers.Log[] = await provider.getLogs(filter);
      for (const log of logs) {
        try {
          const parsed = iface.parseLog(log);
          const account: string = parsed.args['account'];
          const amount: BigNumber = parsed.args['amount'];
          totalFullPrecision = totalFullPrecision.add(amount);

          const usdcEther = amount.mul(BKAMI_TO_USDC).div(ONE_ETHER);

          const amountUsdc10 = usdcEther.div(ethers.utils.parseUnits("1", 11));
          const amountUsdcRoundUp = (!amountUsdc10.toString().endsWith("0"))
            ? amountUsdc10.div(10).add(1)
            : amountUsdc10.div(10);
          totalUsdc = totalUsdc.add(amountUsdcRoundUp);
          console.log(account, amount.toString(), amountUsdc10.toString(), amountUsdcRoundUp.toString());
          lines.push(`erc20,${ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN},${account},${ethers.utils.formatUnits(amountUsdcRoundUp,6)},`);
        } catch (err) {
          console.log(err);
          console.warn("⚠️ Could not decode log:", log);
        }
      }
    } catch (err) {
      console.error("❌ Error fetching logs:", err);
    }

    if (toBlock >= latestBlock) break;

    fromBlock = toBlock + 1;
    toBlock = fromBlock + blockPerQuery;
  }

  console.log("TOTAL bKAMI (full precision):", ethers.utils.formatEther(totalFullPrecision));
  console.log("TOTAL USDC (round up):", ethers.utils.formatUnits(totalUsdc, 6));
  fs.writeFileSync(
    path.join(__dirname, "./airdrop.csv"),
    lines.join("\n")
  );
}

runAsyncMain(main);
