import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  impersonateAndFund,
  mine,
  runAsyncMain,
} from '../../../helpers';
import { ContractInstances } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { getDeployContext } from '../../deploy-context';
import { BigNumber } from 'ethers';
import { appendTransactionsToBatch, approve, investWithToken, setMaxTotalSupply } from '../../../safe-tx-builder';
import { ContractAddresses } from '../../contract-addresses/types';
import path from 'path';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

const TEST_SEED_WHALE = "0x0835500323aC2a78275fd74971464f99F2A595D8";

async function lovTokenSeedDepositTestnet(
  amountBN: BigNumber,
  accountAddress: string,
  maxSupply: BigNumber,
) {
  const vault = INSTANCES.LOV_PT_USD0pp_MAR_2025_A.TOKEN;
  const vaultDecimals = await vault.decimals();
  const depositToken = INSTANCES.EXTERNAL.PENDLE.USD0pp_MAR_2025.PT_TOKEN;
  const depositTokenDecimals = await depositToken.decimals();

  console.log("\nseedDeposit(%f, %s, %f)", amountBN, accountAddress, maxSupply);

  console.log("\tdeposit token balance:", ethers.utils.formatUnits(
    await depositToken.balanceOf(accountAddress),
    depositTokenDecimals,
  ));
  await mine(depositToken.approve(vault.address, amountBN));

  const quote = await vault.investQuote(amountBN, depositToken.address, 0, 0);

  console.log("\tExpect Shares:", ethers.utils.formatUnits(
    quote.quoteData.expectedInvestmentAmount,
    vaultDecimals,
  ));
  await mine(
    vault.setMaxTotalSupply(maxSupply)
  );
  await mine(
    vault.investWithToken(quote.quoteData)
  );

  console.log("\tAccount balance of vault:", ethers.utils.formatUnits(
    await vault.balanceOf(accountAddress),
    vaultDecimals,
  ));
  console.log("\tmaxTotalSupply of vault:", ethers.utils.formatUnits(
    await vault.maxTotalSupply(),
    vaultDecimals,
  ));
}

async function lovTokenSeedDepositMainnet(
  amountBN: BigNumber,
  accountAddress: string,
  maxSupply: BigNumber,
) {
  const vault = INSTANCES.LOV_PT_USD0pp_MAR_2025_A.TOKEN;
  const vaultDecimals = await vault.decimals();
  const depositToken = INSTANCES.EXTERNAL.PENDLE.USD0pp_MAR_2025.PT_TOKEN;
  const depositTokenDecimals = await depositToken.decimals();

  console.log("\nseedDeposit(%f, %s, %f)", amountBN, accountAddress, maxSupply);

  console.log("\tdeposit token balance:", ethers.utils.formatUnits(
    await depositToken.balanceOf(accountAddress),
    depositTokenDecimals,
  ));

  const quote = await vault.investQuote(amountBN, depositToken.address, 0, 0);

  console.log("\tExpect Shares:", ethers.utils.formatUnits(
    quote.quoteData.expectedInvestmentAmount,
    vaultDecimals,
  ));
  
  const filename = path.join(__dirname, "../transactions-batch.json");
  appendTransactionsToBatch(
    filename,
    [
      setMaxTotalSupply(vault, maxSupply),
      approve(depositToken, vault.address, amountBN),
      investWithToken(vault, quote.quoteData),
    ]
  );
}

async function main() {
  let owner: SignerWithAddress;
  ({owner, ADDRS, INSTANCES} = await getDeployContext(__dirname));
  
  if (network.name === 'localhost') {
    const signer = await impersonateAndFund(owner, TEST_SEED_WHALE);
    await mine(INSTANCES.EXTERNAL.PENDLE.USD0pp_MAR_2025.PT_TOKEN.connect(signer).transfer(owner.getAddress(), DEFAULT_SETTINGS.LOV_PT_USD0pp_MAR_2025_A.SEED_DEPOSIT_SIZE));

    await lovTokenSeedDepositTestnet(
      DEFAULT_SETTINGS.LOV_PT_USD0pp_MAR_2025_A.SEED_DEPOSIT_SIZE, 
      await owner.getAddress(), 
      DEFAULT_SETTINGS.LOV_PT_USD0pp_MAR_2025_A.MAX_TOTAL_SUPPLY
    )
  } else {
    await lovTokenSeedDepositMainnet(
      DEFAULT_SETTINGS.LOV_PT_USD0pp_MAR_2025_A.SEED_DEPOSIT_SIZE, 
      ADDRS.CORE.MULTISIG, 
      DEFAULT_SETTINGS.LOV_PT_USD0pp_MAR_2025_A.MAX_TOTAL_SUPPLY
    );
  }
}

runAsyncMain(main);
