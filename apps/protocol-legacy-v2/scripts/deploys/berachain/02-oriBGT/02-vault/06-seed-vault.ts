import "@nomiclabs/hardhat-ethers";
import { ethers, network } from "hardhat";
import { impersonateAndFund, mine, runAsyncMain } from "../../../helpers";
import { ContractInstances } from "../../contract-addresses";
import { DEFAULT_SETTINGS } from "../../default-settings";
import { getDeployContext } from "../../deploy-context";
import { BigNumber } from "ethers";

const IMPERSONATE_SEED_WHALE = "0x182a31A27A0D39d735b31e80534CFE1fCd92c38f";

async function seedDeposit(
  INSTANCES: ContractInstances,
  amountBN: BigNumber,
  accountAddress: string,
  maxSupply: BigNumber
) {
  const vault = INSTANCES.VAULTS.ORIBGT.TOKEN;
  const vaultDecimals = await vault.decimals();
  const depositToken = INSTANCES.EXTERNAL.INFRARED.IBGT_TOKEN;
  const depositTokenDecimals = await depositToken.decimals();

  console.log("\nseedDeposit(%f, %s, %f)", amountBN, accountAddress, maxSupply);

  console.log(
    "\tdeposit token balance:",
    ethers.utils.formatUnits(
      await depositToken.balanceOf(accountAddress),
      depositTokenDecimals
    )
  );
  await mine(depositToken.approve(vault.address, amountBN));

  const expectedShares = await vault.previewDeposit(amountBN);

  console.log(
    "\tExpect Shares:",
    ethers.utils.formatUnits(expectedShares, vaultDecimals)
  );
  await mine(vault.seedDeposit(amountBN, accountAddress, maxSupply));

  console.log(
    "\tAccount balance of vault:",
    ethers.utils.formatUnits(
      await vault.balanceOf(accountAddress),
      vaultDecimals
    )
  );
  console.log(
    "\tmaxTotalSupply of vault:",
    ethers.utils.formatUnits(await vault.maxTotalSupply(), vaultDecimals)
  );
}

async function main() {
  const { owner, INSTANCES } = await getDeployContext(__dirname);

  if (network.name === "localhost") {
    const signer = await impersonateAndFund(owner, IMPERSONATE_SEED_WHALE);
    await mine(
      INSTANCES.EXTERNAL.INFRARED.IBGT_TOKEN.connect(signer).transfer(
        owner.getAddress(),
        DEFAULT_SETTINGS.VAULTS.ORIBGT.SEED_DEPOSIT_SIZE
      )
    );
  }

  await seedDeposit(
    INSTANCES,
    DEFAULT_SETTINGS.VAULTS.ORIBGT.SEED_DEPOSIT_SIZE,
    await owner.getAddress(),
    DEFAULT_SETTINGS.VAULTS.ORIBGT.MAX_TOTAL_SUPPLY
  );
}

runAsyncMain(main);
