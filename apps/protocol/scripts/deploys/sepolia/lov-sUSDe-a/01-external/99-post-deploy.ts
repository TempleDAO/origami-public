import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  ensureExpectedEnvvars,
  mine,
} from '../../../helpers';
import { connectToContracts, getDeployedContracts } from '../contract-addresses';
import { DEFAULT_SETTINGS } from '../default-settings';

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  const INSTANCES = connectToContracts(owner);
  const ADDRS = getDeployedContracts();

  await mine(
    INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN.addMinter(
      INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN.owner()
    )
  );
  await mine(
    INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN.addMinter(
      ADDRS.CORE.MULTISIG
    )
  );

  await mine(
    INSTANCES.EXTERNAL.ETHENA.USDE_TOKEN.addMinter(
      INSTANCES.EXTERNAL.ETHENA.USDE_TOKEN.owner()
    )
  );
  await mine(
    INSTANCES.EXTERNAL.ETHENA.USDE_TOKEN.addMinter(
      ADDRS.CORE.MULTISIG
    )
  );

  await mine(INSTANCES.EXTERNAL.ETHENA.SUSDE_TOKEN.setInterestRate(
    DEFAULT_SETTINGS.EXTERNAL.SUSDE_INTEREST_RATE
  ));

  const morphoMarketParams = {
    loanToken: ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN,
    collateralToken: ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN,
    oracle: ADDRS.EXTERNAL.MORPHO.ORACLE,
    irm: ADDRS.EXTERNAL.MORPHO.IRM,
    lltv: DEFAULT_SETTINGS.LOV_SUSDE_5X.MORPHO_BORROW_LEND.LIQUIDATION_LTV,
  };

  // Setup morpho
  {
    await mine(INSTANCES.EXTERNAL.MORPHO.SINGLETON.enableIrm(
      ADDRS.EXTERNAL.MORPHO.IRM
    ));

    await mine(INSTANCES.EXTERNAL.MORPHO.SINGLETON.enableLltv(
      DEFAULT_SETTINGS.LOV_SUSDE_5X.MORPHO_BORROW_LEND.LIQUIDATION_LTV
    ));

    await mine(INSTANCES.EXTERNAL.MORPHO.SINGLETON.createMarket(
      morphoMarketParams
    ));
  }

  // Seed with DAI liquidity
  {
    const amount = ethers.utils.parseEther("100000000");
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