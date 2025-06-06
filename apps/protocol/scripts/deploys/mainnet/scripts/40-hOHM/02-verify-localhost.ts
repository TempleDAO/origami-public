import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  impersonateAndFund2,
  mine,
  runAsyncMain,
  ZERO_ADDRESS,
} from '../../../helpers';
import { ContractInstances } from '../../contract-addresses';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { getDeployContext } from '../../deploy-context';
import { BigNumber } from 'ethers';
import { ContractAddresses } from '../../contract-addresses/types';
import * as fs from 'fs';
import path from 'path';
import { IERC20Metadata__factory } from '../../../../../typechain';

let INSTANCES: ContractInstances;
let ADDRS: ContractAddresses;
const GOHM_AMOUNT = ethers.utils.parseEther("1000");
const GOHM_WHALE = '0x56D24a19dCbF8b08BEbAe9995Ea41Cb001120235';

async function joinWithGohm(
  owner: SignerWithAddress,
  gohmAmountBN: BigNumber,
  accountAddress: string,
) {
  const vault = INSTANCES.VAULTS.hOHM.TOKEN;
  const vaultDecimals = await vault.decimals();
  const assetToken = INSTANCES.EXTERNAL.OLYMPUS.GOHM_TOKEN;
  const assetTokenDecimals = await assetToken.decimals();
  const liabilitiesToken = INSTANCES.EXTERNAL.SKY.USDS_TOKEN;
  const liabilitiesTokenDecimals = await liabilitiesToken.decimals();

  console.log("\tgOHM token balance:", ethers.utils.formatUnits(
    await assetToken.balanceOf(accountAddress),
    assetTokenDecimals,
  ));
  const allowance = await assetToken.allowance(await owner.getAddress(), vault.address);
  console.log("\tcurrent allowance:", ethers.utils.formatUnits(
    allowance,
    assetTokenDecimals,
  ));
  if (allowance.lt(gohmAmountBN)) {
    await mine(assetToken.approve(vault.address, ethers.constants.MaxUint256));
  }

  await mine(
    vault.joinWithToken(
      assetToken.address,
      gohmAmountBN,
      accountAddress
    )
  );

  console.log("\tAccount balance of vault:", ethers.utils.formatUnits(
    await vault.balanceOf(accountAddress),
    vaultDecimals,
  ));
  console.log("\tAccount balance of liabilities:", ethers.utils.formatUnits(
    await liabilitiesToken.balanceOf(accountAddress),
    liabilitiesTokenDecimals,
  ));
  console.log("\tmaxTotalSupply of vault:", ethers.utils.formatUnits(
    await vault.maxTotalSupply(),
    vaultDecimals,
  ));
  
  const sharePrices = await vault.convertFromShares(ethers.utils.parseUnits("1", vaultDecimals));
  console.log("\tasset[0] share price:", ethers.utils.formatUnits(
    sharePrices.assets[0],
    assetTokenDecimals,
  ));
  console.log("\tliabilities[0] share price:", ethers.utils.formatUnits(
    sharePrices.liabilities[0],
    liabilitiesTokenDecimals,
  ));
}

async function comparePrices(owner: SignerWithAddress) {
  const entries: {[token: string]: string} = JSON.parse(fs.readFileSync(path.join(__dirname, "../../40-hOHM/01-core/v3-token-mappings.json"), 'utf-8'));
  const mappedTokens = Object.keys(entries);

  for (let i = 0; i < mappedTokens.length; ++i) {
    const token = IERC20Metadata__factory.connect(mappedTokens[i], owner);
    const symbol = mappedTokens[i] === ZERO_ADDRESS ? "ETH" : await token.symbol();
    const pricesV3 = await INSTANCES.CORE.TOKEN_PRICES.V3.tokenPrice(mappedTokens[i]);
    const pricesV4 = await INSTANCES.CORE.TOKEN_PRICES.V4.tokenPrice(mappedTokens[i]);
  
    const diff = pricesV3.sub(pricesV4);
    console.log(`${symbol} (${mappedTokens[i]})`);
    console.log(`\tdiff=${diff.toString()}`);
    console.log(`\tv3=${pricesV3.toString()} v4=${pricesV4.toString()}`);

    if (!diff.isZero()) throw new Error("TokenPrices doesn't match");
  }
}

async function dumpPrices() {
  const prices = await INSTANCES.CORE.TOKEN_PRICES.V4.tokenPrices([
    ADDRS.EXTERNAL.SKY.USDS_TOKEN,
    ADDRS.EXTERNAL.WETH_TOKEN,
    ADDRS.EXTERNAL.OLYMPUS.OHM_TOKEN,
    ADDRS.EXTERNAL.OLYMPUS.GOHM_TOKEN,
    ADDRS.VAULTS.hOHM.TOKEN
  ]);
  console.log("Token Prices ($):");
  console.log("\tUSDS:", ethers.utils.formatUnits(prices[0], 30));
  console.log("\tWETH:", ethers.utils.formatUnits(prices[1], 30));
  console.log("\tOHM:", ethers.utils.formatUnits(prices[2], 30));
  console.log("\tgOHM:", ethers.utils.formatUnits(prices[3], 30));
  console.log("\thOHM:", ethers.utils.formatUnits(prices[4], 30));
}

async function main() {
  let owner: SignerWithAddress;
  ({owner, ADDRS, INSTANCES} = await getDeployContext(__dirname));
  
  await comparePrices(owner);
  await dumpPrices();

  const signer = await impersonateAndFund2(GOHM_WHALE);
  await mine(INSTANCES.EXTERNAL.OLYMPUS.GOHM_TOKEN.connect(signer).transfer(
    owner.getAddress(), 
    GOHM_AMOUNT
  ));
  
  await joinWithGohm(
    owner,
    GOHM_AMOUNT,
    await owner.getAddress(),
  );

  await dumpPrices();
}

runAsyncMain(main);
