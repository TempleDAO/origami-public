import "@nomiclabs/hardhat-ethers";
import { ethers } from "hardhat";
import { blockTimestamp, encodedOraclePrice, impersonateAndFund2, mine, runAsyncMain } from "../../../helpers";
import { ContractInstances } from "../../contract-addresses";
import { BigNumber } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ContractAddresses } from "../../contract-addresses/types";
import { IERC20Metadata, OrigamiSuperSkyManager, OrigamiDelegated4626Vault, ISkyStakingRewards__factory } from "../../../../../typechain";
import { DEFAULT_SETTINGS } from "../../default-settings";
import { getDeployContext } from "../../deploy-context";

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

const DEPOSIT_TOKEN_WHALE = "0xCe01C90dE7FD1bcFa39e237FE6D8D9F569e8A6a3";
const DEPOSIT_AMOUNT = "1000000"; // SKY

interface TestContracts {
  DEPOSIT_TOKEN: IERC20Metadata;
  VAULT_TOKEN: OrigamiDelegated4626Vault;
  DEPOSIT_TOKEN_DECIMALS: number;
  VAULT_TOKEN_DECIMALS: number;
  MANAGER: OrigamiSuperSkyManager;
  FARM_REWARDS_TOKEN: IERC20Metadata;
}
let TEST_CONTRACTS: TestContracts;

const getContracts = async (): Promise<TestContracts> => ({
  DEPOSIT_TOKEN: INSTANCES.EXTERNAL.SKY.SKY_TOKEN,
  DEPOSIT_TOKEN_DECIMALS: await INSTANCES.EXTERNAL.SKY.SKY_TOKEN.decimals(),
  VAULT_TOKEN: INSTANCES.VAULTS.SKYp.TOKEN,
  VAULT_TOKEN_DECIMALS: await INSTANCES.VAULTS.SKYp.TOKEN.decimals(),
  MANAGER: INSTANCES.VAULTS.SKYp.MANAGER,
  FARM_REWARDS_TOKEN: INSTANCES.EXTERNAL.SKY.USDS_TOKEN,
});

async function dumpPrices() {
  const prices = await INSTANCES.CORE.TOKEN_PRICES.V4.tokenPrices([
    ADDRS.EXTERNAL.SKY.USDS_TOKEN,
    ADDRS.EXTERNAL.SKY.SKY_TOKEN,
    ADDRS.VAULTS.SKYp.TOKEN,
  ]);
  console.log("Token Prices:");
  console.log("\tUSDS:", ethers.utils.formatUnits(prices[0], 30));
  console.log("\tSKY:", ethers.utils.formatUnits(prices[1], 30));
  console.log("\tSKY+:", ethers.utils.formatUnits(prices[2], 30));
}

async function deposit(
  amountBN: BigNumber,
  account: SignerWithAddress,
) {
  console.log("\ndeposit(%s, %s)",
    ethers.utils.formatUnits(amountBN, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS),
    await account.getAddress()
  );

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
  amountBN: BigNumber,
  account: SignerWithAddress,
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
  const signer = await impersonateAndFund2(DEPOSIT_TOKEN_WHALE);
  await mine(TEST_CONTRACTS.DEPOSIT_TOKEN.connect(signer).transfer(
    owner.getAddress(),
    amount
  ));
}

async function dumpFarms() {
    console.log("===== FARMS ======");
    const numFarms = await TEST_CONTRACTS.MANAGER.maxFarmIndex();
    const farmIndexes = [...Array(numFarms+1).keys()];
    const farmDetails = await TEST_CONTRACTS.MANAGER.farmDetails(farmIndexes);
    for (const details of farmDetails) {
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
    console.log(`Switching from farm ${await TEST_CONTRACTS.MANAGER.currentFarmIndex()} to farm ${index}`);
    await TEST_CONTRACTS.MANAGER.switchFarms(index);
}

async function anvilMineForwardSeconds(secs: number) {
    await ethers.provider.send("evm_setNextBlockTimestamp", [
        (await blockTimestamp()) + secs
    ]);
    await ethers.provider.send("evm_mine", []);
}

async function claimFarmRewards(indexes: number[], rewardsRecipient: string) {
    console.log("Claiming Farm Rewards for indexes:", indexes)
    await TEST_CONTRACTS.MANAGER.claimFarmRewards(indexes, rewardsRecipient);
}

async function updateDaiTokenPrice() {
  // Need to extend out the STALENESS_THRESHOLD since we're moving through time
  const signer = await impersonateAndFund2(ADDRS.CORE.MULTISIG);
  await mine(INSTANCES.CORE.TOKEN_PRICES.V4.connect(signer).setTokenPriceFunction(
    ADDRS.EXTERNAL.SKY.USDS_TOKEN,
    encodedOraclePrice(
      ADDRS.EXTERNAL.CHAINLINK.DAI_USD_ORACLE,
      DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.DAI_USD_ORACLE.STALENESS_THRESHOLD + 7*86_400,
    )
  ));
}

async function notifyRewards() {
  const USDS_WHALE = '0x467194771dAe2967Aef3ECbEDD3Bf9a310C76C65';
  const signer1 = await impersonateAndFund2(USDS_WHALE);
  const amountBN = ethers.utils.parseEther("5000000");
  await mine(
    TEST_CONTRACTS.FARM_REWARDS_TOKEN.connect(signer1).transfer(ADDRS.EXTERNAL.SKY.STAKING_FARMS.STAKE_SKY_EARN_USDS, amountBN)
  );

  const farm = ISkyStakingRewards__factory.connect(ADDRS.EXTERNAL.SKY.STAKING_FARMS.STAKE_SKY_EARN_USDS, signer1);
  const distributor = await farm.rewardsDistribution();
  const signer2 = await impersonateAndFund2(distributor);
  console.log("Reward rate before:", await farm.rewardRate());
  console.log("Reward period end:", await farm.periodFinish());
  await mine(farm.connect(signer2).notifyRewardAmount(amountBN));
  console.log("Reward rate after:", await farm.rewardRate());
  console.log("Reward period end:", await farm.periodFinish());
}

async function main() {
  const [owner, bob] = await ethers.getSigners();
  ({ADDRS, INSTANCES} = await getDeployContext(__dirname));
  TEST_CONTRACTS = await getContracts();

  await updateDaiTokenPrice();

  await dumpPrices();
  await dumpFarms();

  const depositAmount = ethers.utils.parseUnits(DEPOSIT_AMOUNT, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS);
  await getDepositTokens(owner, depositAmount);

  await deposit(depositAmount, bob);

  await dumpFarms();
  await anvilMineForwardSeconds(DEFAULT_SETTINGS.VAULTS.SKYp.SWITCH_FARM_COOLDOWN_SECS);
  await switchFarms(1);
  await notifyRewards();
  await anvilMineForwardSeconds(DEFAULT_SETTINGS.VAULTS.SKYp.SWITCH_FARM_COOLDOWN_SECS);
  await dumpFarms();

  // Need to take off a small amount from the maxExit, as the liabilities
  // are increasing between maxExit and the exitToToken call
  const maxExitAmount = await TEST_CONTRACTS.VAULT_TOKEN.maxRedeem(await bob.getAddress());
  await redeem(maxExitAmount, bob);

  await claimFarmRewards([1], await bob.getAddress());
  console.log("USDS.balanceOf(owner):", 
    ethers.utils.formatEther(
      await TEST_CONTRACTS.FARM_REWARDS_TOKEN.balanceOf(await owner.getAddress())
    )
  );
  console.log("USDS.balanceOf(swapper):", 
    ethers.utils.formatEther(
      await TEST_CONTRACTS.FARM_REWARDS_TOKEN.balanceOf(TEST_CONTRACTS.MANAGER.swapper())
    )
  );
  console.log("USDS.balanceOf(bob):", 
    ethers.utils.formatEther(
      await TEST_CONTRACTS.FARM_REWARDS_TOKEN.balanceOf(await bob.getAddress())
    )
  );
  console.log("USDS.balanceOf(multisig):", 
    ethers.utils.formatEther(
      await TEST_CONTRACTS.FARM_REWARDS_TOKEN.balanceOf(ADDRS.CORE.MULTISIG)
    )
  );
  await dumpFarms();
  await dumpPrices();
}

runAsyncMain(main);