import { ethers } from "hardhat";
import { impersonateAndFund2, mine, runAsyncMain } from "../../../helpers";
import { ContractInstances } from "../../contract-addresses";
import { BigNumber } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ContractAddresses } from "../../contract-addresses/types";
import { IERC20Metadata, OrigamiDelegated4626Vault, OrigamiErc4626WithRewardsManager } from "../../../../../typechain";
import { getDeployContext } from "../../deploy-context";

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

const DEPOSIT_TOKEN_WHALE = "0xf8191D98ae98d2f7aBDFB63A9b0b812b93C873AA";
const DEPOSIT_AMOUNT = "10000"; // USDS

interface TestContracts {
  DEPOSIT_TOKEN: IERC20Metadata;
  VAULT_TOKEN: OrigamiDelegated4626Vault;
  DEPOSIT_TOKEN_DECIMALS: number;
  VAULT_TOKEN_DECIMALS: number;
  MANAGER: OrigamiErc4626WithRewardsManager;
}
let TEST_CONTRACTS: TestContracts;

const getContracts = async (): Promise<TestContracts> => ({
  DEPOSIT_TOKEN: INSTANCES.EXTERNAL.SKY.USDS_TOKEN,
  DEPOSIT_TOKEN_DECIMALS: await INSTANCES.EXTERNAL.SKY.USDS_TOKEN.decimals(),
  VAULT_TOKEN: INSTANCES.VAULTS.OAC_USDS_IMF_MOR.TOKEN,
  VAULT_TOKEN_DECIMALS: await INSTANCES.VAULTS.OAC_USDS_IMF_MOR.TOKEN.decimals(),
  MANAGER: INSTANCES.VAULTS.OAC_USDS_IMF_MOR.MANAGER,
});

async function dumpPrices() {
  const prices = await INSTANCES.CORE.TOKEN_PRICES.V4.tokenPrices([
    ADDRS.EXTERNAL.SKY.USDS_TOKEN,
    ADDRS.EXTERNAL.IMF.IMF_TOKEN,
    ADDRS.VAULTS.OAC_USDS_IMF_MOR.TOKEN,
  ]);
  console.log("Token Prices:");
  console.log("\tUSDS:", ethers.utils.formatUnits(prices[0], 30));
  console.log("\tIMF:", ethers.utils.formatUnits(prices[1], 30));
  console.log("\toAC-USDS-IMF-MOR:", ethers.utils.formatUnits(prices[2], 30));
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

async function main() {
  const [owner, bob] = await ethers.getSigners();
  ({ADDRS, INSTANCES} = await getDeployContext(__dirname));
  TEST_CONTRACTS = await getContracts();

  await dumpPrices();

  const depositAmount = ethers.utils.parseUnits(DEPOSIT_AMOUNT, TEST_CONTRACTS.DEPOSIT_TOKEN_DECIMALS);
  await getDepositTokens(owner, depositAmount);
  await deposit(depositAmount, bob);

  // Need to take off a small amount from the maxExit, as the liabilities
  // are increasing between maxExit and the exitToToken call
  const maxExitAmount = await TEST_CONTRACTS.VAULT_TOKEN.maxRedeem(await bob.getAddress());
  await redeem(maxExitAmount, bob);

  await dumpPrices();
}

runAsyncMain(main);
