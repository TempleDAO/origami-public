import "@nomiclabs/hardhat-ethers";
import { ethers } from "hardhat";
import { blockTimestamp, ensureExpectedEnvvars, impersonateAndFund, mine } from "../../../helpers";
import { ContractInstances, connectToContracts1, getDeployedContracts1 } from "../../contract-addresses";
import { BigNumber } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ContractAddresses } from "../../contract-addresses/types";
import { 
    IERC20Metadata, 
    OrigamiSuperSavingsUsdsManager, OrigamiSuperSavingsUsdsVault } from "../../../../../typechain";
import { DEFAULT_SETTINGS } from "../../default-settings";

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

const DEPOSIT_TOKEN_WHALE = "0x4292956942489BA02322330739f45aF01Bb33bfA";
const DEPOSIT_AMOUNT = "1000"; // USDS

interface TestContracts {
  DEPOSIT_TOKEN: IERC20Metadata;
  VAULT_TOKEN: OrigamiSuperSavingsUsdsVault;
  DEPOSIT_TOKEN_DECIMALS: number;
  VAULT_TOKEN_DECIMALS: number;
  MANAGER: OrigamiSuperSavingsUsdsManager;
  FARM_REWARDS_TOKEN: IERC20Metadata;
}
let TEST_CONTRACTS: TestContracts;

const getContracts = async (): Promise<TestContracts> => ({
  DEPOSIT_TOKEN: INSTANCES.EXTERNAL.SKY.USDS_TOKEN,
  DEPOSIT_TOKEN_DECIMALS: await INSTANCES.EXTERNAL.SKY.USDS_TOKEN.decimals(),
  VAULT_TOKEN: INSTANCES.VAULTS.SUSDSpS.TOKEN,
  VAULT_TOKEN_DECIMALS: await INSTANCES.VAULTS.SUSDSpS.TOKEN.decimals(),
  MANAGER: INSTANCES.VAULTS.SUSDSpS.MANAGER,
  FARM_REWARDS_TOKEN: INSTANCES.EXTERNAL.SKY.SKY_TOKEN,
});

async function dumpPrices() {
  const prices = await INSTANCES.CORE.TOKEN_PRICES.V3.tokenPrices([
    ADDRS.EXTERNAL.SKY.USDS_TOKEN,
    ADDRS.EXTERNAL.SKY.SUSDS_TOKEN,
    // ADDRS.EXTERNAL.SKY.SKY_TOKEN,
    ADDRS.VAULTS.SUSDSpS.TOKEN,
  ]);
  console.log("Token Prices:");
  console.log("\tUSDS:", ethers.utils.formatUnits(prices[0], 30));
  console.log("\tsUSDS:", ethers.utils.formatUnits(prices[1], 30));
//   console.log("\tSKY:", ethers.utils.formatUnits(prices[2], 30));
  console.log("\tsUSDS+s:", ethers.utils.formatUnits(prices[2], 30));
}

async function deposit(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  console.log("\ndeposit(%f, %s)", amountBN, await account.getAddress());

  await mine(
    TEST_CONTRACTS.DEPOSIT_TOKEN.transfer(account.getAddress(), amountBN)
  );

  console.log("\tdeposit token balance:", ethers.utils.formatUnits(
    await TEST_CONTRACTS.DEPOSIT_TOKEN.balanceOf(account.getAddress()),
    TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS
  ));
  await mine(
    TEST_CONTRACTS.DEPOSIT_TOKEN.connect(account).approve(
      TEST_CONTRACTS.VAULT_TOKEN.address,
      amountBN
    )
  );

  const expectedShares = await TEST_CONTRACTS.VAULT_TOKEN.previewDeposit(amountBN);

  console.log("\tExpect:", ethers.utils.formatUnits(
    expectedShares,
    TEST_CONTRACTS.VAULT_TOKEN_DECIMALS,
  ));
  await mine(
    TEST_CONTRACTS.VAULT_TOKEN.connect(account).deposit(
        amountBN,
        await account.getAddress(),
    )
  );

  console.log("\tAccount balance of vault:", ethers.utils.formatUnits(
    await TEST_CONTRACTS.VAULT_TOKEN.balanceOf(account.getAddress()),
    TEST_CONTRACTS.VAULT_TOKEN_DECIMALS,
  ));
}

async function redeem(
  account: SignerWithAddress,
  amountBN: BigNumber
) {
  const userAddress = await account.getAddress();
  console.log("\nredeem(%f, %s, %s)", amountBN, userAddress, userAddress);

  console.log("\tBefore:");
  console.log("\t\tAccount balance of vault:", ethers.utils.formatUnits(
    await TEST_CONTRACTS.VAULT_TOKEN.balanceOf(account.getAddress()),
    TEST_CONTRACTS.VAULT_TOKEN_DECIMALS
  ));
  console.log("\t\tAccount balance of deposit token:", ethers.utils.formatUnits(
    await TEST_CONTRACTS.DEPOSIT_TOKEN.balanceOf(account.getAddress()),
    TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS
  ));

  const expectedAssets = await TEST_CONTRACTS.VAULT_TOKEN.previewRedeem(amountBN);

  console.log("\tExpect:", ethers.utils.formatUnits(
    expectedAssets,
    TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS,
  ));
  await mine(
    TEST_CONTRACTS.VAULT_TOKEN.connect(account).redeem(
      amountBN,
      userAddress,
      userAddress
    )
  );

  console.log("\tAfter:");
  console.log("\t\tAccount balance of vault:", ethers.utils.formatUnits(
    await TEST_CONTRACTS.VAULT_TOKEN.balanceOf(userAddress),
    TEST_CONTRACTS.VAULT_TOKEN_DECIMALS
  ));
  console.log("\t\tAccount balance of deposit token:", ethers.utils.formatUnits(
    await TEST_CONTRACTS.DEPOSIT_TOKEN.balanceOf(userAddress),
    TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS
  ));

  console.log("\t\tmaxRedeem afterwards:", ethers.utils.formatUnits(
    await TEST_CONTRACTS.VAULT_TOKEN.maxRedeem(userAddress),
    TEST_CONTRACTS.VAULT_TOKEN_DECIMALS,
  ));
}

async function getDepositTokens(owner: SignerWithAddress, amount: BigNumber) {
  const signer = await impersonateAndFund(owner, DEPOSIT_TOKEN_WHALE);
  await mine(TEST_CONTRACTS.DEPOSIT_TOKEN.connect(signer).transfer(owner.getAddress(), amount));
}

async function dumpFarms() {
    console.log("===== FARMS ======");
    const numFarms = await TEST_CONTRACTS.MANAGER.maxFarmIndex();
    for (let i=0; i <= numFarms; ++i) {
        const details = await TEST_CONTRACTS.MANAGER.farmDetails(i);
        console.log("FARM ", i);
        console.log("farm.staking:", details.farm.staking);
        console.log("farm.rewardsToken:", details.farm.rewardsToken);
        console.log("farm.referral:", details.farm.referral);
        console.log("stakedBalance:", ethers.utils.formatEther(details.stakedBalance));
        console.log("totalSupply:", ethers.utils.formatEther(details.totalSupply));
        console.log("rewardRate:", ethers.utils.formatEther(details.rewardRate));
        console.log("unclaimedRewards:", ethers.utils.formatEther(details.unclaimedRewards));
        console.log("------");
    }
    console.log("==================");
}

async function switchFarms(index: number) {
    console.log("Switching to farm:", index);
    await TEST_CONTRACTS.MANAGER.switchFarms(index)
}

async function anvilMineForwardSeconds(secs: number) {
    await ethers.provider.send("evm_setNextBlockTimestamp", [
        (await blockTimestamp()) + secs
    ]);
}

async function claimFarmRewards(indexes: number[]) {
    console.log("Claiming Farm Rewards for indexes:", indexes)
    await TEST_CONTRACTS.MANAGER.claimFarmRewards(indexes);
}

async function main() {
  ensureExpectedEnvvars();
  const [owner, bob] = await ethers.getSigners();
  ADDRS = await getDeployedContracts1(__dirname);
  INSTANCES = connectToContracts1(owner, ADDRS);
  TEST_CONTRACTS = await getContracts();

  await dumpPrices();
  await dumpFarms();

  const depositAmount = ethers.utils.parseUnits(DEPOSIT_AMOUNT, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS);
  await getDepositTokens(owner, depositAmount);

  await deposit(bob, depositAmount);

  await dumpFarms();
  await anvilMineForwardSeconds(DEFAULT_SETTINGS.VAULTS.SUSDSpS.SWITCH_FARM_COOLDOWN_SECS);
  await switchFarms(1);
  await dumpFarms();

  // Need to take off a small amount from the maxExit, as the liabilities
  // are increasing between maxExit and the exitToToken call
  const maxExitAmount = await TEST_CONTRACTS.VAULT_TOKEN.maxRedeem(await bob.getAddress());
  await redeem(bob, maxExitAmount);

  await claimFarmRewards([1]);
  console.log("SKY.balanceOf(owner):", await TEST_CONTRACTS.FARM_REWARDS_TOKEN.balanceOf(await owner.getAddress()));
  console.log("SKY.balanceOf(swapper):", await TEST_CONTRACTS.FARM_REWARDS_TOKEN.balanceOf(TEST_CONTRACTS.MANAGER.swapper()));
  await dumpFarms();

  await dumpPrices();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });