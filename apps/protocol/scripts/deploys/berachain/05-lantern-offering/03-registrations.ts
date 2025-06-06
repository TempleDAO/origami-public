import '@nomiclabs/hardhat-ethers';
import { OrigamiLanternOffering__factory } from '../../../../typechain';
import { mine, runAsyncMain } from '../../helpers';
import { getDeployContext } from '../deploy-context';
import * as fs from 'fs';
import path from 'path';
import { BigNumber } from 'ethers';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  // Load in registrations from file
  const bkami: {[key: string]: BigNumber} = JSON.parse(fs.readFileSync(path.join(__dirname, "./bkami.json"), 'utf-8'));
  const registrations = Object.entries(bkami).map((v) => ({account: v[0], amount: BigNumber.from(v[1])}));
  const lanternFest = OrigamiLanternOffering__factory.connect(ADDRS.PERIPHERY.LANTERN_OFFERING, owner);

  // Chunk tx's into 100 addresses at a time since the gas amount is high
  const chunkSize = 100;
  for (let i = 0; i < registrations.length; i += chunkSize) {
    console.log(`\tregistering chunk: ${i}-${i+chunkSize}`);
    const chunk = registrations.slice(i, i + chunkSize);

    // Get the encoded calldata for each chunk and register
    const data = await lanternFest.batchRegisterInputs(chunk);
    await mine(lanternFest.batchRegister(data));
  }

  console.log("Total Registered:", await lanternFest.totalSupply());
  console.log("Total Offered:", await lanternFest.totalOffered());
}

runAsyncMain(main);
