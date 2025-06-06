


import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
    blockTimestamp,
  ensureExpectedEnvvars,
} from '../../helpers';
import * as fs from 'fs';

async function main() {
  ensureExpectedEnvvars();
  
  const snapshotFilename = process.env["ANVIL_SNAPSHOT_PATH"];
  if (!snapshotFilename) {
    throw new Error(`Expected envvar ANVIL_SNAPSHOT_PATH missing`);
  }

  const blockBefore = await ethers.provider.getBlockNumber();
  const tsBefore = await blockTimestamp();
  console.log("#BLOCK BEFORE:", blockBefore);
  console.log("BLOCK TIMESTAMP BEFORE:", tsBefore);

  // Load the state
  {
    let contents = fs
        .readFileSync(snapshotFilename,'utf8')
        .trim();
    contents = contents.slice(1, contents.length-1); 
    await ethers.provider.send("anvil_loadState", [contents]);
  }

  // Update the block timestamp based on 1 second per nonce
  // Anvil doesn't do this automatically
  {
    const blockAfter = await ethers.provider.getBlockNumber();
    const newTs = tsBefore + blockAfter - blockBefore;
    if (newTs > tsBefore) {
        await ethers.provider.send("evm_setNextBlockTimestamp", [newTs]);
    }
    await ethers.provider.send("anvil_mine", [1]);
  }

  console.log("#BLOCK AFTER:", await ethers.provider.getBlockNumber());
  console.log("BLOCK TIMESTAMP AFTER:", await blockTimestamp());
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
