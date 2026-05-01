import "@nomiclabs/hardhat-ethers";
import { ethers } from "hardhat";
import { runAsyncMain, ZERO_ADDRESS } from "../../../helpers";
import { ContractInstances } from "../../contract-addresses";
import { ContractAddresses } from "../../contract-addresses/types";
import { getDeployContext } from "../../deploy-context";
import { IERC20Metadata__factory } from "../../../../../typechain";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;
let OWNER: SignerWithAddress;

async function getSymbol(tokenOrNative: string): Promise<string> {
  if (tokenOrNative === ZERO_ADDRESS) return "BERA";

  const token = IERC20Metadata__factory.connect(tokenOrNative, OWNER);
  return token.symbol();
}

async function dumpPrices() {
  const addresses = [
    ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
    ADDRS.EXTERNAL.BERACHAIN.HONEY_TOKEN,
    ZERO_ADDRESS,
    ADDRS.EXTERNAL.BERACHAIN.WBERA_TOKEN,
    ADDRS.EXTERNAL.INFRARED.IBGT_TOKEN,
    ADDRS.EXTERNAL.OLYMPUS.OHM_TOKEN,
    ADDRS.EXTERNAL.PAYPAL.BYUSD_TOKEN,
    ADDRS.EXTERNAL.RESERVIOR.RUSD_TOKEN,
    ADDRS.EXTERNAL.INFRARED.IBERA_TOKEN,

    ADDRS.EXTERNAL.KODIAK.ISLANDS.OHM_HONEY_V3,
    ADDRS.EXTERNAL.BEX.LP_TOKENS.HONEY_BYUSD,
    ADDRS.EXTERNAL.KODIAK.ISLANDS.RUSD_HONEY_V3,
    ADDRS.EXTERNAL.KODIAK.ISLANDS.WBERA_IBERA_V3,
    ADDRS.EXTERNAL.KODIAK.ISLANDS.WBERA_HONEY_V3,
    ADDRS.EXTERNAL.KODIAK.ISLANDS.WBERA_IBGT_V3,
    
    ADDRS.VAULTS.BOYCO_USDC_A.TOKEN,
    ADDRS.VAULTS.ORIBGT.TOKEN,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_OHM_HONEY_A.TOKEN,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_BYUSD_HONEY_A.TOKEN,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_RUSD_HONEY_A.TOKEN,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_IBERA_A.TOKEN,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_HONEY_A.TOKEN,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_IBGT_A.TOKEN,
  ];

  const prices = await INSTANCES.CORE.TOKEN_PRICES.V5.tokenPrices(addresses);
  const symbols = await Promise.all(addresses.map(a => getSymbol(a)));

  console.log("Token Prices:");
  for (let i = 0; i < addresses.length; ++i) {
    console.log(`\t${symbols[i]}: ${ethers.utils.formatUnits(prices[i], 30)}`);
  }
}

async function main() {
  ({owner: OWNER, ADDRS, INSTANCES} = await getDeployContext(__dirname));
  await dumpPrices();
}

runAsyncMain(main);
