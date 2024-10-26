import "@nomiclabs/hardhat-ethers";
import { ethers } from "hardhat";
import { ensureExpectedEnvvars, ZERO_ADDRESS } from "../../../helpers";
import { ContractInstances, connectToContracts, getDeployedContracts } from "../../contract-addresses";
import { ContractAddresses } from "../../contract-addresses/types";
import { IERC20Metadata__factory } from "../../../../../typechain";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

async function dumpPrices(owner: SignerWithAddress) {
  const addresses = [
    ADDRS.EXTERNAL.ETHENA.USDE_TOKEN, 
    ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN, 
    ADDRS.LOV_SUSDE_A.TOKEN,
    ADDRS.LOV_USDE_A.TOKEN,
    ADDRS.LOV_WEETH_A.TOKEN,
    ADDRS.EXTERNAL.ETHERFI.WEETH_TOKEN, 
    ADDRS.LOV_EZETH_A.TOKEN,
    ZERO_ADDRESS, 
    ADDRS.EXTERNAL.WETH_TOKEN, 
    ADDRS.EXTERNAL.RENZO.EZETH_TOKEN, 
    ADDRS.LOV_WSTETH_A.TOKEN,
    ADDRS.EXTERNAL.LIDO.STETH_TOKEN, 
    ADDRS.EXTERNAL.LIDO.WSTETH_TOKEN,
    ADDRS.LOV_SUSDE_B.TOKEN,
    ADDRS.LOV_USDE_B.TOKEN,
    ADDRS.LOV_WOETH_A.TOKEN,
    ADDRS.EXTERNAL.ORIGIN.OETH_TOKEN,
    ADDRS.EXTERNAL.ORIGIN.WOETH_TOKEN, 
    ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN,
    ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN,
  ];
  
  console.log("Token Prices:");
  for (const i in addresses) {
    const price = await INSTANCES.CORE.TOKEN_PRICES.V2.tokenPrice(addresses[i]);
    const token = IERC20Metadata__factory.connect(addresses[i], owner);
    const symbol = addresses[i] === ZERO_ADDRESS ? "ETH" : await token.symbol();
    console.log(`\t${symbol} = ${ethers.utils.formatUnits(price, 30)}`);
  }
}

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  await dumpPrices(owner);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
