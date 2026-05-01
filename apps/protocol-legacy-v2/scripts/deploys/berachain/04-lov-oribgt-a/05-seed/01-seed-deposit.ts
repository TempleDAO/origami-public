import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  impersonateAndFund2,
  mine,
  runAsyncMain,
} from '../../../helpers';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { getDeployContext } from '../../deploy-context';
import { BigNumber } from 'ethers';
import { appendTransactionsToBatch, approve, investWithToken, setMaxTotalSupply } from '../../../safe-tx-builder';
import path from 'path';
import { IERC20Metadata, OrigamiLovToken } from '../../../../../typechain';
import { ContractAddresses } from '../../contract-addresses/types';

const TEST_SEED_WHALE = "0x5286bC17220D51a36e55F5664d63A61Bf9b127A6";
const CHRONICLE_ADMIN = "0x6b5463295fec645729f74c7471952c61913b990d";

let VAULT: OrigamiLovToken;
let VAULT_DECIMALS: number;
let DEPOSIT_TOKEN: IERC20Metadata;
let DEPOSIT_TOKEN_DECIMALS: number;

async function seedQuote(
  amountBN: BigNumber,
  accountAddress: string,
  maxSupply: BigNumber
) {
  console.log("\nseedDeposit(%f, %s, %f)", amountBN, accountAddress, maxSupply);

  console.log("\tdeposit token balance:", ethers.utils.formatUnits(
    await DEPOSIT_TOKEN.balanceOf(accountAddress),
    DEPOSIT_TOKEN_DECIMALS,
  ));

  const quote = await VAULT.investQuote(amountBN, DEPOSIT_TOKEN.address, 0, 0);

  console.log("\tExpect Shares:", ethers.utils.formatUnits(
    quote.quoteData.expectedInvestmentAmount,
    VAULT_DECIMALS,
  ));

  return quote;
}

async function lovTokenSeedDepositTestnet(
  amountBN: BigNumber,
  accountAddress: string,
  maxSupply: BigNumber,
) {
  const quote = await seedQuote(amountBN, accountAddress, maxSupply);

  await mine(VAULT.setMaxTotalSupply(maxSupply));
  await mine(DEPOSIT_TOKEN.approve(VAULT.address, amountBN));
  await mine(VAULT.investWithToken(quote.quoteData));

  console.log("\tAccount balance of vault:", ethers.utils.formatUnits(
    await VAULT.balanceOf(accountAddress),
    VAULT_DECIMALS,
  ));
  console.log("\tmaxTotalSupply of vault:", ethers.utils.formatUnits(
    await VAULT.maxTotalSupply(),
    VAULT_DECIMALS,
  ));
}

async function lovTokenSeedDepositMainnet(
  amountBN: BigNumber,
  accountAddress: string,
  maxSupply: BigNumber,
) {
  const quote = await seedQuote(amountBN, accountAddress, maxSupply);
  
  const filename = path.join(__dirname, "../transactions-batch.json");
  appendTransactionsToBatch(
    filename,
    [
      setMaxTotalSupply(VAULT, maxSupply),
      approve(DEPOSIT_TOKEN, VAULT.address, amountBN),
      investWithToken(VAULT, quote.quoteData),
    ]
  );
}

async function chronicleGrantToll(ADDRS: ContractAddresses) {
  const chronicleAdmin = await impersonateAndFund2(CHRONICLE_ADMIN);
  const abi = [
    "function kiss(address) external",
  ];

  const oracle = new ethers.Contract(ADDRS.EXTERNAL.CHRONICLE.IBGT_WBERA_ORACLE, abi, chronicleAdmin);
  await oracle.kiss(ADDRS.ORACLES.IBGT_WBERA);
}

async function main() {
  const {owner, ADDRS, INSTANCES} = await getDeployContext(__dirname);
  VAULT = INSTANCES.LOV_ORIBGT_A.TOKEN;
  VAULT_DECIMALS = await VAULT.decimals();
  DEPOSIT_TOKEN = INSTANCES.VAULTS.ORIBGT.TOKEN;
  DEPOSIT_TOKEN_DECIMALS = await DEPOSIT_TOKEN.decimals();

  if (network.name === 'localhost') {
    // Grant the Chronicle labs toll for the oracle
    await chronicleGrantToll(ADDRS);

    const signer = await impersonateAndFund2(TEST_SEED_WHALE);
    await mine(DEPOSIT_TOKEN.connect(signer).transfer(owner.getAddress(), DEFAULT_SETTINGS.LOV_ORIBGT_A.SEED_DEPOSIT_SIZE));

    await lovTokenSeedDepositTestnet(
      DEFAULT_SETTINGS.LOV_ORIBGT_A.SEED_DEPOSIT_SIZE, 
      await owner.getAddress(), 
      DEFAULT_SETTINGS.LOV_ORIBGT_A.MAX_TOTAL_SUPPLY
    );
  } else {
    await lovTokenSeedDepositMainnet(
      DEFAULT_SETTINGS.LOV_ORIBGT_A.SEED_DEPOSIT_SIZE, 
      ADDRS.CORE.MULTISIG, 
      DEFAULT_SETTINGS.LOV_ORIBGT_A.MAX_TOTAL_SUPPLY
    );
  }
}

runAsyncMain(main);
