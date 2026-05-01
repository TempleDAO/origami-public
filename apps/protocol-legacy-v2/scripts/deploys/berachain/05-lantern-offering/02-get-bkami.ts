import { BigNumber, ethers } from "ethers";
import { runAsyncMain } from "../../helpers";
import * as fs from 'fs';
import path from "path";

// Boyco Points
const abi = [
  "event Award(address indexed to, uint256 indexed amount, address indexed awardedBy)",
];

// bKAMI Contract address on mainnet
const contractAddress = "0xCfFE9112BfA141aE9170BE4d172d40a455662564";

// Define block range
const fromBlock: number = 21618506;
const toBlock: number | "latest" = 21723937; // One block past the last Award

async function main() {
  
  const iface = new ethers.utils.Interface(abi);
  
  const provider = new ethers.providers.JsonRpcBatchProvider(process.env.MAINNET_RPC_URL);
  const filter: ethers.providers.Filter = {
    address: contractAddress,
    fromBlock,
    toBlock,
    topics: [iface.getEventTopic("Award")],
  };

  const awards = new Map<string, BigNumber>(); 
  let totalAwarded: BigNumber = BigNumber.from(0);
  try {
    const logs: ethers.providers.Log[] = await provider.getLogs(filter);

    for (const log of logs) {
      try {
        const parsed = iface.parseLog(log);
        const to: string = parsed.args['to'];
        let amount: BigNumber = parsed.args['amount'];
        if (amount.isZero()) continue;
        totalAwarded = totalAwarded.add(amount);

        const existing = awards.get(to);
        if (existing) amount = amount.add(existing);
        awards.set(to, amount);
      } catch (err) {
        console.log(err);
        console.warn("⚠️ Could not decode log:", log);
      }
    }
  } catch (err) {
    console.error("❌ Error fetching logs:", err);
  }

  fs.writeFileSync(
    path.join(__dirname, "./bkami.json"),
    JSON.stringify(Object.fromEntries(awards), null, 2)
  );
  console.log("Wrote events to bkami.json");
  console.log("------")
  console.log(`Awarded ${ethers.utils.formatEther(totalAwarded)} over ${awards.size} accounts`);
}

runAsyncMain(main);
