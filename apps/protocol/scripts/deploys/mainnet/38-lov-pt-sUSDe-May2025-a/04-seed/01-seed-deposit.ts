import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  impersonateAndFund,
  mine,
  runAsyncMain,
} from '../../../helpers';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { getDeployContext } from '../../deploy-context';
import { BigNumber } from 'ethers';
import { appendTransactionsToBatch, approve, investWithToken, setMaxTotalSupply } from '../../../safe-tx-builder';
import path from 'path';
import { IERC20Metadata, OrigamiLovToken } from '../../../../../typechain';

const TEST_SEED_WHALE = "0x8C0824fFccBE9A3CDda4c3d409A0b7447320F364";

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

async function main() {
  const {owner, ADDRS, INSTANCES} = await getDeployContext(__dirname);
  VAULT = INSTANCES.LOV_PT_SUSDE_MAY_2025_A.TOKEN;
  VAULT_DECIMALS = await VAULT.decimals();
  DEPOSIT_TOKEN = INSTANCES.EXTERNAL.PENDLE.SUSDE_MAY_2025.PT_TOKEN;
  DEPOSIT_TOKEN_DECIMALS = await DEPOSIT_TOKEN.decimals();

  if (network.name === 'localhost') {
    const signer = await impersonateAndFund(owner, TEST_SEED_WHALE);
    await mine(INSTANCES.EXTERNAL.PENDLE.SUSDE_MAY_2025.PT_TOKEN.connect(signer).transfer(owner.getAddress(), DEFAULT_SETTINGS.LOV_PT_SUSDE_MAY_2025_A.SEED_DEPOSIT_SIZE));

    await lovTokenSeedDepositTestnet(
      DEFAULT_SETTINGS.LOV_PT_SUSDE_MAY_2025_A.SEED_DEPOSIT_SIZE, 
      await owner.getAddress(), 
      DEFAULT_SETTINGS.LOV_PT_SUSDE_MAY_2025_A.MAX_TOTAL_SUPPLY
    )
  } else {
    await lovTokenSeedDepositMainnet(
      DEFAULT_SETTINGS.LOV_PT_SUSDE_MAY_2025_A.SEED_DEPOSIT_SIZE, 
      ADDRS.CORE.MULTISIG, 
      DEFAULT_SETTINGS.LOV_PT_SUSDE_MAY_2025_A.MAX_TOTAL_SUPPLY
    );
  }
}

runAsyncMain(main);
