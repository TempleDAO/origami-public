import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  ensureExpectedEnvvars,
  mine,
  impersonateAndFund
} from '../../../helpers';
import { connectToContracts, getDeployedContracts } from '../contract-addresses';
import { DEFAULT_SETTINGS } from '../default-settings';

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  const INSTANCES = connectToContracts(owner);
  const ADDRS = getDeployedContracts();

  const morphoMarketParams = {
    loanToken: ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN,
    collateralToken: ADDRS.EXTERNAL.ETHENA.USDE_TOKEN,
    oracle: ADDRS.EXTERNAL.MORPHO.USDE_USD_ORACLE,
    irm: ADDRS.EXTERNAL.MORPHO.IRM,
    lltv: DEFAULT_SETTINGS.LOV_USDE.MORPHO_BORROW_LEND.LIQUIDATION_LTV,
  };

  const morphoOwnerAddr = await INSTANCES.EXTERNAL.MORPHO.SINGLETON.owner();

  // This works in local fork testing. For actual testnet deploy, a multisig
  // operation will be required instead.
  const morphoOwner = await impersonateAndFund(owner, morphoOwnerAddr);

  // Setup morpho
  {
    await mine(INSTANCES.EXTERNAL.MORPHO.SINGLETON.connect(morphoOwner).enableLltv(
      DEFAULT_SETTINGS.LOV_USDE.MORPHO_BORROW_LEND.LIQUIDATION_LTV
    ));

    await mine(INSTANCES.EXTERNAL.MORPHO.SINGLETON.createMarket(
      morphoMarketParams
    ));
  }

  // Seed with DAI liquidity
  {
    const amount = ethers.utils.parseEther("10000000");
    await mine(INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN.mint(
      await owner.getAddress(),
      amount
    ));
    await mine(INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN.approve(
      ADDRS.EXTERNAL.MORPHO.SINGLETON,
      amount
    ));

    await mine(INSTANCES.EXTERNAL.MORPHO.SINGLETON.supply(
      morphoMarketParams, 
      amount, 
      0, 
      await owner.getAddress(), 
      []
    ));
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });